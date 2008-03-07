#!/bin/sh
#
# $Id: firefox.sh,v 1.8 2007-06-22 15:13:03 rbasch Exp $
# Firefox wrapper script for Athena.

moz_progname=firefox

# Profile directory's parent.
prof_parent=$HOME/.mozilla/firefox

# The following lockers need to be attached to run plugins and helper
# applications.
lockers="infoagents acro"

if [ $(lsb_release --short --id) == "Debian" ]; then
  firefox_libdir=/usr/lib/iceweasel
else
  firefox_libdir=/usr/lib/firefox
fi

# mozilla-xremote-client sends a command to a running Mozilla
# application using X properties.  Its possible return codes are:
#   0  success
#   1  failed to connect to the X server
#   2  no running window found
#   3  failed to send command
#   4  usage error
moz_remote=$firefox_libdir/mozilla-xremote-client

# testlock is used to test whether the profile directory's lock file
# is actually locked.
testlock=/usr/bin/testlock

# Set the plugin path.  We allow the user to skip loading our
# standard plugins via the MOZ_PLUGIN_PATH_OVERRIDE variable.
if [ "${MOZ_PLUGIN_PATH_OVERRIDE+set}" = set ]; then
  MOZ_PLUGIN_PATH="$MOZ_PLUGIN_PATH_OVERRIDE"
else
  # Append our plugin path to the user's setting (if any).
  MOZ_PLUGIN_PATH=${MOZ_PLUGIN_PATH:+"$MOZ_PLUGIN_PATH:"}$plugin_path
fi
export MOZ_PLUGIN_PATH

# Get the profile directory path, by parsing the profiles.ini file.
get_profdir () {
  inifile="$prof_parent/profiles.ini"
  if [ ! -s "$inifile" ]; then
    return 1
  fi
  awk -F= -v parent="$prof_parent" '
    BEGIN {
      nprofiles = 0;
      use_default = 1;
    }
  
    $1 ~ /^\[.*\]$/ {
      section = substr($1, 2, length($1) - 2);
      if (section ~ /^Profile[0-9]*$/) {
        id = section;
        nprofiles++;
      }
    }
    $1 == "StartWithLastProfile" {
      if (section == "General")
        use_default = int($2);
    }
    $1 == "Name"       { a[id, "name"] = $2; }
    $1 == "IsRelative" { a[id, "isrelative"] = $2; }
    $1 == "Path"       { a[id, "path"] = $2; }
    $1 == "Default"    { a[id, "default"] = $2; }
  
    END {
      count = 0;
      default = "";
      for (i = 0; i < nprofiles; i++) {
        id = "Profile" i;
        if (a[id, "name"] != "" && a[id, "isrelative"] != "" &&
            a[id, "path"] != "") {
          count++;
          if (int(a[id, "default"]) != 0)
            default = id;
        }
      }
      if (use_default != 0 && default != "")
        id = default;
      else if (nprofiles == 1 && count == 1)
        id = "Profile0";
      else
        id = "";
      if (id != "") {
        if (int(a[id, "isrelative"]) == 0)
          print a[id, "path"];
        else
          print parent "/" a[id, "path"];
      }
    }' $inifile
}

