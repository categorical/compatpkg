
_compat32stage(){ local pkgnamer="$1"
    declare -A fs gs;_pkgmap -32 'fs';_pkgmap -64 'gs'
    [ "$pkgnamer" ]&&[ "${fs[$pkgnamer]-}" ]&&[ "${gs[$pkgnamer]-}" ] \
        ||_Enotfound "$pkgnamer"
    local pkg32="${fs[$pkgnamer]}" pkg64="${gs[$pkgnamer]}"
    local pkgname="${pkgnamer}-compat32"
    local pkg="$pkgdir/$(sed "s/^\(.*\)\(\(-.*\)\{3\}\)$/$pkgname\2/"<<<"${pkg32##*/}")"
    pkg="${pkg%.*}.tgz"
    local sta="$stagedir/$pkgname"
    local sta0="$sta/sta0" sta1="$sta/sta1"

    [ ! -d "$sta" ]||_do sudo rm -r "$sta";_do mkdir -p "$sta0"
    #pushd "$sta0" &>/dev/null;trap 'popd>/dev/null;trap - RETURN' RETURN
    tar xf "$pkg32" -C"$sta0"
    
    # relocates bin 
    _compat32bin
    
    # there's nothing else to do here
    # dir etc, bin, usr/include, etc. can be removed by heuristic
    # as they should not overwrite 64bit pkg
    # but special case has to be considered e.g.
    # mesa has intel_icd.i686.json in usr/share/vulkan/icd.d
    # and that has no conflict with intel_icd.x86_64.json from 64bit
    # and should be included
    # 
    # instead of branch this case by case, let the 64bit pkg decide what to keep
    # as long as compat32 pkg is of the same version
    #

    _do mkdir -p "$sta1"
    # anything already in 64bit pkg does not come in
    _compat32pkgmask "$sta1"

    # except for doc/, doinst.sh and slack-desc
    _compat32doc "$sta1"
    _compat32doinst "$sta1"
    _setdesc "$pkgname" "$sta1" "$sta0"
    
    # removes *.new files, since doinst.sh no longer has config fn to use them
    find "$sta1" -name '*.new' -exec rm -f {} +

    _makepkg "$sta1" "$pkg"
    # n.b.
    # - gdk-pixbuf2, gtk+2 and gtk+3 have binaries named *-32
    #   alien renamed all bins to *-32 in these pkgs and did the same to pango and llvm
    #
    #   one reason would be that script executed by doinst.sh,
    #   e.g. /usr/bin/update-gdk-pixbuf-loaders, has line
    #   "if [ -x /usr/bin/gdk-pixbuf-query-loaders-32 ]; then"
    #
}
_compat32bin2(){ local d="$1"
    local a="$sta0/usr/bin";[ -d "$a" ]||return 0
    local c="$d/usr/bin/32";rm -rf "$d/usr/bin"
    install -dm755 "$c"
    find "$a" -type f -exec cp -nat"$c" {} +
    (cd "$d";rmdir -p 'usr/bin/32' --ignore-fail-on-non-empty)
}
_compat32bin(){
    local a="$sta0/usr/bin";[ -d "$a" ]||return 0
    local c="$sta0/usr_bin";mkdir "$c"
    find "$a" -type f -exec cp -nat"$c" {} +
    rm -rf "$a";mkdir -p "$a/32"
    rsync -a "$c/" "$a/32/";rm -rf "$c"
}
_compat32pkgmask(){ local d="$1"

    declare -a us;mapfile -t us< <(tar tf "$pkg64")
    declare -a vs;mapfile -t vs< <({
        find "$sta0" -type f,l -printf '%P\n'
        find "$sta0" -type d -printf '%P\n'|sed '/^$/d;s/$/\//'
        printf '%s\n' "${us[@]}" "${us[@]}"
    }|sed '/^$/d'|sort|uniq -u)
    rsync -aH --files-from=<(printf '%s\n' "${vs[@]}"|sed '/^$/d') "$sta0/" "$d/"
    # -H, e.g. same inode files in usr/lib/dri of mesa pkg
}
_compat32doc(){ local d="$1"
    local a="$sta0/usr/doc";[ ! -d "$a" ]&&return
    
    # retains COPYING and AUTHORS, and anything not in 64bit pkg (nothing?)
    local c="$d/usr/doc";mkdir -p "$c"
    declare -a opts=(-type f \( -name 'COPYING' -o -name 'AUTHORS' \) -printf '%P\n')
    declare -a vs;mapfile -t vs< <(find "$a" "${opts[@]}"|sed '/^$/d')
    rsync -a --files-from=<(printf '%s\n' "${vs[@]}"|sed '/^$/d') "$a/" "$c/"
    (cd "$d";rmdir -p 'usr/doc' --ignore-fail-on-non-empty)
    #find "$d" -type d -depth -exec rmdir --ignore-fail-on-non-empty {} +
}
_compat32doinst(){ local d="$1"
    local f="$sta0/install/doinst.sh";[ ! -f "$f" ]&&return
    
    local g="$d/install/doinst.sh"
    install -TDm755 /dev/null "$g"
    sed '/^( cd \(\(usr\/\)\?lib\(\/.*\)\?\|usr\/bin\) ;.*)$/!d' "$f" \
        |sed 's/cd usr\/bin/\0\/32/;T;s/ln -sf ..\//\0..\//' \
        |tee "$g">/dev/null
    [ -s "$g" ]||rm "$f"
    
    # there's no pkg in scope uses the config/preserve_perms
    # function with arg other than etc*
}

pkgset=(
Mako
SDL2
SDL2_gfx
SDL2_image
SDL2_mixer
SDL2_net
SDL2_ttf
aaa_libraries
aalib
alsa-lib
alsa-oss
alsa-plugins
at-spi2-atk
at-spi2-core
atk
attr
audiofile
brotli
bzip2
c-ares
cairo
cdparanoia
cracklib
cups
cups-filters
curl
cyrus-sasl
dbus
dbus-glib
e2fsprogs
egl-wayland
eglexternalplatform
elfutils
elogind
esound
eudev
expat
ffmpeg
fftw
flac
fluidsynth
fontconfig
freeglut
freetype
fribidi
gamin
gc
gdk-pixbuf2
gdk-pixbuf2-xlib
giflib
glew
glib2
glu
gmp
gnome-keyring
gnutls
gobject-introspection
graphene
graphite2
gst-plugins-bad-free
gst-plugins-base
gst-plugins-good
gst-plugins-libav
gstreamer
gtk+2
gtk+3
harfbuzz
icu4c
intel-vaapi-driver
isl
jansson
jasper
json-c
json-glib
keyutils
krb5
lame
lcms
lcms2
libFS
libICE
libSM
libX11
libXScrnSaver
libXau
libXaw
libXcomposite
libXcursor
libXdamage
libXdmcp
libXevie
libXext
libXfixes
libXfont2
libXfontcache
libXft
libXi
libXinerama
libXmu
libXp
libXpm
libXrandr
libXrender
libXres
libXt
libXtst
libXv
libXvMC
libXxf86dga
libXxf86misc
libXxf86vm
libaio
libarchive
libasyncns
libbluray
libcaca
libcap
libcdio
libcdio-paranoia
libclc
libdbusmenu
libdmx
libdrm
libdvdnav
libedit
libepoxy
libexif
libffi
libfontenc
libgcrypt
libglade
libglvnd
libgnt
libgpg-error
libgphoto2
libgudev
libidn
libidn2
libieee1284
libinput
libjpeg-turbo
libmad
libmng
libmpc
libnice
libnl3
libnotify
libnsl
libnss_nis
libogg
libpcap
libpciaccess
libpng
libpthread-stubs
libpwquality
librsvg
libsamplerate
libsigc++3
libsndfile
libssh
libtasn1
libtheora
libtiff
libtirpc
libtool
libunistring
libunwind
liburing
libusb
libva
libvdpau
libvorbis
libvpx
libwacom
libwebp
libxcb
libxkbcommon
libxml2
libxshmfence
libxslt
llvm
lm_sensors
lmdb
lz4
lzlib
lzo
mariadb
mesa
mozilla-nss
mpg123
ncurses
nettle
ocl-icd
openal-soft
opencl-headers
openexr
openjpeg
openldap
openssl
openssl-solibs
opus
orc
p11-kit
pam
pango
pcre
pcre2
pipewire
pixman
plzip
polkit
popt
pulseaudio
python-six
qt5
readline
rpcsvc-proto
samba
sane
sbc
sdl
slang
speex
speexdsp
sqlite
startup-notification
svgalib
taglib
talloc
tdb
tevent
util-linux
v4l-utils
vid.stab
vulkan-sdk
wavpack
wayland
woff2
xcb-util
xorgproto
xxHash
xz
zlib
zstd

libdvdread
nghttp2
opencv
libvisual
neon
libsoup
libproxy
)

