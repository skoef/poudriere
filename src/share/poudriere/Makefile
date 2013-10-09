SUBDIR=		awk \
		html

NO_OBJ=		yes

PREFIX?=	/usr/local

FILESDIR=	${PREFIX}/share/poudriere
FILES=		bulk.sh \
		clean.sh \
		combo.sh \
		common.sh \
		common.sh.freebsd \
		common.sh.dragonfly \
		daemon.sh \
		distclean.sh \
		jail.sh \
		options.sh \
		ports.sh \
		pkgclean.sh \
		processonelog.sh \
		queue.sh \
		status.sh \
		testport.sh
FILESMODE=	${BINMODE}

beforeinstall:
	mkdir -p ${DESTDIR}${FILESDIR} \
		${DESTDIR}${FILESDIR}/awk \
		${DESTDIR}${FILESDIR}/html/assets/bootstrap/css \
		${DESTDIR}${FILESDIR}/html/assets/bootstrap/img \
		${DESTDIR}${FILESDIR}/html/assets/bootstrap/js \
		${DESTDIR}${FILESDIR}/html/assets/dataTables/css \
		${DESTDIR}${FILESDIR}/html/assets/dataTables/images \
		${DESTDIR}${FILESDIR}/html/assets/dataTables/js \

.include <bsd.prog.mk>
