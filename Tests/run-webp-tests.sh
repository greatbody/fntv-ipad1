#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
SOURCE="$PWD/build/webp/libwebp-1.6.0"
if [ ! -d "$SOURCE" ]; then echo 'Run build.sh first to fetch the pinned decoder source.' >&2; exit 2; fi
cmake -S "$SOURCE" -B build/webp/build-host -G Ninja \
    -DCMAKE_BUILD_TYPE=MinSizeRel -DBUILD_SHARED_LIBS=OFF \
    -DWEBP_ENABLE_SIMD=OFF -DWEBP_USE_THREAD=OFF
cmake --build build/webp/build-host --target webpdecoder -j 4
mkdir -p build/tests
xcrun clang -O2 -Wall -Wextra -Werror -I "$SOURCE/src" Tools/webp-selftest.c \
    build/webp/build-host/libwebpdecoder.a -o build/tests/webp-selftest
build/tests/webp-selftest Tests/Fixtures/fixture-lossless.webp 3b0c8dc5
build/tests/webp-selftest Tests/Fixtures/fixture-lossy.webp 2822f5c8
