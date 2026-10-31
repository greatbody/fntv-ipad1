# Third-party notices

## libwebp 1.6.0

The Google WebM Project's libwebp decoder is downloaded from its official release archive and linked during the build. It is licensed under BSD-3-Clause with Google's Additional IP Rights Grant (Patents). The complete upstream notices are preserved in [Assets/libwebp-LICENSE.txt](Assets/libwebp-LICENSE.txt) and copied into the application bundle. These terms are separate from the MIT license for this project's own source and original artwork.

Upstream: https://github.com/webmproject/libwebp/tree/v1.6.0

## Original artwork and synthetic fixtures

The PNG artwork in `Assets/` was created for this public repository with [Tools/generate-assets.swift](Tools/generate-assets.swift). See [Assets/README.md](Assets/README.md), [Assets/LICENSE.txt](Assets/LICENSE.txt), and its manifest. No vendor image or distributed font file is used as a generator input.

The small WebP test images are synthetic gradients. See [Tests/Fixtures/README.md](Tests/Fixtures/README.md) for provenance. They contain no user media.

## External platform prerequisites

Apple frameworks and the Apple SDK/toolchain are external prerequisites. They are not distributed by this repository and are not licensed by this project's MIT license. Obtain and use them under the applicable Apple terms. SDK preparation operates on a build-local copy; it does not grant rights to the input SDK or its system libraries.

FNTV compatibility names and protocol references identify the supported server software. This is an independent project, not an official vendor client. No official APK, extracted vendor artwork, SDK archive or user media is included.
