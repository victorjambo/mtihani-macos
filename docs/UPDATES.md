# Application updates and releases

Mtihani uses the official Sparkle **2.9.6** Swift package (resolved version in
`mtihani-macos.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`).
The application target uses Swift 5 language mode, Swift 6.3.3/Xcode 26.6, and a
macOS **15.6** deployment target. The project-level target remains 26.5, but the
application and tests override it. Existing distributed DMGs are in `dist/`;
there was no checked-in packaging or CI pipeline before this integration.

## Runtime and preferences

`AppDelegate` retains one `UpdateManager` and starts it at application launch.
Its `SparkleUpdateDriver` retains the only `SPUStandardUpdaterController`, its
delegates, and KVO subscriptions. The same manager is passed to the AppKit
popover, its Settings window, and the SwiftUI Settings scene. No capture,
backend, or click-trigger path calls the updater. XCTest host launches skip
live services, and wrapper tests inject a fake driver.

- **Check for Updates…** closes the popover and invokes Sparkle's user-initiated
  check. Its availability follows `canCheckForUpdates`, including bringing an
  existing Sparkle update dialog back into focus.
- **General · Updates** shows the bundle's marketing version and build, the two
  Sparkle preferences, and **Check for Updates Now**. The existing form scrolls
  within the same Settings window.
- Checks default **on**, scheduled by Sparkle about every **24 hours**.
  Downloads default **off**. If users enable downloads, Sparkle may install
  downloaded updates when they quit. Its normal UI controls installation and
  relaunch; Mtihani never forces a quit or implements a binary installer.
- `automaticallyChecksForUpdates`, `automaticallyDownloadsUpdates`, and
  `allowsAutomaticUpdates` are observed through KVO. Settings writes directly
  through these APIs; no `AppStorage` or parallel persisted preference exists.
  Turning checks off disables the automatic-download control according to
  Sparkle's policy. Restarting the app does not reset user choices.
- A background update adds a dot and an accessible “Update available” status to
  the menu-bar item, with explanatory text in the popover. Sparkle continues to
  present its standard UI without stealing focus from another app. Giving the
  update attention or ending its session clears the reminder.
- Sparkle owns normal networking, download, validation, cancellation, and
  installation errors. OSLog category `updates` records error domain/code only.
  Invalid build configuration leaves the controls unavailable and a readable
  Settings message; it does not crash or display a launch-time modal.

## Configuration and trust

Set `SPARKLE_FEED_URL` and `SPARKLE_PUBLIC_ED_KEY` in
`Configuration/Updates.xcconfig`, or override these build settings with an
external `-xcconfig` file or `xcodebuild` arguments. Use `https:/$()/host/path`
inside xcconfig files so `//` is not treated as a comment. The bundled
`SUFeedURL` and `SUPublicEDKey` expand these settings. There is one feed per
build, with no runtime channels or backend version API.

The production URL is
`https://mtihani-app-frontend.vercel.app/appcast.xml`. Its source is
`apps/frontend/public/appcast.xml` in the sibling `mtihani-app` repository and
Vercel serves it as a static XML asset. Before the first release, replace the
empty feed with the signed output from `generate-appcast.sh`. The public
key is configured for the `mtihani` signing key created in this Mac's login
Keychain on 2026-09-09. Release signing must use that same key. Back it up securely
before distributing; another Mac must obtain the existing key through secure
transfer rather than generate a replacement. If a build overrides the public
key with an empty or invalid value, the updater refuses to start and the release
packaging validator refuses to package that build.

`Info.plist` sets `SUEnableAutomaticChecks = YES`,
`SUScheduledCheckInterval = 86400`, `SUAutomaticallyUpdate = NO`, and
`SUVerifyUpdateBeforeExtraction = YES`. Archive EdDSA validation is required
before extraction. This also constrains future key rotation: with this option,
Sparkle requires a Developer ID signed DMG to rotate a lost EdDSA key. Keep
secure backups and follow Sparkle's key-rotation guide rather than replacing
both signing identities at once.

Releases intentionally use an unsigned app in an unsigned DMG. Sparkle EdDSA
still authenticates updates independently of Apple code signing:

1. Xcode archives with distribution code signing disabled, then the release
   script removes Xcode's ad-hoc linker signature from the outer app.
