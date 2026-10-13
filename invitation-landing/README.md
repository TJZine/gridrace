# Invitation landing assets

Local preparation only. `config.mjs` ships with an empty allowlist; the app's
`GridRaceInvitationOrigins` defaults to an empty build setting. No domain, Apple
team, bundle identity, installation URL or provider identity has been invented.
Manual code entry/sharing remains available. The current app entitlement retains
Sign in with Apple; use the dedicated associated-domains template only after
signing and host inputs are confirmed.

For each environment supply `GRIDRACE_INVITATION_HOST`, `APPLE_TEAM_ID`,
`ENVIRONMENT_BUNDLE_ID`, the confirmed App Store URL (optional),
`APPLE_PROVIDER_SERVICE_ID` and `SUPABASE_APPLE_REDIRECT_URL`. Set the same exact
HTTPS origin in app build configuration and landing `allowedOrigins`. Keep
staging and production independent. Build settings use the xcconfig URL escape
shown in `templates/Invitations.xcconfig`.

The host must serve `index.html` at `/join/<code>` without redirect discovery;
serve the four asset files at their absolute root paths. Serve the substituted
association JSON at `/.well-known/apple-app-site-association` as application/json,
without authentication or redirects. Do not deploy unresolved templates.

Required host configuration:

- Send `Referrer-Policy: no-referrer` on HTML and assets. The HTML meta policy is
  additional protection. Send a header CSP matching the meta policy, plus
  `frame-ancestors 'none'`, and `X-Content-Type-Options: nosniff`.
- Disable access logs for `/join/*` at every CDN, proxy and origin. Where logs
  cannot be disabled, replace the complete path/code with `/join/[redacted]`
  before emission. Do not record raw request URLs in error logs or tracing.
- Do not enable analytics, roster previews, third-party scripts/resources,
  external fonts, redirects to discover invitations, or deferred-install claims.

Local parser/DOM checks: `node --test invitation-landing/tests/*.test.mjs`.
Static assets do not prove deployed logging/referrer policy. Confirm actual HTTPS
routing, association fetch, signed-device link handling, Apple/Supabase provider
flow and protected storage separately before distribution. Reopen the original
link after installation; no automatic install continuation is promised.

Association template syntax follows [Apple's components reference](https://developer.apple.com/documentation/bundleresources/applinks/details-swift.dictionary/components-swift.dictionary).
The application parser remains the strict authority; AASA wildcard routing is
not a substitute for rejecting empty queries/fragments and the code alphabet.
