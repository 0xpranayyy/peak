# Xcode Cloud for Peak

Use Xcode Cloud when your Mac is on an **Xcode beta** but App Store / TestFlight needs a **GM (public) Xcode** archive. Cloud runners pick a released Xcode independently of what you have installed locally.

Local archive / export / Transporter: [RELEASE.md](RELEASE.md) · Connect packaging checklists: [APP_STORE.md](APP_STORE.md).

## Honest trade-offs

| | First-time Xcode Cloud | Hourly Mac / local archive |
| --- | --- | --- |
| Setup | App Store Connect app, GitHub grant, workflow, env secrets | Already have signing + `PrivySecrets.local.plist` |
| Cost | Free tier minutes, then paid | Your Mac time |
| Beta Mac | **Wins** — Archive on public Xcode | Stuck if only beta can archive for Connect |
| Secrets | **Must** be env vars in the workflow (never commit `PrivySecrets.local.plist`) | Local gitignored plist |

After the first workflow works, starting a build is a few clicks. The painful part is only the initial Connect ↔ GitHub ↔ secrets wiring.

## Prerequisites

- [ ] **Paid Apple Developer Program** team (Peak uses `49BZ7S974W`).
- [ ] **App Store Connect app** for bundle `com.pranay.peak` already exists (or create it before the first upload).
- [ ] Repo on **GitHub** (`0xpranayyy/peak` or your fork) — Xcode Cloud clones from the remote.
- [ ] This branch includes `ci_scripts/ci_post_clone.sh` (writes PrivySecrets from env).

## 1. Create a workflow

### From Xcode (usual path)

1. Open `Peak.xcodeproj` in Xcode.
2. **Product → Xcode Cloud → Create Workflow…** (or the Report navigator → Cloud tab → **Get Started**).
3. Select the **Peak** app / product when asked.
4. If prompted, **grant GitHub access** to Xcode Cloud / App Store Connect (first time only — approve the Apple GitHub App for this repo).
5. Finish the wizard; you can refine settings in Connect next.

### From App Store Connect