2. The unsigned app is packaged in an unsigned DMG.
3. Sparkle signs the **final DMG bytes** and produces the appcast.
4. HTTPS hosting serves the appcast, notes, and DMG independently of NestJS.

This distribution model triggers macOS Gatekeeper warnings and provides no
Apple Developer ID identity or notarization assurance. Users may need to use
Finder's **Open** action and explicitly approve the app in Privacy & Security.
Sparkle's EdDSA signature protects updates but does not remove those warnings.

The same DMG serves direct downloads and Sparkle updates; Sparkle supports
DMGs, so no separate ZIP update artifact is necessary. Keep app archives and
Sparkle dSYMs for diagnostics.

### Sandbox and signing details

The existing sandbox and outgoing-network entitlement remain enabled.
`SUEnableInstallerLauncherService = YES` enables Sparkle's bundled
`Installer.xpc`. These two narrow Mach lookup exceptions were added:

```text
$(PRODUCT_BUNDLE_IDENTIFIER)-spks
$(PRODUCT_BUNDLE_IDENTIFIER)-spki
```

Xcode expands the identifier during code signing. The downloader XPC service
is not enabled because Mtihani already has `com.apple.security.network.client`.
No additional XPC copy phases, app groups, or TLS exceptions are needed.
The existing local-network ATS exception belongs to backend development;
update configuration requires HTTPS, including private test feeds.
The normal development and test signing settings remain unchanged. Production
release automation passes `CODE_SIGNING_ALLOWED=NO`, removes any ad-hoc outer
app signature, and packages the application directly from the archive; it does
not export, distribution-sign, notarize, or staple it.

## One-time release owner setup

From the repository root, resolve dependencies and locate the official tools:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -resolvePackageDependencies -project mtihani-macos.xcodeproj \
  -scheme mtihani-macos -clonedSourcePackagesDirPath "$PWD/build/SourcePackages"
export SPARKLE_BIN="$PWD/build/SourcePackages/artifacts/sparkle/Sparkle/bin"
"$SPARKLE_BIN/generate_keys" --account mtihani
```

`generate_keys` creates the private EdDSA key in the login Keychain and prints
its public key. Put **only that public key** in `SPARKLE_PUBLIC_ED_KEY`; it is
safe and necessary to commit the public key. `generate_keys --account mtihani
-p` retrieves the existing public key. Keep the private key in Keychain. For a
secure backup/CI transfer, `generate_keys --account mtihani -x
/secure/location/outside-repository/key` exports it; protect that file and
import it into a secret manager. Do not commit it, put it in an `.env` file, or
embed it in any app resource. Never print it in logs or pass its contents as a
command-line argument. Ignoring a file in Git is not a storage strategy.

Set up HTTPS static hosting with a stable feed URL, suitable XML content type,
short feed cache lifetime, and immutable versioned artifacts. Hosting may be an
object store, static website, or GitHub Release asset URL; the app never calls
GitHub APIs.

## Production release procedure

The complete local workflow through Supabase artifact publication can be run
with `scripts/release-to-supabase.sh`. It deliberately stops after staging the
new feed in the frontend repository: deploying that feed and testing an upgrade
from the previous installed version remain explicit release gates.

```bash
export SUPABASE_URL=https://PROJECT_REF.supabase.co
export SUPABASE_SERVICE_ROLE_KEY='load-this-from-a-secret-manager'
export SUPABASE_RELEASE_BUCKET=mtihani-releases

bash scripts/release-to-supabase.sh /path/to/release-notes.html
```

The bucket must already exist and be public. The script never overwrites a
published object. It archives with distribution signing disabled, removes the
outer app's ad-hoc linker signature, invokes the DMG and appcast scripts,
uploads the versioned DMG and notes, downloads
both public objects to verify their SHA-256 hashes, and copies the appcast to
`../mtihani-app/apps/frontend/public/appcast.xml` only after verification.
Keep the service-role key outside the repository; it is read from the process
environment and written only to a temporary mode-0600 curl header file.

1. Update `MARKETING_VERSION` and increment `CURRENT_PROJECT_VERSION` in both
   application build configurations. Use positive integer builds, always
   greater than every previously released build. Sparkle compares builds,
   not just marketing versions. Run the tests below.
2. Confirm the real public key and production HTTPS feed are configured. Keep
   the previous appcast and release artifacts in the local `releases/` working
   directory so packaging can enforce increasing builds. Do not place `dist/`
   legacy DMGs without Sparkle in this directory.
3. Archive with Xcode signing disabled:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -project mtihani-macos.xcodeproj -scheme mtihani-macos \
  -configuration Release -destination 'generic/platform=macOS' \
  -clonedSourcePackagesDirPath "$PWD/build/SourcePackages" \
  -archivePath "$PWD/build/Mtihani.xcarchive" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY='' \
  ONLY_ACTIVE_ARCH=NO archive
```

