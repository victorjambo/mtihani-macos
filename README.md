# Mtihani for macOS

Mtihani is a lightweight menu-bar companion for permitted coding-practice and
mock-assessment sessions. A manual command or observed global multi-click
captures the display containing the pointer, uploads one PNG to the selected account session,
and returns to its waiting state after the backend accepts the capture.

## Requirements

- macOS 15.6 or newer, matching the application target
- Xcode 26.3 or newer (local Intel build verified on macOS 15.7.3)
- A running Mtihani backend and an active backend session UUID

## Run

1. Open `mtihani-macos.xcodeproj` in Xcode.
2. Select the `mtihani-macos` scheme and **My Mac** destination. In
   **Product → Scheme → Edit Scheme → Run → Info**, use **Debug**. Press **⌘R**.
3. Choose **Sign in** in the menu bar or Settings. Complete browser Google login
   and explicitly confirm **Continue as your email**.
4. Return to Mtihani and choose or create a session in Settings → Sessions.
   Account → Switch account preserves the current account if cancelled.
5. **Test connection** checks public server reachability, not session authorization.
6. Grant Screen Recording access when requested. If macOS asks for a relaunch,
   quit and start Mtihani again.

Debug builds use **Sign to Run Locally** with no developer team or certificate.
No Apple Account is required for this local signing mode. Its identity changes
when the app is rebuilt, so macOS may ask for Screen Recording permission again.

**Any Mac** is a build/archive destination and cannot launch the debugger. A
shared Intel/Apple silicon build needs both `x86_64` and `arm64` architectures;
see the [unsigned release runbook](docs/UNSIGNED-RELEASE.md) for packaging.

The backend URL comes from the build configuration's `APIBaseURL` value.
The current Xcode project maps both Debug and Release builds to `Release.xcconfig`,
which uses the live Render backend and Vercel frontend. Rebuild after changing
these values. `Info.plist` adds `/api` to `API_URL`; do not include it twice.
For local development, map the project and app Debug configurations back to
`Debug.xcconfig`, which contains the loopback endpoints and development callback.

Settings has Sessions, Capture, Permissions, Updates and Account tabs. Selection
is remembered per account/environment. A missing or closed previous session pauses
capture until explicitly replaced. **New session** becomes active only after server confirmation.

See [authentication and manual verification](docs/DESKTOP-AUTH.md) for configuration,
Keychain behavior, callbacks, migration and release acceptance checks.

## Capture behavior

- **Capture Now** and the configurable native global multi-click trigger both call the same
  capture coordinator.
- The click trigger defaults to 3 clicks and can be set from 3 to 6 clicks in
  Settings. Changes take effect immediately.
- The global click is observed and is never consumed or replaced.
- Only left mouse-down events outside Mtihani count. Timing and positional reset
  follow macOS native multi-click detection. Only the exact threshold triggers;
  six clicks at threshold three do not cause a second capture.
- The saved trigger preference is suspended without authentication, an eligible
  session or Screen Recording access. Manual capture does not require the toggle.
- The pointer display is selected at initiation (main display fallback). Mtihani
  windows are excluded and the menu is dismissed before manual capture.
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

Check for updates in **Settings → Updates**, alongside the current version/build
and Sparkle's automatic-check/download preferences. The menu-bar popover shows
an update notice when one is available, but has no separate update-check action.
Scheduling and installation remain owned by the existing Sparkle configuration.

The Sparkle public key in `Debug.xcconfig` and `Release.xcconfig` corresponds to the
`mtihani` signing key in the release Mac's login Keychain. Before distributing,
securely back up that key and provision the production HTTPS feed.
Builds with a missing or invalid public key keep update controls unavailable. See
[application updates and releases](docs/UPDATES.md) for key setup, sandbox
details, universal app ZIP/appcast generation, Supabase publication, private update
testing, and the production release procedure. For the exact release command,
environment-variable reference, and version-bump checklist, use the
[unsigned release runbook](docs/UNSIGNED-RELEASE.md).
Current verification results and remaining manual checks are recorded in
[update verification](docs/UPDATE-VERIFICATION.md).
