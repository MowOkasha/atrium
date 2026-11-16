#!/usr/bin/env bash
# Builds a universal, ad-hoc signed Atrium.app and a release zip in ./build
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-$(cat VERSION)}"
BUILD_NUMBER="${BUILD_NUMBER:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
APP="build/Atrium.app"

rm -rf build && mkdir -p build/bin "$APP/Contents/MacOS" "$APP/Contents/Resources"
for arch in arm64 x86_64; do
  echo "→ Compiling Atrium $VERSION ($arch)"
  swift build -c release --triple "$arch-apple-macosx26.0"
  cp "$(swift build -c release --triple "$arch-apple-macosx26.0" --show-bin-path)/Atrium" "build/bin/Atrium-$arch"
done

echo "→ Assembling app bundle"
lipo -create build/bin/Atrium-arm64 build/bin/Atrium-x86_64 -output "$APP/Contents/MacOS/Atrium"
rm -rf build/bin
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"

echo "→ Building icon"
ICONSET="build/AppIcon.iconset"
mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
  sips -z $s $s Resources/icon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) Resources/icon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "→ Signing (ad-hoc)"
codesign --force --options runtime --sign - "$APP"

ZIP="build/Atrium-$VERSION.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
echo "✓ $APP"
echo "✓ $ZIP  sha256: $(shasum -a 256 "$ZIP" | cut -d' ' -f1)"
