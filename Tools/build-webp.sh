#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${SDK_PATH:?Set SDK_PATH to your prepared build SDK}"
ROOT="$PWD"
SDK="$(cd "$SDK_PATH" && pwd)"
WEBP="$ROOT/build/webp"
VERSION=1.6.0
SHA256=e4ab7009bf0629fd11982d4c2aa83964cf244cffba7347ecd39019a9e38c4564
ARCHIVE="$WEBP/libwebp-$VERSION.tar.gz"
SOURCE="$WEBP/libwebp-$VERSION"
mkdir -p "$WEBP"
if [ ! -f "$ARCHIVE" ]; then
  curl --fail --location --retry 3 --connect-timeout 15 --max-time 180 --proto '=https' --tlsv1.2 \
    "https://storage.googleapis.com/downloads.webmproject.org/releases/webp/libwebp-$VERSION.tar.gz" \
    -o "$ARCHIVE.download"
  printf '%s  %s\n' "$SHA256" "$ARCHIVE.download" | shasum -a 256 -c -
  mv "$ARCHIVE.download" "$ARCHIVE"
fi
printf '%s  %s\n' "$SHA256" "$ARCHIVE" | shasum -a 256 -c -
if [ ! -d "$SOURCE" ]; then tar -xzf "$ARCHIVE" -C "$WEBP"; fi
cmake -S "$SOURCE" -B "$WEBP/build-armv7" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_ARCHITECTURES=armv7 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=5.1 -DCMAKE_OSX_SYSROOT="$SDK" \
  -DCMAKE_C_COMPILER="$(xcrun --find clang)" \
  -DCMAKE_C_FLAGS="-target armv7-apple-ios5.1 -fPIC" \
  -DCMAKE_BUILD_TYPE=MinSizeRel -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
  -DBUILD_SHARED_LIBS=OFF -DWEBP_ENABLE_SIMD=OFF -DWEBP_USE_THREAD=OFF \
  -DWEBP_BUILD_ANIM_UTILS=OFF -DWEBP_BUILD_CWEBP=OFF -DWEBP_BUILD_DWEBP=OFF \
  -DWEBP_BUILD_GIF2WEBP=OFF -DWEBP_BUILD_IMG2WEBP=OFF -DWEBP_BUILD_VWEBP=OFF \
  -DWEBP_BUILD_WEBPINFO=OFF -DWEBP_BUILD_LIBWEBPMUX=OFF \
  -DWEBP_BUILD_WEBPMUX=OFF -DWEBP_BUILD_EXTRAS=OFF
cmake --build "$WEBP/build-armv7" --target webpdecoder -j 4
mkdir -p "$WEBP/lib" "$WEBP/include/webp"
cp "$WEBP/build-armv7/libwebpdecoder.a" "$WEBP/lib/"
cp "$SOURCE/src/webp/decode.h" "$SOURCE/src/webp/types.h" "$WEBP/include/webp/"
