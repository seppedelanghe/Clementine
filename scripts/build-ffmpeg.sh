#!/usr/bin/env bash
# Builds a static, LGPL, arm64-only ffmpeg for bundling. docs/ffmpeg.md explains the choices.
#
# Every dependency is pinned to an exact version and SHA-256. Upgrading one is a deliberate edit
# here: bump the version, update the checksum, rebuild.
set -euo pipefail

FFMPEG=ffmpeg-9.0.2
FFMPEG_SHA256=8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e
LAME=lame-3.101
LAME_SHA256=7578af6eebd578b2bd64e468fac4ae1f03670a7e028166e67f855674b9b6aeac
OGG=libogg-1.3.6
OGG_SHA256=5c8253428e181840cd20d41f3ca16557a9cc04bad4a3d04cce84808677fa1061
VORBIS=libvorbis-1.3.7
VORBIS_SHA256=b33cc4934322bcbf6efcbacf49e3ca01aadbea4114ec9589d1b1e9d20f72954b
OPUS=opus-1.6.1
OPUS_SHA256=6ffcb593207be92584df15b32466ed64bbec99109f007c82205f0194572411a1
VPX=libvpx-1.17.0
VPX_SHA256=1020f184046187baa2985dbde38e0691f49c44088bca7a1842b0236c6081dc0a

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/ffmpeg"
SOURCES="$WORK/sources" # Kept: an LGPL release must ship the exact sources it was built from.
SRC="$WORK/src"
PREFIX="$WORK/prefix"
OUT="$WORK/bin"
LICENSES="$WORK/licenses"
MIN_MACOS=14.0
JOBS="$(sysctl -n hw.ncpu)"

export CC=clang
export CFLAGS="-arch arm64 -mmacosx-version-min=$MIN_MACOS -O2"
export LDFLAGS="-arch arm64 -mmacosx-version-min=$MIN_MACOS"
# Only our prefix: a Homebrew .pc file would otherwise link a dylib that users don't have.
export PKG_CONFIG_LIBDIR="$PREFIX/lib/pkgconfig"
unset PKG_CONFIG_PATH CPATH LIBRARY_PATH

command -v pkg-config >/dev/null || { echo "pkg-config is required: brew install pkgconf" >&2; exit 1; }

rm -rf "$SRC" "$PREFIX" "$OUT" "$LICENSES"
mkdir -p "$SOURCES" "$SRC" "$PREFIX" "$OUT" "$LICENSES"

fetch() {
    local file="$1" url="$2" sha256="$3"
    if [[ ! -f "$SOURCES/$file" ]]; then
        curl -fL --retry 3 -o "$SOURCES/$file.part" "$url"
        mv "$SOURCES/$file.part" "$SOURCES/$file"
    fi
    echo "$sha256  $SOURCES/$file" | shasum -a 256 -c --quiet -
    tar -xf "$SOURCES/$file" -C "$SRC"
}

autotools() {
    local dir="$1"
    shift
    (cd "$SRC/$dir" && ./configure --prefix="$PREFIX" --enable-static --disable-shared "$@" && make -j"$JOBS" && make install)
}

fetch "$FFMPEG.tar.xz" "https://ffmpeg.org/releases/$FFMPEG.tar.xz" "$FFMPEG_SHA256"
fetch "$LAME.tar.gz" "https://downloads.sourceforge.net/project/lame/lame/${LAME#lame-}/$LAME.tar.gz" "$LAME_SHA256"
fetch "$OGG.tar.xz" "https://downloads.xiph.org/releases/ogg/$OGG.tar.xz" "$OGG_SHA256"
fetch "$VORBIS.tar.xz" "https://downloads.xiph.org/releases/vorbis/$VORBIS.tar.xz" "$VORBIS_SHA256"
fetch "$OPUS.tar.gz" "https://downloads.xiph.org/releases/opus/$OPUS.tar.gz" "$OPUS_SHA256"
fetch "$VPX.tar.gz" "https://github.com/webmproject/libvpx/archive/refs/tags/v${VPX#libvpx-}.tar.gz" "$VPX_SHA256"

autotools "$OGG"
# 1.3.7's configure adds -force_cpusubtype_ALL on Darwin, which arm64 builds don't support.
sed -i '' 's/ -force_cpusubtype_ALL//' "$SRC/$VORBIS/configure"
autotools "$VORBIS" --with-ogg="$PREFIX" --disable-oggtest --disable-docs --disable-examples
autotools "$OPUS" --disable-doc --disable-extra-programs
# ffmpeg only encodes with LAME; its decoder would pull in libmpg123 since 3.101.
autotools "$LAME" --disable-frontend --disable-decoder

(
    cd "$SRC/$VPX"
    # The unversioned arm64-darwin-gcc target means iOS; darwin23 is macOS 14, the minimum.
    ./configure --prefix="$PREFIX" --target=arm64-darwin23-gcc --enable-static --disable-shared --enable-pic \
        --disable-examples --disable-tools --disable-docs --disable-unit-tests \
        --extra-cflags="-mmacosx-version-min=$MIN_MACOS"
    make -j"$JOBS"
    make install
)

(
    cd "$SRC/$FFMPEG"
    ./configure --prefix="$PREFIX" --cc=clang --arch=arm64 \
        --extra-cflags="$CFLAGS -I$PREFIX/include" --extra-ldflags="$LDFLAGS -L$PREFIX/lib" \
        --pkg-config=pkg-config --pkg-config-flags=--static \
        --enable-static --disable-shared \
        --disable-autodetect --enable-videotoolbox --enable-audiotoolbox --enable-zlib \
        --disable-ffplay --disable-ffprobe --disable-doc --disable-debug --disable-network --disable-avdevice \
        --enable-libmp3lame --enable-libopus --enable-libvorbis --enable-libvpx \
        --disable-encoders \
        --enable-encoder=h264_videotoolbox,hevc_videotoolbox,aac_at,aac,libmp3lame,libopus,libvorbis,libvpx_vp9,flac,pcm_s16le,pcm_s16be,wmv2,wmav2,mpeg4,gif \
        --disable-muxers \
        --enable-muxer=mp4,mov,ipod,matroska,webm,avi,asf,gif,mp3,ogg,oga,opus,flac,wav,aiff \
        --disable-protocols --enable-protocol=file,pipe
    make -j"$JOBS"
    cp ffmpeg "$OUT/ffmpeg"
)

# Anything outside the OS would be missing on users' Macs.
if otool -L "$OUT/ffmpeg" | tail -n +2 | grep -vE '^[[:space:]]+(/usr/lib/|/System/Library/)'; then
    echo "ffmpeg links a library outside the OS (listed above)" >&2
    exit 1
fi

cp "$SRC/$FFMPEG/LICENSE.md" "$LICENSES/ffmpeg-LICENSE.md"
cp "$SRC/$FFMPEG/COPYING.LGPLv2.1" "$LICENSES/ffmpeg-COPYING.LGPLv2.1"
cp "$SRC/$LAME/COPYING" "$LICENSES/lame-COPYING"
cp "$SRC/$OGG/COPYING" "$LICENSES/libogg-COPYING"
cp "$SRC/$VORBIS/COPYING" "$LICENSES/libvorbis-COPYING"
cp "$SRC/$OPUS/COPYING" "$LICENSES/opus-COPYING"
cp "$SRC/$VPX/LICENSE" "$LICENSES/libvpx-LICENSE"
cp "$SRC/$VPX/PATENTS" "$LICENSES/libvpx-PATENTS"

echo "Built $OUT/ffmpeg ($(du -h "$OUT/ffmpeg" | cut -f1))"
