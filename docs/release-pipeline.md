# Tag-driven Shorebird release pipeline

## Context

Releasing `garble` to TestFlight and the Play Console used to be a manual local process: bump `version:` in `pubspec.yaml`, run `shorebird release ios` / `android`, upload IPA/AAB by hand. The release pipeline replaces that with a tag push: a one-shot version-bump command (`scripts/version`) creates the tag, GitHub Actions builds and uploads to both stores, and the only manual step is `git push --tags`.

The repo already had the prerequisites in place: Shorebird is initialised (`shorebird.yaml`, app id `dd401d70-473a-4269-800f-f40841c944a0`), Android signing reads `android/key.properties` (gitignored), and iOS uses Flutter build vars driven by `pubspec.yaml`.

## Approach

Two pieces:

1. **`scripts/version`** — bash script: validate input, auto-bump build number, commit, tag.
2. **`.github/workflows/release.yml`** — triggered on `v*` tag push; two parallel jobs (Android → Play Console internal track; iOS → TestFlight) using Shorebird's official actions.

iOS Release config stays on automatic signing locally; CI overrides to manual signing via an `ios/ExportOptions.plist` passed to `shorebird release ios`, so local Xcode builds keep working as today.

---

## Files

### `scripts/version` (executable bash)

Behaviour: `scripts/version 0.1.0`

1. Validates exactly one arg matching `^[0-9]+\.[0-9]+\.[0-9]+$`.
2. Refuses to run if `git status --porcelain` is non-empty.
3. Parses current `+N` from line `^version: ` in `pubspec.yaml` and increments to `N+1`.
4. Refuses if tag `v<arg>+<N+1>` already exists.
5. Rewrites the `version:` line in place to `version: <arg>+<N+1>`.
6. `git add pubspec.yaml`, commit `chore: bump version to <arg>+<N+1>`.
7. Annotated tag `v<arg>+<N+1>` with the same message.
8. Prints "Push with: `git push && git push --tags`".

Build-number monotonicity is enforced by always incrementing — both stores require strictly increasing build numbers. The tag-existence check now keys on the full `(semver, build)` pair, so reusing a semver with a fresh build number is allowed: that is the intended retry path after a failed CI upload (see Failure recovery in Verification).

### `ios/ExportOptions.plist`

Manual-signing export options used by CI only (passed via `--export-options-plist`). Local `flutter build ipa` ignores this file unless explicitly pointed at it, so existing automatic signing in Xcode stays intact for development.

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store</string>
  <key>teamID</key><string>G67Z2FG39C</string>
  <key>signingStyle</key><string>manual</string>
  <key>provisioningProfiles</key>
  <dict>
    <key>uk.co.chrishale.garble</key>
    <string>Garble App Store</string>
  </dict>
  <key>uploadBitcode</key><false/>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
