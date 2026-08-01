# Peak release cadence

Short post-TestFlight maintenance guide. Credentials, Connect checklists, and E2E paths live elsewhere — link out, don’t duplicate.

- Credentials / hosting / E2E A·B·B2·C → [PRODUCTION.md](PRODUCTION.md)
- Connect packaging, SIWA, Nutrition Labels, review notes → [APP_STORE.md](APP_STORE.md)
- Archive / export / Sentry one-liners → [README Shipping a build](../README.md#shipping-a-build)

## Web vs iOS

| Piece | What it is | How you ship |
| --- | --- | --- |
| **API** (`backend/`) | Privy auth, Builder/Relayer trading, legal redirects | Deploy host (Railway → `https://api.peakapp.site`). No App Store round-trip. |
| **Legal HTML** (`website/legal/`) | Privacy / Terms / Support | Cloudflare Pages. App opens URLs from `Peak/Info.plist`. |
| **iOS** (`Peak/`) | UI, auth UX, trading screens, geo gate | Archive → export → TestFlight / App Store. Bundle `com.pranay.peak`, team `49BZ7S974W`. |

Server secrets and most trading bugs are API-only. Client bugs, UI, plist URL changes, and new native capabilities need a new iOS build.

## API-only vs new iOS build

**Deploy API only when** you change `backend/` behavior, host env, or Pages legal copy — and the app already talks to `https://api.peakapp.site` with the right plist URLs.

**Ship a new iOS build when** you change SwiftUI / native code, bump marketing version, change `PEAK_*` URLs in Info.plist, add entitlements (e.g. SIWA), or fix a client-side crash/geo/auth bug.

Optional before either: `./scripts/release-sanity.sh` (plist HTTPS, legal keys, backend `npm run check` — no secrets).

## Version vs build number

In `Peak.xcodeproj` (app + widget targets stay in sync):

| Setting | Current | When to bump |
| --- | --- | --- |
| `MARKETING_VERSION` | `1.1` | User-visible release (what Settings shows as the version). |
| `CURRENT_PROJECT_VERSION` | `2` | **Every** TestFlight / App Store upload. Connect rejects a build number it already accepted. |

`ExportOptions.plist` sets `manageAppVersionAndBuildNumber` = **false** so export does not rewrite the git number. Bump in the project first.

## Archive → export → TestFlight

1. Bump `CURRENT_PROJECT_VERSION` (and `MARKETING_VERSION` if this is a named release).
2. Confirm `Peak/Info.plist`: `PEAK_BACKEND_URL` = `https://api.peakapp.site`; legal URLs = working HTTPS pages (see PRODUCTION.md table).
3. `./scripts/release-sanity.sh`
4. Archive + export (from repo root):

```bash
xcodebuild archive -project Peak.xcodeproj -scheme Peak \
  -destination 'generic/platform=iOS' -archivePath build/Peak.xcarchive

xcodebuild -exportArchive -archivePath build/Peak.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/export
```

Archive signs Apple Development; export re-signs with Apple Distribution via `ExportOptions.plist` (`method` = `app-store-connect`, team `49BZ7S974W`, automatic signing, `uploadSymbols` = true).

5. Upload IPA with Transporter, or:

```bash
xcrun altool --upload-app -f build/export/Peak.ipa -t ios \
  --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
```

App record for `com.pranay.peak` must already exist in App Store Connect.

6. Upload dSYMs to **Sentry** (Apple gets them via `uploadSymbols`; Sentry does not):

```bash
sentry-cli debug-files upload --org <org> --project <project> build/Peak.xcarchive/dSYMs
```

`CrashReporting` is Release-only — empty Sentry after a Debug run is expected.

## Smoke after each TestFlight upload

Physical device, build pointed at hosted API. Full A/B/B2 detail: [PRODUCTION.md E2E](PRODUCTION.md#e2e-paths-run-when-secrets--https-backend-are-live) · [APP_STORE.md smoke](APP_STORE.md#testflight-smoke-hosted-api).

Quick pass each upload:

- [ ] **Markets** — list loads; open an event; chart / order book looks sane
- [ ] **Event book / trade sheet** — prices update; sheet opens (place a tiny order only if Builder path is live)
- [ ] **Auth** — Email/Apple/Google **or** Connect wallet SIWE; Portfolio not “backend not configured”
- [ ] **Import B2** — existing-path / import key → Cash matches ~pUSD; Import CTA if missing; optional ~$1 buy + cancel
- [ ] **Legal URLs** — Settings → Privacy / Terms / Support open (Pages host while apex SSL is 525)

## Debugging

| Symptom | Where |
| --- | --- |
| Client crash / Release exception | Sentry (after dSYM upload). Apple Organizer if you only uploaded to Connect. |
| Unreadable Sentry stacks | Re-upload dSYMs from that archive’s `dSYMs` folder. |
| Xcode “missing Sentry.framework dSYM” | Warning only (upload still works). Peak uses `Sentry-Dynamic` so the archive should include that dSYM — see [APP_STORE.md](APP_STORE.md#sentryframework-missing-dsym-xcode-16-upload-warning). |
| Auth / setup / order `5xx` | Railway (or host) logs for `backend/`; confirm host env matches `.env.example` keys (never commit `.env`). |
| Device-only oddity | Mac **Console** app → device → filter for Peak process; reproduce once. |
| “Backend not configured” | Host missing Builder/Relayer/Privy; or Release build still on bad URL (Release rejects localhost / plain HTTP). |

## Cadence

| When | Do |
| --- | --- |
| **Weekly** (while iterating) | API deploys as needed; one TestFlight if iOS changed; run the smoke list above. |
| **Before App Store submit** | Full [APP_STORE.md](APP_STORE.md) + [PRODUCTION.md](PRODUCTION.md); bump marketing version if user-facing; smoke A + B (+ B2); confirm Nutrition Labels / encryption answers with counsel. |
| **API hotfix, no client change** | Deploy backend only; re-smoke Markets + auth + one trade path on the **existing** TestFlight build. |
