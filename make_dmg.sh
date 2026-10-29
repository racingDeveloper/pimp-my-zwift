#!/bin/bash
# Builds the app and packages it as build/PimpMyZwift-<version>.dmg (drag to Applications).
set -euo pipefail
cd "$(dirname "$0")"

./build.sh
APP="build/Pimp My Zwift.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
DMG="build/PimpMyZwift-$VERSION.dmg"
STAGING="build/dmg"

rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname "Pimp My Zwift $VERSION" -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGING"
echo "OK: $DMG"
