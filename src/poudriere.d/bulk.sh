#!/bin/sh

usage() {
	echo "poudriere bulk -f listpkgs [-c] [-j jailname]"
	echo "-f listpkgs: list of packages to build"
	echo "-c run make config for the given port"
	echo "-j jailname run only on the given jail"
	exit 1
}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
CONFIGSTR=0
. ${SCRIPTPREFIX}/common.sh

LOGS="${POUDRIERE_DATA}/logs"

while getopts "f:cnj:" FLAG; do
	case "${FLAG}" in
		c)
		CONFIGSTR=1
		;;
		f)
		LISTPKGS=${OPTARG}
		;;
		j)
		zfs list ${ZPOOL}/poudriere/${OPTARG} >/dev/null 2>&1 || err 1 "No such jail: ${OPTARG}"
		JAILNAMES="${OPTARG}"
		;;
		*)
		usage
		;;
	esac
done

test -z ${LISTPKGS} && usage
test -f ${LISTPKGS} || err 1 "No such list of packages: ${LISTPKGS}"

STATUS=0 # out of jail #

trap sig_handler SIGINT SIGTERM SIGKILL

test -z ${JAILNAMES} && JAILNAMES=`zfs list -rH ${ZPOOL}/poudriere | awk '/^'${ZPOOL}'\/poudriere\// { sub(/^'${ZPOOL}'\/poudriere\//, "", $1); print $1 }'`

for JAILNAME in ${JAILNAMES}; do
	JAILBASE=`zfs list -H -o mountpoint ${ZPOOL}/poudriere/${JAILNAME}`
	PKGDIR=${POUDRIERE_DATA}/packages/bulk-${JAILNAME}
	/bin/sh ${SCRIPTPREFIX}/start_jail.sh -n ${JAILNAME} || err 1 "Failed to start jail."

	STATUS=1 #injail
	prepare_jail
	(
	for port in `cat ${LISTPKGS}`; do
		PORTDIRECTORY="/usr/ports/${port}"

		test -d ${JAILBASE}/${PORTDIRECTORY} || {
			msg "No such port ${port}"
			continue
		}

		msg "building ${port}"
		jexec -U root ${JAILNAME} make -C ${PORTDIRECTORY} install
# Package all newly build ports
	done
	msg "Packaging all installed ports"
	if [ -x ${JAILBASE}/usr/sbin/pkg ]; then
		jexec -U root ${JAILNAME} /usr/sbin/pkg create -a -o /usr/ports/packages/All/
	else
		for pkg in `jexec -U root ${JAILNAME} ${PKG_INFO}`; do
			msg_n "packaging ${pkg}"
			test -f ${POUDRIERE_DATA}/packages/bulk-${JAILNAME}/All/${pkg}.tbz || jexec -U root ${JAILNAME} /usr/sbin/pkg_create -b ${pkg} /usr/ports/packages/All/${pkg}.tbz
			echo " done"
		done
	fi
	) 2>&1 | tee ${LOGS}/${PORTNAME}-${JAILNAME}.bulk.log

	cleanup
	STATUS=0 #injail
done

