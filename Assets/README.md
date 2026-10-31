# Original artwork

The 18 PNG files in this directory are original programmatic artwork for this
independent client, licensed under [MIT](LICENSE.txt). They contain simple
geometric media symbols and the plain text “NAS CINEMA” / “FNTV iPad client”.
They do not contain vendor artwork, logos, screenshots, extracted APK content,
or user media. “FNTV” identifies compatibility; this is not an official client.

The existing filenames and pixel dimensions are retained as resource interfaces.
The `brand-*` names do not imply that those images are official brand assets.
`manifest.json` records each PNG's dimensions, SHA-256, source and licence.

Regenerate on macOS with its Swift toolchain:

```sh
swift Tools/generate-assets.swift
```

The generator uses system AppKit drawing and system fonts; no font files or extra
packages are redistributed. Normal application builds use the checked-in PNGs
and do not run the generator. System font rendering or PNG encoding may change
between macOS versions, so regeneration also updates the recorded hashes.
The generator checks the decoded PNG dimensions and the 18-file inventory.

The [libwebp notice](libwebp-LICENSE.txt) is separate from the artwork licence.
It retains libwebp 1.6.0's BSD copyright, conditions and disclaimer, followed by
Google's Additional IP Rights Grant (Patents). It is not covered or replaced by
the MIT licence. Builds distributing the decoder must retain this notice.
