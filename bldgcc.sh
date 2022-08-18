readonly -a gccpkgnames=('gcc' 'gcc-g++' 'gccboot')
readonly nproc1=$(($(nproc)>1?$(nproc)/2:1))
_gccsetvar(){
    disturl='https://ftp.gnu.org/gnu/gcc/gcc-11.2.0/gcc-11.2.0.tar.xz'
    distfilename='gcc-11.2.0.tar.xz'
    dist="$distdir/$distfilename"
    progname='gcc' pkgver='11.2.0' pkgrel=1
    arch='x86_64' build='x86_64-slackware-linux'
    read pkgname1 pkgname2 pkgname3 <<<"${gccpkgnames[*]}"
    read -d $'\0' pkg1 pkg2 pkg3 < <(for v in "${gccpkgnames[@]}";do
        printf '%s\n' "$pkgdir/$(_gccpkgfilename "$v")"
    done;printf '\0')
    src="$srcdir/$progname-$pkgver"
    bld="$src/bld"
    sta="$stagedir/$progname-$pkgver"
    sta0="$sta/sta0"
    sta1="$sta/sta1"    # gcc
    sta2="$sta/sta2"    # cpp
    sta3="$sta/sta3"    # boot

    v='https://mirrors.slackware.com/slackware/slackware64-15.0/source'
    paturl="$v/d/gcc/patches/gcc-no_fixincludes.diff.gz"
    pat="$distdir/gcc-no_fixincludes.diff.gz"
}    
_gccpkgfilename(){ local pkgname="$1"
    printf '%s-%s_biarch-%s-%s.tgz' "$pkgname" "$pkgver" "$arch" "$pkgrel"
}
_gccprepare(){
    _gccsetvar
    [ -d "$distdir" ]||_do mkdir -p "$distdir"
    _getdist "$disturl" 'dist'
    _getdist "$paturl" 'pat'
    [ ! -d "$src" ]||_do rm -rf "$src"
    _extract "$dist" "$src"
    # disables installing e.g. include-fixed/X11/Xw32defs.h to DESTDIR
    (cd "$src";zcat "$pat"|patch -p0)

}
_gccboot(){
    _gccprepare
    [ ! -d "$bld" ]||_do rm -r "$bld";_do mkdir -p "$bld"
    pushd "$bld" &>/dev/null;trap 'popd>/dev/null;trap - RETURN' RETURN 
    
    declare -a opts=(
        --prefix=/usr
        --libdir=/usr/lib64
        --mandir=/usr/man
        --infodir=/usr/info
        --disable-bootstrap # excludes c++
        --enable-languages=c
        --target=$build
        --build=$build
        --host=$build
        --enable-multilib
        --disable-lto   # halves the size
        --disable-shared
        # region: convinces gcc not to look for non existing gnu/stubs-32.h
        --with-newlib
        --without-headers
        --disable-threads
        --disable-gcov
        # endregion
    )
    $src/configure "${opts[@]}"
    make -j$(nproc) all-gcc
    make -j$(nproc) all-target-libgcc
    [ ! -d "$sta" ]||_do sudo rm -r "$sta";_do mkdir -p "$sta0"
    DESTDIR="$sta0" make -j$(nproc) install-gcc install-target-libgcc
    
    [ ! -d "$sta3" ]||_do sudo rm -r "$sta3";mkdir "$sta3";
    declare -a vs=(
        'usr/bin'
        'usr/lib64'
        'usr/libexec'
    ) 
    _do rsync -Har --files-from=<(printf '%s\n' "${vs[@]}"|sed '/^$/d') "$sta0" "$sta3"
    _gccstripobj "$sta3"
    
    local f="$syspkgdir/slackware64/d/gcc-11.2.0-x86_64-2.txz"
    _setdesc "$pkgname3" "$sta3" "$f"
    
    _makepkg -l "$sta3" "$pkg3"
    
    # https://gcc.gnu.org/wiki/FAQ#gnu_stubs-32.h
    # https://gcc.gnu.org/legacy-ml/gcc-help/2009-07/msg00371.html

    # this pkg gccboot must replace the gcc pkg when installed
}
_gccbuild(){
    _gccprepare
    [ ! -d "$bld" ]||_do rm -r "$bld";_do mkdir -p "$bld"
    pushd "$bld" &>/dev/null;trap 'popd>/dev/null;trap - RETURN' RETURN 
    declare -a opts=(
        --prefix=/usr
        --libdir=/usr/lib64
        --mandir=/usr/man
        --infodir=/usr/info
        --enable-shared
        --enable-bootstrap
        #--disable-bootstrap
        --enable-languages=c,c++
        --enable-threads=posix
        --enable-checking=release
        --enable-objc-gc
        --with-system-zlib
        --enable-libstdcxx-dual-abi
        --with-default-libstdcxx-abi=new
        --disable-libstdcxx-pch
        --disable-libunwind-exceptions
        --enable-__cxa_atexit
        --disable-libssp
        --enable-gnu-unique-object
        --enable-plugin
        --enable-lto
        --disable-install-libiberty
        --disable-werror
        --with-gnu-ld
        --with-isl
        --verbose
        --with-arch-directory='amd64'
        --disable-gtktest
        --enable-clocale=gnu
        --target=$build
        --build=$build
        --host=$build
        --enable-multilib
        
        # $ ../config.sub x86_64-linux
        # https://gcc.gnu.org/onlinedocs/gccint/Configure-Terms.html
    )
    CFLAGS='-O2 -fPIC -pipe' LDFLAGS='-L/usr/lib64' $src/configure "${opts[@]}"
    make -j$(nproc)
    [ ! -d "$sta" ]||_do sudo rm -r "$sta";_do mkdir -p "$sta0"
    DESTDIR="$sta0" make -j$(nproc) install

    # --enable-languages=c and --enable-bootstrap installs c++ also
    # --enable-languages=c,c++ and --disable-bootstrap installs same set of files
}
_gccstage(){
    _gccsetvar
    local d f

    d="$sta0/usr/lib64/gcc/$build/$pkgver"
    install -Dt"$d" "$bld/gcc/specs"

    d="$sta0/usr/share/gdb/auto-load/usr/lib64"
    f="$(find "$sta0/usr/lib64" -name '*-gdb.py')"
    [ ! -f "$f" ]||{ install -Dt"$d" "$f";_do rm -f "$f";}

    d="$sta0/usr/info"
    _do rm -f "$d/dir"
    find "$d" -type f -not -name '*.gz' -exec gzip -9 {} +
    
    d="$sta0/lib";mkdir -p "$d"
    ln -sf '/usr/bin/cpp' "$d/cpp"

    d="$sta0/usr/bin"
    [ -f "$d/gcc-$pkgver" ]||mv "$d/gcc" "$d/gcc-$pkgver"
    ln -sf gcc-$pkgver "$d/gcc"
    ln -sf gcc-$pkgver "$d/cc"
    ln -sf gcc-$pkgver "$d/$build-cc" 
    ln -sf gcc-$pkgver "$d/$build-gcc" 
    ln -sf gcc-$pkgver "$d/$build-gcc-$pkgver"
    ln -sf gcc-ar "$d/$build-gcc-ar"
    ln -sf gcc-nm "$d/$build-gcc-nm"
    ln -sf gcc-ranlib "$d/$build-gcc-ranlib"
    f="$syspkgdir/slackware64/d/gcc-11.2.0-x86_64-2.txz"
    tar xf "$f" -C"$sta0" usr/bin/c89 usr/bin/c99
   
    [ -f "$d/g++-gcc-$pkgver" ]||mv "$d/g++" "$d/g++-gcc-$pkgver"
    ln -sf g++-gcc-$pkgver "$d/c++"
    ln -sf g++-gcc-$pkgver "$d/g++"
    ln -sf g++-gcc-$pkgver "$d/$build-c++"
    ln -sf g++-gcc-$pkgver "$d/$build-g++"


    d="$sta0/usr/man"
    find "$d" -type f -not -name '*.gz' -exec gzip -9 {} +
    ln -sf gcc.1.gz "$d/man1/cc.1.gz"
    ln -sf g++.1.gz "$d/man1/c++.1.gz"
    
    while read -r -d $'\0';do _do rm "$REPLY"
    done< <(find "$sta0/usr/lib"{,64} -type f -name '*.la' -print0)

    _gccstripobj "$sta0"
    
    _gccstage_cpp
    _gccstage_c
}

