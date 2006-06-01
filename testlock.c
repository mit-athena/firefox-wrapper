#include <stdio.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>
#include <fcntl.h>
#include <string.h>
#include <errno.h>

int main(int argc, char **argv)
{
  char *progname, *filename;
  int fd;
  struct flock lock;

  progname = argv[0];
  if (argc != 2)
    {
      fprintf(stderr, "%s: Usage: %s <lock_file>\n", progname, progname);
      return 4;
    }
  filename = argv[1];

  /* Open the file. */
  fd = open(filename, O_RDWR, 0600);
  if (fd == -1)
    {
      fprintf(stderr, "%s: Cannot open %s: %s\n", progname, filename,
	      strerror(errno));
      return 3;
    }

  /* See if there is a write lock on the file. */
  lock.l_type = F_WRLCK;
  lock.l_whence = SEEK_SET;
  lock.l_start = 0;
  lock.l_len = 0;
  if (fcntl(fd, F_GETLK, &lock) == -1)
    {
      fprintf(stderr, "%s: Cannot get the lock for %s: %s\n", progname,
	      filename, strerror(errno));
      return 3;
    }
  close(fd);
  if (lock.l_type != F_UNLCK)
    {
      /* The file is locked; print the PID of the locking process. */
      printf("%ld\n", (long) lock.l_pid);
      return 2;
    }
  return 0;
}
