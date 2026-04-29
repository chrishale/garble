# Tag-driven Fastlane release pipeline

## Context

Releasing `garble` to TestFlight and the Play Console used to be a manual local process: bump `version:` in `pubspec.yaml`, run `shorebird release ios` / `android`, upload IPA/AAB by hand. The release pipeline replaces that with a tag push: a one-shot version-bump command (`scripts/version`) creates the tag, GitHub Actions runs Fastlane lanes that build via Shorebird and upload to both stores. The only manual step is `git push --tags`.

The lanes are designed to run **locally too** — the same `bundle exec fastlane ios beta` / `android internal` commands work from a developer's machine, with signing artefacts already in place (cert in keychain, profile installed via Xcode, on-disk `android/key.properties`).

The repo already had the prerequisites in place: Shorebird is initialised (`shorebird.yaml`, app id `dd401d70-473a-4269-800f-f40841c944a0`), Android signing reads `android/key.properties` (gitignored), and iOS uses Flutter build vars driven by `pubspec.yaml`.

## Approach

Three pieces:

1. **`scripts/version`** — bash script: validate input, auto-bump build number, commit, tag.
2. **`fastlane/Fastfile`** — two lanes (`ios beta`, `android internal`). Each builds via the `shorebird_release` action (Fastlane plugin) then uploads via `upload_to_testflight` / `upload_to_play_store`. Signing setup is gated by env-var presence: in CI the lane decodes base64 secrets and installs cert/profile/keystore; locally the lane skips installation and trusts the developer's existing setup.
3. **`.github/workflows/release.yml`** — triggered on `v*` tag push; one matrix job (`{android: ubuntu-latest, ios: macos-14}`) installs Ruby/Flutter/Shorebird and invokes the relevant Fastlane lane. All store-specific logic lives in the Fastfile.

iOS Release config stays on automatic signing in the project file. The lane's `update_code_signing_settings` call (CI-only) flips the Release config to manual signing referencing the `Garble App Store` profile before `xcodebuild archive` runs, so local Xcode builds keep working as today.

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

Build-number monotonicity is enforced by always incrementing — both stores require strictly increasing build numbers. The tag-existence check keys on the full `(semver, build)` pair, so reusing a semver with a fresh build number is allowed: that is the intended retry path after a failed CI upload (see Failure recovery in Verification).

### `Gemfile` (repo root)

Pulls in `fastlane` and the plugins listed in `fastlane/Pluginfile`. Bundler caches both via `bundler-cache: true` in CI.

### `fastlane/Pluginfile`

```ruby
gem "fastlane-plugin-shorebird"
```

Provides the `shorebird_release` action used by both lanes. The `shorebird` CLI itself must be on PATH separately (CI installs via `shorebirdtech/setup-shorebird@v1`; local devs have it installed already).

### `fastlane/Appfile`

Identifies the iOS bundle ID (`uk.co.chrishale.garble`) + team ID (`G67Z2FG39C`) and Android package name (`uk.co.chrishale.garble`).

### `fastlane/Fastfile`

Two lanes plus shared helpers.

**Helpers (gated on env-var presence so they no-op locally):**
- `install_ios_signing` — when `IOS_DIST_CERT_P12_BASE64` is set: runs `setup_ci`, decodes the cert into a temp file, calls `import_certificate` against a temp keychain, decodes `IOS_PROVISIONING_PROFILE_BASE64` into `~/Library/MobileDevice/Provisioning Profiles/`, then `update_code_signing_settings` on `Runner.xcodeproj` to switch the Release config to manual signing with profile `Garble App Store` and identity `Apple Distribution`.
- `install_android_signing` — when `ANDROID_KEYSTORE_BASE64` is set: decodes the keystore to `android/app/upload-keystore.jks` and writes `android/key.properties` from the four `ANDROID_*` env vars.
- `app_store_api_key_content` / `play_service_account_json` — read either an inline env var or, if a `*_PATH` env var is set (local convenience), the file at that path.

**`platform :ios → lane :beta`**
1. `install_ios_signing`.
2. `app_store_connect_api_key(key_id:, issuer_id:, key_content:)`.
3. `shorebird_release(platform: "ios", flutter_version: "latest", args: "--export-options-plist=ios/ExportOptions.plist")`.
4. `upload_to_testflight(api_key:, ipa: build/ios/ipa/garble.ipa, skip_waiting_for_build_processing: true)`.

**`platform :android → lane :internal`**
1. `install_android_signing`.
2. `shorebird_release(platform: "android", flutter_version: "latest")`.
3. `upload_to_play_store(track: "internal", release_status: "draft", aab: build/app/outputs/bundle/release/app-release.aab, json_key_data:, skip_upload_*: true)`.

**Why `release_status: "draft"`:** Play Console refuses non-draft uploads on apps that have never been published to Production with `Only releases with status draft may be created on draft app.`. After the first manual Production publish the lane can flip this to `"completed"`.

### `ios/ExportOptions.plist`

Manual-signing export options used both by Fastlane (CI) and any local invocation. The `<string>Garble App Store</string>` value must match the **profile name** chosen when creating the App Store distribution profile in the Apple Developer portal — set this when generating the profile stored as `IOS_PROVISIONING_PROFILE_BASE64`.

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

### `.github/workflows/release.yml`

Trigger: `push: tags: ['v*']`. One matrix job, both entries run in parallel.

```yaml
strategy:
  fail-fast: false
  matrix:
    include:
      - { platform: android, os: ubuntu-latest, lane: android internal }
      - { platform: ios,     os: macos-14,      lane: ios beta }
```

