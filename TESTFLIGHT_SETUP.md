# PeptideX — TestFlight Setup Guide

## App Details
- **App Name:** PeptideX
- **Bundle ID:** `com.peptidesai.app`
- **Widget Bundle ID:** `com.peptidesai.app.widgets`
- **Watch Bundle ID:** `com.peptidesai.app.watchkitapp`
- **Watch Widget Bundle ID:** `com.peptidesai.app.watchkitapp.widgets`
- **App Group:** `group.com.peptidesai.app`
- **iCloud Container:** `iCloud.com.peptidesai.app`

---

## Quick Checklist

Work through this top-to-bottom before running the workflow. Each item maps to a step below.

- [ ] Apple Developer Program active ($99/year membership)
- [ ] App Group `group.com.peptidesai.app` registered in Developer Portal
- [ ] iCloud Container `iCloud.com.peptidesai.app` registered in Developer Portal
- [ ] App ID `com.peptidesai.app` registered with App Groups + HealthKit + Sign In with Apple + iCloud
- [ ] App Group linked to `com.peptidesai.app` (click Configure → tick the group → Save)
- [ ] iCloud Container linked to `com.peptidesai.app` (Configure iCloud → tick CloudKit + the container → Save)
- [ ] App ID `com.peptidesai.app.widgets` registered with App Groups
- [ ] App Group linked to `com.peptidesai.app.widgets`
- [ ] App ID `com.peptidesai.app.watchkitapp` registered with App Groups
- [ ] App Group linked to `com.peptidesai.app.watchkitapp`
- [ ] App ID `com.peptidesai.app.watchkitapp.widgets` registered with App Groups
- [ ] App Group linked to `com.peptidesai.app.watchkitapp.widgets`
- [ ] App created in App Store Connect with bundle ID `com.peptidesai.app`
- [ ] Apple Distribution certificate downloaded and exported as `.p12`
- [ ] App Store Connect API key created with App Manager access, `.p8` file saved
- [ ] All 6 GitHub Secrets added (see Step 6)
- [ ] Secrets verified with the verification commands (see Step 6)

---

## Step 1: Register Shared Resources and App IDs in the Developer Portal

> **Do this in order.** Shared resources (App Group + iCloud Container) must exist before you can link them to App IDs.

### 1a. Create the App Group