```

The `<string>Garble App Store</string>` value must match the **profile name** chosen when creating the App Store distribution profile in the Apple Developer portal — set this when generating the profile stored as `IOS_PROVISIONING_PROFILE_BASE64`.

### `.github/workflows/release.yml`

Trigger: `push: tags: ['v*']`. Two jobs run in parallel.

**`android` job (`ubuntu-latest`)**
1. `actions/checkout@v4`
2. `actions/setup-java@v4` — Temurin 17 (matches `build.gradle.kts`).
3. `subosito/flutter-action@v2` with `channel: stable` (Shorebird tracks stable).
4. `shorebirdtech/setup-shorebird@v1` with `cache: true`.
5. Decode `ANDROID_KEYSTORE_BASE64` to `android/app/upload-keystore.jks`. Write `android/key.properties` with the four secrets (alias, key password, store password, `storeFile=upload-keystore.jks`).
6. `flutter pub get`.
7. `shorebirdtech/shorebird-release@v1` with `platform: android` (the wrapper handles non-interactive invocation; `SHOREBIRD_TOKEN` env propagates).
8. `r0adkll/upload-google-play@v1`: `serviceAccountJsonPlainText: ${{ secrets.PLAY_SERVICE_ACCOUNT_JSON }}`, `packageName: uk.co.chrishale.garble`, `releaseFiles: build/app/outputs/bundle/release/app-release.aab`, `track: internal`, `status: completed`.

**`ios` job (`macos-14`)**
1. `actions/checkout@v4`
2. `subosito/flutter-action@v2` (stable).
3. `shorebirdtech/setup-shorebird@v1`.
4. `apple-actions/import-codesign-certs@v3`: `p12-file-base64: IOS_DIST_CERT_P12_BASE64`, `p12-password: IOS_DIST_CERT_PASSWORD`.
5. Inline step: decode `IOS_PROVISIONING_PROFILE_BASE64` to `~/Library/MobileDevice/Provisioning Profiles/garble_appstore.mobileprovision` (exact filename doesn't matter; macOS resolves by UUID/name).
6. `flutter pub get`.
7. `shorebirdtech/shorebird-release@v1` with `platform: ios`, `args: --export-options-plist=ios/ExportOptions.plist`.
8. `apple-actions/upload-testflight-build@v3`: `app-path: build/ios/ipa/garble.ipa`, `issuer-id`, `api-key-id`, `api-private-key` (the `.p8` contents pasted into a secret — not base64).

Both jobs set `env: SHOREBIRD_TOKEN: ${{ secrets.SHOREBIRD_TOKEN }}` at the job level so the Shorebird CLI auto-detects CI mode.

---

## Required GitHub Secrets

| Secret | Source |
|---|---|
| `SHOREBIRD_TOKEN` | Shorebird Console → Account → API Keys |
| `ANDROID_KEYSTORE_BASE64` | `base64 -i upload-keystore.jks` |
| `ANDROID_KEY_ALIAS` | from existing local `android/key.properties` |
| `ANDROID_KEY_PASSWORD` | same |
| `ANDROID_STORE_PASSWORD` | same |
| `PLAY_SERVICE_ACCOUNT_JSON` | Created in Google Cloud Console, invited into Play Console (steps below). Raw JSON, not base64. |
| `IOS_DIST_CERT_P12_BASE64` | `base64 -i dist.p12` |
| `IOS_DIST_CERT_PASSWORD` | password used when exporting the .p12 |
| `IOS_PROVISIONING_PROFILE_BASE64` | `base64 -i Garble_AppStore.mobileprovision` |
| `APPSTORE_API_KEY_ID` | App Store Connect → Users and Access → Integrations → Key ID |
| `APPSTORE_ISSUER_ID` | same page → Issuer ID |
| `APPSTORE_API_PRIVATE_KEY` | contents of the `.p8` file (paste raw) |

## One-time prerequisites

1. **First Play Console upload must be manual.** `r0adkll/upload-google-play` cannot create an app — upload one AAB by hand to the internal track in Play Console first, then CI takes over.
2. **Generate the iOS distribution cert and App Store provisioning profile** (steps below).
3. **Create all secrets above** in the repo's Settings → Secrets and variables → Actions.

### Generating `PLAY_SERVICE_ACCOUNT_JSON`

The service account itself lives in Google Cloud, but Play Console has to invite it as a user before it can publish. Two consoles, in this order:

**In [Google Cloud Console](https://console.cloud.google.com):**

1. Top bar project picker → **New project** if you don't already have one for this app (e.g. `garble-publishing`). Otherwise select an existing project.
2. Visit [console.cloud.google.com/apis/library/androidpublisher.googleapis.com](https://console.cloud.google.com/apis/library/androidpublisher.googleapis.com) → **Enable** (skips the menu maze; this is the Google Play Android Developer API).
3. Hamburger menu → **IAM & Admin → Service Accounts** → **+ Create service account**.
   - Name: `garble-ci-publisher` (or anything memorable). Skip the optional "Grant access" steps — Play Console grants permissions, not Cloud IAM.
   - **Done**.
4. Open the new service account → **Keys** tab → **Add Key → Create new key → JSON** → **Create**. A `.json` file downloads. The contents of this file go into the `PLAY_SERVICE_ACCOUNT_JSON` GitHub secret (paste the entire JSON, not base64).
5. Copy the service account's **email** (looks like `garble-ci-publisher@<project-id>.iam.gserviceaccount.com`) — you'll need it next.

**In [Play Console](https://play.google.com/console):**

6. Left rail: **Users and permissions** (top-level item on the Play Console home, not nested under Setup any more). Click **Invite new users**.
7. **Email address**: paste the service account email from step 5.
8. **App permissions** → **Add app** → pick **Garble** → tick at minimum:
   - **View app information and download bulk reports (read-only)**
   - **Manage testing track releases** (sufficient for the workflow's `track: internal`).
   You can grant **Manage production releases** later if you want CI to push to production.
9. **Account permissions**: leave at defaults (no account-wide perms needed).
10. **Invite user**. The service account is added immediately — no email confirmation step (it's a non-human account).
11. (One-time, if not already done) **Setup → API access** in Play Console: confirm the linked Google Cloud project is the one from step 1. If not linked yet, this page lets you link it. Once linked, the Android Publisher API will accept the service account's tokens.

If anything 401/403s on the first CI run, the cause is almost always that step 8's app permission scope doesn't cover the track you're uploading to.

### Generating `dist.p12` (Apple distribution certificate)

You only need to do this once per Apple Developer account; an existing dist cert works fine if you already have one in Keychain.

1. Open **Keychain Access** on macOS → menu **Keychain Access → Certificate Assistant → Request a Certificate from a Certificate Authority…**
   - Email: your Apple ID email.
   - Common Name: `Garble Distribution` (anything memorable).
   - **CA Email Address: leave blank**.
   - Choose **Saved to disk** → save `CertificateSigningRequest.certSigningRequest`.
2. Go to [developer.apple.com/account/resources/certificates](https://developer.apple.com/account/resources/certificates/list) → **+** → choose **Apple Distribution** (works for both App Store and Ad Hoc) → upload the `.certSigningRequest` file → **Download** the resulting `.cer`.
3. Double-click the `.cer` to import into Keychain (login keychain, "My Certificates" category).
4. In Keychain Access, find the certificate, expand it to confirm the matching private key is underneath, **right-click → Export "Apple Distribution: …"**, choose **Personal Information Exchange (.p12)**, save as `dist.p12`, set a strong password.
5. That password becomes `IOS_DIST_CERT_PASSWORD`. The file becomes `IOS_DIST_CERT_P12_BASE64` via:
   ```sh
   base64 -i dist.p12 | pbcopy
   ```
   Paste straight into the GitHub secret.

### Generating `Garble_AppStore.mobileprovision` (provisioning profile)

1. First, ensure the **App ID** exists: [developer.apple.com/account/resources/identifiers](https://developer.apple.com/account/resources/identifiers/list). If `uk.co.chrishale.garble` isn't listed, **+ → App IDs → App** with that bundle ID. Capabilities should match what the app actually uses (likely none beyond defaults right now).
2. Go to [Profiles](https://developer.apple.com/account/resources/profiles/list) → **+** → **App Store Connect** under Distribution → **Continue**.
3. **App ID**: pick `uk.co.chrishale.garble`.
4. **Certificates**: select the Apple Distribution cert you just created.
5. **Provisioning Profile Name**: type `Garble App Store` (this exact string is what `ios/ExportOptions.plist` references — change one and the other must match).
6. **Generate** → **Download** → save as `Garble_AppStore.mobileprovision`.
7. Encode for the secret:
   ```sh
   base64 -i Garble_AppStore.mobileprovision | pbcopy
   ```
   Paste into `IOS_PROVISIONING_PROFILE_BASE64`.

### Generating the App Store Connect API key (`.p8`)

Used by `apple-actions/upload-testflight-build` instead of an Apple ID.

1. [appstoreconnect.apple.com/access/integrations/api](https://appstoreconnect.apple.com/access/integrations/api) (Users and Access → Integrations → App Store Connect API → Team Keys).
2. **Generate API Key** (or **+**). Give it a name like `Garble CI`. **Access**: `App Manager` is sufficient for TestFlight uploads (`Developer` won't be enough).
3. **Download** the `.p8` file — Apple only lets you download it once.
4. Note the **Key ID** (10-char string shown next to the key) and the **Issuer ID** (UUID at the top of the page). These become `APPSTORE_API_KEY_ID` and `APPSTORE_ISSUER_ID`.
5. For `APPSTORE_API_PRIVATE_KEY`, paste the **raw text contents** of the `.p8` file (including the `-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----` lines) — do **not** base64-encode it. The action expects the PEM body directly.

---

## Verification

1. **Script unit-check** (no push):
   - On a throwaway branch: `./scripts/version 9.9.9` → check `pubspec.yaml` updated, commit exists, tag `v9.9.9+<N+1>` exists. Run again with the same arg → should **succeed** and produce `v9.9.9+<N+2>` (each run bumps the build number, so the new tag is unique). Clean up with `git tag -d v9.9.9+<N+1> v9.9.9+<N+2> && git reset --hard <pre-test sha>`.
   - Run with dirty tree → should refuse.
   - Run with `0.1` (bad arg) → should refuse.

2. **End-to-end release** (real bump after secrets are configured):
   - `./scripts/version 1.0.1` → produces `1.0.1+<N+1>` and tag `v1.0.1+<N+1>`.
   - `git push && git push --tags`.
   - Watch the Actions tab: both jobs should go green in roughly 8–15 min.
   - Confirm: AAB visible in Play Console internal track; build visible in App Store Connect → TestFlight at the new build number.

3. **Failure recovery**: if a job fails midway, fix the cause and re-run `./scripts/version 1.0.1` — it will produce `v1.0.1+<N+2>` (a fresh tag at the same semver). The previous failed tag can be left in place or deleted at your leisure; what matters is that the build number bumps, since App Store Connect consumes the build number even on failed uploads.
