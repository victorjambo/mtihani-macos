# Mtihani for macOS

Mtihani is a lightweight menu-bar companion for permitted coding-practice and
mock-assessment sessions. A manual command or observed global triple-click
captures the main display, uploads one PNG to the configured backend session,
and returns to its waiting state after the backend accepts the capture.

## Requirements

- macOS 26.5 or newer, matching the existing project deployment target
- Xcode 26.6 or newer
- A running Mtihani backend and an active backend session UUID

## Run

1. Open `mtihani-macos.xcodeproj` in Xcode.
2. Select the `mtihani-macos` scheme and run the app.
3. Open the menu-bar item, choose **Settings**, and configure the backend API
   URL and session ID.
4. Select **Test Connection**.
5. Grant Screen Recording access when requested. If macOS asks for a relaunch,
   quit and start Mtihani again.

The development backend URL defaults to `http://localhost:3000/api`. Production
deployments should use HTTPS.

## Capture behavior

- **Capture Now** and a native global triple left-click both call the same
  capture coordinator.
- The global click is observed and is never consumed or replaced.
- Only one capture can run at a time.
- Screenshots are encoded as PNG in memory and are not written to disk.
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
