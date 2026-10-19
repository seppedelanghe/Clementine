#!/usr/bin/env bash
# Builds, signs, notarizes and packages a release into build/release/.
#
# Needs a "Developer ID Application" identity in the keychain and a notarytool keychain profile
# named "clementine" (xcrun notarytool store-credentials clementine --apple-id … --team-id …).
# NOTARIZE=0 skips notarization: still Developer ID signed, but Gatekeeper makes users approve it.
set -euo pipefail

NOTARIZE="${NOTARIZE:-1}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="$(plutil -extract CFBundleShortVersionString raw Support/Info.plist)"
# The personal developer account, not any company identity that may share the keychain.
IDENTITY="$(security find-identity -v -p codesigning | grep -o '"Developer ID Application: Seppe De Langhe ([^"]*"' | head -1 | tr -d '"')"
[[ -n "$IDENTITY" ]] || { echo "No personal Developer ID Application identity in the keychain" >&2; exit 1; }

APP=build/Clementine.app
OUT=build/release
ZIP="$OUT/Clementine-$VERSION.zip"
SOURCES="$OUT/Clementine-$VERSION-ffmpeg-sources.tar.gz"

rm -rf "$OUT"
mkdir -p "$OUT"

make app CONFIG=release SIGN_IDENTITY="$IDENTITY"
codesign --verify --strict --deep "$APP"

if [[ "$NOTARIZE" == 1 ]]; then
    # notarytool takes a zip; once the ticket is stapled the app is zipped again for distribution.
    ditto -c -k --keepParent "$APP" "$OUT/notarize.zip"
    xcrun notarytool submit "$OUT/notarize.zip" --keychain-profile clementine --wait | tee "$OUT/notarize.log"
    grep -q "status: Accepted" "$OUT/notarize.log" || { echo "Notarization was not accepted (see $OUT/notarize.log)" >&2; exit 1; }
    xcrun stapler staple "$APP"
    rm "$OUT/notarize.zip"
    spctl --assess --type execute --verbose "$APP"
fi
ditto -c -k --keepParent "$APP" "$ZIP"

# The LGPL requires publishing the exact sources the bundled ffmpeg was built from.
tar -czf "$SOURCES" -C build/ffmpeg sources -C "$ROOT" scripts/build-ffmpeg.sh

# The appcast lists only this release: the feed URL in Info.plist always resolves to the latest
# release's copy. generate_appcast signs the zip with the EdDSA key in the keychain.
scripts/fetch-sparkle-tools.sh
mkdir "$OUT/appcast"
cp "$ZIP" "$OUT/appcast/"
build/sparkle/bin/generate_appcast \
    --download-url-prefix "https://github.com/seppedelanghe/Clementine/releases/download/v$VERSION/" \
    -o "$OUT/appcast.xml" "$OUT/appcast"
rm -rf "$OUT/appcast"

echo "Release $VERSION:"
ls -lh "$ZIP" "$SOURCES" "$OUT/appcast.xml"