_gccstage_c(){
    [ ! -d "$sta1" ]||_do sudo rm -r "$sta1";mkdir "$sta1";

    declare -a vs;mapfile -t vs< <({
        cd "$sta0";find . -type f,l
        [ ! -d "$sta2" ]||{ cd "$sta2";find . -type f,l;find . -type f,l;}
    }|sort|uniq -u)
    _do rsync -ar --files-from=<(for v in ${vs[@]};do printf '%s\n' "$v";done) \
        "$sta0" "$sta1"
    
    # doc
    local f="$syspkgdir/slackware64/d/gcc-11.2.0-x86_64-2.txz"
    tar xf "$f" -C"$sta1" usr/doc
    tar xf "$f" -C"$sta1" install/slack-desc

    # these files are missing as compared to stock pkg
    declare -a vs
    vs=(
    'usr/info/libffi.info.gz'
    'usr/lib64/gcc/x86_64-slackware-linux/11.2.0/ada_target_properties'
    'usr/lib64/gcc/x86_64-slackware-linux/11.2.0/include/ISO_Fortran_binding.h'
    'usr/lib64/gcc/x86_64-slackware-linux/11.2.0/libcaf_single.a'
    'usr/lib64/gcc/x86_64-slackware-linux/11.2.0/libcaf_single.la'
    'usr/lib64/gcc/x86_64-slackware-linux/11.2.0/plugin/libcc1plugin.la'
    'usr/lib64/gcc/x86_64-slackware-linux/11.2.0/plugin/libcp1plugin.la'
    'usr/libexec/gcc/x86_64-slackware-linux/11.2.0/buildid'
    'usr/libexec/gcc/x86_64-slackware-linux/11.2.0/test2json'
    'usr/libexec/gcc/x86_64-slackware-linux/11.2.0/vet'
    )    
    tar xf "$f" -C"$sta1" "${vs[@]}"
    vs=(
    'lib'
    'usr/include'
    'usr/share/gcc-11.2.0/python'
    )
    install -d "${vs[@]/#/$sta1/}"
   
    _makepkg -l "$sta1" "$pkg1"
}
_gccstage_cpp(){
    [ ! -d "$sta2" ]||_do sudo rm -r "$sta2";mkdir "$sta2";
    declare -a vs;vs=(
        # dir
        'usr/include/c++'
        'usr/share/gdb'
        "usr/share/gcc-$pkgver/python/libstdcxx"
        # file
        "usr/libexec/gcc/$build/$pkgver/cc1plus"
    )
    mapfile -tO"${#vs[@]}" vs< <(cd "$sta0";find usr/bin -type f,l -name '*++*')
    mapfile -tO"${#vs[@]}" vs< <(cd "$sta0";find usr/lib -type f,l -name '*++*')
    mapfile -tO"${#vs[@]}" vs< <(cd "$sta0";find usr/lib64 -type f,l -name '*++*')
    mapfile -tO"${#vs[@]}" vs< <(cd "$sta0";find usr/man/man1 -type f,l -name '*++*')
    _do rsync -ar --files-from=<(for v in ${vs[@]};do printf '%s\n' "$v";done) \
        "$sta0" "$sta2"

    # doc
    local d="$sta2/usr/doc/gcc-$pkgver/libstdc++-v3"
    install -Dpm644 -t"$d" "$src/libstdc++-v3/"{README,ChangeLog,doc/html/faq.html}
    sed -i '1001,$d' "$d/ChangeLog";touch -r {"$src/libstdc++-v3","$d"}/ChangeLog

    f="$syspkgdir/slackware64/d/gcc-g++-11.2.0-x86_64-2.txz"
    tar xf "$f" -C"$sta2" install/slack-desc
    
    _makepkg -l "$sta2" "$pkg2"
}
_gccstripobj(){ local d="$1"
    declare -a vs;_getobjfile 'vs' "$d" -e
    if [ "${#vs[@]}" -gt 0 ];then
    strip --strip-unneeded "${vs[@]}"
    readelf -d "${vs[@]}"|grep -i 'rpath'||:
    patchelf --remove-rpath "${vs[@]}"
    fi
    declare -a us;_getobjfile 'us' "$d" -a
    if [ "${#us[@]}" -gt 0 ];then
    strip -g "${us[@]}"
    fi
}

# n.b.
# - To be able to compile 32 bit program such as wine, the system needs to have
#   a) biarch gcc, b) 32bit glibc and c) other dependencies of the program in 32bit
#   Speaking of c), a compatibility package can be obtained by modifying stock 32bit
#   package. a) and b) however, building one requires the other as it may appear,
#   i.e. building biarch gcc requires 32bit glibc, and building 32bit glibc requires
#   an existing biarch gcc. The former is more artificial, compiler does not need
#   library to compile code. To achieve a) and b), an intermediate gcc is needed
#   and the steps are:
#    1) build the intermediate gcc, it is biarch and does not depend on 32bit glibc
#    2) use the intermediate to build the 32bit glibc
#    3) use stock gcc and 32bit glibc to build biarch gcc
#   
#   equivalent script options are:
#    1) --gccboot
#    2) --setboot, --glibc
#    3) --setboot1, --gcc, -b
#    optional 4) --glibc, -B, -b
#   
# - gcc non cross built on another machine is useless.
#
