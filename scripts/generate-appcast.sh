#!/bin/bash
# Sparkle's official tool owns metadata extraction and EdDSA signatures.
set -euo pipefail

if [[ $# != 2 ]]; then
    echo "Usage: $0 /path/to/releases https://updates.example.com/" >&2
    exit 2
fi
: "${SPARKLE_BIN:?Set SPARKLE_BIN to the resolved Sparkle artifact bin directory}"
script_dir="$(cd "$(dirname "$0")" && pwd)"
releases="$(cd "$1" && pwd)"
prefix="${2%/}/"
python3 "$script_dir/validate-update.py" url "$prefix"
[[ -x "$SPARKLE_BIN/generate_appcast" ]] || { echo "Sparkle generate_appcast is missing." >&2; exit 1; }

# A CI secret file must live outside the repository. Its contents are never
# passed as command-line arguments or echoed. Local signing uses Keychain.
key_args=(--account "${SPARKLE_KEY_ACCOUNT:-mtihani}")
if [[ -n "${SPARKLE_PRIVATE_KEY_FILE:-}" ]]; then
    [[ -r "$SPARKLE_PRIVATE_KEY_FILE" ]] || { echo "Signing key file is unreadable." >&2; exit 1; }
    key_args=(--ed-key-file "$SPARKLE_PRIVATE_KEY_FILE")
fi
"$SPARKLE_BIN/generate_appcast" "${key_args[@]}" \
    --download-url-prefix "$prefix" \
    --release-notes-url-prefix "$prefix" \
    --maximum-deltas 0 \
    -o "$releases/appcast.xml" "$releases"
python3 "$script_dir/validate-update.py" feed "$releases/appcast.xml"
echo "Validated $releases/appcast.xml. Publish archives and notes first; publish the feed last."
