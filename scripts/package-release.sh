#!/bin/bash
# Ad-hoc sign and package a universal app in a Sparkle-compatible ZIP archive.
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
executable="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")"
lipo "$app/Contents/MacOS/$executable" -verify_arch x86_64 arm64

# Native arm64 code must retain a valid signature even without Developer ID.
# Expand the same sandbox entitlements Xcode uses, then sign the outer bundle.
entitlements="$(mktemp "${TMPDIR:-/tmp}/mtihani-release-entitlements.XXXXXX")"
trap 'rm -f "$entitlements"' EXIT
python3 - "$script_dir/../mtihani-macos/mtihani-macos.entitlements" \
    "$app/Contents/Info.plist" "$entitlements" <<'PYTHON'
import pathlib
import plistlib
import sys

source, info_path, destination = map(pathlib.Path, sys.argv[1:])
info = plistlib.loads(info_path.read_bytes())
def expand(value):
    if isinstance(value, str):
        return value.replace("$(PRODUCT_BUNDLE_IDENTIFIER)", info["CFBundleIdentifier"])
    if isinstance(value, list):
        return [expand(item) for item in value]
    if isinstance(value, dict):
        return {key: expand(item) for key, item in value.items()}
    return value
pathlib.Path(destination).write_bytes(plistlib.dumps(expand(plistlib.loads(source.read_bytes()))))
PYTHON
# Archiving strips framework headers, invalidating the vendor resource seal.
# Re-seal the framework while retaining its already signed nested helpers.
for framework in "$app/Contents/Frameworks/"*.framework; do
    [[ -d "$framework" ]] || continue
    codesign --force --sign - --timestamp=none "$framework"
done
codesign --force --sign - --timestamp=none --entitlements "$entitlements" "$app"
codesign --verify --deep --strict --all-architectures "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "$artifact"
echo "Packaged $artifact. Add matching release notes, then run generate-appcast.sh."
