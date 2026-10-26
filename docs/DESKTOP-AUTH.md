# Desktop sign-in setup and verification

The full backend/frontend endpoint contracts, trust boundaries, rollout and manual
acceptance checklist live in the sibling application's
[desktop authentication guide](../../mtihani-app/docs/DESKTOP-AUTH.md).

The current project maps both the app Debug and Release configurations to
`Release.xcconfig`, so running from Xcode uses production. For local development,
map the project and app Debug configurations back to `Debug.xcconfig`.
APIBaseURL is composed from API_URL in Info.plist. FrontendBaseURL
comes from FRONTEND_BASE_URL. No server URL or client key is entered in Settings.

For local debugging, choose the `mtihani-macos` scheme, **Debug** configuration,
and **My Mac** run destination. The app and test Debug targets use **Sign to Run
Locally** (ad-hoc signing) without a team or certificate. Xcode 26.3 successfully
builds this configuration on Intel macOS 15.7.3. Ad-hoc rebuilds change the code
identity, so Screen Recording permissions may need to be granted again. Choose
**Any Mac** only for a build/archive, not to run the debugger.

| Build   | Bundle ID                           | Registered callback                       |
| ------- | ----------------------------------- | ----------------------------------------- |
| Debug   | `com.victorjambo.mtihani-macos.dev` | `com.mtihani.desktop.dev://auth/callback` |
| Release | `com.victorjambo.mtihani-macos`     | `com.mtihani.desktop://auth/callback`     |

Debug: API `http://localhost:3000/api`, frontend `http://localhost:5173`, backend
`DESKTOP_ENVIRONMENT=development`. Release: API
`https://mtihani-backend.onrender.com/api`, frontend
`https://mtihani-client.vercel.app`, backend `DESKTOP_ENVIRONMENT=production`.
Production settings live in the native repository's **Release.xcconfig**, not a
`.env` file or the Xcode scheme's runtime environment variables:

```xcconfig
API_URL = https:/$()/mtihani-backend.onrender.com
FRONTEND_BASE_URL = https:/$()/mtihani-client.vercel.app
DESKTOP_ENVIRONMENT = production
DESKTOP_CALLBACK_SCHEME = com.mtihani.desktop
SPARKLE_FEED_URL = https:/$()/mtihani-client.vercel.app/appcast.xml
```

`$()` prevents `//` from becoming an xcconfig comment. `Info.plist` adds `/api`
to `API_URL`. The app reads the expanded settings from its built Info.plist,
so rebuild and relaunch after changes.

In **Render → mtihani-backend → Environment**, set:

```dotenv
DESKTOP_ENVIRONMENT=production
FRONTEND_URL=https://mtihani-client.vercel.app
CORS_ORIGIN=https://mtihani-client.vercel.app
GOOGLE_REDIRECT_URI=https://mtihani-client.vercel.app/api/auth/google/callback
```

Keep the existing Google client ID and client secret in Render. In Google Auth
Platform's Web client, register that exact `GOOGLE_REDIRECT_URI`. Google redirects
to the web backend callback, never directly to a native scheme. In Vercel, leave
`VITE_API_URL` unset; the checked-in `/api/*` rewrite points to Render.

Backend requests, device authentication, and the connection check allow 120 seconds
for a Render Free cold start. Ambiguous upload and token-refresh failures are not
automatically replayed. A longer timeout does not guarantee Render will preserve
an upload through every cold start or restart.

After rebuilding, sign in again against the fresh database, configure an AI
provider in the web app's Settings, choose/create a native session, open the same
session on the frontend, grant Screen Recording permission, and use Capture Now.
No provider key, Google client secret, or Supabase credential is stored in the
native configuration. Quit other installed native builds if they also register
the production callback while testing browser return.

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
