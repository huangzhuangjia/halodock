#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

swift build -c release

APP_DIR="$ROOT_DIR/.build/HaloDock.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$ROOT_DIR/.build/release/HaloDock" "$APP_DIR/Contents/MacOS/HaloDock"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

swiftc -parse-as-library Sources/HaloDock/BrandIcon.swift Scripts/GenerateAppIcon.swift -o .build/generate-app-icon
.build/generate-app-icon .build/HaloDock.iconset
iconutil -c icns .build/HaloDock.iconset -o "$APP_DIR/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP_DIR"
codesign --verify --strict "$APP_DIR"

echo "Built $APP_DIR"
