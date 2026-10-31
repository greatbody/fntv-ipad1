#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/tests
for target in diagnostic_login smoke_protocol smoke_flow; do
    output="build/tests/${target//_/-}-selftest"
    xcrun clang -fno-objc-arc -fblocks -Wall -Wextra -Wno-deprecated-declarations \
        -DFNTV_DIAGNOSTICS=1 -ITests/SmokeStubs -ISources/UI \
        "Tests/${target}_selftest.m" Sources/UI/FNTVDiagnostics.m \
        -framework Foundation -o "$output"
    "$output"
done
xcrun clang -fno-objc-arc -fblocks -Wall -Wextra -DFNTV_DIAGNOSTICS=1 -ITests/SmokeStubs -ISources/UI \
    Tests/audio_policy_selftest.m Sources/UI/FNTVAudio.m -framework Foundation \
    -o build/tests/audio-policy-selftest
build/tests/audio-policy-selftest
xcrun clang -fno-objc-arc -fblocks -Wall -Wextra -DFNTV_DIAGNOSTICS=1 -ITests/SmokeStubs -ISources/UI \
    Tests/audio_release_flow_selftest.m -framework Foundation -o build/tests/audio-release-flow-selftest
build/tests/audio-release-flow-selftest
