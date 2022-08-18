#!/bin/bash
set -euo pipefail
readonly thisdir="$(dirname "$(readlink -f "$0")")"
source "$thisdir/defines.sh"
for v in "$thisdir/bld"{gcc,glibc}.sh;do source "$v";done
source $thisdir/compat32.sh

_copysyspkgs32(){
    local d="$syspkgmnt";_f(){
        ! mountpoint "$d" &>/dev/null||_do sudo umount "$d"
        [ ! -d "$d" ]||_do sudo rmdir "$d"
    };_f;trap '_f;trap - RETURN' RETURN
    [ -d "$d" ]||_do sudo mkdir "$d";_do sudo mount -oro,loop "$sysdvd32" "$d"
   
    local a="$d/slackware";[ -d "$a/a" ]||_Enotfound "$a/a"
    local c="$syspkgdir/slackware";[ -d "$c" ]||_do sudo mkdir -p "$c"
    _do sudo rsync -a --info=progress2 "$a/" "$c/"
}
_downloadalien(){
    local url='http://www.slackware.com/~alien/multilib/15.0'
    local d="$aliendir"
    _do mkdir -p "$d"
    (cd "$d";lftp -c "mirror -c '$url' .")
}
_getpkgnamebyidx(){ local v="$1" optstr="${2-}"
    if [ "$v" ]&&[ -z "$(sed 's/[0-9]//g'<<<"$v")" ];then
        declare -a vs;_pkgarr 'vs' $optstr
        [ "${vs[v-1]-}" ]||_Enotfound "$v";v="${vs[v-1]}"
    fi
    printf '%s\n' "$v"
}
_getpkgbyidx(){ local v="$1" optstr="${2-}"
    v="$(_getpkgnamebyidx "$v" "$optstr")"
    declare -A vs;_pkgmap 'vs' $optstr
    [ "$v" ]&&[ "${vs[$v]-}" ]||_Enotfound "$v";v="${vs[$v]}"
    printf '%s\n' "$v"
}
_Install(){ local v="$1" # pkgname or idx 1 bound
    local pkg;pkg="$(_getpkgbyidx "$v" "${2-}")"
    _isinstalled "$pkg"||sudo upgradepkg -terse -install-new -reinstall "$pkg"
}
_Remove(){ local v="$1" # pkgname or idx 1 bound
    local pkg;pkg="$(_getpkgbyidx "$v")"
    ! _isinstalled "$pkg"||sudo removepkg -terse "$pkg"
}
_Clean(){
    [ ! -d "$stagedir" ]||_do sudo rm -r "$stagedir"
    [ ! -d "$srcdir" ]||_do rm -rf "$srcdir"
}
# creates 32bit compatibility package using stock package specified by pkgname
_Compat32(){
    if [ $# -gt 0 ];then
    local v="$1" # pkgname or idx 1 bound
    local pkgname;pkgname="$(_getpkgnamebyidx "$v" -32)"
    _compat32stage "$pkgname";return
    fi

    declare -a us=("${pkgset[@]}")
    if [ ! "${arg_overwrite-}" = 't' ];then
    declare -a vs;_pkgarr 'vs';vs=("${vs[@]%-compat32}")
    mapfile -t 'us'< <(printf '%s\n' "${pkgset[@]}" "${vs[@]}" "${vs[@]}" \
        |sed '/^$/d'|sort|uniq -u)
    fi
    for v in "${us[@]}";do _compat32stage "$v";done
}
_haspkg(){ local pkgname="$1"
    declare -a vs;_pkgarr 'vs'
    [ "$(printf '%s\n' "$pkgname-compat32" "${vs[@]}"|sed '/^$/d'|sort|uniq -d)" ]
}
_Compat32install(){
    for v in "${pkgset[@]/%/-compat32}";do _Install "$v";done
}
_Compat32remove(){
    for v in "${pkgset[@]/%/-compat32}";do _removepkgname "$v";done
}
_Compat32comparepkg(){
    for v in "${pkgset[@]/%/-compat32}";do _Comparepkg "$v";done
}
_Comparepkg(){ local v="$1" # pkgname or idx 1 bound
    local pkgname;pkgname="$(_getpkgnamebyidx "$v")"
    
    declare -A aa ab ac ad
    _pkgmap 'aa'
    _pkgmap 'ab' -32
    _pkgmap 'ac' -64
    _pkgmap 'ad' -al
    pkgnamer="${pkgname%-compat32}"
    local pkgnamea="$pkgname"
    local pkgnameb="$pkgnamer"
    local pkgnamec="$pkgnamer"
    local pkgnamed;case $pkgname in
        aaa_glibc*|glibc*);&
        gcc*)pkgnamed="$pkgnamer";;
        *)pkgnamed="$pkgnamer-compat32"
    esac
    local pkga="${aa[$pkgnamea]-}"   # compat32
    local pkgb="${ab[$pkgnameb]-}"   # 32
    local pkgc="${ac[$pkgnamec]-}"   # 64
    local pkgd="${ad[$pkgnamed]-}"   # alien

    local v;v="$(set -e
    _comparepkgcomm -12 "$pkga" "$pkgc" -a "$pkgnamea" -b "$pkgnamec 64bit" 2>&1
    _comparepkgcomm -13 "$pkga" "$pkgd" -a "$pkgnamea" -b "$pkgnamed alien" 2>&1
    _comparepkgcomm -23 "$pkga" "$pkgd" -a "$pkgnamea" -b "$pkgnamed alien" 2>&1
    )"
    [ "${arg_terse-}" = 't' ]||{ printf '%s\n\n' "$v" >&2;return;}

    v="$(sed '/^.*\/$/d;/^\(install\/\|usr\/doc\/\)/d'<<<"$v")"
    
    #grep -vq $'^\x1b.*info'<<<"$v"||return 0    # skips if nothing left to show
    v="$(sed '/^\x1b.*info/{h;d};x;/^$/{x;b};{x;H;s/.*//;x}'<<<"$v")";[ "$v" ]||return 0
    
    [ -t 2 ]&&{ printf '%s\n\n' "$v" >&2;return;}
    printf '%s\n\n' "$(sed 's/\x1b\[[0-9]\+m//g'<<<"$v")" >&2
}
_comparepkgcomm(){
    local optstr aa ab
    declare -a args;while [ $# -gt 0 ];do case "$1" in
        -12|-13|-23)optstr="$1";;
        -a)shift;aa="$1";;-b)shift;ab="$1";;
        -*);;*)args+=("$1")
    esac;shift;done;set -- "${args[@]}"
    local a="$1" b="$2"
    [ -f "$a" ]||{ _war 'not found %s' "$aa";return;}
    [ -f "$b" ]||{ _war 'not found %s' "$ab";return;}
    local s=$'\e[4m%s\e[0m'
    local v;case $optstr in
        -12)_inf "intersection of $s and $s" "$aa" "$ab";;
        -13)_inf "set of files in $s but not in $s" "$ab" "$aa";;
        -23)_inf "set of files in $s but not in $s" "$aa" "$ab";;
        *)_Eabort
    esac
    comm "$optstr" <(tar tf "$a"|sort) <(tar tf "$b"|sort) >&2
}
_List(){
    local optstr=;[ "${arg_system-}" ]&&optstr="-${arg_system}"
    declare -a vs;_pkgarr 'vs' $optstr
    #declare -A us;_pkgmap 'us' $optstr
    declare -A us;_getinstalledpkgmap 'us'

    declare -a xs=("${glibcpkgnames[@]}" "${gccpkgnames[@]}")

    for ((i=0;i<${#vs[@]};i++));do
        local v="${vs[i]}"
        local s1='%-30s' s2='%-30.30s'
        local u="${us[$v]-}";[ "$u" ]||s2=$"\e[33m$s2\e[0m" u='(not installed)'
        local x;for x in "${xs[@]}";do
            [ ! "$x" = "$v" ]||{ s1=$"\e[32m$s1\e[0m";break;}
        done
        printf "\e[1m%4d\e[0m $s1 $s2\n" $((i+1)) "$v" "$u"
    done
}
_status(){
    declare -a vs=(
        gccboot
        gcc
        gcc-brig
        gcc-g++
        gcc-gdc
        gcc-gfortran
        gcc-gnat
        gcc-go
        gcc-objc
        glibc
        aaa_glibc-solibs
        glibc-i18n
        glibc-profile
        glibc-compat32
        aaa_glibc-solibs-compat32
        glibc-i18n-compat32
        glibc-profile-compat32
    )
    declare -A us;_getinstalledpkgmap 'us'
    local i;for ((i=0;i<${#vs[@]};i++));do
        local v="${vs[i]}"
        local s1='%-30s' s2='%-40.40s'
        local u="${us[$v]-}";[ -z "$u" ]&&u='(not installed)' \
            ||u="$(sed 's/_biarch\|-compat32/\x1b\[31m\0\x1b\[0m/'<<<"$u")"
        printf "\e[1m%4d\e[0m $s1 $s2\n" $((i+1)) "$v" "$u"
    done
   
    declare -a xs;_pkgarr 'xs'
    declare -a gs;mapfile -t 'gs'< \
        <(printf '%s\n' "${xs[@]}" "${vs[@]}" "${vs[@]}"|sed '/^$/d'|sort|uniq -u)
    
    declare -a hs=("${pkgset[@]/%/-compat32}") # in case gs empty
    local n="$(printf '%s\n' "${hs[@]}" "${!us[@]}"|sort|uniq -d|wc -l)"
    printf '\e[1m%4d\e[0m %-30s (total: \e[31m%d\e[0m/%d)\n' \
        $((i+1)) '*-compat32' "$n" "${#gs[@]}"

}
_pkgarr(){
    local d="$pkgdir";declare -a args;while [ $# -gt 0 ];do case "$1" in
        -32)d="$syspkgdir/slackware";;
        -64)d="$syspkgdir/slackware64";;
        -al)d="$alienpkg";;
        -*);;*)args+=("$1")
    esac;shift;done;set -- "${args[@]}"
    local vvs="$1"

    mapfile -t "$vvs"< <([ -d "$d" ];find "$d" -name '*.t?z' \
        |awk -F- -vOFS=- 'sub(/.*\//,"")&&NF-=3' \
        |sort)
}
_pkgmap(){ # [pkgname]=pkg
    local d="$pkgdir";declare -a args;while [ $# -gt 0 ];do case "$1" in
        -32)d="$syspkgdir/slackware";;
        -64)d="$syspkgdir/slackware64";;
        -al)d="$alienpkg";;
        -*);;*)args+=("$1")
    esac;shift;done;set -- "${args[@]}"
    declare -n _vs="$1"
    local v k;while read -r v k;do _vs["$k"]="$v"
        done< <([ -d "$d" ]&&find "$d" -type f -name '*.t?z' \
        |awk -F- -vOFS=- -vORS=' ' '1;{sub(/.*\//,"");NF-=3;printf "%s\n",$0}')
}
declare -A _installedpkgmap
_getinstalledpkgmap(){ declare -n _vs="$1" # [pkgname]=pkgname-pkgver-arch-pkgrel
    if [ -z "${_installedpkgmap[*]-}" ];then
    local d='/var/lib/pkgtools/packages'
    local v k;while read -r v k;do _installedpkgmap["$k"]="$v"
        done< <(find "$d" -type f \
        |awk -F- -vOFS=- -vORS=' ' 'sub(/.*\//,"");{NF-=3;printf "%s\n",$0}' \
        |sort)
    fi
    for v in "${!_installedpkgmap[@]}";do _vs["$v"]="${_installedpkgmap[$v]}";done
}
_isinstalled(){ local pkg="$1"
    local pkgstr="${pkg##*/}";pkgstr="${pkgstr%.*}"
    test -f "/var/lib/pkgtools/packages/$pkgstr"
}
_removepkgname(){ local pkgname="$1"
    declare -A us;_getinstalledpkgmap 'us'
    [ "$pkgname" ]&&[ "${us[$pkgname]-}" ]||return 0
    sudo removepkg -terse "${us[$pkgname]}"
}
# sets up biarch gcc and glibc
_setbiarch(){
    _removepkgname 'gccboot'
    declare -a vs=('glibc-compat32' 'gcc' 'gcc-g++')
    for v in "${vs[@]}";do _Install "$v";done
}
# resets to stock 64bit gcc and glibc
_unsetbiarch(){
    _removepkgname 'gccboot'
    for v in 'gcc' 'gcc-g++';do _Install "$v" '-64';done
    for v in "${glibcpkgnames[@]}";do _removepkgname "$v";done
}
# sets up gccboot for purpose of build 32bit glibc
_setboot(){ 
    _removepkgname 'gcc';_Install 'gccboot'
    _Install 'gcc-g++' -64
    for v in "${glibcpkgnames[@]}";do _removepkgname "$v";done
}
# sets up 32bit glibc for purpose of build biarch gcc
_setboot1(){
    _removepkgname 'gccboot';_Install 'gcc' -64
    _Install 'glibc-compat32'
}
_dumpdata(){
    local d="$datadir" f="$dumpdata.tgz"
    [ ! -f "$f" ]||_Err 'found %s' "$f";[ -d "$d" ]||_Enotfound "$d"
    find "$d" -type f -printf '%P\n'|sed '/^$/d'|tar c -C"$d" -T-|gzip>"$f"
}
_loaddata(){
    local d="$datadir" f="$dumpdata.tgz"
    [ -f "$f" ]||_Enotfound "$f"
    [ ! -d "$d" ]||_do rm -r "$d";_do mkdir -p "$d"
    tar xf "$f" -C"$d"
}
_allpkgs(){
    local d="$pkgdir";[ ! -d "$d" ]||_Err 'found %s' "$d"
    
    "$0" -B;"$0" --gccboot;
    "$0" --setboot;"$0" --glibc
    "$0" --setboot1;"$0" --gcc
    "$0" -b;"$0" --glibc;"$0" -B
    "$0" -m;"$0" -Cu 2>"$thisdir/log_compat32comparepkg"
}
_main(){ _usage(){ cat<<-EOF
	SYNOPSIS
	    $0 --list|--status
	    $0 --gccboot|--gcc|--glibc
	    $0 -b|-B|--setboot|--setboot1
	    $0 --copysyspkgs32|--downloadalien
	    $0 -m|--compat32 [pkgname|idx_1_bound]
	    $0 -a|--compat32install|-A|--compat32remove
	    $0 -d|--dumpdata|-D|--loaddata
	    $0 --clean
	    $0 -i|--install|-r|--remove pkgname|idx_1_bound
	OPTIONS
	    -y
	    --system {32|64|al|}
	        --list prints compat32 pkgs by default
	        --system specifies alternative pkgs to print 
	        e.g. value 32 means stock pkgs of 32bit slackware
	        -y means --system 64
    
	EXAMPLES
	    $0 l                    prints packages
	    $0 s                    prints a summary of current setup
	    $0 -om                  creates predefined list of compatibility packages
	    $0 -m dbus              creates dbus-compat32 pkg using 32bit dbus package
	    $0 -Cu 2>log            logs changes of -m packages for verification
	    $0 -a                   installs packages created by -m
	    $0 -b                   sets up biarch gcc and glibc. see comments in bldgcc.sh
	    $0 -idbus-compat32      installs dbus-compat32 package
	    $0 -r1                  removes idx 1 package as shown by --list
	
	EOF
    exit $1;}
    declare -a args;while [ $# -gt 0 ];do case "$1" in
        --)args+=("$@");break;;--*|-?);;
        -*)
        for((i=1;i<${#1};i++));do local v="${1:i:1}";case "$v" in
            [mri])args+=("-$v");v="${1:i+1}";[ "$v" ]&&args+=("$v");break;;
            *)args+=("-$v");;
        esac;done;shift;continue;;
    esac;args+=("$1");shift;done;set -- "${args[@]}"
    args=();local verb=;while [ $# -gt 0 ];do case "$1" in
        --)shift;args+=("$@");break;;
        -u|--terse)arg_terse='t';;
        -o|--overwrite)arg_overwrite='t';;
        --system)shift;arg_system="$1";;
        -y)arg_system='64';;
        -i|--install|-r|--remove);&
        --downloadalien|--copysyspkgs32);&
        -b|--setbiarch|-B|--unsetbiarch|--setboot|--setboot1);&
        -m|--compat32|-c|--comparepkg|-C|--compat32comparepkg);&
        -a|--compat32install|-A|--compat32remove);&
        --gccboot|--gcc|--gccstage);&
        --glibc|--glibcstage);&
        --clean|-d|--dumpdata|-D|--loaddata|--allpkgs);&
        l|-l|--list|s|-s|--status)verb="$1";;
        -*);;
        *)args+=("$1");;
    esac;shift;done;set -- "${args[@]}"
    case "$verb" in
        --gcc)_gccbuild;_gccstage;;
        --gccboot)_gccboot;;
        --gccstage)_gccstage;;
        --glibc)_glibcbuild;_glibcstage;;
        --glibcstage)_glibcstage;;
        --copysyspkgs32)_copysyspkgs32;;
        --downloadalien)_downloadalien;;
        -m|--compat32)_Compat32 "$@";;
        -c|--comparepkg)_Comparepkg "$@";;
        -a|--compat32install)_Compat32install;;
        -A|--compat32remove)_Compat32remove;;
        -C|--compat32comparepkg)_Compat32comparepkg;;
        -b|--setbiarch)_setbiarch;;
        -B|--unsetbiarch)_unsetbiarch;;
        --setboot)_setboot;;
        --setboot1)_setboot1;;
        -i|--install)_Install "$@";;
        -r|--remove)_Remove "$@";;
        --clean)_Clean;;
        -d)_dumpdata;;
        -D)_loaddata;;
        --allpkgs)_allpkgs;;
        s|-s|--status)_status;;
        l|-l)_List;;
        *)_usage 1;;
    esac
}
_main "$@"

