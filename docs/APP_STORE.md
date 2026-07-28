# App Store / TestFlight prep

Checklist for shipping Peak via TestFlight and App Store Connect. Do **not** invent Connect submissions, screenshots, or secrets in-repo. Builder credential rotation is **deferred** until you explicitly ask.

Related: [PRODUCTION.md](PRODUCTION.md) (credentials, hosting, E2E A/B/C).

## Current packaging status (in-repo)

| Item | Status |
| --- | --- |
| Development Team | Paid team `49BZ7S974W` (signing configured; archive/export path documented in README) |
| `Peak/Info.plist` `PEAK_BACKEND_URL` | Set → `https://api.peakapp.site` |
| `PEAK_PRIVACY_URL` / `PEAK_TERMS_URL` / `PEAK_SUPPORT_URL` | Set → Cloudflare Pages (`https://peak-website-88n.pages.dev/legal/*`) while apex `peakapp.site` SSL is broken (525) |
| `PrivacyInfo.xcprivacy` | Present (see Nutrition Labels below) |
| `ITSAppUsesNonExemptEncryption` | `false` in Info.plist (+ Xcode `INFOPLIST_KEY_*`) — confirm with counsel |
| Sign in with Apple entitlement | **Still omitted** from `Peak/Peak.entitlements`. Re-add on the paid team before relying on native SIWA (below) |
| App Groups `group.com.pranay.peak` | Present (Reown / WalletConnect) |
| Legal HTML | Live on Pages (`website/legal/*`); substantive counsel-reviewed copy. Apex custom domain SSL still needs Cloudflare fix for marketing home |

## Before App Store Connect

- [x] **Paid Apple Developer Program team** — team `49BZ7S974W` is configured in the Xcode project.
- [ ] Confirm bundle ID `com.pranay.peak` is registered under that team / App Store Connect app record exists.
- [ ] Archive a Release build pointed at the hosted API (plist URLs above; Release rejects localhost / plain HTTP).
- [ ] Upload via Transporter / `altool` (see README **Shipping a build**).

## Sign in with Apple entitlement (when to re-add)

Native SIWA is **intentionally omitted** from `Peak/Peak.entitlements` (historically Personal Team–safe). Privy’s Apple login UI can still appear without the native entitlement.

**Re-add when** you want App Store / TestFlight Apple login on the paid team:

1. Xcode → Peak target → Signing & Capabilities → **+ Capability** → **Sign in with Apple**.
2. That adds `com.apple.developer.applesignin` (Default) to `Peak/Peak.entitlements`. Do not hand-edit XML unless you know the capability format.
3. Confirm the App ID in the [Apple Developer portal](https://developer.apple.com/account/resources/identifiers/list) has Sign in with Apple enabled.
4. Clean build; let Automatic signing refresh the provisioning profile **with** `applesignin`.

**If Xcode still complains about SIWA after it was removed** (stale profile):

1. Xcode → Settings → Accounts → Apple ID → Download Manual Profiles
2. Delete stale `iOS Team Provisioning Profile: com.pranay.peak` under `~/Library/Developer/Xcode/UserData/Provisioning Profiles/`
3. Product → Clean Build Folder → build again so the profile regenerates **without** `applesignin`

Prefer documenting this here rather than commented XML in `.entitlements` (avoids Xcode plist confusion).

## Privacy Nutrition Labels (align with `PrivacyInfo.xcprivacy`)

In App Store Connect → App Privacy, declare data to match the manifest (no tracking):

| Collected type (Connect wording) | In `PrivacyInfo.xcprivacy` | Linked to user | Used for tracking | Purpose |
| --- | --- | --- | --- | --- |
| Device ID | `NSPrivacyCollectedDataTypeDeviceID` | Yes | No | App Functionality |
| Other User Content | `NSPrivacyCollectedDataTypeOtherUserContent` | Yes | No | App Functionality |
| Other Financial Info | `NSPrivacyCollectedDataTypeOtherFinancialInfo` | Yes | No | App Functionality |

Also declare:

- **Tracking:** No (`NSPrivacyTracking` = false; no tracking domains)
- **Required Reason API:** UserDefaults — reason `CA92.1` (already in the privacy manifest)

Do not invent extra data types in Connect that are not in the manifest (or update the manifest first if product reality changes).

## Export compliance

- [ ] `ITSAppUsesNonExemptEncryption` is already `false` (standard HTTPS only). Confirm with counsel before answering the App Store Connect encryption questions the same way.
- [ ] If counsel says otherwise, flip the plist / build setting and update Connect answers — do not guess.

## Screenshots, age rating, review notes

Prepare in Connect (assets live outside this repo):

- [ ] **Screenshots** — Markets browse, event detail / trade sheet, Portfolio, Connect wallet / sign-in. Use current Liquid Glass UI; no fake balances.
- [ ] **Age rating** — Prediction markets + wallet / crypto. Answer questionnaire honestly (likely mature / financial themes; follow Apple’s current matrix).
- [ ] **Review notes** (suggested outline for the reviewer):
  - Peak is a native client for Polymarket **prediction markets**.
  - Auth: Privy (email / social) and **WalletConnect SIWE** (MetaMask, Rainbow, etc.).
  - Trading goes through Peak’s hosted HTTPS API (`api.peakapp.site`); no localhost in Release.
  - Demo account / test wallet instructions if you provide them for review.
  - Privacy / Terms / Support URLs are the Cloudflare Pages `/legal/*` pages (currently `peak-website-88n.pages.dev` while apex SSL is fixed).

Do **not** invent a fake submission ID or “already submitted” status in docs or chat.

## TestFlight smoke (hosted API)

**Still required on a physical device.** Use a device build against `https://api.peakapp.site` (or the URL in Info.plist). Full detail: [PRODUCTION.md E2E](PRODUCTION.md#e2e-paths-run-when-secrets--https-backend-are-live).

### Smoke A — Social path

1. Sign in Email / Apple / Google (Privy).
2. Choose **New account** → setup / deposit wallet when Builder + Relayer are configured.
3. Confirm Portfolio / setup does not show “backend not configured”.
4. Optional: fund → buy → sell if live credentials allow.

### Smoke B — Wallet SIWE

1. **Connect wallet** → approve SIWE in MetaMask (or Rainbow / Coinbase).
2. Existing Polymarket path / Gamma profile as prompted.
3. Confirm positions match polymarket.com for that account wallet.
4. Place or cancel an order if Builder + signing path are live.

## Legal & support

- [x] Consumer legal pages live at `website/legal/*` on Cloudflare Pages (not drafted API HTML).
- [ ] **Cloudflare:** attach custom domain `peakapp.site` / `www` to the Pages project with a working SSL cert (apex currently **525**). Then retarget Info.plist + `backend/legalPages.mjs` `WEBSITE_ORIGIN` back to `https://peakapp.site`.
- [ ] **Support inbox:** pages use `mailto:support@peakapp.site` — provision MX/mailbox for that address (branded; not a personal address).
- [x] Info.plist points at working Pages legal URLs for TestFlight / review.

## Builder credentials

**Deferred.** Do not rotate Polymarket builder API key / secret / passphrase until you explicitly request it. Shipping with existing host secrets is fine until then.

## Quick local sanity (optional)

```bash
# Packaging checks (no secrets)
./scripts/release-sanity.sh

# If you edit Info.plist, unsigned compile sanity:
DEVELOPER_DIR=/Users/pranay/Downloads/Xcode-beta.app/Contents/Developer \
  xcodebuild -scheme Peak -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO build
```
