#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
./Scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
ARCH=$(uname -m)
mkdir -p dist
swiftc -parse-as-library Sources/HaloDock/BrandIcon.swift Scripts/GenerateDMGBackground.swift -o .build/generate-dmg-background
.build/generate-dmg-background .build/installer-background.tiff
if [[ ! -x .build/dmg-tools/bin/python ]]; then
    DMG_PYTHON="${DMG_PYTHON:-python3}"
    "$DMG_PYTHON" -m venv .build/dmg-tools
fi
.build/dmg-tools/bin/python -c 'from importlib.metadata import version; assert version("dmgbuild") == "1.6.7"' 2>/dev/null || .build/dmg-tools/bin/pip install dmgbuild==1.6.7
OUTPUT="$ROOT_DIR/dist/HaloDock-$VERSION-macos-$ARCH.dmg"
.build/dmg-tools/bin/python Scripts/build-dmg.py "$OUTPUT"
hdiutil verify "$OUTPUT"
(cd "$ROOT_DIR/dist" && shasum -a 256 "$(basename "$OUTPUT")") > "$OUTPUT.sha256"
echo "Built $OUTPUT"
