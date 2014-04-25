#!/bin/sh
# 
# Copyright (c) 2010-2013 Baptiste Daroussin <bapt@FreeBSD.org>
# Copyright (c) 2012-2013 Bryan Drewery <bdrewery@FreeBSD.org>
# All rights reserved.
# 
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
# 
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

usage() {
	cat << EOF
poudriere jail [parameters] [options]

Parameters:
    -c            -- Create a jail
    -d            -- Delete a jail
    -i            -- Show information about a jail
    -l            -- List all available jails
    -s            -- Start a jail
    -k            -- Stop a jail
    -u            -- Update a jail
    -r newname    -- Rename a jail

Options:
    -q            -- Quiet (Do not print the header)
    -n            -- Print only jail name (for use with -l)
    -J n          -- Run buildworld in parallel with n jobs.
    -j jailname   -- Specify the jailname
    -v version    -- Specify which version of FreeBSD to install in the jail.
    -a arch       -- Indicates the architecture of the jail: i386 or amd64
                     (Default: same as the host)
    -f fs         -- FS name (tank/jails/myjail) if fs is "none" then do not
                     create on ZFS.
    -M mountpoint -- Mountpoint
    -m method     -- When used with -c, overrides the default method (ftp).
                     Could also be "http", "svn", "svn+http",
                     "svn+https", "svn+file", "svn+ssh", "csup".
                     Please note that with the svn and csup methods the world
                     will be built. Note that building from sources can use
                     src.conf and jailname-src.conf in
                     /usr/local/etc/poudriere.d/.  Other possible method are:
                     "allbsd" (Retrieve a snapshot from allbsd.org's website)
                     or "ftp-archive" (Retrieve an old release that is no
                     longer available on "ftp").
    -P patch      -- Specify a patch to apply to the source before building.
    -t version    -- Version of FreeBSD to upgrade the jail to.

Options for -s and -k:
    -p tree       -- Specify which ports tree the jail to start/stop with.
    -z set        -- Specify which SET the jail to start/stop with.
EOF
	exit 1
}

list_jail() {
	local format
	local j name version arch method mnt timestamp time

	format='%-20s %-20s %-7s %-9s %-20s %s\n'
	if [ ${QUIET} -eq 0 ]; then
		if [ ${NAMEONLY} -eq 0 ]; then
			printf "${format}" "JAILNAME" "VERSION" "ARCH" \
			    "METHOD" "TIMESTAMP" "PATH"
		else
			echo JAILNAME
		fi
	fi
	[ -d ${POUDRIERED}/jails ] || return 0
	for j in $(find ${POUDRIERED}/jails -type d -maxdepth 1 -mindepth 1 -print); do
		name=${j##*/}
		if [ ${NAMEONLY} -eq 0 ]; then
			version=$(jget ${name} version)
			arch=$(jget ${name} arch)
			method=$(jget ${name} method)
			mnt=$(jget ${name} mnt)
			timestamp=$(jget ${name} timestamp 2>/dev/null || :)
			time=
			[ -n "${timestamp}" ] && \
			    time="$(date -j -r ${timestamp} "+%Y-%m-%d %H:%M:%S")"
			printf "${format}" "${name}" "${version}" "${arch}" \
			    "${method}" "${time}" "${mnt}"
		else
			echo ${name}
		fi
	done
}

delete_jail() {
	test -z ${JAILNAME} && usage
	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	jail_runs ${JAILNAME} &&
		err 1 "Unable to delete jail ${JAILNAME}: it is running"
	msg_n "Removing ${JAILNAME} jail..."
	TMPFS_ALL=0 destroyfs ${JAILMNT} jail
	rm -rf ${POUDRIERED}/jails/${JAILNAME} || :
	echo " done"
}

cleanup_new_jail() {
	msg "Error while creating jail, cleaning up." >&2
	delete_jail
}

# Lookup new version from newvers and set in jset version
update_version() {
	local version_extra="$1"

	eval `grep "^[RB][A-Z]*=" ${JAILMNT}/usr/src/sys/conf/newvers.sh `
	RELEASE=${REVISION}-${BRANCH}
	[ -n "${version_extra}" ] &&
	    RELEASE="${RELEASE} ${version_extra}"
	jset ${JAILNAME} version "${RELEASE}"
	echo "${RELEASE}"
}

# Set specified version into login.conf
update_version_env() {
	local release="$1"
	local login_env osversion

	osversion=`awk '/\#define __FreeBSD_version/ { print $3 }' ${JAILMNT}/usr/include/sys/param.h`
	login_env=",UNAME_r=${release% *},UNAME_v=FreeBSD ${release},OSVERSION=${osversion}"

	[ "${ARCH}" = "i386" -a "${REALARCH}" = "amd64" ] &&
		login_env="${login_env},UNAME_p=i386,UNAME_m=i386"

	sed -i "" -e "s/,UNAME_r.*:/:/ ; s/:\(setenv.*\):/:\1${login_env}:/" ${JAILMNT}/etc/login.conf
	cap_mkdb ${JAILMNT}/etc/login.conf
}

rename_jail() {
	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	msg_n "Renaming '${JAILNAME}' in '${NEWJAILNAME}'"
	mv ${POUDRIERED}/jails/${JAILNAME} ${POUDRIERED}/jail/${NEWJAILNAME}
	echo " done"
}

update_jail() {
	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	jail_runs ${JAILNAME} &&
		err 1 "Unable to update jail ${JAILNAME}: it is running"

	METHOD=$(jget ${JAILNAME} method)
	if [ -z "${METHOD}" -o "${METHOD}" = "-" ]; then
		METHOD="ftp"
		jset ${JAILNAME} method ${METHOD}
	fi
	msg "Upgrading using ${METHOD}"
	case ${METHOD} in
	ftp|http|ftp-archive)
		MASTERMNT=${JAILMNT}
		MASTERNAME=${JAILNAME}
		[ -n "${RESOLV_CONF}" ] && cp -v "${RESOLV_CONF}" "${JAILMNT}/etc/"
		do_jail_mounts ${JAILMNT} ${ARCH}
		JNETNAME="n"
		if [ -z "${TORELEASE}" ]; then
			injail env PAGER=/bin/cat /usr/sbin/freebsd-update fetch install
		else
			# Install new kernel
			injail env PAGER=/bin/cat /usr/sbin/freebsd-update -r ${TORELEASE} upgrade install ||
				err 1 "Fail to upgrade system"
			# Reboot
			update_version_env ${TORELEASE}
			# Install new world
			injail env PAGER=/bin/cat /usr/sbin/freebsd-update install ||
				err 1 "Fail to upgrade system"
			# Reboot
			update_version_env ${TORELEASE}
			# Remove stale files
			injail env PAGER=/bin/cat /usr/sbin/freebsd-update install || :
			jset ${JAILNAME} version ${TORELEASE}
		fi
		jstop
		umountfs ${JAILMNT} 1
		update_version
		[ -n "${RESOLV_CONF}" ] && rm -f ${JAILMNT}/etc/resolv.conf
		update_version_env $(jget ${JAILNAME} version)
		markfs clean ${JAILMNT}
		;;
	csup)
		msg "csup has been deprecated by FreeBSD. Only use if you are syncing with your own csup repo."
		install_from_csup
		update_version_env $(jget ${JAILNAME} version)
		make -C ${JAILMNT}/usr/src delete-old delete-old-libs DESTDIR=${JAILMNT} BATCH_DELETE_OLD_FILES=yes
		markfs clean ${JAILMNT}
		;;
	svn*)
		install_from_svn version_extra
		RELEASE=$(update_version "${version_extra}")
		update_version_env "${RELEASE}"
		make -C ${JAILMNT}/usr/src delete-old delete-old-libs DESTDIR=${JAILMNT} BATCH_DELETE_OLD_FILES=yes
		markfs clean ${JAILMNT}
		;;
	allbsd|gjb|url=*)
		[ -z "${VERSION}" ] && VERSION=$(jget ${JAILNAME} version)
		[ -z "${ARCH}" ] && ARCH=$(jget ${JAILNAME} arch)
		delete_jail
		create_jail
		;;
	*)
		err 1 "Unsupported method"
		;;
	esac
	jset ${JAILNAME} timestamp $(date +%s)
}

