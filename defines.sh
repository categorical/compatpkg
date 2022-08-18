#!/bin/bash
# region defines
readonly datadir="$HOME/.compatpkg"
readonly distdir="$datadir/dist"
readonly pkgdir="$datadir/pkg"
readonly srcdir='/tmp/compatpkg_src'
readonly stagedir='/tmp/compatpkg_stage'
readonly syspkgdir='/opt/syspkg'
readonly sysdvd32='/sta/c/inet/la/slackware-15.0-install-dvd.iso'
readonly syspkgmnt='/mnt2'
readonly alienpkg="$HOME/.compatpkgalien"
readonly dumpdata='/sta/c/compatpkg_data'
# endregion

# region utils
_esed(){ printf '%s' "$1"|sed 's/[.[\*^$/]/\\&/g';}
_onexit(){ printf "exit: %d\n" $?>&2;};trap _onexit EXIT
_inf(){ printf '\e[36minfo: \e[0m%s\n' "$(printf "$1" "${@:2}")">&2;}
_err(){ printf '\e[31merror: \e[0m%s\n' "$(printf "$1" "${@:2}")">&2;}
_war(){ printf '\e[33mwarn: \e[0m%s\n' "$(printf "$1" "${@:2}")">&2;}
_confirm(){ read -p "$(printf '\e[35mconfirm: \e[0m%s [y/N]:' "$(printf "$1" "${@:2}")")";[ "${REPLY,,}" = 'y' ]||exit 1;}
_Err(){ _err "$@";exit 1;}
_Enotfound(){ _Err 'not found %s' "$1";}
_Eabort(){ _Err 'abort %s' "${FUNCNAME[1]}";}
_Einvalid(){ _Err 'invalid %s' "$(declare -p "$1")";}
_do()(set -x;"$@")
_httpgetfilename(){ local url="$1"
    local opts=('-sLI' '-XGET')
    local r;r=$(curl "${opts[@]}" "$url" 2>/dev/null)
    local v=$(sed -n 's/^.*filename=\(.*\)$/\1/p'<<<"$r"|sed 's/\r$//'|sed 's/^"\|"$//g'|tail -n1)
    if [ -z "$v" ];then
        v=$(sed -n 's/^Location:\(.*\)$/\1/ip'<<<"$r"|sed 's/^\s*\|\r$//g'|tail -n1)
        [ "$v" ]||v="$url";v="$(basename "${v%%\?*}")"
    fi
    printf '%s' "$v"
}
_httpgetfile(){ local url="$1" d="$2" vf="${3-}"
    local v;v="$(_httpgetfilename "$url")"
    [[ $v =~ ^[a-zA-Z0-9._-]+$ ]]||_Err 'filename %s' "$v"
    [ -d "$d" ]||_Enotfound "$d"
    local opts=('-L' '-o' "$d/$v")
    _do curl "${opts[@]}" "$url"
    [ -z "$vf" ]||eval "$vf='$d/$v'"
}
_extract(){ local f="$1" d="$2"
    [ -f "$f" ]||_Enotfound "$f"
    local v="$(basename "$f")"
    case "$v" in
        *.tar.gz|*.tgz|*.tar.bz2|*.tar.xz)
            _do mkdir -p "$d"
            _do tar xf "$f" -C "$d" --strip-component 1
            ;;
        *.zip);&
        *.7z);&
        *)_Eabort;;
    esac
}
# endregion

_getdist(){ local url="$1" vf="$2"
    declare -n f="$vf";if [ ! -f "$f" ];then
        _httpgetfile "$url" "$distdir" "$vf"
        _inf 'downloaded %s' "$(basename "$f")"
    fi
}
_getobjfile(){
    local depth aa ae
    declare -a args;while [ $# -gt 0 ];do case "$1" in
        -depth)shift;depth="$1";;
        -a)aa='t';;-e)ae='t';;
    -*);;*)args+=("$1");esac;shift;done;set -- "${args[@]}"
    local vvs="$1" d="$2"

    declare -a opts=(-type f)
    [ -z "${depth-}" ]||opts=(-maxdepth $depth "${opts[@]}")
    
    local ve='ELF.*\(executable\|shared object\)' va='ar archive'
    local v="$ve\|$va";[ "${ae-}" = 't' ]&&v="$ve";[ "${aa-}" = 't' ]&&v="$va"

    declare -n _vs="$vvs";local i=0;[ -z ${_vs[@]+x} ]||i="${#_vs[@]}"
    mapfile -tO$i "$vvs"< <(find "$d" "${opts[@]}" -exec file {} +|grep "$v"|cut -f1 -d:)
}
_setrootowner(){ local d="$1"
    find "$d" \
        -type d -exec chmod 755 {} + -o \
        -type f -executable -exec chmod 755 {} + -o \
        -type f -exec chmod 644 {} +
    sudo chown -R 'root:root' "$d"
}
_makepkg(){
    local al;declare -a args;while [ $# -gt 0 ];do case "$1" in
        -l)al='t';;
    -*);;*)args+=("$1");esac;shift;done;set -- "${args[@]}"
    local d="$1" f="$2"
   
    _setrootowner "$d"
    [ -d "$pkgdir" ]||_do mkdir -p "$pkgdir"
    pushd "$d" &>/dev/null
        case ${al-} in
            t)
            sudo makepkg -l y -c n "$f" # sudo required for -l y
            sudo chown `id -u`:`id -g` "$f";;
            *)makepkg -l n -c n "$f" >/dev/null
        esac
        popd >/dev/null
    
}
_patch(){ local vu="$1" vp="$2"
    declare -n _u="$vu" _p="$vp"
    for i in "${!_p[@]}";do
        IFS=, read a b< <(printf '%s\n' "${_p[i]}")
        _getdist "${_u[i]}" 'a'
        declare -a opts=(-p0);[ -z "$b" ]||opts=($b)
        (cd "$src";zcat "$a"|patch "${opts[@]}")
    done
}
_setdesc(){ local pkgname="$1" d="$2" f="$3"
    [ ! -d "$f" ]||[ -f "$f/install/slack-desc" ]||return 0
    pkgname="${pkgname:0:18}";local v="$(printf '%1.0s' $(seq "${#pkgname}"))"
    install -dm755 "$d/install"
    if [ -d "$f" ];then cat "$f/install/slack-desc"
    else tar xOf "$f" install/slack-desc;fi \
        |sed "0,/^ *|/s//$v|/;s/^[^ ]\+:/$pkgname:/" \
        |tee "$d/install/slack-desc">/dev/null
}

