#!/usr/bin/env bash
# Builds docxide-pdf, the DOCX → PDF renderer, and gathers the fonts it needs on macOS.
#
# Pinned like the ffmpeg build: the crate by version and SHA-256 (its Cargo.lock pins and
# checksums every dependency), the Rust toolchain by version, the fonts by commit and SHA-256.
set -euo pipefail

# 0.18.4 reads extra font folders from DOCXSIDE_FONTS; later releases renamed it DOCXIDE_FONTS.
DOCXIDE=docxide-pdf-0.18.4
DOCXIDE_SHA256=811a7804fb4fb2a6bfe8b5ba363d3c752fd9623213310d301ec2a0300396989c
RUST_TOOLCHAIN=1.99.1
# google/fonts holds the released Carlito and Caladea builds.
FONTS_COMMIT=47d54ca1ebb14fd864695f1d39dc734f39017c33
FONTS=(
    "carlito/Carlito-Regular.ttf f6418f708baede9789daef5d458c0f53d2a888af9820e8062934e504fedc6595"
    "carlito/Carlito-Bold.ttf bb5d20f79b82599ec72983597437373a80f2d2085fa91fc144fd74e876a594db"
    "carlito/Carlito-Italic.ttf 0b019225e58d702bfedcbd35c21696769f8ee115cb6343f84c2f240312450d1c"
    "carlito/Carlito-BoldItalic.ttf b32928186c119599e03ca6a1ffc680fdcb7fac95772f4b95d989cf6cd3861517"
    "carlito/OFL.txt 58402f82a7c332a700294988fe7554fbb0a63a8d27ccc1ee3bbc640311990a00"
    "caladea/Caladea-Regular.ttf f1e899278b7b4491aba5b6a8253c4b04c050cc59b21865be5c37559a775153cd"
    "caladea/Caladea-Bold.ttf ae3cb2dcbc925809dd29d2a44e9802211cab66be541bacbfc9c08c74b27c3742"
    "caladea/Caladea-Italic.ttf 4359a8e24f748b6447b1ff6d7a174febe70961d29f8bb8634b56dacd740a3deb"
    "caladea/Caladea-BoldItalic.ttf ccabaa7b7e2fdf253d2b1a5fa699dd8a3df8d835a9eb285ad82631a677eb76c0"
    "caladea/OFL.txt ccdab61d371d8c8683a128a92cd7d498dbdb1d37689f7cb21f1bf6b16658d213"
)

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$ROOT/build/docxide"
SOURCES="$WORK/sources"
SRC="$WORK/src/$DOCXIDE"
OUT="$WORK/bin"
FONTS_OUT="$WORK/fonts"
LICENSES="$WORK/licenses"

# rustup's default location, which its installer only adds to PATH for new shells.
export PATH="${CARGO_HOME:-$HOME/.cargo}/bin:$PATH"
command -v rustup >/dev/null || { echo "rustup is required: https://rustup.rs" >&2; exit 1; }

rm -rf "$WORK/src" "$OUT" "$FONTS_OUT" "$LICENSES"
mkdir -p "$SOURCES" "$WORK/src" "$OUT" "$FONTS_OUT" "$LICENSES/docxide-pdf-dependencies"

fetch() {
    local file="$1" url="$2" sha256="$3"
    if [[ ! -f "$SOURCES/$file" ]]; then
        curl -fL --retry 3 -o "$SOURCES/$file.part" "$url"
        mv "$SOURCES/$file.part" "$SOURCES/$file"
    fi
    echo "$sha256  $SOURCES/$file" | shasum -a 256 -c --quiet -
}

fetch "$DOCXIDE.crate" "https://static.crates.io/crates/docxide-pdf/$DOCXIDE.crate" "$DOCXIDE_SHA256"
tar -xzf "$SOURCES/$DOCXIDE.crate" -C "$WORK/src"

