#!/usr/bin/env bash
# Fetches Sparkle's command-line tools (generate_keys, sign_update, generate_appcast) into
# build/sparkle. Pinned to the same version as the Sparkle package in Package.swift.
set -euo pipefail

SPARKLE=2.10.0
SPARKLE_SHA256=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/sparkle"
ARCHIVE="$WORK/Sparkle-$SPARKLE.tar.xz"

mkdir -p "$WORK"
if [[ ! -f "$ARCHIVE" ]]; then
    curl -fL --retry 3 -o "$ARCHIVE.part" \
        "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE/Sparkle-$SPARKLE.tar.xz"
    mv "$ARCHIVE.part" "$ARCHIVE"
fi
echo "$SPARKLE_SHA256  $ARCHIVE" | shasum -a 256 -c --quiet -
rm -rf "$WORK/bin"
tar -xf "$ARCHIVE" -C "$WORK" bin