Use a fresh archive destination for each release. The app is located at
`build/Mtihani.xcarchive/Products/Applications/mtihani-macos.app`.

4. Produce the unsigned direct-download/Sparkle DMG:

```bash
bash scripts/package-release.sh \
  build/Mtihani.xcarchive/Products/Applications/mtihani-macos.app releases
```

The script verifies bundle configuration, increasing builds, and embedded
Sparkle components. It preserves executable permissions/symlinks using `ditto`,
removes any outer ad-hoc app signature from the staging copy, verifies the copy
is unsigned, adds an Applications shortcut, and creates an unsigned DMG. It
refuses to overwrite an existing versioned artifact.
Existing `dist/` artifacts are unchanged.

5. Add concise matching notes, for example `releases/Mtihani-1.1.0-2.html`,
   alongside `Mtihani-1.1.0-2.dmg`. Use a complete HTML document with a body
   for a linked release-notes file; HTML fragments are embedded by Sparkle.
   Markdown and text files also work in Sparkle 2.9.6. Then generate/sign:

```bash
export SPARKLE_BIN="$PWD/build/SourcePackages/artifacts/sparkle/Sparkle/bin"
bash scripts/generate-appcast.sh releases https://mtihani-app-frontend.vercel.app/
```

The official `generate_appcast` extracts versions and metadata and creates
EdDSA signatures using Keychain account `mtihani`. It updates `appcast.xml`
and includes release notes. The wrapper checks HTTPS URLs, signatures' metadata,
archive lengths, and distinct build numbers; Sparkle performs cryptography.
Deltas are disabled for V1. Do not alter the DMG after appcast generation.
Keep older artifacts available even if the generator moves them to
`old_updates/`; existing clients or cached feeds may still reference them.

```text
releases/
  Mtihani-1.0.0-1.dmg
  Mtihani-1.0.0-1.html
  Mtihani-1.1.0-2.dmg
  Mtihani-1.1.0-2.html
  appcast.xml
```

6. Upload the DMG and linked notes first. Verify their HTTPS URLs and content
   lengths, then replace `apps/frontend/public/appcast.xml` with the generated
   `appcast.xml` and deploy it last.
   Verify the feed over HTTPS with `curl --fail --proto '=https'
   --proto-redir '=https' --location URL`. Retain immutable archive URLs and
   ensure any redirects also use HTTPS. Never upload credentials or keys.
7. Install the previous Sparkle-enabled Mtihani version into Applications,
   select **Check for Updates…**, review notes, install/relaunch, and confirm
   the new version/build in Settings. Announce the release only after this
   succeeds. Existing pre-Sparkle releases need one manual DMG installation.

### Future CI

Reuse the unsigned archive and scripts above. Supply the Sparkle key either in
the build user's Keychain or through
`SPARKLE_PRIVATE_KEY_FILE` pointing to a protected temporary secret file outside
the checkout. `SPARKLE_KEY_ACCOUNT` overrides the default `mtihani` account.
Supply storage credentials through the host's secret mechanism. Do not enable
shell tracing, echo secrets, or retain temporary secret files as artifacts.
No CI provider, upload command, or backend dependency is imposed here.

## Private development update test

Use a private HTTPS static host with a trusted certificate, or a local HTTPS
server using a certificate trusted on the test Mac. Do not disable certificate
verification or add production ATS exceptions. Use a separate test Sparkle
key (`generate_keys --account mtihani-update-test`) and bundle identifier,
for example `com.victorjambo.mtihani-macos.updater-test`, to isolate preferences,
sandbox containers, installations, and capture permissions from daily use.

