#!/bin/sh

usage() {

	echo "poudriere lsjail [-q] [-n JAIL]"
	echo "-q don't print header."
	echo "-n JAIL print infos about JAIL"
	exit 1

}

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh


JAILNAMES=`zfs list -rH ${ZPOOL}/poudriere | awk '/^'${ZPOOL}'\/poudriere\// { sub(/^'${ZPOOL}'\/poudriere\//, "", $1); print $1 }'`

while getopts "n:q" FLAG; do
        case "${FLAG}" in
	  n)
	  NAME=${OPTARG}
	  ;;
	  q)
	  NOHEADER=1
	  ;;
	  *)
	  usage
	  ;; 
	esac
done

[ "${JAILNAMES}X" = "X" ] && err 1 "No jails found."
[ "${NOHEADER}X" = "1X" ] || printf '%-20s %-13s %s\n' "JAILNAME" "VERSION" "ARCH"

for JAILNAME in ${JAILNAMES};do
	MNT=`zfs list -H -o mountpoint ${ZPOOL}/poudriere/${JAILNAME}`

	if [ -d ${MNT} -a -d ${MNT}/boot/kernel ];then
		VERSION=`jail -U root -c path=${MNT} command=uname -r`
		ARCH=`jail -u root -c path=${MNT} command=uname -p`
		
		printf '%-20s %-13s %s\n' ${JAILNAME} ${VERSION} ${ARCH}
	fi
done
