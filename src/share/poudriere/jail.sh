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
	echo "poudriere jail [parameters] [options]

Parameters:
    -c            -- create a jail
    -d            -- delete a jail
    -l            -- list all available jails
    -u            -- update a jail
    -C            -- Cleanup jail mounts (contingency cleanup)

Options:
    -q            -- quiet (Do not print the header)
    -J n          -- Run buildworld in parallel with n jobs.
    -j jailname   -- Specifies the jailname
    -v version    -- Specifies which version of DragonFly we want in jail
                     e.g. \"3.4\", \"3.6\", or \"master\"
    -a arch       -- Does nothing - set to be same as host
    -f fs         -- FS name (\$BASEFS/worlds/myjail)
    -M mountpoint -- mountpoint
    -Q quickworld -- when used with -u jail is incrementally updated
    -m method     -- when used with -c forces the method to use by default
                     \"git\" to build world from source.  There are no other
                     method options at this time.
    -p tree       -- Specify which ports tree the jail to start/stop with
    -P patch      -- Specify a patch file to apply to the source before committing.
    -t version    -- version to upgrade to"
	exit 1
}

list_jail() {
	[ ${QUIET} -eq 0 ] &&
		printf '%-20s %-20s %-7s %-7s\n' "JAILNAME" "VERSION" "ARCH" "METHOD"
	for j in $(find ${POUDRIERED}/jails -type d -maxdepth 1 -mindepth 1 -print); do
		name=${j##*/}
		version=$(jget ${name} version)
		arch=$(jget ${name} arch)
		method=$(jget ${name} method)
		printf '%-20s %-20s %-7s %-7s\n' "${name}" "${version}" "${arch}" "${method}"
	done
}

cleanup_new_jail() {
	msg "Error while creating jail, cleaning up." >&2
	delete_jail
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
DISMOUNT=0
METHOD=git
JOB_OVERRIDE="0"
PTNAME=default
SETNAME=""

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
. ${SCRIPTPREFIX}/common.sh
. ${SCRIPTPREFIX}/jail.sh.${BSDPLATFORM}

while getopts "J:j:v:a:z:m:n:f:M:Cdlqcip:iut:z:P:Q" FLAG; do
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

case "${CREATE}${LIST}${DELETE}${UPDATE}${INFO}${DISMOUNT}" in
	10000)
		test -z ${JAILNAME} && usage
		create_jail
		;;
	01000)
		list_jail
		;;
	00100)
		test -z ${JAILNAME} && usage
		delete_jail
		;;
	00010)
		test -z ${JAILNAME} && usage
		update_jail
		;;
	00001)
		test -z ${JAILNAME} && usage
		jail_dismount
		;;
	*)
		usage
		;;
esac