build_and_install_world() {
	case "${ARCH}" in
	mips64)
		export TARGET=mips
		;;
	armv6)
		export TARGET=arm
		;;
	esac
	export TARGET_ARCH=${ARCH}
	export SRC_BASE=${JAILMNT}/usr/src
	mkdir -p ${JAILMNT}/etc
	[ -f ${JAILMNT}/etc/src.conf ] && rm -f ${JAILMNT}/etc/src.conf
	touch ${JAILMNT}/etc/src.conf
	[ -f ${POUDRIERED}/src.conf ] && cat ${POUDRIERED}/src.conf > ${JAILMNT}/etc/src.conf
	[ -f ${POUDRIERED}/${JAILNAME}-src.conf ] && cat ${POUDRIERED}/${JAILNAME}-src.conf >> ${JAILMNT}/etc/src.conf
	unset MAKEOBJPREFIX
	export __MAKE_CONF=/dev/null
	export SRCCONF=${JAILMNT}/etc/src.conf
	MAKE_JOBS="-j${PARALLEL_JOBS}"

	fbsdver=$(awk '/^\#define[[:blank:]]__FreeBSD_version/ {print $3}' ${JAILMNT}/usr/src/sys/sys/param.h)
	hostver=$(sysctl -n kern.osreldate)
	make_cmd=make
	if [ ${hostver} -gt 1000000 -a ${fbsdver} -lt 1000000 ]; then
		FMAKE=$(which fmake 2>/dev/null)
		[ -n "${FMAKE}" ] ||
			err 1 "You need fmake installed on the host: devel/fmake"
		make_cmd=${FMAKE}
	fi

	# Don't enable CCACHE for 10, there are still obscure clang and ld
	# issues
	if [ ${fbsdver} -lt 1000000 ]; then
		: ${CCACHE_PATH:="/usr/local/libexec/ccache"}
		if [ -n "${CCACHE_DIR}" -a -d ${CCACHE_PATH}/world ]; then
			export CCACHE_DIR
			export CC="${CCACHE_PATH}/world/cc"
			export CXX="${CCACHE_PATH}/world/c++"
			unset CCACHE_TEMPDIR
		fi
	fi

	msg "Starting make buildworld with ${PARALLEL_JOBS} jobs"
	${make_cmd} -C ${JAILMNT}/usr/src buildworld ${MAKE_JOBS} \
	    ${MAKEWORLDARGS} || err 1 "Failed to 'make buildworld'"
	msg "Starting make installworld"
	${make_cmd} -C ${JAILMNT}/usr/src installworld DESTDIR=${JAILMNT} \
	    DB_FROM_SRC=1 || err 1 "Failed to 'make installworld'"
	${make_cmd} -C ${JAILMNT}/usr/src DESTDIR=${JAILMNT} DB_FROM_SRC=1 \
	    distrib-dirs || err 1 "Failed to 'make distrib-dirs'"
	${make_cmd} -C ${JAILMNT}/usr/src DESTDIR=${JAILMNT} distribution ||
	    err 1 "Failed to 'make distribution'"

	case "${ARCH}" in
	mips)
		cp `which qemu-mips` ${JAILMNT}/usr/bin/qemu-mips
		;;
	mips64)
		cp `which qemu-mips64` ${JAILMNT}/usr/bin/qemu-mips64
		;;
	armv6)
		cp `which qemu-arm` ${JAILMNT}/usr/bin/qemu-arm
		;;
	esac
}