for entry in "${FONTS[@]}"; do
    read -r path sha256 <<<"$entry"
    file="${path%%/*}-${path##*/}"
    fetch "$file" "https://raw.githubusercontent.com/google/fonts/$FONTS_COMMIT/ofl/$path" "$sha256"
    case "$file" in
        *.ttf) cp "$SOURCES/$file" "$FONTS_OUT/${path##*/}" ;;
        *) cp "$SOURCES/$file" "$LICENSES/${path%%/*}-OFL.txt" ;;
    esac
done

# docxide-pdf only knows Carlito as a stand-in the other way round; without these two aliases
# Calibri and Cambria text falls back to Arial and reflows.
ALIAS='        "Carlito" => Some("Calibri"),'
grep -qF "$ALIAS" "$SRC/src/fonts/mod.rs" || { echo "docxide-pdf's font alias table moved; update the patch" >&2; exit 1; }
sed -i '' "s|^$ALIAS\$|$ALIAS\\
        \"Calibri\" => Some(\"Carlito\"),\\
        \"Cambria\" => Some(\"Caladea\"),|" "$SRC/src/fonts/mod.rs"

rustup toolchain install "$RUST_TOOLCHAIN" --profile minimal --no-self-update
(
    cd "$SRC"
    export MACOSX_DEPLOYMENT_TARGET=14.0
    export CARGO_TARGET_DIR="$WORK/target"
    export CARGO_PROFILE_RELEASE_STRIP=symbols
    cargo "+$RUST_TOOLCHAIN" build --release --locked --bin docxide-pdf
    cp "$CARGO_TARGET_DIR/release/docxide-pdf" "$OUT/docxide-pdf"
)

# Anything outside the OS would be missing on users' Macs.
if otool -L "$OUT/docxide-pdf" | tail -n +2 | grep -vE '^[[:space:]]+(/usr/lib/|/System/Library/)'; then
    echo "docxide-pdf links a library outside the OS (listed above)" >&2
    exit 1
fi

cp "$SRC/LICENSE" "$LICENSES/docxide-pdf-LICENSE"
# The crates compiled into the binary, without dev and build dependencies; their MIT and Apache
# licenses ask for the notices to travel with it.
(
    cd "$SRC"
    cargo "+$RUST_TOOLCHAIN" tree --locked --edges normal --prefix none --format '{p}' |
        sed 's/ (\*)$//; s/ (.*)$//' | sort -u >"$WORK/crates.txt"
    cargo "+$RUST_TOOLCHAIN" metadata --locked --format-version 1 >"$WORK/metadata.json"
)
python3 -I - "$WORK/crates.txt" "$WORK/metadata.json" "$LICENSES/docxide-pdf-dependencies" <<'EOF'
import json, pathlib, shutil, sys

crates = set(pathlib.Path(sys.argv[1]).read_text().split("\n")) - {""}
packages = json.loads(pathlib.Path(sys.argv[2]).read_text())["packages"]
out = pathlib.Path(sys.argv[3])
for package in packages:
    name = f"{package['name']} v{package['version']}"
    if name not in crates or package["name"] == "docxide-pdf":
        continue
    directory = pathlib.Path(package["manifest_path"]).parent
    notices = [p for p in directory.iterdir() if p.name.upper().startswith(("LICENSE", "COPYING", "NOTICE"))]
    # A few crates only declare their license in Cargo.toml; that declaration is what we can ship.
    if not notices:
        (out / f"{package['name']}-{package['version']}-LICENSE.txt").write_text(
            f"{name}\nLicense: {package['license']}\nAuthors: {', '.join(package['authors']) or 'not listed'}\n"
            f"Source: {package['repository'] or 'https://crates.io/crates/' + package['name']}\n"
        )
    for notice in notices:
        shutil.copy(notice, out / f"{package['name']}-{package['version']}-{notice.name}")
EOF

echo "Built $OUT/docxide-pdf ($(du -h "$OUT/docxide-pdf" | cut -f1)), fonts $(du -sh "$FONTS_OUT" | cut -f1)"
