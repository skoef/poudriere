#!/bin/sh

usage() {
	echo "poudriere jail [parameters] [options]

Parameters:
    -c            -- create a jail
    -d            -- delete a jail
    -l            -- list all available jails
    -s            -- start a jail
    -k            -- kill (stop) a jail
    -u            -- update a jail
    -i            -- show informations

Options:
    -q            -- quiet (remove the header in list)
    -j jailname   -- Specifies the jailname
    -v version    -- Specifies which version of FreeBSD we want in jail
    -a arch       -- Indicates architecture of the jail: i386 or amd64
                     (Default: same as host)
    -f fs         -- FS name (tank/jails/myjail)
    -M mountpoint -- mountpoint
    -m method     -- when used with -c forces the method to use by default
                     \"ftp\", could also be \"svn\", \"csup\" please note
                     that with svn and csup the world will be built. note
                     that building from sources can use src.conf and
                     jail-src.conf from localbase/etc/poudriere.d"
	exit 1
}

info_jail() {
	test -z ${JAILNAME} && usage
	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	JAILFS=`jail_get_fs ${JAILNAME}`
	nbb=$(zfs_get poudriere:stats_built)
	nbf=$(zfs_get poudriere:stats_failed)
	nbi=$(zfs_get poudriere:stats_ignored)
	nbq=$(zfs_get poudriere:stats_queued)
	tobuild=$((nbq - nbb - nbf - nbi))
	zfs list -H -o poudriere:type,poudriere:name,poudriere:version,poudriere:arch,poudriere:stats_built,poudriere:stats_failed,poudriere:stats_ignored,poudriere:status ${JAILFS}| \
		awk -v q="$nbq" -v tb="$tobuild" '/^rootfs/  {
			print "Jailname: " $2;
			print "FreeBSD Version: " $3;
			print "FreeBSD arch: "$4;
			print "Status: ", $7;
			print "Nb packages built: "$5;
			print "Nb packages failed: "$6;
			print "Nb packages ignored: "$7;
			print "Nb packages queued: "q;
			print "Nb packages to be built: "tb;
		}'
}

list_jail() {
	[ ${QUIET} -eq 0 ] && \
		printf '%-20s %-13s %-7s %-7s %-7s %-7s %-7s %s\n' "JAILNAME" "VERSION" "ARCH" "SUCCESS" "FAILED" "IGNORED" "QUEUED" "STATUS"
	zfs list -Hd1 -o poudriere:type,poudriere:name,poudriere:version,poudriere:arch,poudriere:stats_built,poudriere:stats_failed,poudriere:stats_ignored,poudriere:stats_queued,poudriere:status ${ZPOOL}/poudriere | \
		awk '/^rootfs/ { printf("%-20s %-13s %-7s %-7s %-7s %-7s %-7s %s\n",$2, $3, $4, $5, $6, $7, $8, $9) }'
}

