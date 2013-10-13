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
    -s            -- Start a jail (chroot)
    -u            -- Update a jail

Options:
    -q            -- Quiet (Do not print the header)
    -J n          -- Run buildworld in parallel with n jobs.
    -j jailname   -- Specify the jailname
    -v version    -- Specify which version of DragonFly we want in jail
                     e.g. "3.4", "3.6", or "master"
    -M mountpoint -- Mountpoint
    -Q quickworld -- when used with -u jail is incrementally updated
    -m method     -- when used with -c forces the method to use by default
                     "git" to build world from source.  There are no other
                     method options at this time.
    -P patch      -- Specify a patch to apply to the source before building.
    -t version    -- Version of DragonFly to upgrade the jail to.

Options for -s:
    -p tree       -- Specify which ports tree the jail to start/stop with.
    -z set        -- Specify which SET the jail to start/stop with.
EOF
	exit 1
}

list_jail() {
	local format
	local j name version arch method mnt mntx hack

	format='%-20s %-13s %-17s %-7s %-7s %s\n'
	[ ${QUIET} -eq 0 ] &&
		printf "${format}" "JAILNAME" "VERSION" "LAST-UPDATED" "ARCH" "METHOD" "PATH"
	[ -d ${POUDRIERED}/jails ] || return 0
	for j in $(find ${POUDRIERED}/jails -type d -maxdepth 1 -mindepth 1 -print); do
		name=${j##*/}
		version=$(jget ${name} version)
		arch=$(jget ${name} arch)
		method=$(jget ${name} method)
		hack=$(jget ${name} timestamp)
		mntx=$(jget ${name} mnt)
		case ${mntx} in
		    ${BASEFS}/*)
		    	mnt=BASEFS${mntx#${BASEFS}}
			;;
		    *)
			mnt=${mntx}
			;;
		esac
		printf "${format}" "${name}" "${version}" "${hack}" "${arch}" "${method}" "${mnt}"
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
QUICK=0
METHOD=git
PTNAME=default
SETNAME=""

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh
. ${SCRIPTPREFIX}/jail.sh.${BSDPLATFORM}

TMPFS_ALL=0

while getopts "J:j:v:z:m:n:M:sdlqcip:ut:z:P:Q" FLAG; do
	case "${FLAG}" in
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
			# Option masked on DF
			ARCH=${OPTARG}
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
			# Option masked on DF
			JAILFS=${OPTARG}
			;;
		M)
			JAILMNT=${OPTARG}
			;;
		Q)
			QUICK=1
			;;
		s)
			START=1
			;;
		k)
			# Option masked on DF
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

if [ -n "${JAILNAME}" -a ${CREATE} -eq 0 ]; then
	ARCH=$(jget ${JAILNAME} arch)
	JAILFS=$(jget ${JAILNAME} fs)
	JAILMNT=$(jget ${JAILNAME} mnt)
fi

check_jobs
case "${CREATE}${LIST}${STOP}${START}${DELETE}${UPDATE}" in
	100000)
		test -z ${JAILNAME} && usage
		create_jail
		;;
	010000)
		list_jail
		;;
	001000)
		# -k stop option not supported on DF
		;;
	000100)
		test -z ${JAILNAME} && usage
		porttree_exists ${PTNAME} || err 2 "No such ports tree ${PTNAME}"
		start_a_jail
		;;
	000010)
		test -z ${JAILNAME} && usage
		delete_jail
		;;
	000001)
		test -z ${JAILNAME} && usage
		update_jail ${QUICK}
		;;
	*)
		usage
		;;
esac
