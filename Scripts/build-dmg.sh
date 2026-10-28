#!/bin/zsh
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"
./Scripts/build-app.sh
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
ARCH=$(uname -m)
mkdir -p dist
STAGING_DIR=$(mktemp -d "$ROOT_DIR/.build/dmg-stage.XXXXXX")
trap 'rm -rf "$STAGING_DIR"' EXIT
/usr/bin/ditto .build/HaloDock.app "$STAGING_DIR/HaloDock.app"
ln -s /Applications "$STAGING_DIR/Applications"
cat > "$STAGING_DIR/安装说明.txt" <<'TXT'
HaloDock 安装说明

1. 将 HaloDock.app 拖到 Applications 文件夹。
2. 首次安装前，请退出正在运行的 HaloDock 开发版本。
3. 从“应用程序”中打开 HaloDock，点击菜单栏里的“歪头屏”图标使用。

本包为 Apple Silicon (arm64) 本地构建，最低支持 macOS 13。
使用 ad-hoc 签名，尚未经过 Apple Developer ID 签名与公证。
若系统阻止打开，请在“系统设置 → 隐私与安全性”中查看对应提示。

更新时先退出旧版，再用新版替换 Applications 中的 HaloDock.app。
TXT
OUTPUT="$ROOT_DIR/dist/HaloDock-$VERSION-macos-$ARCH.dmg"
hdiutil create -volname "HaloDock $VERSION" -srcfolder "$STAGING_DIR" -format UDZO -ov "$OUTPUT"
hdiutil verify "$OUTPUT"
(cd "$ROOT_DIR/dist" && shasum -a 256 "$(basename "$OUTPUT")") > "$OUTPUT.sha256"
echo "Built $OUTPUT"