1. Create an external `UpdateTest.xcconfig` with the private HTTPS feed and the
   test **public** key. Build old version `1.0.0`/build `1` and new version
   `1.0.1`/build `2`, passing `-xcconfig /private/path/UpdateTest.xcconfig`,
   `PRODUCT_BUNDLE_IDENTIFIER=com.victorjambo.mtihani-macos.updater-test`,
   `MARKETING_VERSION=...`, and `CURRENT_PROJECT_VERSION=...` to `xcodebuild`.
   Both builds must use the same test ID, feed, and public key. Use separate
   output directories and preserve the old and new bundles.
2. Use the unsigned DMG packaging flow above with the test settings. A ZIP is
   also supported by Sparkle for development-only update testing; keep those
   ZIPs in a separate test release directory. Never mutate an app's Info.plist
   after generating its Sparkle archive signature.
3. Put only the new artifact and matching notes in the test release directory.
   Run `generate-appcast.sh` with `SPARKLE_KEY_ACCOUNT=mtihani-update-test` and
   the private HTTPS download prefix. Host the generated files there.
4. Install the **old** app in a writable Applications directory; quit other
   test copies. Do not run from a DMG, Xcode debugger, or translocated download.
5. Launch it and select **Check for Updates…**. Confirm Sparkle finds `1.0.1`,
   displays notes, validates the signature, installs, and relaunches. Confirm
   **Version 1.0.1 (2)** and unchanged connection/capture preferences.
6. Check again to see Sparkle's up-to-date UI. Cancel an offered update and
   confirm the app stays usable. On the private host only, test offline,
   malformed feed, missing download, and modified archive bytes: Sparkle must
   report failure and never replace the installed app. Restore signed bytes
   afterwards. Verify that the action becomes available after each failure.
7. Toggle both preferences, close/reopen Settings, quit/relaunch, and confirm
   persistence. Verify checks default on and downloads off for a clean test
   container. Enable downloads and verify Sparkle's install-on-quit behavior.
8. For background discovery, clear `SULastCheckTime` in **the test app's sandbox
   preference domain only**, or set it to one day ago plus 30 seconds before
   launch. Leave another app active and confirm the status reminder, standard
   Sparkle alert, and ability to focus it from the menu. Do not shorten the
   production interval or add timers. Also test while the app stays open.
9. Verify Settings scrolling/keyboard access, toggle names/disabled states
   with VoiceOver, Capture Now, configurable triple-click capture, connection
   testing, session selection, and quit. A real permitted capture requires
   Screen Recording permission and a reachable test backend; updater tests do
   not require either. Inspect Console's Sparkle logs and `updates` category.

## Automated verification

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
xcodebuild -resolvePackageDependencies -project mtihani-macos.xcodeproj -scheme mtihani-macos
xcodebuild -project mtihani-macos.xcodeproj -scheme mtihani-macos \
  -configuration Debug -destination 'platform=macOS' build
xcodebuild -project mtihani-macos.xcodeproj -scheme mtihani-macos \
  -configuration Release -destination 'generic/platform=macOS' ONLY_ACTIVE_ARCH=NO build
xcodebuild -project mtihani-macos.xcodeproj -scheme mtihani-macos \
  -configuration Debug -destination 'platform=macOS' test
python3 -m unittest discover -s scripts/tests
bash -n scripts/package-release.sh scripts/generate-appcast.sh \
  scripts/release-to-supabase.sh
```

This is an Xcode application, not a standalone Swift package, so Swift tests
run through the existing XCTest target rather than `swift test`.
Use `swift-format` from Xcode to format/lint edited Swift files; compilation
performs type checking. Inspect built Info.plist and `codesign -d --entitlements
:- APP` for expanded feed, public key, defaults, and sandbox names. Verify
`Contents/Frameworks/Sparkle.framework` contains `Autoupdate`, `Updater.app`,
and `XPCServices/Installer.xpc` in both Debug and Release builds.

Official references: [setup and signing](https://sparkle-project.org/documentation/),
[programmatic integration](https://sparkle-project.org/documentation/programmatic-setup/),
[sandbox integration](https://sparkle-project.org/documentation/sandboxing/),
[gentle reminders](https://sparkle-project.org/documentation/gentle-reminders/),
[publishing](https://sparkle-project.org/documentation/publishing/).
