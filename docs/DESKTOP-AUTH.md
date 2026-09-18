# Desktop sign-in setup and verification

The full backend/frontend endpoint contracts, trust boundaries, rollout and manual
acceptance checklist live in the sibling application's
[desktop authentication guide](../../mtihani-app/docs/DESKTOP-AUTH.md).

Use `Debug.xcconfig` for local development and `Release.xcconfig` for distribution.
APIBaseURL is still composed from API_SCHEME/API_HOST in Info.plist. FrontendBaseURL
comes from FRONTEND_BASE_URL. No server URL or client key is entered in Settings.

| Build | Bundle ID | Registered callback |
| --- | --- | --- |
| Debug | `com.victorjambo.mtihani-macos.dev` | `com.mtihani.desktop.dev://auth/callback` |
| Release | `com.victorjambo.mtihani-macos` | `com.mtihani.desktop://auth/callback` |

Debug: API `http://localhost:3000/api`, frontend `http://localhost:5173`, backend
`DESKTOP_ENVIRONMENT=development`. Release: API
`https://mtihani-app-production.up.railway.app/api`, frontend
`https://mtihani-app-frontend.vercel.app`, backend `DESKTOP_ENVIRONMENT=production`.
Google redirects to the web backend callback, never directly to a native scheme.

ASWebAuthenticationSession retains PKCE verifier/state in memory. Only the short-lived
handoff code and state travel in the callback. Device access/refresh credentials live
in environment/API-scoped Keychain, not UserDefaults. The account ID inside the
envelope is stable; one account is active. Native sign-out clears local credentials
even offline and warns if remote revocation cannot be confirmed. It does not sign
out the browser or Google. Offline restore keeps credentials; invalid renewal
requires browser sign-in again. Refresh response loss may also require sign-in
because replay protection rejects already-used refresh tokens.

Before distribution manually verify actual Google/browser return and switching,
signed-app Keychain persistence, Debug/Release callback isolation, permission
denial/grant, multiple displays, click counts 3/6 and ignored local clicks, keyboard
and VoiceOver navigation, small-window and long-label layouts, and Sparkle's existing
test-feed update flow. These cannot be established by unit mocks. Do not publish a
release or revoke production keys as part of local verification.
