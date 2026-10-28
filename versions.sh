# Pinned sources for the ReelsCreator macOS binaries:
# FFmpeg (LGPL, VideoToolbox), OpenH264 (fallback H.264 encoder) and whisper-cli (whisper.cpp with Metal).
# Any change to versions.sh or build.sh is a new recipe and gets a new tag: macos-binaries-<recipe hash>.
FFMPEG_VERSION=8.1.3
FFMPEG_URL=https://ffmpeg.org/releases/ffmpeg-8.1.3.tar.xz
FFMPEG_SHA256=7138d28c96d9d3e3af4ee3d8cad72741f8ffb40da90c1112235dea3ecd3178a3

OPENH264_VERSION=2.6.0
OPENH264_URL=https://github.com/cisco/openh264/archive/refs/tags/v2.6.0.tar.gz
OPENH264_SHA256=558544ad358283a7ab2930d69a9ceddf913f4a51ee9bf1bfb9e377322af81a69

WHISPER_VERSION=b5454
WHISPER_URL=https://github.com/ggml-org/whisper.cpp/archive/refs/tags/b5454.tar.gz
WHISPER_SHA256=9aa617f410d9c7f0dae952eb2b77eafdcfb310c2d622cca1f83633fd89a213bc

# Electron 45 requires macOS 12.
MACOS_MIN=12.0