1. Open [Identifiers](https://developer.apple.com/account/resources/identifiers/list)
2. Click **+** → select **App Groups** → **Continue**
3. Description: `PeptideX Shared Group`
4. Identifier: `group.com.peptidesai.app`
5. Click **Continue** → **Register**

### 1b. Create the iCloud Container

1. Identifiers → **+** → select **iCloud Containers** → **Continue**
2. Description: `PeptideX`
3. Identifier: `iCloud.com.peptidesai.app`
4. Click **Continue** → **Register**

### 1c. Register the main App ID (`com.peptidesai.app`)

1. Identifiers → **+** → **App IDs** → **App** → **Continue**
2. Description: `PeptideX`
3. Bundle ID: **Explicit** → `com.peptidesai.app`
4. Under **Capabilities**, tick all four:
   - ☑ **App Groups**
   - ☑ **HealthKit**
   - ☑ **Sign In with Apple**
   - ☑ **iCloud** (tick **Include CloudKit support** in the Configure dialog)
5. Click **Configure** (or **Edit**) next to **App Groups** → tick `group.com.peptidesai.app` → **Continue**
6. Click **Configure** (or **Edit**) next to **iCloud** → tick **CloudKit** and `iCloud.com.peptidesai.app` → **Continue**
7. Click **Continue** → **Register**

### 1d. Register the widget App ID (`com.peptidesai.app.widgets`)

1. Identifiers → **+** → **App IDs** → **App** → **Continue**
2. Description: `PeptideX Widgets`
3. Bundle ID: **Explicit** → `com.peptidesai.app.widgets`
4. Under **Capabilities**, tick:
   - ☑ **App Groups**
5. Click **Configure** next to **App Groups** → tick `group.com.peptidesai.app` → **Continue**
6. Click **Continue** → **Register**

### 1e. Register the watch App ID (`com.peptidesai.app.watchkitapp`)

1. Identifiers → **+** → **App IDs** → **App** → **Continue**
2. Description: `PeptideX Watch`
3. Bundle ID: **Explicit** → `com.peptidesai.app.watchkitapp`
4. Under **Capabilities**, tick:
   - ☑ **App Groups**
5. Click **Configure** next to **App Groups** → tick `group.com.peptidesai.app` → **Continue**
6. Click **Continue** → **Register**

### 1f. Register the watch widget App ID (`com.peptidesai.app.watchkitapp.widgets`)

The watch widget is a separate extension target with its own bundle ID and its own entitlements. It reads the shared `watch_data.json` from the App Group container, so it needs `App Groups` enabled and linked just like the other targets. Skipping this step is the most common cause of `Provisioning profile "iOS Team Provisioning Profile: com.peptidesai.app.watchkitapp.widgets" doesn't match the entitlements file's value for the com.apple.security.application-groups entitlement` at archive time.

1. Identifiers → **+** → **App IDs** → **App** → **Continue**
2. Description: `PeptideX Watch Widgets`
3. Bundle ID: **Explicit** → `com.peptidesai.app.watchkitapp.widgets`
4. Under **Capabilities**, tick:
   - ☑ **App Groups**
5. Click **Configure** next to **App Groups** → tick `group.com.peptidesai.app` → **Continue**
6. Click **Continue** → **Register**

> **Common mistake:** Forgetting to click **Configure** and actually tick the group/container after enabling a capability. The capability checkbox alone is not enough — the group/container must be explicitly linked. If the archive fails with an `application-groups entitlement` mismatch or `Entitlement com.apple.developer.icloud-containers not found`, this is the cause.

---

## Step 2: Create App in App Store Connect

1. Go to [App Store Connect → My Apps](https://appstoreconnect.apple.com/apps)
2. Click **+** → **New App**
3. Platform: **iOS**
4. Name: `PeptideX`
5. Bundle ID: select `com.peptidesai.app` (must appear after Step 1c)
6. SKU: `peptidex` (any unique string works)
7. Primary Language: your language of choice
8. Click **Create**

---

## Step 3: Create a Distribution Certificate

> Skip to "Export as .p12" if you already have an Apple Distribution certificate in Keychain.

### Create a Certificate Signing Request (CSR)

```bash
openssl req -nodes -newkey rsa:2048 \
  -keyout ~/Desktop/distribution.key \
  -out ~/Desktop/distribution.csr \
  -subj "/emailAddress=YOUR_APPLE_EMAIL/CN=YOUR_NAME/C=US"
```

### Upload and download the certificate

1. Go to [Certificates](https://developer.apple.com/account/resources/certificates/list) → **+**
2. Select **Apple Distribution** → **Continue**
3. Upload `distribution.csr` → **Continue**
4. Download the resulting `.cer` file (e.g. `distribution_identity.cer`)

### Export as .p12

```bash
# Convert .cer to .pem
openssl x509 -in ~/Desktop/distribution_identity.cer \
  -inform DER -out ~/Desktop/distribution.pem -outform PEM

# Bundle key + cert into .p12 — you will be prompted to set a password
# USE A STRONG PASSWORD AND REMEMBER IT — you need it for APPLE_CERTIFICATE_PASSWORD
openssl pkcs12 -export \
  -inkey ~/Desktop/distribution.key \
  -in ~/Desktop/distribution.pem \
  -out ~/Desktop/distribution.p12
```

> If you already have the certificate in Keychain Access: open **Keychain Access** → **My Certificates** → right-click the "Apple Distribution: …" cert → **Export** → save as `.p12` → set a password.

---

## Step 4: Create an App Store Connect API Key

1. Go to [App Store Connect → Users and Access → Integrations → App Store Connect API](https://appstoreconnect.apple.com/access/api)
2. If prompted, click **Request Access** first
3. Click **+** to generate a new key
4. Name: `GitHub Actions`
5. Access: **App Manager** (minimum required for TestFlight uploads)
6. Click **Generate**
7. **Download the `.p8` file immediately** — it can only be downloaded once. If you miss it, delete and regenerate.
8. Copy the **Key ID** (10-character string shown in the table, e.g. `ABC1234DEF`)
9. Copy the **Issuer ID** (UUID shown at the top of the page, e.g. `12345678-1234-1234-1234-123456789012`)

---

## Step 5: Find Your Team ID

1. Go to [Membership Details](https://developer.apple.com/account#MembershipDetailsCard)
2. Your **Team ID** is the 10-character alphanumeric string (e.g. `LFGMAA62R4`)

---

## Step 6: Add GitHub Secrets

Go to: **GitHub repo → Settings → Secrets and variables → Actions → New repository secret**

Add all 6 secrets exactly as named below (case-sensitive):

| Secret Name | Value |
|---|---|
| `APPLE_CERTIFICATE_BASE64` | Base64 of the `.p12` file |
| `APPLE_CERTIFICATE_PASSWORD` | Password you set when exporting `.p12` |
| `APPLE_TEAM_ID` | 10-char Team ID from Step 5 (e.g. `LFGMAA62R4`) |
| `APPLE_CONNECT_KEY_ID` | API Key ID from Step 4 (e.g. `ABC1234DEF`) |
| `APPLE_CONNECT_ISSUER_ID` | Issuer ID UUID from Step 4 |
| `APPLE_CONNECT_PRIVATE_KEY` | Full contents of the `.p8` file |

### How to encode each secret

**`APPLE_CERTIFICATE_BASE64`** — the entire `.p12` file base64-encoded, no line breaks:
```bash
# macOS
base64 -i ~/Desktop/distribution.p12 | pbcopy
# Linux / GitHub Actions runner
base64 -w 0 ~/Desktop/distribution.p12
```
Paste the result directly into the secret value field (no quotes, no newlines).

**`APPLE_CONNECT_PRIVATE_KEY`** — the raw contents of the `.p8` file, including the header/footer lines:
```bash
cat ~/Desktop/AuthKey_XXXXXXXXXX.p8
```
The value must look exactly like:
```
-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg...
-----END PRIVATE KEY-----
```

### Verify your secrets locally before adding them

Run these checks on your Mac **before** pasting anything into GitHub — they catch the most common mistakes:

```bash
# 1. Check the .p12 decodes to a real certificate (should show 1000+ bytes)
base64 -i ~/Desktop/distribution.p12 | base64 --decode | wc -c

# 2. Verify the .p12 password is correct (should print certificate info)
openssl pkcs12 -info -in ~/Desktop/distribution.p12 \
  -passin pass:YOUR_P12_PASSWORD -noout

# 3. Verify the .p8 key is a valid EC private key (should print "read EC key")
openssl ec -in ~/Desktop/AuthKey_XXXXXXXXXX.p8 -noout -text 2>&1 | head -3

# 4. Confirm Team ID format (exactly 10 uppercase alphanumeric chars)
echo "LFGMAA62R4" | grep -E '^[A-Z0-9]{10}$' && echo "OK" || echo "INVALID FORMAT"

# 5. Confirm Key ID format (exactly 10 uppercase alphanumeric chars)
echo "ABC1234DEF" | grep -E '^[A-Z0-9]{10}$' && echo "OK" || echo "INVALID FORMAT"

# 6. Confirm Issuer ID is a UUID
echo "12345678-1234-1234-1234-123456789012" | \
  grep -E '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' \
  && echo "OK" || echo "INVALID FORMAT"
```

---

## Step 7: Run the Workflow

1. Go to the **Actions** tab in your GitHub repository
2. Click **iOS TestFlight Deploy** in the left sidebar
3. Click **Run workflow** → **Run workflow**
4. The build takes **30–45 minutes** on the first run (cold build + Apple processing)
5. After the workflow completes, check **App Store Connect → TestFlight** — builds appear within 15–30 minutes of a successful upload

---

## Troubleshooting

### "FATAL: Secret 'APPLE_CERTIFICATE_BASE64' is not set or empty"

The workflow validates all 6 secrets before starting. Check which secret is named incorrectly:
- Secret names are **case-sensitive** and must match exactly
- Go to **Settings → Secrets and variables → Actions** and verify each name
- If a secret value is empty, delete it and re-add it

### "Decoded certificate is only N bytes"

The `APPLE_CERTIFICATE_BASE64` value is corrupt. Common causes:
- Line breaks were added when copying (use `base64 -w 0` on Linux or `base64 -i ... | tr -d '\n'`)
- You copied the wrong file (e.g. `.cer` instead of `.p12`)
- The base64 was double-encoded

Verify: `echo "$APPLE_CERTIFICATE_BASE64" | base64 --decode | wc -c` should return > 2000.

### "FATAL: xcodegen still not on PATH after install"

This is fixed in the current workflow — the Homebrew bin directory is now written to `$GITHUB_PATH` so all subsequent steps inherit it. If you see this, make sure your branch has the latest workflow changes (PR #40 or later).

### "Preflight — MISSING: App ID com.peptidesai.app"

The bundle ID has not been registered. Follow **Step 1c** for the main app, **1d** for widgets, or **1e** for the watch app.

### "Preflight — MISSING capability: APP_GROUPS"

The capability is enabled but the App Group isn't linked, or the capability wasn't saved. Fix:
1. Developer Portal → Identifiers → click the App ID
2. Under App Groups, click **Configure** (not just the checkbox)
3. Tick `group.com.peptidesai.app` → **Continue** → **Save**
4. Re-run the workflow

### "Preflight — MISSING capability: HEALTHKIT"

Open the App ID `com.peptidesai.app` → tick **HealthKit** → **Save**.

### "Preflight — MISSING capability: APPLE_ID_AUTH"

Open the App ID `com.peptidesai.app` → tick **Sign In with Apple** → **Save**.

### "Preflight — MISSING capability: ICLOUD"

Open the App ID `com.peptidesai.app` → tick **iCloud** → click **Configure** next to iCloud → tick **CloudKit (Include CloudKit support)** and `iCloud.com.peptidesai.app` → **Continue** → **Save**.

### Archive fails: "doesn't match the entitlements file's value for com.apple.security.application-groups"

The App Group capability is not linked to the App ID in the Developer Portal. The workflow's preflight verifies the capability is *enabled* but the ASC public API doesn't expose which specific groups are linked, so a mis-link is only caught at archive time. The error message names the offending profile (e.g. `com.peptidesai.app.watchkitapp.widgets`); fix that App ID specifically.

The watch widgets bundle (`com.peptidesai.app.watchkitapp.widgets`) is the most common offender here because Xcode auto-creates the App ID via `-allowProvisioningUpdates` if it's missing, but auto-creation never links the App Group — it has to be done by hand. Step 1f covers registering it ahead of time.

Fix:
1. Developer Portal → Identifiers → click the named App ID
2. App Groups → **Configure** → tick `group.com.peptidesai.app` → **Continue** → **Save**
3. Repeat for any other App ID listed in the error or whose dumped profile shows `(none)` for application-groups
4. Re-run the workflow

### Archive fails: "Entitlement com.apple.developer.icloud-containers not found and could not be included in profile"

The iCloud Container `iCloud.com.peptidesai.app` is missing or not linked to `com.peptidesai.app`. The preflight can verify the iCloud capability is enabled, but not container linkage.

Fix:
1. Developer Portal → Identifiers → iCloud Containers — verify `iCloud.com.peptidesai.app` exists (Step 1b). If not, register it.
2. Identifiers → click `com.peptidesai.app` → tick **iCloud** → click **Configure** → tick **CloudKit** and `iCloud.com.peptidesai.app` → **Continue** → **Save**
3. Re-run the workflow

### Archive fails: "No signing certificate 'iOS Distribution' found"

The certificate wasn't imported. Causes:
- `APPLE_CERTIFICATE_BASE64` is corrupt (see above)
- `APPLE_CERTIFICATE_PASSWORD` is wrong — verify it locally with `openssl pkcs12 -info -in distribution.p12 -passin pass:YOUR_PASSWORD -noout`
- The certificate is expired — check its expiry date in Keychain Access or Developer Portal → Certificates

### Upload fails: "authentication" / 401 / "invalid credentials"

- `APPLE_CONNECT_KEY_ID` or `APPLE_CONNECT_ISSUER_ID` is wrong — double-check against the App Store Connect API keys page
- `APPLE_CONNECT_PRIVATE_KEY` is missing the `-----BEGIN PRIVATE KEY-----` / `-----END PRIVATE KEY-----` header lines
- The API key was revoked — check App Store Connect → Users and Access → Integrations → App Store Connect API

### Upload succeeds but build not visible in TestFlight

- Processing takes 15–30 minutes on Apple's side
- Check **App Store Connect → TestFlight → your app** for processing status or compliance questions

### Build artifacts

Every workflow run (success or failure) uploads logs and IPA to **GitHub Actions → your run → Artifacts**:
- `xcodebuild-archive.log` — full archive output
- `xcodebuild-export.log` — full export output
- `upload.log` — upload output
- `*.ipa` — the signed IPA file

Download these when diagnosing failures instead of re-running the workflow blind.
