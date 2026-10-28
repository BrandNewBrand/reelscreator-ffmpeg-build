# ReelsCreator – FFmpeg and whisper-cli build for macOS

This repository holds the build scripts for the FFmpeg and whisper.cpp binaries that ship with the macOS version of
**ReelsCreator**, a free desktop app by Brand new Brand. It contains only the build recipe. There is no application
code here.

FFmpeg is licensed under the GNU LGPL 2.1 or later. ReelsCreator runs `ffmpeg` and `ffprobe` as separate programs. This
repository lets anyone rebuild those exact binaries from the original sources, change them and replace the copies
inside the app.

## What is built

| Component | Version | License | Source (pinned) | SHA-256 of the source archive |
|---|---|---|---|---|
| FFmpeg (`ffmpeg`, `ffprobe`) | 8.1.3 | LGPL-2.1-or-later | https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz | `7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3` |
| OpenH264 (linked into FFmpeg) | 2.6.0 | BSD-2-Clause | https://github.com/cisco/openh264/archive/refs/tags/v2.6.0.tar.gz | `558544ad358283a7ab2930d69a9ceddf913f4a51ee9bf1bfb9e377322af81a69` |
| whisper.cpp (`whisper-cli`) | b5454 | MIT | https://github.com/ggml-org/whisper.cpp/archive/refs/tags/b5454.tar.gz | `9aa617f410d9c7f0dae952eb2b77eafdcfb310c2d622cca1f83633fd89a213bc` |

The versions and checksums live in [`versions.sh`](versions.sh). [`build.sh`](build.sh) downloads each archive and
checks it against the SHA-256 before it builds anything.

Two architectures are built: `arm64` (Apple silicon) and `x64` (Intel). The minimum macOS version is 12.0.

### Patches

None. The sources are built unmodified, exactly as downloaded from the URLs above.

### FFmpeg configure options

```
--prefix=<work>/ffmpeg-out --arch=<aarch64|x86_64> --cc=clang
--disable-gpl --disable-nonfree --disable-version3
--enable-static --disable-shared
--disable-autodetect --enable-videotoolbox --enable-audiotoolbox --enable-zlib --enable-libopenh264
--disable-doc --disable-debug --disable-ffplay
--pkg-config-flags=--static
--extra-cflags="-mmacosx-version-min=12.0 -I<work>/deps/include"
--extra-ldflags="-mmacosx-version-min=12.0 -L<work>/deps/lib"
--extra-libs=-lc++
```

- No GPL or nonfree components (`--disable-gpl --disable-nonfree`) and no LGPL v3 (`--disable-version3`).
- `--disable-autodetect` keeps any library installed on the build machine (for example from Homebrew) out of the build.
  Only the libraries enabled explicitly are used:
  - Apple VideoToolbox and AudioToolbox, the system hardware H.264 encoder and decoder;
  - zlib from macOS;
  - OpenH264, built from source and linked statically. It is a fallback H.264 encoder.
- `ffmpeg` and `ffprobe` are linked statically against the FFmpeg libraries. They depend only on libraries that ship
  with macOS, and the script checks this with `otool -L`.

OpenH264 is built with `make OS=darwin ARCH=<arm64|x86_64> CFLAGS_OPT="-O3 -mmacosx-version-min=12.0" install-static`.

### whisper.cpp CMake options

```
-DCMAKE_BUILD_TYPE=Release -DBUILD_SHARED_LIBS=OFF
-DCMAKE_OSX_ARCHITECTURES=<arm64|x86_64> -DCMAKE_OSX_DEPLOYMENT_TARGET=12.0
-DGGML_METAL=ON -DGGML_METAL_EMBED_LIBRARY=ON -DGGML_NATIVE=OFF
-DWHISPER_BUILD_TESTS=OFF -DWHISPER_BUILD_EXAMPLES=ON -DWHISPER_SDL2=OFF
x64 only: -DGGML_AVX=ON -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_F16C=ON
```

## Reproducing the build

You need:

- a Mac with the same architecture as the target (`arm64` on Apple silicon, `x64` on Intel), because the script does
  not cross-compile;
- Xcode or the Xcode Command Line Tools (`xcode-select --install`);
- `nasm`, `pkg-config` and `cmake`, for example `brew install nasm pkgconf cmake`.

Then run:

```sh
git clone https://github.com/BrandNewBrand/reelscreator-ffmpeg-build.git
cd reelscreator-ffmpeg-build
git checkout macos-binaries-<recipe>   # the tag named in BUILDINFO.txt of the binaries you have
./build.sh arm64 ./out                 # or: ./build.sh x64 ./out
```

The result is `out/reelscreator-macos-<arch>.tar.gz` and its `.sha256` file. The archive contains:

```
reelscreator-macos-<arch>/
  bin/ffmpeg, bin/ffprobe, bin/whisper-cli
  licenses/       license texts of FFmpeg, OpenH264 and whisper.cpp
  BUILDINFO.txt   versions, source URLs, checksums and the exact configure and cmake options
```

At the end the script checks the result and fails if any of these is wrong:

- the binaries link only to system libraries and have the right architecture;
- `ffmpeg -buildconf` contains no `--enable-gpl` or `--enable-nonfree`;
- `ffmpeg -L` reports the GNU Lesser General Public License;
- the encoders `h264_videotoolbox`, `libopenh264`, `aac` and `prores_ks` are present;
- a short test encode with OpenH264 works.

Builds are not bit-for-bit reproducible, because compiler versions and temporary paths differ. They are functionally
equivalent when built from the same tag.

ReelsCreator's official binaries are built on GitHub-hosted runners: `macos-15` for arm64 and `macos-15-intel` for
x64, with the default Xcode and the Homebrew tools above. [`.github/workflows/build.yml`](.github/workflows/build.yml)
runs the same build in this repository on demand (Actions → *Build macOS binaries* → *Run workflow*).

### Tags

Every recipe gets a tag `macos-binaries-<recipe>`. `<recipe>` is the first 12 hex characters of the SHA-256 of
`versions.sh` followed by `build.sh`:

```sh
cat versions.sh build.sh | shasum -a 256 | cut -c1-12
```

`BUILDINFO.txt` inside each binary archive links to the matching tag.

## Replacing the binaries in ReelsCreator

The LGPL lets you use a modified FFmpeg with ReelsCreator. Build your own `ffmpeg` and `ffprobe`, then put them in place
of the bundled ones:

```
ReelsCreator.app/Contents/Resources/bin/ffmpeg
ReelsCreator.app/Contents/Resources/bin/ffprobe
```

Changing files inside a signed app bundle invalidates its code signature. You can re-sign the app locally with
`codesign --force --deep --sign - ReelsCreator.app`. ReelsCreator needs these encoders from FFmpeg:

- `h264_videotoolbox`, or `libopenh264` as the fallback;
- `aac`;
- `prores_ks`.

## Windows

The Windows version of ReelsCreator uses the LGPL shared builds of FFmpeg from
[BtbN/FFmpeg-Builds](https://github.com/BtbN/FFmpeg-Builds). Their build scripts and sources are published there. The
DLLs sit next to `ffmpeg.exe` in the app's `resources/bin` folder and can be replaced.

## License

The scripts in this repository are released under the MIT License (see [LICENSE](LICENSE)). The components they build
keep their own licenses: FFmpeg LGPL-2.1-or-later, OpenH264 BSD-2-Clause, whisper.cpp MIT.
