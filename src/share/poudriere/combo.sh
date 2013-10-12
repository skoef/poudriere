#!/bin/sh
# 
# Copyright (c) 2011-2013 Baptiste Daroussin <bapt@FreeBSD.org>
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
set -e

usage() {
	echo "poudriere combo [options]

Parameters:
    -C          -- Cleanup jail mounts (contingency cleanup)
    -i          -- Show jail information
    -x          -- List all failed ports in last or ongoing build

Options:
    -j name     -- Run only on the given jail
    -p tree     -- Specify on which ports tree the bulk will be done"
	exit 1
}

INFO=0
LISTFAIL=0
DISMOUNT=0

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
PTNAME="default"

. ${SCRIPTPREFIX}/common.sh

[ $# -eq 0 ] && usage

while getopts "j:p:Cix" FLAG; do
	case "${FLAG}" in
		C)
			DISMOUNT=1
			;;
		j)
			JAILNAME=${OPTARG}
			;;
		p)
			PTNAME=${OPTARG}
			;;
		i)
			INFO=1
			;;
		x)
			LISTFAIL=1
			;;
		*)
			usage
			;;
	esac
done


[ -z "${JAILNAME}" ] && err 1 "Don't know on which jail to run please specify -j"

MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
MASTERMNT=${POUDRIERE_DATA}/build/${MASTERNAME}/ref

export MASTERNAME
export MASTERMNT

list_jail_info () {
	[ $# -ne 2 ] && eargs num_queued num_to_build
	local EPOCH
	local building_started
	local elapsed elapsed_days elapsed_hms elapsed_timestamp
	echo "Jailname:              $(jget name)"
	echo "BSD version:           $(jget version)"
	echo "BSD arch:              $(jget arch)"
	echo "Install/update method: $(jget method)"
	echo "World built:           $(bget timestamp)"
	echo "Status:                $(bget status)"
	EPOCH=$(zget epoch)
	if [ "${EPOCH}" != "-" -a "${EPOCH}" != "0" ]; then
	   building_started=$(date -j -r ${EPOCH} "+%Y-%m-%d %H:%M:%S")
	   elapsed=$(expr `date "+%s"` - ${EPOCH})
	   elapsed_days=$(expr ${elapsed} / 86400)
	   elapsed_hms=$(date -j -u -r ${elapsed} "+%H:%M:%S")
	   case ${elapsed_days} in
	     0) elapsed_timestamp="${elapsed_hms}" ;;
	     1) elapsed_timestamp="1 day, ${elapsed_hms}" ;;
	     *) elapsed_timestamp="${elapsed_days} days, ${elapsed_hms}" ;;
	   esac
	   echo "Building started:      ${building_started}"
	   echo "Elapsed time:          ${elapsed_timestamp}"
	fi
	echo "Packages built:        $(bget stats_built)"
	echo "Packages failed:       $(bget stats_failed)"
	echo "Packages ignored:      $(bget stats_ignored)"
	echo "Packages skipped:      $(bget stats_skipped)"
	echo "Packages queued:       ${1}"
	echo "Packages to be built:  ${2}"
}

info_jail() {
	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	nbb=$(bget stats_built|sed -e 's|-|0|g')
	nbf=$(bget stats_failed|sed -e 's|-|0|g')
	nbi=$(bget stats_ignored|sed -e 's|-|0|g')
	nbs=$(bget stats_skipped|sed -e 's|-|0|g')
	nbq=$(bget stats_queued|sed -e 's|-|0|g')
	tobuild=$((nbq - nbb - nbf - nbi - nbs))
	list_jail_info ${nbq} ${tobuild}
}

jail_dismount() {
	[ $# -ne 0 ] && eargs
	local mnt

	cd /
	msg "Umounting file systems"
	mnt=${MASTERMNT%/ref}
	mount | awk -v mnt="${mnt}" '{ if ($3 ~ mnt && $3 !~ /\/ref/) { print $3 }}' |  sort -r | xargs umount -v || :
	mount | awk -v mnt="${mnt}" '{ if ($3 ~ mnt) { print $3 }}' |  sort -r | xargs umount -v || :
}

list_failures() {
	local FLIST=$(log_path)/last_run.failed
	if [ -f ${FLIST} ]; then
	    cat ${FLIST}
	else
	    msg "There are no logged failures."	
	fi
}

case "${INFO}${DISMOUNT}${LISTFAIL}" in
	100)
		test -z ${JAILNAME} && usage
		info_jail
		;;
	010)
		test -z ${JAILNAME} && usage
		jail_dismount
		;;
	001)
		test -z ${JAILNAME} && usage
		list_failures
		;;
	*)
		usage
		;;
esac
