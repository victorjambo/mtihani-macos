# Mtihani for macOS

Mtihani is a lightweight menu-bar companion for permitted coding-practice and
mock-assessment sessions. A manual command or observed global multi-click
captures the main display, uploads one PNG to the configured backend session,
and returns to its waiting state after the backend accepts the capture.

## Requirements

- macOS 15.6 or newer, matching the application target
- Xcode 26.6 or newer
- A running Mtihani backend and an active backend session UUID

## Run

1. Open `mtihani-macos.xcodeproj` in Xcode.
2. Select the `mtihani-macos` scheme and run the app.
3. Sign in to the Mtihani web app, open **Settings**, generate a **Mtihani
   Client Key**, and copy it. The plaintext key is shown only once.
4. Open the menu-bar item, choose **Settings**, and configure the backend API
   URL, Mtihani Client Key, and session ID.
5. Select **Test Connection**.
6. Grant Screen Recording access when requested. If macOS asks for a relaunch,
   quit and start Mtihani again.

The development backend URL defaults to `http://localhost:3000/api`. Production
deployments should use HTTPS.

Settings lists backend sessions newest-first while retaining manual session-ID
entry. **Start New Session** in the menu-bar popover creates a backend session
and immediately makes it the current session.

## Capture behavior

- **Capture Now** and the configurable native global multi-click trigger both call the same
  capture coordinator.
- The click trigger defaults to 3 clicks and can be set from 2 to 5 clicks in
  Settings. Changes take effect immediately.
- The global click is observed and is never consumed or replaced.
- Only one capture can run at a time.
- Screenshots are encoded as PNG in memory and are not written to disk.
- The macOS client does not impose its own upload-size limit; the backend's
  `MAX_CAPTURE_SIZE_MB` setting controls the accepted size.
- The client stops after the backend returns `202 Accepted`; it does not poll
  for analysis results or connect to SSE.

## Tests

Run the macOS unit tests from Xcode with **Product → Test**, or from a shell:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild \
  -project mtihani-macos.xcodeproj \
  -scheme mtihani-macos \
  -destination 'platform=macOS' \
  test
```

The tests use mocks and do not require Screen Recording permission or a live
backend.

## Application updates

The menu-bar popover includes **Check for Updates…**. Settings includes the
current version/build and Sparkle's automatic-check/download preferences.
Checks default to daily; automatic downloads and install-on-quit are opt-in.

The Sparkle public key in `Configuration/Updates.xcconfig` corresponds to the
`mtihani` signing key in the release Mac's login Keychain. Before distributing,
securely back up that key and provision the production HTTPS feed.
Builds with a missing or invalid public key keep update controls unavailable. See
[application updates and releases](docs/UPDATES.md) for key setup, sandbox
details, Developer ID/notarization, DMG/appcast generation, private update
testing, and the production release procedure.
Current verification results and remaining manual checks are recorded in
[update verification](docs/UPDATE-VERIFICATION.md).
