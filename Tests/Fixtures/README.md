# Synthetic fixtures

`fixture-lossless.webp` and `fixture-lossy.webp` encode an original programmatically generated 64 × 96 colour gradient. They contain no NAS image, user data, vendor artwork or photograph. Both were encoded with libwebp 1.6.0. The host decoder test scales each to 32 × 48 RGBA and checks an FNV-1a checksum (`3b0c8dc5` lossless; `2822f5c8` lossy), then rejects truncated input. These fixture images are provided under the repository's MIT licence.

`../signature-fixtures.json` uses reserved `.invalid` hostnames, fixed artificial timestamps/nonces, and synthetic request bodies. Its expected signatures are interoperability regression values, not credentials or captured NAS requests. Other tests use synthetic media IDs, fixture-only tokens/passwords and loopback servers created only for the test run. The UI framework stubs implement the minimum behaviours needed for host control-flow checks; they do not emulate a real iPad.
