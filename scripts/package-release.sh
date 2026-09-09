#!/bin/bash
# Package an already Developer ID exported, notarized, stapled .app as a DMG.
set -euo pipefail

if [[ $# != 2 ]]; then
    echo "Usage: $0 /path/to/export/mtihani-macos.app /path/to/releases" >&2
    exit 2
fi
: "${DEVELOPER_ID_APPLICATION:?Set the Developer ID Application certificate name}"
: "${NOTARYTOOL_PROFILE:?Set the notarytool Keychain profile name}"
[[ "$DEVELOPER_ID_APPLICATION" == "Developer ID Application:"* ]] || {
    echo "A Developer ID Application identity is required." >&2
    exit 1
}
script_dir="$(cd "$(dirname "$0")" && pwd)"
app="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
mkdir -p "$2"
releases="$(cd "$2" && pwd)"
python3 "$script_dir/validate-update.py" app "$app" --previous-feed "$releases/appcast.xml"

codesign --verify --deep --strict --verbose=2 "$app"
framework="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
for component in "$app" "$app/Contents/Frameworks/Sparkle.framework" "$framework/Autoupdate" "$framework/Updater.app" "$framework/XPCServices/Installer.xpc" "$framework/XPCServices/Downloader.xpc"; do
    identity="$(codesign -dv --verbose=4 "$component" 2>&1)"
    if ! [[ "$identity" == *"Authority=$DEVELOPER_ID_APPLICATION"* && "$identity" == *"runtime"* ]]; then
        echo "Export through Xcode using Developer ID: $component is not distribution-signed with Hardened Runtime." >&2
        exit 1
    fi
done
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
artifact="$releases/Mtihani-$version-$build.dmg"
[[ ! -e "$artifact" ]] || { echo "Refusing to overwrite $artifact" >&2; exit 1; }
staging="$(mktemp -d "${TMPDIR:-/tmp}/mtihani-release.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/$(basename "$app")"
ln -s /Applications "$staging/Applications"
hdiutil create -volname Mtihani -srcfolder "$staging" -format UDZO "$artifact"
codesign --sign "$DEVELOPER_ID_APPLICATION" --timestamp "$artifact"
xcrun notarytool submit "$artifact" --keychain-profile "$NOTARYTOOL_PROFILE" --wait
xcrun stapler staple "$artifact"
xcrun stapler validate "$artifact"
codesign --verify --strict "$artifact"
echo "Packaged $artifact. Add matching release notes, then run generate-appcast.sh."