# Prompt the user on how to deal with an existing locked profile when
# no running Firefox window can be found, and take action accordingly.
# Parameter 1 is the profile directory path.
# If the function returns, the lock file(s) will have been removed per
# the user's choice, and the caller should continue.  Otherwise, the
# process will exit.
dispose_lock () {
  lockfile="$1/.parentlock"
  locklink="$1/lock"
  # Extract the IP address and PID from the contents of the symlink.
  # Also note whether firefox used fnctl() to lock .parentlock,
  # which is indicated with a leading '+' in the PID.
  eval `ls -l $locklink | awk '{
    if (split($NF, a, ":") == 2)
      printf("lock_ip=%s ; lock_pid=%d ; use_fcntl=%d\n",
              a[1], int(a[2]), (substr(a[2], 1, 1) == "+")); }'`

  # If we cannot recognize the link contents, just continue.
  if [ -z "$lock_ip" ]; then
    return 0
  fi

  local=false
  if [ "$use_fcntl" -ne 0 ]; then
    # An fcntl()-style lock was acquired; check it.
    if [ -f "$lockfile" ]; then
      # testlock tests whether there is a write lock on the file.
      # If so, it outputs the locker's PID, and exits with status 2.
      # If the lock is held by a process running on another host, the
      # PID will be 0.
      pid=`$testlock "$lockfile" 2>/dev/null`
      if [ $? -ne 2 ]; then
        # File is not locked, remove the symlink and continue.
        rm -f "$locklink"
        return 0
      fi
      # The file is locked.  If the lock is held by a process on
      # this machine, the locker pid will be non-0.
      if [ "$pid" -ne 0 ]; then
        local=true
      fi
    fi
  else
    # Handle an old-style (symlink) lock.
    my_host=`hostname`
    if [ "$lock_ip" = "`host $my_host | awk '{ print $NF; }'`" ]; then
      # Lock is held on this machine.
      local=true
    fi
  fi

  if [ "$local" = true ]; then
    # The lock is held by a process on this machine; check if it is
    # still running.
    if kill -0 $lock_pid 2>/dev/null ; then
      # Lock is held by a running process.
      lock_host="this machine"
    else
      # Process is no longer running.  Nuke the lock and continue.
      rm -f "$lockfile" "$locklink"
      return 0
    fi
  else
    # The lock is held by a process on another machine.  Get its
    # host name.
    lock_host=`host $lock_ip | \
      sed -n -e 's/^.*domain name pointer \(.*\)$/\1/p' | \
      sed -e 's/\.*$//' | tr '[A-Z]' '[a-z]'`
    if [ -z "$lock_host" ]; then
      lock_host="$lock_ip"
    fi
  fi

  dialog_text="
  Your Firefox profile directory is locked by process $lock_pid  
  on $lock_host.  
"

  dialog_text="$dialog_text
  If you select \"OK\" to continue, the profile will be forcibly  
  unlocked; if the process holding the lock is still running,  
  you risk corrupting your profile.

  If you are not certain whether your Firefox process is still
  running on $lock_host, select \"Cancel\" to exit  
  without starting Firefox.  
"

  zenity --title "Firefox profile locked" --warning --text "$dialog_text"

  case $? in
  0)
    rm -f "$lockfile" "$locklink"
    ;;
  *)
    exit 1
    ;;
  esac
}

# Give a warning if we're running on a dialup machine.
if [ -x /etc/athena/dialuptype ]; then
  cat << \EOF

*** PLEASE DO NOT RUN FIREFOX ON THE DIALUPS! ***

Firefox is a very large and resource-intensive program, and it is
not appropriate to run it on a dialup machine.

Please run Firefox on your local machine rather than on a dialup.

Thank you.

EOF
fi

# Attach needed lockers.
for locker in $lockers ; do
  /bin/attach -h -n -q $locker
done

# Configure fontconfig to use fonts for MathML.
if [ -z "$FONTCONFIG_FILE" ]; then
  FONTCONFIG_FILE=/mit/infoagents/share/fonts/fonts.conf
  export FONTCONFIG_FILE
fi

# If this is the first time the user has run firefox, create
# the top-level profile directory now, so that we can set
# the ACL appropriately.
if [ ! -d "$prof_parent" ]; then
  mkdir -p "$prof_parent"
  /usr/bin/fs setacl "$prof_parent" system:anyuser none system:authuser none
fi

# We want Firefox to download files for helper applications to
# /var/tmp instead of /tmp, so that users have a better chance
# of retrieving them later.
if [ -z "$TMPDIR" ]; then
  TMPDIR=/var/tmp
  export TMPDIR
fi

# If the user specified any option, skip the check for a running
# Firefox, and invoke the program now.
case "$1" in
-*)
  exec /usr/bin/firefox.debathena-orig "$@"
  ;;
esac

if [ "${MOZ_NO_REMOTE+set}" = "set" ]; then
  found_running=false
else
  # See if there is a running instance of Firefox.
  user="${LOGNAME:+-u $LOGNAME}"
  $firefox_libdir/run-mozilla.sh $moz_remote $user -a "$moz_progname" \
    "ping()" >/dev/null 2>&1
  case $? in
  0)
    found_running=true
    ;;
  2)
    # This is the expected status when there is no running firefox window.
    # Clear the error condition.
    remote_error=
    found_running=false
    ;;
  *)
    # An unexpected error occurred.
    found_running=error
    ;;
  esac
fi

# If Firefox is not running, check for a (possibly stale) lock on
# the profile directory.
if [ $found_running != true ]; then
  profdir=`get_profdir`
  if [ -n "$profdir" ]; then
    # firefox now uses fcntl()-style locking on .parentlock, but an
    # apparent openafs bug leaves the lock set after the program exits.
    # Fortunately, it still maintains the "lock" symlink (which may
    # also have been left from running a pre-1.5.0 firefox on the
    # profile), so use its presence to help detect a stale lock.
    if [ -h "$profdir/lock" ]; then
      # The symlink exists, so the profile is (potentially) locked.
      dispose_lock "$profdir"
    else
      # The symlink is gone, so just nuke the lock file, to work around
      # the aforementioned openafs bug.
      rm -f "$profdir/.parentlock"
    fi
  fi
fi

exec $firefox_libdir/firefox "$@"