1. [App Store Connect](https://appstoreconnect.apple.com) → **Apps** → **Peak**.
2. **Xcode Cloud** (sidebar) → **Get Started** / **Create Workflow**.
3. Link the GitHub repository if not already linked; grant access when Apple asks.

## 2. Workflow settings (required)

In the workflow editor (Xcode or Connect → Xcode Cloud → Workflows → Peak workflow):

| Setting | Value |
| --- | --- |
| **Xcode version** | A **public / GM** release (e.g. latest non-beta). **Do not** pick an Xcode beta for Archive — Connect rejects or blocks GM distribution from beta toolchains. |
| **macOS** | Matching recommended pair for that Xcode (Cloud offers a pair). |
| **Scheme** | **Peak** |
| **Actions** | **Archive - iOS** (required for TestFlight / App Store). A plain **Build - iOS** action often has **no Distribution identity** in the keychain — that is why Privy signing used to hard-fail. Keep Build only as an optional compile check. |
| **Post-actions** | **TestFlight Internal Testing** (or External when ready) so a green Archive lands in Connect. |
| **Start condition** | Manual is fine for the first builds; later: branch `main` on push, or tag. |

Signing: leave **automatic** / managed by Cloud for team `49BZ7S974W`. Cloud provisions certificates and profiles.

### Critical: use Archive - iOS, not only Build - iOS

| Action | Keychain identities | TestFlight | PrivySDK sign |
| --- | --- | --- | --- |
| **Archive - iOS** | Apple Distribution (after Cloud signing setup) | Yes | Prefers Distribution |
| **Build - iOS** | Often **empty** (`CODE_SIGN_IDENTITY='-'`) | No | Ephemeral self-signed, or **skip** (exit 0) if import fails |

Build 8-style logs (`CI_XCODEBUILD_ACTION='build'`, identities `-`, `security import of ephemeral cert failed`) mean the Default workflow is still **Build - iOS**. That cannot ship to TestFlight.

#### Exact clicks — switch Default workflow to Archive (App Store Connect)

1. Open [App Store Connect](https://appstoreconnect.apple.com) → **Apps** → **Peak**.
2. Sidebar → **Xcode Cloud** → **Workflows**.
3. Open the **Default** (or active) workflow → **Edit Workflow** (pencil / Edit).
4. Under **Actions**:
   - If the only action is **Build - iOS**: select it → **Delete** (or disable), **or** leave it and add Archive beside it.
   - Click **+** / **Add Action** → choose **Archive - iOS** (platform iOS, scheme **Peak**).
5. Under **Post-Actions** → **+** → **TestFlight Internal Testing** (pick an internal group when asked).
6. Confirm **Environment** still has `PRIVY_APP_ID`, `PRIVY_APP_CLIENT_ID`, `WALLETCONNECT_PROJECT_ID` (Secret).
7. **Save**.
8. Back on the workflow → **Start Build** → branch **`main`** → latest commit → Start.

#### Exact clicks — same change from Xcode

1. Open `Peak.xcodeproj` → Report navigator (speech bubble) → **Cloud** tab.
2. Select the Peak workflow → **Manage Workflows…** / gear → edit the workflow.
3. **Actions** → replace or add **Archive - iOS** (not only Build).
4. **Post-Actions** → TestFlight Internal Testing → Save.
5. **Start Build** on **`main`**.

### PrivySDK / TMS-91065 (Sign PrivySDK XCFramework)

Peak runs `scripts/sign-privy-xcframework.sh` in a build phase (after Frameworks / Resources, before Embed Extensions) so App Store Connect accepts the unsigned Privy XCFramework (nested SwiftyJSON).

On Cloud:

1. There is **no** `ci_pre_xcodebuild.sh` (removed — it could fail the job before `xcodebuild`).
2. The **Sign PrivySDK** build phase (after package resolve) exports `IDENTITY="${EXPANDED_CODE_SIGN_IDENTITY:-$CODE_SIGN_IDENTITY}"` and signs `PrivySDK.xcframework`.
3. The script prefers: build-env identity → Apple Distribution → Apple Development → any keychain identity → (CI only) ephemeral self-signed in a **temporary keychain** (`create-keychain` → `security import -f pkcs12 -T codesign` → `set-key-partition-list`).
4. On **Build-only** (`CI_XCODEBUILD_ACTION=build`) or empty/`-` CODE_SIGN identities: if ephemeral import still fails, the phase **exits 0** with  
   `Skipping PrivySDK sign on Build-only; add Archive - iOS for TestFlight/TMS-91065`  
   so a compile-check workflow does not red-fail. **Archive / install still require a successful sign.**
5. Logs include `identity_path=…`, `ephemeral_import=…` (no secret values).

`ENABLE_USER_SCRIPT_SANDBOXING` must stay **No** so the phase can touch the keychain and SPM checkout.

**Archive must still produce a signed `PrivySDK.xcframework`** (Apple Distribution when available, otherwise the ephemeral CI signer). Do not rely on ad-hoc (`codesign -s -`) for TestFlight / App Store nested frameworks.

If Archive fails with `no codesigning identity available to sign PrivySDK.xcframework` even after this fallback, confirm automatic signing for team `49BZ7S974W`, check the build log for `identity_path=` / `ephemeral_import=`, and re-run.

## 3. Environment variables (secrets)

`ci_scripts/ci_post_clone.sh` writes `Peak/PrivySecrets.local.plist` from these names. Add them under the workflow → **Environment** (mark as **Secret** so values are hidden in logs).

| Name | Required? | Source |
| --- | --- | --- |
| `PRIVY_APP_ID` | **Yes** (Archive) | Privy Dashboard → your app |
| `PRIVY_APP_CLIENT_ID` | **Yes** (Archive) | Privy Dashboard → app client (iOS) |
| `WALLETCONNECT_PROJECT_ID` | **Yes** (Archive) | [Reown Cloud](https://cloud.reown.com) |
| `SENTRY_DSN` | Optional | Sentry project DSN |

Do **not** commit `Peak/PrivySecrets.local.plist`. Do **not** put these in tracked `Info.plist`. Local Macs keep using the gitignored plist; Cloud only uses env → post-clone script.

On Archive, the script **exits non-zero** if any required Privy / WalletConnect var is missing (without printing secret values).

## 4. Start a build → TestFlight

1. Confirm the workflow action is **Archive - iOS** (not only Build) — see exact clicks above.
2. Confirm Environment secrets above are set.
3. Connect → **Xcode Cloud** → select the workflow → **Start Build** on branch **`main`** (pick the commit with this fix), **or** Xcode → Report navigator → Cloud → start build.
4. Watch **Clone** → **ci_post_clone** → resolve packages → **Sign PrivySDK** (build phase) → **Archive**.
5. In the Sign PrivySDK log lines, expect `identity_path=keychain` / `build_env` (Distribution) on Archive. On leftover Build-only runs you may see `ephemeral_*` or the skip banner (`Skipping PrivySDK sign on Build-only…`).
6. On success with a TestFlight post-action: build appears under **TestFlight** → iOS builds (processing may take minutes).
7. Assign to an internal group and install on device. Smoke: [APP_STORE.md](APP_STORE.md#testflight-smoke-hosted-api) · [RELEASE.md](RELEASE.md).

Bump `CURRENT_PROJECT_VERSION` (and `MARKETING_VERSION` when needed) in the project **before** the commit you archive — same rule as local uploads ([RELEASE.md](RELEASE.md)).

## 5. First-run GitHub access

If Clone fails with permission / “can’t access repository”:

1. App Store Connect → **Users and Access** → **Xcode Cloud** / **Integrations**, or the workflow’s GitHub prompt.
2. Install / authorize the **Apple** GitHub App for `0xpranayyy/peak` (or your org/user).
3. Re-run the build.

## Related

- [RELEASE.md](RELEASE.md) — version bumps, local `xcodebuild` archive/export, post-upload smoke
- [APP_STORE.md](APP_STORE.md) — Connect packaging, SIWA, TMS-91065 / Privy signing, Nutrition Labels
- [PRODUCTION.md](PRODUCTION.md) — credentials and hosted API
- [README Shipping a build](../README.md#shipping-a-build) — local Transporter / `altool` path
