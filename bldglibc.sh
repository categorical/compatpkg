glibcpkgnames=('glibc' 'glibc-i18n' 'aaa_glibc-solibs' 'glibc-profile')
readonly -a glibcpkgnames=("${glibcpkgnames[@]/%/-compat32}")

_glibcpkgfilename(){ local pkgname="$1"
    printf '%s-%s-%s-%s.tgz\n' "$pkgname" "$pkgver" "$arch" "$pkgrel"
}
_glibcsetvar(){
    disturl='https://ftp.gnu.org/gnu/glibc/glibc-2.33.tar.bz2'
    dist="$distdir/glibc-2.33.tar.bz2"   
    progname='glibc' pkgver='2.33' pkgrel=1
    arch='x86_64' build='i586-slackware-linux'
    read pkgname4 pkgname1 pkgname2 pkgname3<<<"${glibcpkgnames[*]}"
    read -d $'\0' pkg4 pkg1 pkg2 pkg3 < <(for v in "${glibcpkgnames[@]}";do
        printf '%s\n' "$pkgdir/$(_glibcpkgfilename "$v")"
    done;printf '\0')
    src="$srcdir/$progname-$pkgver"
    bld="$src/bld"
    sta="$stagedir/$progname-$pkgver"
    sta0="$sta/sta0"
    sta1="$sta/sta1"  # i18n
    sta2="$sta/sta2"  # so
    sta3="$sta/sta3"  # profile
    sta4="$sta/sta4"  # glibc

    v='https://mirrors.slackware.com/slackware/slackware64-15.0/source'
    paturl=(
        "$v/l/glibc/glibc.locale.no-archive.diff.gz"
        "$v/l/glibc/glibc-2.32.en_US.no.am.pm.date.format.diff.gz"
        "$v/l/glibc/glibc.ru_RU.CP1251.diff.gz"
        "$v/l/glibc/glibc-c-utf8-locale.patch.gz"
    )
    pat=(
        "$distdir/glibc.locale.no-archive.diff.gz"
        "$distdir/glibc-2.32.en_US.no.am.pm.date.format.diff.gz"
        "$distdir/glibc.ru_RU.CP1251.diff.gz"
        #"$distdir/glibc-c-utf8-locale.patch.gz,-p1"    
    )
}
_glibcprepare(){
    _glibcsetvar
    [ -d "$distdir" ]||_do mkdir -p "$distdir"
    _getdist "$disturl" 'dist'
    [ ! -d "$src" ]||_do rm -rf "$src"
    _extract "$dist" "$src"
    _patch 'paturl' 'pat'
}
_glibcbuild(){
    _glibcprepare
    [ ! -d "$bld" ]||_do rm -r "$bld";_do mkdir -p "$bld"
    pushd "$bld" &>/dev/null;trap 'popd>/dev/null;trap - RETURN' RETURN 
    declare -a opts=(
        --prefix=/usr
        --libdir=/usr/lib
        --with-headers=/usr/include
        --infodir=/usr/info
        --mandir=/usr/man
        --enable-kernel=2.6.32
        --enable-add-ons
        --enable-profile
        --with-tls
        --with-__thread
        --without-cvs
        --host="$build"
        #i586-slackware-linux # undocumented, "build host target"
        CC='gcc -m32'
        CXX='g++ -m32'
        CFLAGS='-g -O3 -march=i586 -mtune=i686 -I/usr/include'
    )
    ../configure "${opts[@]}"
    make -j$(nproc)    
    # $ ../scripts/config.sub i586-slackware-linux

    [ ! -d "$sta" ]||_do sudo rm -r "$sta";_do mkdir -p "$sta0"
    DESTDIR="$sta0" make -j$(nproc) install
    DESTDIR="$sta0" make -j$(nproc) localedata/install-locales
}
_glibcstage(){
    _glibcsetvar
    local d f

    d="$sta0/bin";mkdir -p "$d"
    ln -sf /sbin/sln "$sta0/bin/sln"

    # region useless
    if false;then
    d="$sta0/usr/lib64/debug";mkdir -p "$d"
    cp -dt"$d" "$sta0/lib64/"l*.so*
    cp -dt"$d" "$sta0/usr/lib64/"*.a
    find "$d" -name '*_p.a' -exec rm {} \;
    
    # libmcheck.a is "relocatable"
    declare -a vs
    _getobjfile 'vs' "$sta0/lib64" -depth 1
    _getobjfile 'vs' "$sta0/usr/lib64" -depth 1
    strip -g "${vs[@]}"
    fi
    # endregion

    f="$sta0/etc/nscd.conf.new"
    install -DTm644 "$src/nscd/nscd.conf" "$f"
  
    local f="$syspkgdir/slackware64/l/glibc-2.33-x86_64-5.txz"
    tar xf "$f" -C"$sta0" usr/doc/$progname-$pkgver

    declare -a us;_getobjfile 'us' "$sta0";strip -g "${us[@]}"

    d="$sta0/usr/info"
    rm -f "$d/dir"
    find "$d" -type f -not -name '*.gz' -exec gzip -9 {} +

    f="$sta0/etc/ld.so.cache"
    rm -f "$f"

    [ -d "$pkgdir" ]||_do mkdir -p "$pkgdir"

    _glibcstage_profile
    _glibcstage_so
    _glibcstage_i18n
    _glibcstage_glibc
}
_glibcstage_glibc(){
    [ ! -d "$sta4" ]||_do sudo rm -r "$sta4";mkdir "$sta4";

    declare -a us;mapfile -t us< <({
        cd "$sta0";find . -type f,l
        cd "$sta1";find . -type f,l;find . -type f,l
        cd "$sta2";find . -type f,l;find . -type f,l
        cd "$sta3";find . -type f,l;find . -type f,l
    }|sort|uniq -u|sed 's/^\.\///')
    mapfile -tO${#us[@]} 'us'< <(cd "$sta0"
        find usr/lib/locale/{C.utf8,en_US{,.utf8}} -type f)
    mapfile -tO${#us[@]} 'us'< <(cd "$sta0";find usr/lib/gconv -type f)
    mapfile -tO${#us[@]} 'us'< <(cd "$sta0";find lib -type f,l)
    declare -a vs;_glibcstagemask 'us' 'vs'
    _do rsync -ar --files-from=<(for v in ${vs[@]};do printf '%s\n' "$v";done) \
        "$sta0" "$sta4"
   
    f="$syspkgdir/slackware64/l/glibc-2.33-x86_64-5.txz"
    _setdesc "$pkgname4" "$sta4" "$f"
    _makepkg -l "$sta4" "$pkg4"

}
_glibcstage_profile(){
    [ ! -d "$sta3" ]||_do sudo rm -r "$sta3";mkdir "$sta3";
    declare -a us;mapfile -t 'us'< <(cd "$sta0";find 'usr/lib' -type f,l -name 'lib*_p.a')
    declare -a vs;_glibcstagemask 'us' 'vs'
    _do rsync -ar --files-from=<(for v in ${vs[@]};do printf '%s\n' "$v";done) \
        "$sta0" "$sta3"
   
    f="$syspkgdir/slackware64/l/glibc-profile-2.33-x86_64-5.txz"
    _setdesc "$pkgname3" "$sta3" "$f"
    _makepkg -l "$sta3" "$pkg3"
   
}
_glibcstage_so(){
    [ ! -d "$sta2" ]||_do sudo rm -r "$sta2";mkdir "$sta2";
   
    declare -a vs;vs=(
        'lib'
        'usr/bin/ldd'
        'usr/lib/gconv'
        'sbin/ldconfig'
    )
    declare -a us;mapfile -t 'us'< <(cd "$sta0";for v in "${vs[@]}";do
        find "$v" -type f,l;done|sort|uniq)
    declare -a vs;_glibcstagemask 'us' 'vs'
    _do rsync -ar --files-from=<(for v in ${vs[@]};do printf '%s\n' "$v";done) \
        "$sta0" "$sta2"
   
    f="$syspkgdir/slackware64/a/aaa_glibc-solibs-2.33-x86_64-5.txz"
    _setdesc "$pkgname2" "$sta2" "$f"
    _makepkg -l "$sta2" "$pkg2"

}
_glibcstage_i18n(){
    [ ! -d "$sta1" ]||_do sudo rm -r "$sta1";mkdir "$sta1";
    declare -a vs;vs=(
        'usr/lib/locale'
        'usr/share/i18n'
        'usr/share/locale'
    )
    declare -a us;mapfile -t 'us'< <(cd "$sta0";for v in "${vs[@]}";do
        find "$v" -type f,l;done|sort|uniq)
    declare -a vs;_glibcstagemask 'us' 'vs'
    _do rsync -ar --files-from=<(for v in ${vs[@]};do printf '%s\n' "$v";done) \
        "$sta0" "$sta1"

    f="$syspkgdir/slackware64/l/glibc-i18n-2.33-x86_64-5.txz"
    _setdesc "$pkgname1" "$sta1" "$f"
    _makepkg -l "$sta1" "$pkg1"

}
_glibcstagemask(){ local iarr=$1 oarr=$2
    declare -n _iarr="$iarr" _oarr="$oarr"
    declare -a ms=(
        'l/glibc-2.33-x86_64-5.txz'
        'l/glibc-i18n-2.33-x86_64-5.txz'
        'l/glibc-profile-2.33-x86_64-5.txz'
        'a/aaa_glibc-solibs-2.33-x86_64-5.txz'
    )
    declare -a ns;mapfile -t ns< <(for m in "${ms[@]}";do
        tar tf "$syspkgdir/slackware64/$m"
    done|sort|uniq)
    mapfile -t '_oarr'< <(printf '%s\n' "${ns[@]}" "${ns[@]}" "${_iarr[@]}"|sort|uniq -u)
}