install_from_svn() {
	local var_version_extra="$1"
	local UPDATE=0
	local proto
	local svn_rev

	[ -d ${JAILMNT}/usr/src ] && UPDATE=1
	mkdir -p ${JAILMNT}/usr/src
	case ${METHOD} in
	svn+http) proto="http" ;;
	svn+https) proto="https" ;;
	svn+ssh) proto="svn+ssh" ;;
	svn+file) proto="file" ;;
	svn) proto="svn" ;;
	esac
	if [ ${UPDATE} -eq 0 ]; then
		msg_n "Checking out the sources from svn..."
		${SVN_CMD} -q co ${proto}://${SVN_HOST}/base/${VERSION} ${JAILMNT}/usr/src || err 1 " fail"
		echo " done"
		if [ -n "${SRCPATCHFILE}" ]; then
			msg_n "Patching the sources with ${SRCPATCHFILE}"
			${SVN_CMD} -q patch ${SRCPATCHFILE} ${JAILMNT}/usr/src || err 1 " fail"
			echo done
		fi
	else
		msg_n "Updating the sources from svn..."
		${SVN_CMD} upgrade ${JAILMNT}/usr/src 2>/dev/null || :
		${SVN_CMD} -q update -r ${TORELEASE:-head} ${JAILMNT}/usr/src || err 1 " fail"
		echo " done"
	fi
	build_and_install_world

	svn_rev=$(${SVN_CMD} info ${JAILMNT}/usr/src |
	    awk '/Last Changed Rev:/ {print $4}')
	setvar "${var_version_extra}" "r${svn_rev}"
}

