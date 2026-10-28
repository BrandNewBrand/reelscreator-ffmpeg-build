#!/usr/bin/env bash
# Builds ffmpeg + ffprobe (LGPL 2.1, no GPL and no nonfree parts, VideoToolbox + AudioToolbox, OpenH264 linked
# statically) and whisper-cli (whisper.cpp with Metal) for one macOS architecture and packs them into a tar.gz.
# Usage: ./build.sh <arm64|x64> <output-dir>
set -euo pipefail

ARCH="${1:?arm64 or x64}"
OUT="${2:?output directory}"
HERE="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=versions.sh
source "$HERE/versions.sh"
RECIPE="$(cat "$HERE/versions.sh" "$HERE/build.sh" | shasum -a 256 | cut -c1-12)"

case "$ARCH" in
  arm64) CPU=arm64; FFARCH=aarch64 ;;
  x64) CPU=x86_64; FFARCH=x86_64 ;;
  *) echo "Unknown architecture: $ARCH" >&2; exit 1 ;;
esac
[ "$(uname -m)" = "$CPU" ] || { echo "Build on a $CPU machine (this one is $(uname -m))" >&2; exit 1; }

WORK="$(mktemp -d)"
DEPS="$WORK/deps"
PKG="$OUT/reelscreator-macos-$ARCH"
mkdir -p "$DEPS" "$PKG/bin" "$PKG/licenses"
export MACOSX_DEPLOYMENT_TARGET="$MACOS_MIN"
JOBS="$(sysctl -n hw.ncpu)"

fetch() { # url sha256 file
  curl -fsSL --retry 3 -o "$WORK/$3" "$1"
  echo "$2  $WORK/$3" | shasum -a 256 -c -
}

echo "== OpenH264 $OPENH264_VERSION (BSD-2-Clause, static - fallback H.264 encoder)"
fetch "$OPENH264_URL" "$OPENH264_SHA256" openh264.tar.gz
tar -xzf "$WORK/openh264.tar.gz" -C "$WORK"
make -C "$WORK/openh264-$OPENH264_VERSION" -j"$JOBS" OS=darwin ARCH="$CPU" PREFIX="$DEPS" \
  CFLAGS_OPT="-O3 -mmacosx-version-min=$MACOS_MIN" install-static >/dev/null

echo "== FFmpeg $FFMPEG_VERSION (LGPL 2.1)"
fetch "$FFMPEG_URL" "$FFMPEG_SHA256" ffmpeg.tar.xz
tar -xJf "$WORK/ffmpeg.tar.xz" -C "$WORK"
FFCONF=(
  --prefix="$WORK/ffmpeg-out" --arch="$FFARCH" --cc=clang
  --disable-gpl --disable-nonfree --disable-version3
  --enable-static --disable-shared
  --disable-autodetect --enable-videotoolbox --enable-audiotoolbox --enable-zlib --enable-libopenh264
  --disable-doc --disable-debug --disable-ffplay
  --pkg-config-flags=--static
  --extra-cflags="-mmacosx-version-min=$MACOS_MIN -I$DEPS/include"
  --extra-ldflags="-mmacosx-version-min=$MACOS_MIN -L$DEPS/lib"
  --extra-libs=-lc++
)
(cd "$WORK/ffmpeg-$FFMPEG_VERSION" && PKG_CONFIG_PATH="$DEPS/lib/pkgconfig" ./configure "${FFCONF[@]}" >/dev/null && make -j"$JOBS" >/dev/null && make install >/dev/null)
cp "$WORK/ffmpeg-out/bin/ffmpeg" "$WORK/ffmpeg-out/bin/ffprobe" "$PKG/bin/"
cp "$WORK/ffmpeg-$FFMPEG_VERSION/COPYING.LGPLv2.1" "$PKG/licenses/ffmpeg-COPYING.LGPLv2.1"
cp "$WORK/ffmpeg-$FFMPEG_VERSION/LICENSE.md" "$PKG/licenses/ffmpeg-LICENSE.md"
cp "$WORK/openh264-$OPENH264_VERSION/LICENSE" "$PKG/licenses/openh264-LICENSE"

