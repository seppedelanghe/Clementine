# Releasing

Releases are Developer ID signed, notarized and published on GitHub Releases. Sparkle reads its
feed from the latest release's `appcast.xml`, so publishing a release is also what ships the update.

## One-time setup

- **Signing identity.** A `Developer ID Application: Seppe De Langhe (…)` certificate from the
  personal developer account, plus Apple's intermediate certificate, which Xcode would otherwise
  install. Without it signing fails with "unable to build chain to self-signed root":

  ```sh
  curl -fsSLo /tmp/DeveloperIDG2CA.cer https://www.apple.com/certificateauthority/DeveloperIDG2CA.cer
  security import /tmp/DeveloperIDG2CA.cer -k ~/Library/Keychains/login.keychain-db
  security find-identity -v -p codesigning   # must list the identity as valid
  ```

- **Notary profile.** An app-specific password for the developer Apple Account, stored once:

  ```sh
  xcrun notarytool store-credentials clementine --apple-id <Apple Account> --team-id <team ID>
  ```

  A 403 "required agreement is missing or has expired" means App Store Connect hasn't caught up
  with an accepted Program License Agreement yet.

- **Sparkle key.** The EdDSA private key lives in the login keychain (`build/sparkle/bin/generate_keys`
  created it); its public half is `SUPublicEDKey` in `Support/Info.plist`. Losing it means installed
  copies can never update again, so keep the exported backup (`generate_keys -x`) somewhere safe.

## Per release

1. Bump both versions in `Support/Info.plist`: `CFBundleShortVersionString` (e.g. `0.1.1`) and
   `CFBundleVersion` (`2`, `3`, …). Sparkle compares `CFBundleVersion`, so it must increase.
2. Commit and push.
3. `make release` — builds, signs, notarizes, staples and writes to `build/release/`:
   `Clementine-<version>.zip`, `Clementine-<version>-ffmpeg-sources.tar.gz` and `appcast.xml`.
   `NOTARIZE=0 make release` skips notarization (0.1.0 shipped that way).
4. Tag and publish all three files; the sources tarball is required by the LGPL:

   ```sh
   git tag -a v<version> -m "Clementine <version>" && git push origin v<version>
   gh release create v<version> --verify-tag --title "Clementine <version>" --notes-file <notes> \
       build/release/Clementine-<version>.zip \
       build/release/Clementine-<version>-ffmpeg-sources.tar.gz \
       build/release/appcast.xml
   ```

5. Check that `https://github.com/seppedelanghe/Clementine/releases/latest/download/appcast.xml`
   offers the new version.

## Pinned dependencies

ffmpeg and its libraries (`scripts/build-ffmpeg.sh`), Sparkle (`Package.swift`, `Package.resolved`)
and Sparkle's tools (`scripts/fetch-sparkle-tools.sh`) are pinned to exact versions and checksums.
Bumping one is a deliberate edit of version and checksum; check upstream security fixes before each
release, since a pinned version never picks them up on its own.
