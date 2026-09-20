# Unsigned macOS release runbook

This runbook publishes an **unsigned** `mtihani-macos.app` inside an unsigned
DMG. The release script builds the app, removes Xcode's ad-hoc outer signature,
creates the DMG, signs the DMG bytes with Sparkle EdDSA, uploads the DMG and
release notes to Supabase Storage, verifies both uploads, and stages the new
`appcast.xml` in the frontend repository.

This workflow does not use Developer ID or Apple notarization. macOS will show
Gatekeeper warnings. A user may need to open the app using Finder's **Open**
action or approve it in **System Settings → Privacy & Security**.

## One-time prerequisites

Install Xcode at `/Applications/Xcode.app`, then resolve the Sparkle package:

```bash
cd /Users/victormutai/workspace/mtihani/mtihani-macos

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -resolvePackageDependencies \
  -project mtihani-macos.xcodeproj \
  -scheme mtihani-macos \
  -clonedSourcePackagesDirPath "$PWD/build/SourcePackages"
```

Create the Sparkle EdDSA signing key once:

```bash
export SPARKLE_BIN="$PWD/build/SourcePackages/artifacts/sparkle/Sparkle/bin"
"$SPARKLE_BIN/generate_keys" --account mtihani
```

The private key remains in the login Keychain under account `mtihani`. Copy the
public key printed by `generate_keys` into `SPARKLE_PUBLIC_ED_KEY` in the update
configuration. Back up the private key securely; do not put it in this
repository or a `.env` file.

In Supabase Dashboard, create a public Storage bucket named
`mtihani-releases`. The script requires the bucket to exist and never
overwrites an existing release object.

## Configure the environment

Copy the example without committing the resulting file:

```bash
cp .env.example .env.release
chmod 600 .env.release
```

`.env.release` is ignored by Git. Fill in the following variables.

### `SUPABASE_URL`

The base URL of the Supabase project that owns the release bucket.

Find it in **Supabase Dashboard → Project Settings → Data API**. It resembles:

```dotenv
SUPABASE_URL="https://abcdefghijk.supabase.co"
```

Do not append `/storage/v1` or the bucket name; the script constructs those
paths.

### `SUPABASE_SERVICE_ROLE_KEY`

A privileged server-side key used only to upload release files.

Find it in **Supabase Dashboard → Project Settings → API Keys**. Use the secret
or legacy `service_role` key, not the public publishable/anonymous key.

```dotenv
SUPABASE_SERVICE_ROLE_KEY="YOUR_SECRET_SERVICE_ROLE_KEY"
```

This value bypasses Storage row-level security. Never commit it, include it in
logs, embed it in the app, or expose it to frontend code.

### `SUPABASE_RELEASE_BUCKET`

The public Storage bucket receiving DMGs and release notes:

```dotenv
SUPABASE_RELEASE_BUCKET="mtihani-releases"
```

The bucket must already exist and be public. The script does not create it.

### `DEVELOPER_DIR`

The installed Xcode developer directory:

```dotenv
DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
```

The script uses this path by default, so it can be omitted when Xcode is in the
standard location.

### `SPARKLE_BIN`

The directory containing Sparkle's `generate_appcast` and `generate_keys`
utilities:

```dotenv
SPARKLE_BIN="/Users/victormutai/workspace/mtihani/mtihani-macos/build/SourcePackages/artifacts/sparkle/Sparkle/bin"
```

The script uses this repository-relative location by default. Set the variable
only when the Sparkle tools are elsewhere. Verify it with:

```bash
test -x "$SPARKLE_BIN/generate_appcast"
```

### `SPARKLE_KEY_ACCOUNT`

The Keychain account label used to find the Sparkle EdDSA private key. It is a
label, not a secret or the key itself:

```dotenv
SPARKLE_KEY_ACCOUNT="mtihani"
```

It must match the account passed to `generate_keys --account`. The script
defaults to `mtihani`.

### `FRONTEND_APPCAST_PATH`

The local destination where the verified generated feed is staged:

```dotenv
FRONTEND_APPCAST_PATH="/Users/victormutai/workspace/mtihani/mtihani-app/apps/frontend/public/appcast.xml"
```

The default assumes `mtihani-app` and `mtihani-macos` are sibling directories.
The script copies the feed here only after the Supabase uploads pass SHA-256
verification. It does not deploy the frontend.

### `SPARKLE_PRIVATE_KEY_FILE`

This is an optional CI alternative to the local Keychain key:

