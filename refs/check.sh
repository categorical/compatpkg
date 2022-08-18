#!/bin/bash
set -euo pipefail
readonly thisdir="$(cd "$(dirname "$0")"&&pwd)"

declare -a vs=(
'https://mirrors.slackware.com/slackware/slackware64-15.0/source/d/gcc/gcc.SlackBuild'
'http://www.slackware.com/~alien/multilib/source/current/gcc/gcc-multilib.SlackBuild'
'http://www.slackware.com/~alien/multilib/source/current/gcc/gcc-static.SlackBuild'
'https://mirrors.slackware.com/slackware/slackware64-15.0/source/l/glibc/glibc.SlackBuild'
'http://www.slackware.com/~alien/multilib/source/current/glibc/glibc-multilib.SlackBuild'
'http://www.slackware.com/~alien/multilib/source/compat32-tools/convertpkg-compat32'
'http://www.slackware.com/~alien/multilib/source/compat32-tools/massconvert32.sh'
)
declare -a us;mapfile -t 'us'< <(for i in "${!vs[@]}";do
printf '%2.2d%s\n' $((i+1)) "$(basename "${vs[i]}")";done)
_get(){
    pushd "$thisdir" &>/dev/null;trap 'popd>/dev/null;trap - RETURN' RETURN
    for((i=0;i<${#vs[@]};i++));do local f="${us[i]}"
        [ -f "$f" ]||curl -Lo"$f" "${vs[i]}"
    done
}
_sethash(){
    pushd "$thisdir" &>/dev/null;trap 'popd>/dev/null;trap - RETURN' RETURN
    md5sum "${us[@]}" >'hash.md5'   
}
_check(){ 
    pushd "$thisdir" &>/dev/null;trap 'popd>/dev/null;trap - RETURN' RETURN
    md5sum -c 'hash.md5'
}

_main(){ _usage(){ cat<<-EOF
	$0 -c|--get|--sethash|-h
	EOF
    exit $1;}
    [ $# -gt 0 ]||set -- -c;while [ $# -gt 0 ];do case $1 in
        --get)_get;;--sethash)_sethash;;-c)_check;;
        -h)_usage 0;;*)_usage 1
    esac;shift;done
}
_main "$@"
