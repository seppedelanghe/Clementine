#!/usr/bin/env bash
# Builds, signs, notarizes and packages a release into build/release/.
#
# Needs a "Developer ID Application" identity in the keychain and a notarytool keychain profile
# named "clementine" (xcrun notarytool store-credentials clementine --apple-id … --team-id …).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(plutil -extract CFBundleShortVersionString raw Support/Info.plist)"
IDENTITY="$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: [^"]*"' | head -1 | tr -d '"')"
[[ -n "$IDENTITY" ]] || { echo "No Developer ID Application identity in the keychain" >&2; exit 1; }

APP=build/Clementine.app
OUT=build/release
ZIP="$OUT/Clementine-$VERSION.zip"
SOURCES="$OUT/Clementine-$VERSION-ffmpeg-sources.tar.gz"

rm -rf "$OUT"
mkdir -p "$OUT"

make app CONFIG=release SIGN_IDENTITY="$IDENTITY"
codesign --verify --strict --deep "$APP"

# notarytool takes a zip; once the ticket is stapled the app is zipped again for distribution.
ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile clementine --wait | tee "$OUT/notarize.log"
grep -q "status: Accepted" "$OUT/notarize.log" || { echo "Notarization was not accepted (see $OUT/notarize.log)" >&2; exit 1; }
xcrun stapler staple "$APP"
rm "$OUT/notarize.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
spctl --assess --type execute --verbose "$APP"

# The LGPL requires publishing the exact sources the bundled ffmpeg was built from.
tar -czf "$SOURCES" -C build/ffmpeg sources -C "$ROOT" scripts/build-ffmpeg.sh

echo "Release $VERSION:"
ls -lh "$ZIP" "$SOURCES"
