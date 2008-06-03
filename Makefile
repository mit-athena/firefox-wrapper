bindir=/usr/bin

all: testlock

testlock: testlock.o
	cc ${LDFLAGS} -o $@ testlock.o ${LIBS}

.c.o:
	${CC} -c ${CPPFLAGS} ${CFLAGS} $<

check:

install:
	mkdir -p ${DESTDIR}${bindir}
	install -c -m 755 firefox.sh ${DESTDIR}${bindir}/firefox.debathena
	install -c -m 755 testlock ${DESTDIR}${bindir}

clean:
	rm -f testlock.o testlock

distclean: clean
	rm -f config.cache config.log config.status Makefile