delete_jail() {
	test -z ${JAILNAME} && usage
	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	jail_runs ${JAILNAME} && \
		err 1 "Unable to remove jail ${JAILNAME}: it is running"

	JAILBASE=`jail_get_base ${JAILNAME}`
	FS=`jail_get_fs ${JAILNAME}`
	msg_n "Removing ${JAILNAME} jail..."
	zfs destroy -r ${FS}
	rmdir ${JAILBASE}
	rm -rf ${POUDRIERE_DATA}/packages/${JAILNAME}
	rm -f ${POUDRIERE_DATA}/logs/*-${JAILNAME}.*.log
	rm -f ${POUDRIERE_DATA}/logs/bulk-${JAILNAME}.log
	echo done
}

cleanup_new_jail() {
	delete_jail
	rm -rf ${JAILBASE}/fromftp
}

update_jail() {
	test -z ${JAILNAME} && usage
	JAILFS=`jail_get_fs ${JAILNAME}`
	JAILBASE=`jail_get_base ${JAILNAME}`
	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	jail_runs ${JAILNAME} && \
		err 1 "Unable to remove jail ${JAILNAME}: it is running"

	METHOD=`zfs_get poudriere:method`
	if [ "${METHOD}" = "-" ]; then
		METHOD="ftp"
		zfs_set poudriere:method "ftp"
	fi
	case ${METHOD} in
	ftp)
		jail_start ${JAILNAME}
		jail -r ${JAILNAME}
		jail -c persist name=${NAME} ip4=inherit ip6=inherit path=${MNT} host.hostname=${NAME} \
			allow.sysvipc allow.mount allow.socket_af allow.raw_sockets allow.chflags
		injail /usr/sbin/freebsd-update fetch install
		jail_stop ${JAILNAME}
		;;
	csup)
		msg "Upgrading using csup"
		RELEASE=`zfs_get poudriere:version`
		install_from_csup
		yes | make -C ${JAILBASE}/usr/src delete-old delete-old-libs DESTDIR=${JAILBASE}
		;;
	svn)
		RELEASE=`zfs_get poudriere:version`
		install_from_svn
		yes | make -C ${JAILBASE} delete-old delete-old-libs DESTDIR=${JAILBASE}
		;;
	*)
		err 1 "Unsupported method"
		;;
	esac

	zfs destroy ${JAILFS}@clean
	zfs snapshot ${JAILFS}@clean
}

build_and_install_world() {
	export TARGET_ARCH=${ARCH}
	export SRC_BASE=${JAILBASE}/usr/src
	mkdir -p ${JAILBASE}/etc
	[ -f ${JAILBASE}/etc/src.conf ] && rm -f ${JAILBASE}/etc/src.conf
	[ -f ${POUDRIERED}/src.conf ] && cat ${POUDRIERED}/src.conf > ${JAILBASE}/etc/src.conf
	[ -f ${POUDRIERED}/${JAILBASE}-src.conf ] && cat ${POUDRIERED}/${JAILBASE}-src.conf >> ${JAILBASE}/etc/src.conf
	unset MAKEOBJPREFIX
	export __MAKE_CONF=/dev/null
	export SRCCONF=${JAILBASE}/etc/src.conf
	msg "Starting make buildworld"
	make -C ${JAILBASE}/usr/src buildworld ${MAKEWORLDARGS} || err 1 "Fail to build world"
	msg "Starting make installworld"
	make -C ${JAILBASE}/usr/src installworld DESTDIR=${JAILBASE} || err 1 "Fail to install world"
	make -C ${JAILBASE}/usr/src DESTDIR=${JAILBASE} distrib-dirs && \
	make -C ${JAILBASE}/usr/src DESTDIR=${JAILBASE} distribution
}

install_from_svn() {
	local UPDATE=0
	[ -d ${JAILBASE}/usr/src ] && UPDATE=1
	mkdir -p ${JAILBASE}/usr/src
	msg "Fetching sources from svn"
	if [ ${UPDATE} -eq 0 ]; then
		svn co http://svn.freebsd.org/base/${RELEASE} ${JAILBASE}/usr/src || err 1 "Fail to fetch sources"
	else
		cd ${JAILBASE}/usr/src && svn up
	fi
	build_and_install_world
}

install_from_csup() {
	mkdir -p ${JAILBASE}/etc
	mkdir -p ${JAILBASE}/var/db
	mkdir -p ${JAILBASE}/usr
	[ -z ${CSUP_HOST} ] && err 2 "CSUP_HOST has to be defined in the configuration to use csup"
	echo "*default base=${JAILBASE}/var/db
*default prefix=${JAILBASE}/usr
*default release=cvs tag=${RELEASE}
*default delete use-rel-suffix
src-all" > ${JAILBASE}/etc/supfile
	csup -z -h ${CSUP_HOST} ${JAILBASE}/etc/supfile || err 1 "Fail to fetch sources"
	build_and_install_world
}

install_from_ftp() {
	mkdir ${JAILBASE}/fromftp
	CLEANUP_HOOK=cleanup_new_jail
	local FREEBSD_BASE
	local URL

	if [ -n "${FREEBSD_HOST}" ]; then
		FREEBSD_BASE=${FREEBSD_HOST}
	else
		FREEBSD_BASE="ftp://${FTPHOST:=ftp.freebsd.org}"
	fi

	if [ ${VERSION%%.*} -lt 9 ]; then
		msg "Fetching sets for FreeBSD ${VERSION} ${ARCH}"
		URL="${FREEBSD_BASE}/pub/FreeBSD/releases/${ARCH}/${VERSION}"
		DISTS="base dict src"
		[ ${ARCH} = "amd64" ] && DISTS="${DISTS} lib32"
		for dist in ${DISTS}; do
			fetch_file ${JAILBASE}/fromftp/ ${URL}/$dist/CHECKSUM.SHA256 || \
				err 1 "Fail to fetch checksum file"
			sed -n "s/.*(\(.*\...\)).*/\1/p" \
				${JAILBASE}/fromftp/CHECKSUM.SHA256 | \
				while read pkg; do
				[ ${pkg} = "install.sh" ] && continue
				# Let's retry at least one time
				fetch_file ${JAILBASE}/fromftp/ ${URL}/${dist}/${pkg}
			done
		done

		msg "Extracting sets:"
		for SETS in ${JAILBASE}/fromftp/*.aa; do
			SET=`basename $SETS .aa`
			echo -e "\t- $SET...\c"
			case ${SET} in
				s*)
					APPEND="usr/src"
					;;
				*)
					APPEND=""
					;;
			esac
			cat ${JAILBASE}/fromftp/${SET}.* | \
				tar --unlink -xpf - -C ${JAILBASE}/${APPEND} || err 1 " Fail" && echo " done"
		done
	else
		URL="${FREEBSD_BASE}/pub/FreeBSD/releases/${ARCH}/${VERSION}"
		DISTS="base.txz src.txz"
		[ ${ARCH} = "amd64" ] && DISTS="${DISTS} lib32.txz"
		for dist in ${DISTS}; do
			msg "Fetching ${dist} for FreeBSD ${VERSION} ${ARCH}"
			fetch_file ${JAILBASE}/fromftp/${dist} ${URL}/${dist}
			msg_n "Extracting ${dist}..."
			tar -xpf ${JAILBASE}/fromftp/${dist} -C  ${JAILBASE}/ || err 1 " fail" && echo " done"
		done
	fi

	msg_n "Cleaning up..."
	rm -rf ${JAILBASE}/fromftp/
	echo " done"
}

create_jail() {
	jail_exists ${JAILNAME} && err 2 "The jail ${JAILNAME} already exists"

	test -z ${VERSION} && usage

	if [ -z ${JAILBASE} ]; then
		[ -z ${BASEFS} ] && err 1 "Please provide a BASEFS variable in your poudriere.conf"
		JAILBASE=${BASEFS}/jails/${JAILNAME}
	fi

	if [ -z ${FS} ] ; then
		[ -z ${ZPOOL} ] && err 1 "Please provide a ZPOOL variable in your poudriere.conf"
		FS=${ZPOOL}/poudriere/${JAILNAME}
	fi

	case ${METHOD} in
	ftp)
		FCT=install_from_ftp
		;;
	svn)
		SVN=`which svn`
		test -z ${SVN} && err 1 "You need svn on your host to use svn method"
		FCT=install_from_svn
		;;
	csup)
		FCT=install_from_csup
		;;
	*)
		err 2 "Unknown method to create the jail"
		;;
	esac

	jail_create_zfs ${JAILNAME} ${VERSION} ${ARCH} ${JAILBASE} ${FS}
	RELEASE=${VERSION}
	${FCT}

	OSVERSION=`awk '/\#define __FreeBSD_version/ { print $3 }' ${JAILBASE}/usr/include/sys/param.h`
	LOGIN_ENV=",UNAME_r=${VERSION},UNAME_v=FreeBSD ${VERSION},OSVERSION=${OSVERSION}"

	if [ "${ARCH}" = "i386" -a "${REALARCH}" = "amd64" ];then
		LOGIN_ENV="${LOGIN_ENV},UNAME_p=i386,UNAME_m=i386"
		cat > ${JAILBASE}/etc/make.conf << EOF
ARCH=i386
MACHINE=i386
MACHINE_ARCH=i386
EOF

	fi

	sed -i .back -e "s/:\(setenv.*\):/:\1${LOGIN_ENV}:/" ${JAILBASE}/etc/login.conf
	cap_mkdb ${JAILBASE}/etc/login.conf
	pwd_mkdb -d ${JAILBASE}/etc/ -p ${JAILBASE}/etc/master.passwd

	cat >> ${JAILBASE}/etc/make.conf << EOF
USE_PACKAGE_DEPENDS=yes
BATCH=yes
PACKAGE_BUILDING=yes
WRKDIRPREFIX=/wrkdirs
EOF

	mkdir -p ${JAILBASE}/usr/ports
	mkdir -p ${JAILBASE}/wrkdirs
	mkdir -p ${POUDRIERE_DATA}/logs

	jail -U root -c path=${JAILBASE} command=/sbin/ldconfig -m /lib /usr/lib /usr/lib/compat
#	chroot -u root ${JAILBASE} /sbin/ldconfig  -m /lib /usr/lib /usr/lib/compat

	zfs snapshot ${FS}@clean
	msg "Jail ${JAILNAME} ${VERSION} ${ARCH} is ready to be used"
}

ARCH=`uname -m`
REALARCH=${ARCH}
START=0
STOP=0
LIST=0
DELETE=0
CREATE=0
QUIET=0
INFO=0
UPDATE=0

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh

while getopts "j:v:a:z:m:n:f:M:sdklqciu" FLAG; do
	case "${FLAG}" in
		j)
			JAILNAME=${OPTARG}
			;;
		v)
			VERSION=${OPTARG}
			;;
		a)
			if [ "${REALARCH}" != "amd64" -a "${REALARCH}" != ${OPTARG} ]; then
				err 1 "Only amd64 host can choose another architecture"
			fi
			ARCH=${OPTARG}
			;;
		m)
			METHOD=${OPTARG}
			;;
		f)
			FS=${OPTARG}
			;;
		M)
			JAILBASE=${OPTARG}
			;;
		s)
			START=1
			;;
		k)
			STOP=1
			;;
		l)
			LIST=1
			;;
		c)
			CREATE=1
			;;
		d)
			DELETE=1
			;;
		q)
			QUIET=1
			;;
		i)
			INFO=1
			;;
		u)
			UPDATE=1
			;;
		*)
			usage
			;;
	esac
done

METHOD=${METHOD:-ftp}

[ $(( CREATE + LIST + STOP + START + DELETE + INFO + UPDATE )) -lt 1 ] && usage

case "${CREATE}${LIST}${STOP}${START}${DELETE}${INFO}${UPDATE}" in
	1000000)
		create_jail
		;;
	0100000)
		list_jail
		;;
	0010000)
		jail_stop ${JAILNAME}
		;;
	0001000)
		export SET_STATUS_ON_START=0
		jail_start ${JAILNAME}
		;;
	0000100)
		delete_jail
		;;
	0000010)
		info_jail ${JAILNAME}
		;;
	0000001)
		update_jail ${JAILNAME}
		;;
esac
