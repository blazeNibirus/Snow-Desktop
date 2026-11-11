#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIGURATION="${CONFIGURATION:-release}"
SNOW_ARCH="${SNOW_ARCH:-$(uname -m)}"
if [ "$SNOW_ARCH" = universal ]; then
    ARCHS=(arm64 x86_64)
else
    ARCHS=("$SNOW_ARCH")
fi
APP="build/Snow Desktop.app"
SAVER="$APP/Contents/Resources/Snow Desktop.saver"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$SAVER/Contents/MacOS"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/Saver-Info.plist "$SAVER/Contents/Info.plist"
BINARIES=()
SAVERS=()
for ARCH in "${ARCHS[@]}"; do
    swift build -c "$CONFIGURATION" --arch "$ARCH"
    BINDIR=$(swift build -c "$CONFIGURATION" --arch "$ARCH" --show-bin-path)
    cp "$BINDIR/SnowDesktop" "build/SnowDesktop-$ARCH"
    BINARIES+=("build/SnowDesktop-$ARCH")
    SAVER_BINARY="build/SnowDesktopSaver-$ARCH"
    xcrun swiftc -O -whole-module-optimization -emit-library \
        -target "$ARCH-apple-macos14.0" -module-name SnowDesktopSaver \
        Sources/SnowCore/*.swift Sources/SnowScreenSaver/*.swift \
        -framework AppKit -framework ScreenSaver -o "$SAVER_BINARY"
    SAVERS+=("$SAVER_BINARY")
done
lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/SnowDesktop"
lipo -create "${SAVERS[@]}" -output "$SAVER/Contents/MacOS/SnowDesktopSaver"
swift Scripts/make-icon.swift "$APP/Contents/Resources/AppIcon.iconset"
iconutil -c icns "$APP/Contents/Resources/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
rm -r "$APP/Contents/Resources/AppIcon.iconset"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
codesign --force --sign "$SIGN_IDENTITY" "$SAVER"
codesign --force --sign "$SIGN_IDENTITY" "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built: %s\n' "$APP"
