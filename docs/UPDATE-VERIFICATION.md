# Update integration verification — 2026-09-09

Verified with Xcode 26.6 / Swift 6.3.3 on macOS 26.6.2.

| Check | Result |
| --- | --- |
| Official Swift package resolution | Sparkle 2.9.6; lockfile present |
| Debug build | Passed with Apple Development signing |
| Release build | Passed; arm64 and x86_64 slices present |
| Swift/macOS XCTest suite | 47 passed, 0 failed, 0 skipped |
| Release metadata validator tests | 7 passed |
| Swift formatting and strict lint | Passed for all edited Swift files |
| Shell syntax, plist/project validation, diff whitespace | Passed |
| Swift compiler diagnostics | No source warnings; Xcode only reports that AppIntents metadata extraction is unnecessary |
| Release bundle verification | Nested Sparkle signatures pass `codesign --verify --deep --strict` |
| Embedded helpers | Sparkle, Autoupdate, Updater.app, Installer.xpc, Downloader.xpc present |
| Signed sandbox entitlements | Sandbox/network retained; app-specific `-spks` and `-spki` names expanded correctly |
| Bundled update defaults | HTTPS feed; daily checks on; downloads off; installer service and pre-extraction verification on |
| Repository private-key pattern scan | No private-key material detected in tracked/new text files |

The ten new XCTest cases cover wrapper lifecycle, check availability, preference
write-through and external state changes, automatic-download availability,
startup errors, reminders, bundle versions, configuration, and Info.plist
policy. The existing 37 cases cover capture, backend client behavior, Settings,
application state, permissions, and click interpretation. Tests do not start
the live updater or connect to production update infrastructure.

Native UI automation timed out on the accessory app and returned an unusable
screenshot. An isolated verification build launched with a separate bundle ID,
synthetic public-key fixture, and reserved `.invalid` feed, then was closed.
**Live menu/Settings interaction, VoiceOver, preference persistence across app
relaunch, real capture, and an old-to-new update installation remain manual
checks.** Wrapper tests cover preference propagation but do not prove persistence
through a real Sparkle UI session. Follow the private test procedure in
[UPDATES.md](UPDATES.md).

The initial verification used an unset production public key. A follow-up on
2026-09-09 generated the `mtihani` key with Sparkle's official tool, kept the
private key in the login Keychain, and configured its public key in
`Configuration/Updates.xcconfig`. The proposed feed endpoint still needs
provisioning: an HTTPS check could not resolve `updates.mtihani.app`. Debug
tests (47 passing) and the universal Release build passed again, and both built
Info.plists were verified to contain the generated 32-byte public key.
The available Apple identity was Apple
Development; Developer ID export, Apple notarization, and EdDSA-signed release
generation were not performed. Release compilation and development signatures
are not a production distribution artifact. Configure the HTTPS host, Developer
ID identity and notarization credentials, securely back up the existing Sparkle
key, then execute the documented release and private installation test.
