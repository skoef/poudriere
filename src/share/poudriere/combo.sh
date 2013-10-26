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
    -d          -- Perform dependency check on entire port tree
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
DEPCHECK=0

SCRIPTPATH=`realpath $0`
SCRIPTPREFIX=`dirname ${SCRIPTPATH}`
PTNAME="default"

. ${SCRIPTPREFIX}/common.sh

[ $# -eq 0 ] && usage

while getopts "j:p:Cdix" FLAG; do
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
		d)
			DEPCHECK=1
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

SETNAME=""
MASTERNAME=${JAILNAME}-${PTNAME}${SETNAME:+-${SETNAME}}
MASTERMNT=${POUDRIERE_DATA}/build/${MASTERNAME}/ref
BUILDNAME=latest
POUDRIERE_BUILD_TYPE=bulk

export MASTERNAME MASTERMNT BUILDNAME POUDRIERE_BUILD_TYPE

info_jail() {
	local nbb nbf nbi nbq nbs tobuild EPOCH
	local building_started status
	local elapsed elapsed_days elapsed_hms elapsed_timestamp
	local ahora=$(date "+%s")
	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	porttree_exists ${PTNAME} || err 1 "No such tree: ${PTNAME}"
	
	status=$(bget status 2>/dev/null || :)
	nbq=$(bget stats_queued 2>/dev/null || :)
	nbf=$(bget stats_failed 2>/dev/null || :)
	nbi=$(bget stats_ignored 2>/dev/null || :)
	nbs=$(bget stats_skipped 2>/dev/null || :)
	nbb=$(bget stats_built 2>/dev/null || :)
	EPOCH=$(bget epoch 2>/dev/null || :)
	tobuild=$((nbq - nbb - nbf - nbi - nbs))

	echo "Jail name:         ${JAILNAME}"
	echo "Jail version:      $(jget ${JAILNAME} version)"
	echo "Jail arch:         $(jget ${JAILNAME} arch)"
	echo "Jail acquired:     $(jget ${JAILNAME} method)"
	echo "Jail built:        $(jget ${JAILNAME} timestamp)"
	echo "Tree name:         ${PTNAME}"
	echo "Tree acquired:     $(pget ${PTNAME} method)"
	echo "Tree updated:      $(pget ${PTNAME} timestamp)"
	echo "Status:            ${status}"
	if [ "${EPOCH}" != "-" -a "${EPOCH}" != "0" ]; then
	   building_started=$(date -j -r ${EPOCH} "+%Y-%m-%d %H:%M:%S")
	   elapsed=$((ahora-EPOCH))
	   elapsed_days=$((elapsed/86400))
	   elapsed_hms=$(date -j -u -r ${elapsed} "+%H:%M:%S")
	   case ${elapsed_days} in
	     0) elapsed_timestamp="${elapsed_hms}" ;;
	     1) elapsed_timestamp="1 day, ${elapsed_hms}" ;;
	     *) elapsed_timestamp="${elapsed_days} days, ${elapsed_hms}" ;;
	   esac
	   echo "Building started:  ${building_started}"
	   echo "Elapsed time:      ${elapsed_timestamp}"
	fi
	echo "Packages built:    ${nbb}"
	echo "Packages failed:   ${nbf}"
	echo "Packages ignored:  ${nbi}"
	echo "Packages skipped:  ${nbs}"
	echo "Packages total:    ${nbq}"
	echo "Packages left:     ${tobuild}"
}

jail_dismount() {
	[ $# -ne 0 ] && eargs
	local mnt
	jail_exists ${JAILNAME} || err 1 "No such jail: ${JAILNAME}"
	porttree_exists ${PTNAME} || err 1 "No such tree: ${PTNAME}"

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

solo_dep_check() {
	ALL=1
	SKIPSANITY=1
	jail_start ${JAILNAME} ${PTNAME} ${SETNAME}
	prepare_ports
	cleanup
}

case "${INFO}${DISMOUNT}${LISTFAIL}${DEPCHECK}" in
	1000)
		test -z ${JAILNAME} && usage
		info_jail
		;;
	0100)
		test -z ${JAILNAME} && usage
		jail_dismount
		;;
	0010)
		test -z ${JAILNAME} && usage
		list_failures
		;;
	0001)
		test -z ${JAILNAME} && usage
		solo_dep_check
		;;
	*)
		usage
		;;
esac