echo "== whisper.cpp $WHISPER_VERSION (MIT, Metal)"
fetch "$WHISPER_URL" "$WHISPER_SHA256" whisper.tar.gz
tar -xzf "$WORK/whisper.tar.gz" -C "$WORK"
WCONF=(
  -DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF
  -DCMAKE_OSX_ARCHITECTURES="$CPU" -DCMAKE_OSX_DEPLOYMENT_TARGET="$MACOS_MIN"
  -DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_NATIVE=OFF
  -DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=ON -DWHISPER_SDL2=OFF
)
# Intel: every Mac that runs macOS 12+ has AVX2/FMA/F16C.
[ "$ARCH" = "x64" ] && WCONF+=(-DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON)
cmake -S "$WORK/whisper.cpp-$WHISPER_VERSION" -B "$WORK/whisper-build" "${WCONF[@]}" >/dev/null
cmake --build "$WORK/whisper-build" --config Release -j"$JOBS" --target whisper-cli >/dev/null
cp "$WORK/whisper-build/bin/whisper-cli" "$PKG/bin/"
cp "$WORK/whisper.cpp-$WHISPER_VERSION/LICENSE" "$PKG/licenses/whisper.cpp-LICENSE"

echo "== checks"
strip -x "$PKG/bin/"* || true
for bin in "$PKG/bin/"*; do
  # System libraries only - nothing from Homebrew or /usr/local.
  if otool -L "$bin" | tail -n +2 | grep -Ev '^\s+(/usr/lib/|/System/Library/)'; then
    echo "$bin links libraries outside the system" >&2; exit 1
  fi
  lipo -archs "$bin" | grep -qx "$CPU" || { echo "$bin: wrong architecture" >&2; exit 1; }
done
BUILDCONF="$("$PKG/bin/ffmpeg" -hide_banner -buildconf)"
if grep -Eq -- '--enable-(gpl|nonfree)' <<<"$BUILDCONF"; then echo "ffmpeg built with GPL/nonfree" >&2; exit 1; fi
"$PKG/bin/ffmpeg" -hide_banner -L | grep -q 'GNU Lesser General Public' || { echo "ffmpeg is not LGPL" >&2; exit 1; }
for enc in h264_videotoolbox libopenh264 aac prores_ks; do
  "$PKG/bin/ffmpeg" -hide_banner -encoders | grep -q " $enc " || { echo "missing encoder $enc" >&2; exit 1; }
done
"$PKG/bin/ffmpeg" -hide_banner -loglevel error -f lavfi -i testsrc2=s=320x240:d=1 -c:v libopenh264 -f null -
"$PKG/bin/whisper-cli" --help >/dev/null 2>&1

cat > "$PKG/BUILDINFO.txt" <<INFO
ReelsCreator - macOS $ARCH binaries built with build.sh
Recipe: https://github.com/BrandNewBrand/reelscreator-ffmpeg-build/tree/macos-binaries-$RECIPE

FFmpeg $FFMPEG_VERSION - LGPL 2.1 or later (no --enable-gpl, no --enable-nonfree)
  source: $FFMPEG_URL
  SHA-256: $FFMPEG_SHA256
  configure: ${FFCONF[*]}
OpenH264 $OPENH264_VERSION - BSD-2-Clause, linked statically
  source: $OPENH264_URL
  SHA-256: $OPENH264_SHA256
whisper.cpp $WHISPER_VERSION - MIT, Metal
  source: $WHISPER_URL
  SHA-256: $WHISPER_SHA256
  cmake: ${WCONF[*]}
INFO

tar -czf "$OUT/reelscreator-macos-$ARCH.tar.gz" -C "$OUT" "reelscreator-macos-$ARCH"
shasum -a 256 "$OUT/reelscreator-macos-$ARCH.tar.gz" | tee "$OUT/reelscreator-macos-$ARCH.tar.gz.sha256"
rm -rf "$WORK"
