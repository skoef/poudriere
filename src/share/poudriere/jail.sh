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
    -l            -- List all available jails
    -u            -- Update a jail
    -C            -- Cleanup jail mounts (contingency cleanup)

Options:
    -q            -- Quiet (Do not print the header)
    -J n          -- Run buildworld in parallel with n jobs.
    -j jailname   -- Specify the jailname
    -v version    -- Specify which version of DragonFly we want in jail
                     e.g. \"3.4\", \"3.6\", or \"master\"
    -M mountpoint -- Mountpoint
    -Q quickworld -- when used with -u jail is incrementally updated
    -m method     -- when used with -c forces the method to use by default
                     \"git\" to build world from source.  There are no other
                     method options at this time.
    -p tree       -- Specify which ports tree the jail to start/stop with
    -P patch      -- Specify a patch file to apply to the source before committing.
    -t version    -- version of DragonFly to upgrade the jail to.
EOF
	exit 1
}

list_jail() {
	local format
	local j name version arch method mnt

	format='%-20s %-20s %-7s %-7s %s\n'
	[ ${QUIET} -eq 0 ] &&
		printf "${format}" "JAILNAME" "VERSION" "ARCH" "METHOD" "PATH"
	for j in $(find ${POUDRIERED}/jails -type d -maxdepth 1 -mindepth 1 -print); do
		name=${j##*/}
		version=$(jget ${name} version)
		arch=$(jget ${name} arch)
		method=$(jget ${name} method)
		mnt=$(jget ${name} mnt)
		printf "${format}" "${name}" "${version}" "${arch}" "${method}" "${mnt}"
	done
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

	osversion=`awk '/\#define __DragonFly_version/ { print $3 }' ${JAILMNT}/usr/include/sys/param.h`
	login_env=",UNAME_r=${release% *},UNAME_v=DragonFly ${release},OSVERSION=${osversion}"

	sed -i "" -e "s/,UNAME_r.*:/:/ ; s/:\(setenv.*\):/:\1${login_env}:/" ${JAILMNT}/etc/login.conf
	cap_mkdb ${JAILMNT}/etc/login.conf
}

update_jail() {
	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	jail_runs ${JAILNAME} &&
		err 1 "Unable to update jail ${JAILNAME}: it is running"

while getopts "J:j:v:z:m:n:M:Cdlqci:ut:P:" FLAG; do
	case "${FLAG}" in
		j)
			JAILNAME=${OPTARG}
			;;
		J)
			JOB_OVERRIDE=${OPTARG}
			;;
		v)
			VERSION=${OPTARG}
			;;
		a)
			# Force it to stay on host's arch
			case "${ARCH}" in
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
		f)
			JAILFS=${OPTARG}
			;;
		C)
			DISMOUNT=1
			;;
		M)
			JAILMNT=${OPTARG}
			;;
		Q)
			QUICK=1
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
		t)
			TORELEASE=${OPTARG}
			;;
		*)
			usage
			;;
	esac
done

if [ -n "${JAILNAME}" -a ${CREATE} -eq 0 ]; then
	ARCH=$(jget ${JAILNAME} arch)
	JAILFS=$(jget ${JAILNAME} fs)
	JAILMNT=$(jget ${JAILNAME} mnt)
fi

if [ "${JOB_OVERRIDE}" = "0" ]; then
	PARALLEL_JOBS=$(sysctl -n hw.ncpu)
else
	PARALLEL_JOBS=${JOB_OVERRIDE}
fi

case "${CREATE}${LIST}${INFO}${DISMOUNT}${DELETE}${UPDATE}" in
	100000)
		test -z ${JAILNAME} && usage
		create_jail
		;;
	010000)
		list_jail
		;;
	001000)
		test -z ${JAILNAME} && usage
		info_jail
		;;
	000100)
		test -z ${JAILNAME} && usage
		jail_dismount
		;;
	000010)
		test -z ${JAILNAME} && usage
		delete_jail
		;;
	000001)
		test -z ${JAILNAME} && usage
		update_jail
		;;
	*)
		usage
		;;
esac