Steps (per matrix entry):
1. `actions/checkout@v4`.
2. `actions/setup-java@v4` (Temurin 17) — Android only.
3. `subosito/flutter-action@v2` (stable channel).
4. `shorebirdtech/setup-shorebird@v1` (cache enabled).
5. `ruby/setup-ruby@v1` (Ruby 3.2, `bundler-cache: true`).
6. `bundle exec fastlane ${{ matrix.lane }}` with all GitHub Secrets exposed as env vars.

The workflow contains no signing logic, no upload logic, and no Shorebird-specific arguments — everything is in the Fastfile.

---

## Local usage

```bash
# One-time
bundle install
cp fastlane/.env.example fastlane/.env       # then fill in values

# Each release
bundle exec fastlane ios beta                # build IPA via shorebird, upload to TestFlight
bundle exec fastlane android internal        # build AAB via shorebird, upload to Play internal
```

`fastlane/.env` (gitignored) supplies `SHOREBIRD_TOKEN`, App Store Connect API credentials, and the Play service account JSON. The `*_BASE64` secrets are intentionally **not** set locally — the lane detects their absence and skips installation, trusting the developer's existing keychain, Xcode-installed profile, and on-disk `android/key.properties`.

For convenience there are two local-only env vars (no GitHub Secret needed):
- `APPSTORE_API_PRIVATE_KEY_PATH` — local path to the `.p8` file. Read instead of `APPSTORE_API_PRIVATE_KEY` if set.
- `PLAY_SERVICE_ACCOUNT_JSON_PATH` — local path to the JSON file. Read instead of `PLAY_SERVICE_ACCOUNT_JSON` if set.

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

No new GitHub Secrets were introduced when the pipeline migrated to Fastlane — the lane consumes the existing names directly.

## One-time prerequisites

1. **First Play Console upload must be manual.** `upload_to_play_store` cannot create an app — upload one AAB by hand to the internal track in Play Console first, then CI takes over.
2. **App must remain `release_status: "draft"`** in the Fastfile until the first manual Production publish (see note in `fastlane/Fastfile`).
3. **Generate the iOS distribution cert and App Store provisioning profile** (steps below).
4. **Create all secrets above** in the repo's Settings → Secrets and variables → Actions.

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
5. **Provisioning Profile Name**: type `Garble App Store` (this exact string is what `ios/ExportOptions.plist` and the Fastfile's `update_code_signing_settings` call reference — change one and the others must match).
6. **Generate** → **Download** → save as `Garble_AppStore.mobileprovision`.
7. Encode for the secret:
   ```sh
   base64 -i Garble_AppStore.mobileprovision | pbcopy
   ```
   Paste into `IOS_PROVISIONING_PROFILE_BASE64`.

### Generating the App Store Connect API key (`.p8`)

Used by Fastlane's `app_store_connect_api_key` action instead of an Apple ID.

1. [appstoreconnect.apple.com/access/integrations/api](https://appstoreconnect.apple.com/access/integrations/api) (Users and Access → Integrations → App Store Connect API → Team Keys).
2. **Generate API Key** (or **+**). Give it a name like `Garble CI`. **Access**: `App Manager` is sufficient for TestFlight uploads (`Developer` won't be enough).
3. **Download** the `.p8` file — Apple only lets you download it once.
4. Note the **Key ID** (10-char string shown next to the key) and the **Issuer ID** (UUID at the top of the page). These become `APPSTORE_API_KEY_ID` and `APPSTORE_ISSUER_ID`.
5. For `APPSTORE_API_PRIVATE_KEY`, paste the **raw text contents** of the `.p8` file (including the `-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----` lines) — do **not** base64-encode it. Fastlane expects the PEM body directly via `key_content:`.

---

## Verification

1. **Script unit-check** (no push):
   - On a throwaway branch: `./scripts/version 9.9.9` → check `pubspec.yaml` updated, commit exists, tag `v9.9.9+<N+1>` exists. Run again with the same arg → should **succeed** and produce `v9.9.9+<N+2>` (each run bumps the build number, so the new tag is unique). Clean up with `git tag -d v9.9.9+<N+1> v9.9.9+<N+2> && git reset --hard <pre-test sha>`.
   - Run with dirty tree → should refuse.
   - Run with `0.1` (bad arg) → should refuse.

2. **Local lane parse:**
   - `bundle install` then `bundle exec fastlane lanes` → expect `ios beta` and `android internal` listed.

3. **Local release** (after filling in `fastlane/.env`):
   - `bundle exec fastlane android internal` → builds AAB via Shorebird, uploads to Play internal track as a draft release.
   - `bundle exec fastlane ios beta` → builds IPA via Shorebird, uploads to TestFlight.
   - Both lanes should skip the base64 install steps locally and use your existing keychain/keystore setup.

4. **End-to-end CI release** (real bump after secrets are configured):
   - `./scripts/version 1.0.1` → produces `1.0.1+<N+1>` and tag `v1.0.1+<N+1>`.
   - `git push && git push --tags`.
   - Watch the Actions tab: both matrix entries should go green in roughly 8–15 min.
   - Confirm: AAB visible in Play Console internal track (as a draft release until promoted); build visible in App Store Connect → TestFlight at the new build number.

5. **Failure recovery**: if a job fails midway, fix the cause and re-run `./scripts/version 1.0.1` — it will produce `v1.0.1+<N+2>` (a fresh tag at the same semver). The previous failed tag can be left in place or deleted at your leisure; what matters is that the build number bumps, since App Store Connect consumes the build number even on failed uploads.