```dotenv
SPARKLE_PRIVATE_KEY_FILE="/secure/path/outside/repository/sparkle-private-key"
```

For local releases, leave it unset and use `SPARKLE_KEY_ACCOUNT`. If CI uses a
key file, store it in the CI secret system and materialize it temporarily
outside the checkout.

## Bump the version

The release script does not choose or increment versions. Set both values in
Xcode before running it:

1. Open `mtihani-macos.xcodeproj` in Xcode.
2. Select the **mtihani-macos** project.
3. Select the **mtihani-macos** application target.
4. Open **General → Identity**.
5. Set **Version** to the intended user-facing version, such as `1.1.0`.
6. Set **Build** to a positive integer greater than every published build, such
   as `2`.
7. Check both Debug and Release build configurations under **Build Settings**
   if Xcode does not update them together.

The underlying settings are:

```text
MARKETING_VERSION = 1.1.0
CURRENT_PROJECT_VERSION = 2
```

Sparkle compares `CURRENT_PROJECT_VERSION` when deciding whether an update is
newer. Never reuse or decrease a published build number, even when the marketing
version changes.

Confirm the Release values before publishing:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild -project mtihani-macos.xcodeproj \
  -scheme mtihani-macos \
  -configuration Release \
  -showBuildSettings | \
  rg 'MARKETING_VERSION|CURRENT_PROJECT_VERSION'
```

The example above produces `Mtihani-1.1.0-2.dmg`.

## Write release notes

Create a complete HTML file outside `releases/`, for example:

```html
<!doctype html>
<html lang="en">
  <body>
    <h2>Mtihani 1.1.0</h2>
    <ul>
      <li>Describe the important change.</li>
      <li>Describe another fix or improvement.</li>
    </ul>
  </body>
</html>
```

Save it as something like `/tmp/mtihani-1.1.0-notes.html`. The script copies
it to the correct versioned name after reading the built app's version and
build.

## Run the release

Load the environment and execute the script:

```bash
cd /Users/victormutai/workspace/mtihani/mtihani-macos

set -a
source .env.release
set +a

bash scripts/release-to-supabase.sh /tmp/mtihani-1.1.0-notes.html
```

The script performs these operations in order:

1. Archives a universal Release build with distribution signing disabled.
2. Removes Xcode's outer ad-hoc app signature and verifies the app is unsigned.
3. Creates an unsigned, versioned DMG containing the app and Applications link.
4. Generates an appcast with a Sparkle EdDSA signature over the final DMG bytes.
5. Uploads the DMG and release notes to the public Supabase bucket without
   overwriting existing objects.
6. Downloads both objects and verifies their SHA-256 hashes against the local
   files.
7. Copies the validated appcast into the frontend repository.

Local outputs are retained under:

```text
build/releases/TIMESTAMP/Mtihani.xcarchive
releases/Mtihani-VERSION-BUILD.dmg
releases/Mtihani-VERSION-BUILD.html
releases/appcast.xml
```

## Publish and test the feed

After the script succeeds:

1. Review the staged frontend `appcast.xml` and confirm its latest enclosure
   points to the uploaded Supabase DMG.
2. Deploy the `mtihani-app` frontend so the feed becomes available at the URL
   configured by `SUFeedURL`.
3. Install the previous Mtihani release and select **Check for Updates…**.
4. Complete the download, installation, and relaunch.
5. Confirm the new Version and Build in Settings.
6. Confirm session, authentication, capture, and menu-bar behavior.
7. Announce the release only after the end-to-end update succeeds.

Do not edit, recompress, or replace the DMG after appcast generation. Any byte
change invalidates the Sparkle signature and file-length metadata. Keep older
DMGs online because existing clients may still reference cached feeds.

## Common failures

- **`generate_appcast` not found:** resolve Swift packages or correct
  `SPARKLE_BIN`.
- **Sparkle signing key not found:** confirm `SPARKLE_KEY_ACCOUNT` matches the
  account originally used with `generate_keys`.
- **Release already exists:** increment the build number. Published filenames
  and Supabase objects are intentionally immutable.
- **Supabase returns 401/403:** check `SUPABASE_URL`, the service-role key, and
  whether the key belongs to that project.
- **Public download verification fails:** confirm the bucket is public and that
  its file-size/MIME restrictions allow DMG and HTML uploads.
- **macOS blocks the app:** this is expected for an unsigned, unnotarized app;
  approve it through Finder's **Open** action or Privacy & Security.