install_from_csup() {
	local var_version_extra="$1"
	local UPDATE=0
	[ -d ${JAILMNT}/usr/src ] && UPDATE=1
	mkdir -p ${JAILMNT}/etc
	mkdir -p ${JAILMNT}/var/db
	mkdir -p ${JAILMNT}/usr
	[ -z ${CSUP_HOST} ] && err 2 "CSUP_HOST has to be defined in the configuration to use csup"
	if [ "${UPDATE}" -eq 0 ]; then
		echo "*default base=${JAILMNT}/var/db
*default prefix=${JAILMNT}/usr
*default release=cvs tag=${VERSION}
*default delete use-rel-suffix
src-all" > ${JAILMNT}/etc/supfile
	fi
	csup -z -h ${CSUP_HOST} ${JAILMNT}/etc/supfile || err 1 "Fail to fetch sources"
	build_and_install_world
}

install_from_ftp() {
	local var_version_extra="$1"
	mkdir ${JAILMNT}/fromftp
	local URL V

	V=${ALLBSDVER:-${VERSION}}
	case $V in
	[0-4].*) HASH=MD5 ;;
	5.[0-4]*) HASH=MD5 ;;
	*) HASH=SHA256 ;;
	esac
	if [ ${V%%.*} -lt 9 ]; then
		msg "Fetching sets for FreeBSD ${V} ${ARCH}"
		case ${METHOD} in
		ftp|http|gjb)
			case ${VERSION} in
				*-PRERELEASE|*-STABLE) type=snapshots ;;
				*) type=releases ;;
			esac

			# Check that the defaults have been changed
			echo ${FREEBSD_HOST} | egrep -E "(_PROTO_|_CHANGE_THIS_)" > /dev/null
			if [ $? -eq 0 ]; then
				msg "FREEBSD_HOST from config invalid; defaulting to http://ftp.freebsd.org"
				FREEBSD_HOST="http://ftp.freebsd.org"
			fi
			URL="${FREEBSD_HOST}/pub/FreeBSD/${type}/${ARCH}/${V}" ;;
		url=*) URL=${METHOD##url=} ;;
		allbsd) URL="https://pub.allbsd.org/FreeBSD-snapshots/${ARCH}-${ARCH}/${V}-JPSNAP/ftp" ;;
		ftp-archive) URL="ftp://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/${ARCH}/${V}" ;;
		esac
		DISTS="base dict src games"
		[ ${ARCH} = "amd64" ] && DISTS="${DISTS} lib32"
		for dist in ${DISTS}; do
			fetch_file ${JAILMNT}/fromftp/ ${URL}/$dist/CHECKSUM.${HASH} ||
				err 1 "Fail to fetch checksum file"
			sed -n "s/.*(\(.*\...\)).*/\1/p" \
				${JAILMNT}/fromftp/CHECKSUM.${HASH} | \
				while read pkg; do
				[ ${pkg} = "install.sh" ] && continue
				# Let's retry at least one time
				fetch_file ${JAILMNT}/fromftp/ ${URL}/${dist}/${pkg}
			done
		done

		msg "Extracting sets:"
		for SETS in ${JAILMNT}/fromftp/*.aa; do
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
			(cat ${JAILMNT}/fromftp/${SET}.* || echo Error) | \
				tar --unlink -xpf - -C ${JAILMNT}/${APPEND} || err 1 " fail"
			echo " done"
		done
	else
		local type
		case ${METHOD} in
			ftp|http|gjb)
				case ${VERSION} in
					*-CURRENT|*-PRERELEASE|*-STABLE) type=snapshots ;;
					*) type=releases ;;
				esac

				# Check that the defaults have been changed
				echo ${FREEBSD_HOST} | egrep -E "(_PROTO_|_CHANGE_THIS_)" > /dev/null
				if [ $? -eq 0 ]; then
					msg "FREEBSD_HOST from config invalid; defaulting to http://ftp.freebsd.org"
					FREEBSD_HOST="http://ftp.freebsd.org"
				fi

				URL="${FREEBSD_HOST}/pub/FreeBSD/${type}/${ARCH}/${ARCH}/${V}"
				;;
			allbsd) URL="https://pub.allbsd.org/FreeBSD-snapshots/${ARCH}-${ARCH}/${V}-JPSNAP/ftp" ;;
			ftp-archive) URL="ftp://ftp-archive.freebsd.org/pub/FreeBSD-Archive/old-releases/${ARCH}/${V}" ;;
			url=*) URL=${METHOD##url=} ;;
		esac
		DISTS="base.txz src.txz games.txz"
		[ ${ARCH} = "amd64" ] && DISTS="${DISTS} lib32.txz"
		for dist in ${DISTS}; do
			msg "Fetching ${dist} for FreeBSD ${V} ${ARCH}"
			fetch_file ${JAILMNT}/fromftp/${dist} ${URL}/${dist}
			msg_n "Extracting ${dist}..."
			tar -xpf ${JAILMNT}/fromftp/${dist} -C  ${JAILMNT}/ || err 1 " fail"
			echo " done"
		done
	fi

	msg_n "Cleaning up..."
	rm -rf ${JAILMNT}/fromftp/
	echo " done"
}

create_jail() {
	jail_exists ${JAILNAME} && err 2 "The jail ${JAILNAME} already exists"

	test -z ${VERSION} && usage

	[ "${JAILNAME#*.*}" = "${JAILNAME}" ] ||
		err 1 "The jailname can not contain a period (.). See jail(8)"

	if [ -z ${JAILMNT} ]; then
		[ -z ${BASEFS} ] && err 1 "Please provide a BASEFS variable in your poudriere.conf"
		JAILMNT=${BASEFS}/jails/${JAILNAME}
	fi

	if [ -z "${JAILFS}" -a -z "${NO_ZFS}" ]; then
		[ -z ${ZPOOL} ] && err 1 "Please provide a ZPOOL variable in your poudriere.conf"
		JAILFS=${ZPOOL}${ZROOTFS}/jails/${JAILNAME}
	fi

	case ${METHOD} in
	ftp|http|gjb|ftp-archive|url=*)
		FCT=install_from_ftp
		;;
	allbsd)
		FCT=install_from_ftp
		ALLBSDVER=`fetch -qo - \
			https://pub.allbsd.org/FreeBSD-snapshots/${ARCH}-${ARCH}/ | \
			sed -n "s,.*href=\"\(.*${VERSION}.*\)-JPSNAP/\".*,\1,p" | \
			sort -k 3 -t - -r | head -n 1 `
		[ -z ${ALLBSDVER} ] && err 1 "Unknown version $VERSION"

		OIFS=${IFS}
		IFS=-
		set -- ${ALLBSDVER}
		IFS=${OIFS}
		RELEASE="${ALLBSDVER}-JPSNAP/ftp"
		;;
	svn*)
		test -z "${SVN_CMD}" && err 1 "You need svn on your host to use svn method"
		case ${VERSION} in
			stable/*![0-9]*)
				err 1 "bad version number for stable version"
				;;
			head@*![0-9]*)
				err 1 "bad revision number for head version"
				;;
			release/*![0-9]*.[0-9].[0-9])
				err 1 "bad version number for release version"
				;;
			releng/*![0-9]*.[0-9])
				err 1 "bad version number for releng version"
				;;
			stable/*|head*|release/*|releng/*.[0-9]) ;;
			*)
				err 1 "version with svn should be: head[@rev], stable/N, release/N or releng/N"
				;;
		esac
		FCT=install_from_svn
		;;
	csup)
		case ${VERSION} in
			.)
				;;
			RELENG_*![0-9]*_[0-9])
				err 1 "bad version number for RELENG"
				;;
			RELENG_*![0-9]*)
				err 1 "bad version number for RELENG"
				;;
			RELENG_*|.) ;;
			*)
				err 1 "version with csup should be: . or RELENG_N or RELEASE_N"
				;;
		esac
		msg "csup has been depreciated by FreeBSD. Only use if you are syncing with your own csup repo."
		FCT=install_from_csup
		;;
	*)
		err 2 "Unknown method to create the jail"
		;;
	esac

	createfs ${JAILNAME} ${JAILMNT} ${JAILFS:-none}
	[ -n "${JAILFS}" -a "${JAILFS}" != "none" ] && jset ${JAILNAME} fs ${JAILFS}
	jset ${JAILNAME} version ${VERSION}
	jset ${JAILNAME} timestamp $(date +%s)
	jset ${JAILNAME} arch ${ARCH}
	jset ${JAILNAME} mnt ${JAILMNT}

	# Wrap the jail creation in a special cleanup hook that will remove the jail
	# if any error is encountered
	CLEANUP_HOOK=cleanup_new_jail
	jset ${JAILNAME} method ${METHOD}
	${FCT} version_extra

	RELEASE=$(update_version "${version_extra}")
	update_version_env "${RELEASE}"

	if [ "${ARCH}" = "i386" -a "${REALARCH}" = "amd64" ]; then
		cat > ${JAILMNT}/etc/make.conf << EOF
ARCH=i386
MACHINE=i386
MACHINE_ARCH=i386
EOF

	fi

	pwd_mkdb -d ${JAILMNT}/etc/ -p ${JAILMNT}/etc/master.passwd

	cat >> ${JAILMNT}/etc/make.conf << EOF
USE_PACKAGE_DEPENDS=yes
BATCH=yes
WRKDIRPREFIX=/wrkdirs
EOF

	mkdir -p ${JAILMNT}/usr/ports
	mkdir -p ${JAILMNT}/wrkdirs
	mkdir -p ${POUDRIERE_DATA}/logs

	jail -U root -c path=${JAILMNT} command=/sbin/ldconfig -m /lib /usr/lib /usr/lib/compat

	markfs clean ${JAILMNT}
	unset CLEANUP_HOOK
	msg "Jail ${JAILNAME} ${VERSION} ${ARCH} is ready to be used"
}

info_jail() {
	local nbb nbf nbi nbq nbs tobuild
	local building_started status log
	local elapsed elapsed_days elapsed_hms elapsed_timestamp
	local now start_time timestamp
	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	porttree_exists ${PTNAME} || err 1 "No such tree: ${PTNAME}"

	POUDRIERE_BUILD_TYPE=bulk
	BUILDNAME=latest

	log=$(log_path)
	now=$(date +%s)

	status=$(bget status 2>/dev/null || :)
	nbq=$(bget stats_queued 2>/dev/null || :)
	nbf=$(bget stats_failed 2>/dev/null || :)
	nbi=$(bget stats_ignored 2>/dev/null || :)
	nbs=$(bget stats_skipped 2>/dev/null || :)
	nbb=$(bget stats_built 2>/dev/null || :)
	tobuild=$((nbq - nbb - nbf - nbi - nbs))

	echo "Jail name:         ${JAILNAME}"
	echo "Jail version:      $(jget ${JAILNAME} version)"
	echo "Jail arch:         $(jget ${JAILNAME} arch)"
	echo "Jail acquired:     $(jget ${JAILNAME} method)"
	timestamp=$(jget ${JAILNAME} timestamp 2>/dev/null || :)
	if [ -n "${timestamp}" ]; then
		echo "Jail updated:      $(date -j -r ${timestamp} "+%Y-%m-%d %H:%M:%S")"
	fi
	echo "Tree name:         ${PTNAME}"
	echo "Tree acquired:     $(pget ${PTNAME} method)"
#	echo "Tree updated:      $(pget ${PTNAME} timestamp)"
	echo "Status:            ${status}"
	if calculate_elapsed ${now} ${log}; then
		start_time=${_start_time}
		elapsed=${_elapsed_time}
		building_started=$(date -j -r ${start_time} "+%Y-%m-%d %H:%M:%S")
		elapsed_days=$((elapsed/86400))
		elapsed_hms=$(date -j -u -r ${elapsed} "+%H:%M:%S")
		case ${elapsed_days} in
			0) elapsed_timestamp="${elapsed_hms}" ;;
			1) elapsed_timestamp="1 day, ${elapsed_hms}" ;;
			*) elapsed_timestamp="${elapsed_days} days, ${elapsed_hms}" ;;
		esac
		echo "Building started:  ${building_started}"
		echo "Elapsed time:      ${elapsed_timestamp}"
		echo "Packages built:    ${nbb}"
		echo "Packages failed:   ${nbf}"
		echo "Packages ignored:  ${nbi}"
		echo "Packages skipped:  ${nbs}"
		echo "Packages total:    ${nbq}"
		echo "Packages left:     ${tobuild}"
	fi

	unset POUDRIERE_BUILD_TYPE
}

ARCH=`uname -m`
REALARCH=${ARCH}
START=0
STOP=0
LIST=0
DELETE=0
CREATE=0
RENAME=0
QUIET=0
NAMEONLY=0
INFO=0
UPDATE=0
PTNAME=default
SETNAME=""

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh

while getopts "iJ:j:v:a:z:m:nf:M:sdklqcip:r:ut:z:P:" FLAG; do
	case "${FLAG}" in
		i)
			INFO=1
			;;
		j)
			JAILNAME=${OPTARG}
			;;
		J)
			PARALLEL_JOBS=${OPTARG}
			;;
		v)
			VERSION=${OPTARG}
			;;
		a)
			[ "${REALARCH}" != "amd64" -a "${REALARCH}" != ${OPTARG} ] &&
				err 1 "Only amd64 host can choose another architecture"
			ARCH=${OPTARG}
			case "${ARCH}" in
			mips)
				[ -x `which qemu-mips` ] || err 1 "You need qemu-mips installed on the host"
				;;
			mips64)
				[ -x `which qemu-mips64` ] || err 1 "You need qemu-mips64 installed on the host"
				;;
			armv6)
				[ -x `which qemu-arm` ] || err 1 "You need qemu-arm installed on the host"
				;;
			esac
			;;
		m)
			METHOD=${OPTARG}
			;;
		n)
			NAMEONLY=1
			;;
		f)
			JAILFS=${OPTARG}
			;;
		M)
			JAILMNT=${OPTARG}
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
		p)
			PTNAME=${OPTARG}
			;;
		P)
			[ -f ${OPTARG} ] || err 1 "No such patch"
			SRCPATCHFILE=${OPTARG}
			;;
		q)
			QUIET=1
			;;
		u)
			UPDATE=1
			;;
		r)
			RENAME=1;
			NEWJAILNAME=${OPTARG}
			;;
		t)
			TORELEASE=${OPTARG}
			;;
		z)
			[ -n "${OPTARG}" ] || err 1 "Empty set name"
			SETNAME="${OPTARG}"
			;;
		*)
			usage
			;;
	esac
done

saved_argv="$@"
shift $((OPTIND-1))

METHOD=${METHOD:-ftp}
if [ -n "${JAILNAME}" -a ${CREATE} -eq 0 ]; then
	ARCH=$(jget ${JAILNAME} arch)
	JAILFS=$(jget ${JAILNAME} fs 2>/dev/null || :)
	JAILMNT=$(jget ${JAILNAME} mnt)
fi

case "${CREATE}${INFO}${LIST}${STOP}${START}${DELETE}${UPDATE}${RENAME}" in
	10000000)
		test -z ${JAILNAME} && usage
		maybe_run_queued "${saved_argv}"
		create_jail
		;;
	01000000)
		test -z ${JAILNAME} && usage
		export MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
		export MASTERMNT=${POUDRIERE_DATA}/build/${MASTERNAME}/ref
		info_jail
		;;
	00100000)
		list_jail
		;;
	00010000)
		test -z ${JAILNAME} && usage
		porttree_exists ${PTNAME} || err 2 "No such ports tree ${PTNAME}"
		maybe_run_queued "${saved_argv}"
		export MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
		export MASTERMNT=${POUDRIERE_DATA}/build/${MASTERNAME}/ref
		jail_runs ${MASTERNAME} ||
		    msg "Jail ${MASTERNAME} not running, but cleaning up anyway"
		jail_stop
		;;
	00001000)
		export SET_STATUS_ON_START=0
		test -z ${JAILNAME} && usage
		porttree_exists ${PTNAME} || err 2 "No such ports tree ${PTNAME}"
		maybe_run_queued "${saved_argv}"
		export MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
		export MASTERMNT=${POUDRIERE_DATA}/build/${MASTERNAME}/ref
		jail_start ${JAILNAME} ${PTNAME} ${SETNAME}
		JNETNAME="n"
		;;
	00000100)
		test -z ${JAILNAME} && usage
		maybe_run_queued "${saved_argv}"
		delete_jail
		;;
	00000010)
		test -z ${JAILNAME} && usage
		maybe_run_queued "${saved_argv}"
		update_jail
		;;
	00000011)
		test -z ${JAILNAME} && usage
		maybe_run_queued "${saved_argv}"
		rename_jail
		;;
	*)
		usage
		;;
esac
