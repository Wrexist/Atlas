# PeptideX — TestFlight Setup Guide

## App Details
- **App Name:** PeptideX
- **Bundle ID:** `com.peptidesai.app`
- **Platform:** iOS (iPhone only)

## Prerequisites
- Apple Developer Program membership ($99/year)
- GitHub repository with Actions enabled

---

## Step 1: Register App IDs (capabilities auto-configure)

PeptideX ships two bundles (main app + widget extension) that share data via an
App Group. The workflow auto-configures the App Group and required capabilities
via the App Store Connect API on every run — you only need to make sure the two
**App IDs** exist in the Developer Portal before the first run.

### 1a. Register the main App ID

1. Go to [Identifiers](https://developer.apple.com/account/resources/identifiers/list)
2. Click **+** → **App IDs** → **App** → **Continue**
3. Description: `PeptideX`
4. Bundle ID: **Explicit** → `com.peptidesai.app`
5. Leave capabilities unchecked (the workflow enables them automatically)
6. Click **Continue** → **Register**

### 1b. Register the widget App ID

1. Identifiers → **+** → **App IDs** → **App** → **Continue**
2. Description: `PeptideX Widgets`
3. Bundle ID: **Explicit** → `com.peptidesai.app.widgets`
4. Leave capabilities unchecked
5. Click **Continue** → **Register**

> **What the workflow auto-configures on every run** (via ASC API, using the API
> key from Step 4):
> - Creates App Group `group.com.peptidesai.app` if it doesn't exist
> - On `com.peptidesai.app`: enables App Groups (linked to the group), HealthKit, Sign In with Apple
> - On `com.peptidesai.app.widgets`: enables App Groups (linked to the group)
>
> The API key must have **App Manager** role or higher.

## Step 2: Create App in App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. **My Apps** → **+** → **New App**
3. Platform: **iOS**
4. Name: `PeptideX`
5. Bundle ID: `com.peptidesai.app`
6. SKU: `peptidex`
7. Click **Create**

## Step 3: Create Distribution Certificate

If you already have an Apple Distribution certificate, skip to exporting it as .p12.

**Create a new one:**
```bash
# Generate a Certificate Signing Request (CSR)
openssl req -nodes -newkey rsa:2048 -keyout distribution.key -out distribution.csr \
  -subj "/emailAddress=YOUR_EMAIL/CN=YOUR_NAME/C=US"
```

1. Go to [Certificates](https://developer.apple.com/account/resources/certificates/list) → **+**
2. Select **Apple Distribution**
3. Upload `distribution.csr`
4. Download the `.cer` file

**Convert to .p12:**
```bash
# Convert .cer to .pem
openssl x509 -in distribution.cer -inform DER -out distribution.pem -outform PEM

# Create .p12 (you'll be prompted for a password — remember it!)
openssl pkcs12 -export -inkey distribution.key -in distribution.pem -out distribution.p12
```

## Step 4: Create App Store Connect API Key

1. Go to [App Store Connect](https://appstoreconnect.apple.com) → **Users and Access** → **Integrations** → **App Store Connect API**
2. Click **+** to generate a new key
3. Name: `GitHub Actions`
4. Access: **App Manager** (minimum role needed for TestFlight uploads)
5. Click **Generate**
6. **Download the `.p8` file immediately** — it can only be downloaded once
7. Note the **Key ID** (shown in the keys list)
8. Note the **Issuer ID** (shown at the top of the keys page)

## Step 5: Find Your Team ID

1. Go to [Apple Developer Membership](https://developer.apple.com/account#MembershipDetailsCard)
2. Your **Team ID** is the 10-character alphanumeric string

## Step 6: Add GitHub Secrets

Go to your repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Add each of these:

| Secret Name | Value | How to Get It |
|---|---|---|
| `APPLE_CERTIFICATE_BASE64` | Base64-encoded .p12 | `base64 -i distribution.p12 \| pbcopy` (macOS) |
| `APPLE_CERTIFICATE_PASSWORD` | .p12 password | The password you set in Step 3 |
| `APPLE_TEAM_ID` | 10-char team ID | From Step 5 |
| `APPLE_CONNECT_KEY_ID` | API Key ID | From Step 4 (shown in the keys list) |
| `APPLE_CONNECT_ISSUER_ID` | Issuer ID | From Step 4 (shown at top of keys page) |
| `APPLE_CONNECT_PRIVATE_KEY` | Contents of .p8 file | `cat AuthKey_XXXXXXXXXX.p8 \| pbcopy` (macOS) |

> Note: Provisioning profiles are created/updated automatically at build time by Xcode
> using the App Store Connect API key (`-allowProvisioningUpdates`). You do **not**
> need to manually create or upload a `.mobileprovision` file. The API key must have
> **App Manager** access so Xcode can register capabilities (App Groups, Sign In with
> Apple, HealthKit) and generate profiles for both the app and widget extension.

## Step 7: Run the Workflow

1. Go to **Actions** tab in GitHub
2. Click **iOS TestFlight Deploy** in the left sidebar
3. Click **Run workflow** → **Run workflow**
4. Wait 10-20 minutes for the build
5. Check **App Store Connect** → **TestFlight** for the new build

---

## Troubleshooting

**Workflow fails at "Validate required secrets"**
- The workflow checks all 7 secrets are configured before starting the build. Check the error message to see which secret is missing, then add it in Settings → Secrets.

**"No signing certificate" error**
- Verify `APPLE_CERTIFICATE_BASE64` is the full base64 output with no line breaks added manually.
- Verify `APPLE_CERTIFICATE_PASSWORD` matches what you set when creating the .p12.

**"Preflight & auto-configure" fails with "App IDs not registered"**
- One or both bundle IDs (`com.peptidesai.app`, `com.peptidesai.app.widgets`) aren't
  registered. Go back to **Step 1** and register them (leave capabilities unchecked —
  the workflow enables them).

**"Preflight & auto-configure" fails with an HTTP 403 / permissions error**
- The App Store Connect API key needs **App Manager** role or higher to create
  App Groups and manage capabilities. Generate a new key with App Manager role in
  App Store Connect → Users and Access → Integrations → App Store Connect API.

**Archive fails with "doesn't match the entitlements file's value" or "doesn't include the <X> capability"**
- The auto-configure step should prevent this. If it happens anyway, the API key
  likely can't write; regenerate with App Manager role and re-run the workflow.

**"App icon missing" error**
- The workflow auto-generates a placeholder icon. For production, add a real 1024x1024 PNG to `Peptide/Resources/Assets.xcassets/AppIcon.appiconset/`.

**Upload fails with "authentication" error**
- Verify `APPLE_CONNECT_KEY_ID`, `APPLE_CONNECT_ISSUER_ID`, and `APPLE_CONNECT_PRIVATE_KEY` are correct.
- The `.p8` key file contents should include the `-----BEGIN PRIVATE KEY-----` and `-----END PRIVATE KEY-----` lines.
- Ensure the API key has "App Manager" or higher access in App Store Connect.

**Upload succeeds but build not visible in TestFlight**
- New builds can take 15-30 minutes to process on Apple's side.
- Check App Store Connect → TestFlight → your app for processing status.

**Debugging failed builds**
- Download the build artifacts from the workflow run (IPA + build logs are saved automatically).
- Check `xcodebuild-archive.log` and `xcodebuild-export.log` for detailed error output.
