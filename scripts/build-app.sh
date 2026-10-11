#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/check-sensitive.py --staged
python3 scripts/check-sensitive.py --history
APP="dist/PauseMic.app"
VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' Resources/Info.plist)
swift build -c release --arch arm64 --arch x86_64
BIN_DIR=$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PauseMic" "$APP/Contents/MacOS/PauseMic"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp -R Resources/en.lproj Resources/zh-Hans.lproj "$APP/Contents/Resources/"
xcrun swift scripts/make-icon.swift .build/AppIcon.iconset
iconutil -c icns .build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
else
    codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
lipo -info "$APP/Contents/MacOS/PauseMic"
python3 scripts/check-sensitive.py --artifacts "$APP"
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    ditto -c -k --sequesterRsrc --keepParent "$APP" dist/notarization.zip
    python3 scripts/check-sensitive.py --artifacts dist/notarization.zip
    xcrun notarytool submit dist/notarization.zip --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP"
fi
ditto -c -k --sequesterRsrc --keepParent "$APP" "dist/PauseMic-${VERSION}-macOS-universal.zip"
python3 scripts/check-sensitive.py --artifacts "dist/PauseMic-${VERSION}-macOS-universal.zip"
(cd dist && shasum -a 256 "PauseMic-${VERSION}-macOS-universal.zip" > SHA256SUMS.txt)
echo "Built $APP (version $VERSION)"
