#!/bin/bash
# Package an unsigned .app in a Sparkle-compatible ZIP archive.
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
artifact="$releases/Mtihani-$version-$build.zip"
[[ ! -e "$artifact" ]] || { echo "Refusing to overwrite $artifact" >&2; exit 1; }
if codesign -dv "$app" >/dev/null 2>&1; then
    echo "Expected an unsigned application, but a code signature is present: $app" >&2
    exit 1
fi
ditto -c -k --sequesterRsrc --keepParent "$app" "$artifact"
echo "Packaged $artifact. Add matching release notes, then run generate-appcast.sh."
