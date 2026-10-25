#!/bin/bash
# 用法：./build.sh            → build/Browser.app
#      APP_NAME=Foo ./build.sh → build/Foo.app（菜单栏显示的名字）
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="${APP_NAME:-Browser}"
APP="build/$APP_NAME.app"

mkdir -p build
if [ ! -f build/AppIcon.icns ]; then
    swiftc -O tools/make_icon.swift -o build/make_icon
    build/make_icon build/AppIcon.iconset
    iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -target arm64-apple-macos13.0 Sources/main.swift \
    -o "$APP/Contents/MacOS/$APP_NAME"
cp build/AppIcon.icns "$APP/Contents/Resources/"
sed "s/__NAME__/$APP_NAME/g" Info.plist > "$APP/Contents/Info.plist"
xattr -cr "$APP"
codesign --force --sign - "$APP"
echo "✅ $APP"
