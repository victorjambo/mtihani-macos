#!/bin/bash
# Build and package an unsigned app, publish it, and stage Mtihani's Sparkle feed.
set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage: scripts/release-to-supabase.sh /path/to/release-notes.html

Required environment variables:
  SUPABASE_URL              Project URL, e.g. https://project-ref.supabase.co
  SUPABASE_SERVICE_ROLE_KEY Service-role key (never commit this value)

Optional environment variables:
  SUPABASE_RELEASE_BUCKET   Public bucket name (default: mtihani-releases)
  SPARKLE_KEY_ACCOUNT       Sparkle signing key account (default: mtihani)
  FRONTEND_APPCAST_PATH     Local feed destination in the frontend repository
EOF
    exit 2
}

[[ $# == 1 ]] || usage

: "${SUPABASE_URL:?Set SUPABASE_URL, for example https://project-ref.supabase.co}"
: "${SUPABASE_SERVICE_ROLE_KEY:?Set SUPABASE_SERVICE_ROLE_KEY without committing it}"

notes_source="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
[[ -f "$notes_source" ]] || { echo "Release notes not found: $notes_source" >&2; exit 1; }

script_dir="$(cd "$(dirname "$0")" && pwd)"
project_root="$(cd "$script_dir/.." && pwd)"
releases="$project_root/releases"
bucket="${SUPABASE_RELEASE_BUCKET:-mtihani-releases}"
base_url="${SUPABASE_URL%/}"
frontend_appcast="${FRONTEND_APPCAST_PATH:-$project_root/../mtihani-app/apps/frontend/public/appcast.xml}"

case "$base_url" in
    https://*) ;;
    *) echo "SUPABASE_URL must be an HTTPS URL." >&2; exit 1 ;;
esac
[[ "$bucket" =~ ^[A-Za-z0-9._-]+$ ]] || {
    echo "SUPABASE_RELEASE_BUCKET contains unsupported characters." >&2
    exit 1
}
for command in xcodebuild curl shasum python3; do
    command -v "$command" >/dev/null || { echo "Missing required command: $command" >&2; exit 1; }
done
[[ -f "$frontend_appcast" ]] || {
    echo "Frontend appcast destination not found: $frontend_appcast" >&2
    exit 1
}

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
sparkle_bin="${SPARKLE_BIN:-$project_root/build/SourcePackages/artifacts/sparkle/Sparkle/bin}"
export SPARKLE_BIN="$sparkle_bin"
[[ -x "$SPARKLE_BIN/generate_appcast" ]] || {
    echo "Sparkle generate_appcast not found at $SPARKLE_BIN/generate_appcast." >&2
    echo "Resolve Swift packages in Xcode or set SPARKLE_BIN explicitly." >&2
    exit 1
}

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
work_dir="$project_root/build/releases/$timestamp"
archive="$work_dir/Mtihani.xcarchive"
mkdir -p "$work_dir" "$releases"
auth_headers="$(mktemp "${TMPDIR:-/tmp}/mtihani-supabase-auth.XXXXXX")"
chmod 600 "$auth_headers"
printf 'Authorization: Bearer %s\napikey: %s\n' \
    "$SUPABASE_SERVICE_ROLE_KEY" "$SUPABASE_SERVICE_ROLE_KEY" >"$auth_headers"
cleanup() {
    rm -f "$auth_headers"
}
trap cleanup EXIT

echo "[1/5] Archiving the unsigned Release build..."
xcodebuild -project "$project_root/mtihani-macos.xcodeproj" \
    -scheme mtihani-macos \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -clonedSourcePackagesDirPath "$project_root/build/SourcePackages" \
    -archivePath "$archive" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY='' \
    ONLY_ACTIVE_ARCH=NO archive

app="$archive/Products/Applications/Mtihani.app"
[[ -d "$app" ]] || { echo "Archived application not found: $app" >&2; exit 1; }
if codesign -dv "$app" >/dev/null 2>&1; then
    codesign --remove-signature "$app"
fi
if codesign -dv "$app" >/dev/null 2>&1; then
    echo "Failed to remove the archived application's outer signature." >&2
    exit 1
fi

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app/Contents/Info.plist")"
artifact_name="Mtihani-$version-$build.dmg"
notes_name="Mtihani-$version-$build.html"
artifact="$releases/$artifact_name"
notes="$releases/$notes_name"

[[ ! -e "$artifact" ]] || { echo "Release already exists: $artifact" >&2; exit 1; }
if [[ "$notes_source" != "$notes" ]]; then
    [[ ! -e "$notes" ]] || { echo "Release notes already exist: $notes" >&2; exit 1; }
    cp "$notes_source" "$notes"
fi

echo "[2/5] Creating the unsigned DMG..."
bash "$script_dir/package-release.sh" "$app" "$releases"

release_prefix="$base_url/storage/v1/object/public/$bucket/"
echo "[3/5] Generating and validating the Sparkle-signed appcast..."
bash "$script_dir/generate-appcast.sh" "$releases" "$release_prefix"

upload_and_verify() {
    local file="$1"
    local content_type="$2"
    local filename upload_url public_url status verification_dir downloaded local_hash remote_hash
    filename="$(basename "$file")"
    [[ "$filename" =~ ^[A-Za-z0-9._-]+$ ]] || {
        echo "Release filename contains unsupported characters: $filename" >&2
        return 1
    }
    upload_url="$base_url/storage/v1/object/$bucket/$filename"
    public_url="$base_url/storage/v1/object/public/$bucket/$filename"
    status="$(curl --silent --show-error --location --head --output /dev/null \
        --write-out '%{http_code}' "$public_url")"
    if [[ "$status" == 2* ]]; then
        echo "Refusing to overwrite published release: $public_url" >&2
        return 1
    fi

    curl --fail --silent --show-error --retry 3 --retry-all-errors \
        --request POST \
        --header "@$auth_headers" \
        --header "Content-Type: $content_type" \
        --header "Cache-Control: public, max-age=31536000, immutable" \
        --header "x-upsert: false" \
        --data-binary "@$file" \
        "$upload_url" >/dev/null

    verification_dir="$(mktemp -d "${TMPDIR:-/tmp}/mtihani-release-verify.XXXXXX")"
    downloaded="$verification_dir/$filename"
    if ! curl --fail --silent --show-error --location --retry 3 --retry-all-errors \
        "$public_url" --output "$downloaded"; then
        rm -f "$downloaded"
        rmdir "$verification_dir"
        return 1
    fi
    local_hash="$(shasum -a 256 "$file" | awk '{print $1}')"
    remote_hash="$(shasum -a 256 "$downloaded" | awk '{print $1}')"
    rm -f "$downloaded"
    rmdir "$verification_dir"
    [[ "$local_hash" == "$remote_hash" ]] || {
        echo "Upload verification failed for $filename: SHA-256 hashes differ." >&2
        return 1
    }
    echo "Verified $public_url"
}

echo "[4/5] Uploading immutable release files to Supabase..."
upload_and_verify "$artifact" application/x-apple-diskimage
upload_and_verify "$notes" 'text/html; charset=utf-8'

echo "[5/5] Staging the appcast only after release files are available..."
python3 "$script_dir/validate-update.py" feed "$releases/appcast.xml"
cp "$releases/appcast.xml" "$frontend_appcast"

cat <<EOF

Release $version ($build) is prepared.
DMG: $release_prefix$artifact_name
Notes: $release_prefix$notes_name
Appcast staged at: $frontend_appcast

Remaining manual safety steps:
  1. Review and deploy the frontend so the new appcast becomes public.
  2. Upgrade from the previous installed Mtihani release end-to-end.
  3. Confirm version $version ($build), then announce the release.
EOF
