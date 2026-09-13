# AOU Hub — releases & updates

Carries the in-app update manifest and the one human-editable release-control
file. No app source lives here.

Official repository: **`ssssoliman937-design/aouapp`** (default branch `main`).

## Files
- **`upaou.json`** — the only file a human edits: `version`, `build`,
  `mandatory`, `minimum_build`, and the bilingual `title_*` / `message_*` that
  students read. It never contains a hash, size, signer, URL or sequence —
  those are generated. (`release-control.json` is an accepted older alias.)
- **`update/update.json`** — the signed manifest the app reads. **Generated**
  from `release-control.json`; never hand-edit it.
- **`update/update.json.sig`** — Ed25519 signature over `update.json`.
- **`update/update.schema.json`** — the manifest schema.

## Publishing a release (from `aou_hub/`)
1. Set `pubspec.yaml` (e.g. `1.5.0+2008`) and edit `release-control.json` to match.
2. `dart run tool/release/build_release.dart --manifest-url https://raw.githubusercontent.com/ssssoliman937-design/aouapp/main/update/update.json`
   — builds the obfuscated universal APK, verifies package/version/signer/ABI, stages `aou_hub/release/<version>-<build>/`.
3. `dart run tool/release/release_control.dart --owner ssssoliman937-design`
   — validates `release-control.json` against `pubspec.yaml` **and** the built APK, then writes `update/update.json`. Fails loudly on any mismatch.
4. `dart run tool/release/manifest_key.dart sign ../aouapp/update/update.json`
5. `dart run tool/release/verify_published.dart` after uploading, to re-download and check everything a real install would.
6. Commit `upaou.json`, `update/update.json`, `update/update.json.sig` to `main`,
   create GitHub Release **`v<version>`** titled **`AOU Hub <version>`**, and upload
   the universal APK asset `AOU-Hub-<version>-<build>-universal.apk` under that tag.
   The asset file name must match the one in `update/update.json` exactly, or the
   in-app updater's SHA-256 check will reject the download.

## Security
`update.json` is signed with Ed25519 and verified by the app against a public
key compiled into the build. No signing key — app or manifest — is in this
repository.
