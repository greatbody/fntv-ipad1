#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
: "${SDK_PATH:?Set SDK_PATH to your own iPhoneOS9.3.sdk directory}"
DIAGNOSTICS="${FNTV_DIAGNOSTICS:-0}"
case "$DIAGNOSTICS" in 0|1) ;; *) echo 'FNTV_DIAGNOSTICS must be 0 or 1' >&2; exit 2 ;; esac
for tool in python3 cmake ninja codesign curl shasum; do command -v "$tool" >/dev/null; done
LINKER="$(xcrun --find ld-classic)"
SDK="$PWD/build/sdk/iPhoneOS9.3.sdk"
python3 Tools/prepare-sdk.py "$SDK_PATH" "$SDK"
SDK_PATH="$SDK" bash Tools/build-webp.sh
APP="build/Payload/FNTV.app"
# Package from an empty app directory so stale resources cannot leak into a rebuild.
rm -rf "$APP"
mkdir -p "$APP"
xcrun clang -target armv7-apple-ios5.1 -isysroot "$SDK" \
    --ld-path="$LINKER" -Wl,-no_implicit_dylibs \
    -fno-objc-arc -fblocks -O2 -Wall -Wextra -Wno-deprecated-declarations -Werror=unguarded-availability \
    -DFNTV_SELF_TEST=1 -DFNTV_DIAGNOSTICS="$DIAGNOSTICS" \
    -ISources/Networking -ISources/UI -Ibuild/webp/include \
    main.m Sources/UI/*.m Sources/Networking/*.m \
    -framework UIKit -framework Foundation -framework CoreGraphics -framework MediaPlayer \
    -framework Security -framework ImageIO -framework AVFoundation \
    build/webp/lib/libwebpdecoder.a -o "$APP/FNTV"
cp Info.plist "$APP/Info.plist"
cp Assets/*.png Assets/libwebp-LICENSE.txt "$APP/"
cp LICENSE "$APP/PROJECT-LICENSE.txt"
cp Assets/LICENSE.txt "$APP/ARTWORK-LICENSE.txt"
printf 'APPL????' > "$APP/PkgInfo"
codesign --force --sign - --timestamp=none --digest-algorithm=sha1,sha256 --entitlements Entitlements.plist "$APP"
codesign --verify "$APP"
plutil -lint "$APP/Info.plist"
FNTV_DIAGNOSTICS="$DIAGNOSTICS" python3 Tests/verify_bundle.py
