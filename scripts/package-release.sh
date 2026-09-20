#!/bin/bash
# Package an unsigned .app as an unsigned DMG.
set -euo pipefail

if [[ $# != 2 ]]; then
    echo "Usage: $0 /path/to/Mtihani.app /path/to/releases" >&2
    exit 2
fi
script_dir="$(cd "$(dirname "$0")" && pwd)"
app="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
mkdir -p "$2"
releases="$(cd "$2" && pwd)"
python3 "$script_dir/validate-update.py" app "$app" --previous-feed "$releases/appcast.xml"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
artifact="$releases/Mtihani-$version-$build.dmg"
[[ ! -e "$artifact" ]] || { echo "Refusing to overwrite $artifact" >&2; exit 1; }
staging="$(mktemp -d "${TMPDIR:-/tmp}/mtihani-release.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/$(basename "$app")"
packaged_app="$staging/$(basename "$app")"
if codesign -dv "$packaged_app" >/dev/null 2>&1; then
    codesign --remove-signature "$packaged_app"
fi
if codesign -dv "$packaged_app" >/dev/null 2>&1; then
    echo "Failed to remove the application signature: $packaged_app" >&2
    exit 1
fi
ln -s /Applications "$staging/Applications"
hdiutil create -volname Mtihani -srcfolder "$staging" -format UDZO "$artifact"
if codesign -dv "$artifact" >/dev/null 2>&1; then
    echo "Expected an unsigned disk image, but a code signature is present: $artifact" >&2
    exit 1
fi
echo "Packaged $artifact. Add matching release notes, then run generate-appcast.sh."
