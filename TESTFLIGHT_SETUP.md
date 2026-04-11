# Peptides AI — TestFlight Setup Guide

## App Details
- **App Name:** Peptides AI
- **Bundle ID:** `com.peptidesai.app`
- **Platform:** iOS (iPhone only)

## Prerequisites
- Apple Developer Program membership ($99/year)
- GitHub repository with Actions enabled

---

## Step 1: Register App ID

1. Go to [Apple Developer Portal](https://developer.apple.com/account/resources/identifiers/list)
2. **Identifiers** → **+** → **App IDs** → **App**
3. Description: `Peptides AI`
4. Bundle ID: **Explicit** → `com.peptidesai.app`
5. No special capabilities needed initially
6. Click **Continue** → **Register**

## Step 2: Create App in App Store Connect

1. Go to [App Store Connect](https://appstoreconnect.apple.com)
2. **My Apps** → **+** → **New App**
3. Platform: **iOS**
4. Name: `Peptides AI`
5. Bundle ID: `com.peptidesai.app`
6. SKU: `peptidesai`
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

## Step 4: Create Provisioning Profile

1. Go to [Profiles](https://developer.apple.com/account/resources/profiles/list) → **+**
2. Select **App Store Connect** (under Distribution)
3. Select App ID: `com.peptidesai.app`
4. Select your distribution certificate
5. Name it (e.g., `Peptides AI App Store`) — **remember this exact name**
6. Download the `.mobileprovision` file

## Step 5: Create App-Specific Password

1. Go to [appleid.apple.com](https://appleid.apple.com)
2. **Sign-In and Security** → **App-Specific Passwords**
3. Click **+** → Label: `GitHub Actions`
4. Copy the generated password

## Step 6: Find Your Team ID

1. Go to [Apple Developer Membership](https://developer.apple.com/account#MembershipDetailsCard)
2. Your **Team ID** is the 10-character alphanumeric string

## Step 7: Add GitHub Secrets

Go to your repo → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

Add each of these:

| Secret Name | Value | How to Get It |
|---|---|---|
| `APPLE_CERTIFICATE_BASE64` | Base64-encoded .p12 | `base64 -i distribution.p12 \| pbcopy` (macOS) |
| `APPLE_CERTIFICATE_PASSWORD` | .p12 password | The password you set in Step 3 |
| `APPLE_PROVISIONING_PROFILE` | Base64-encoded .mobileprovision | `base64 -i profile.mobileprovision \| pbcopy` (macOS) |
| `APPLE_PROVISIONING_PROFILE_NAME` | Profile name | Exactly as typed in Step 4 (e.g., `Peptides AI App Store`) |
| `APPLE_TEAM_ID` | 10-char team ID | From Step 6 |
| `APPLE_ID` | Apple ID email | Your Apple Developer account email |
| `APPLE_APP_SPECIFIC_PASSWORD` | App-specific password | From Step 5 |

## Step 8: Run the Workflow

1. Go to **Actions** tab in GitHub
2. Click **iOS TestFlight Deploy** in the left sidebar
3. Click **Run workflow** → **Run workflow**
4. Wait 10-20 minutes for the build
5. Check **App Store Connect** → **TestFlight** for the new build

---

## Troubleshooting

**Build fails at "Select Xcode version"**
- Xcode 26 may not be installed on the GitHub runner yet. Try changing `xcode-version` to `latest-beta` in the workflow file.

**"No signing certificate" error**
- Verify `APPLE_CERTIFICATE_BASE64` is the full base64 output with no line breaks added manually.
- Verify `APPLE_CERTIFICATE_PASSWORD` matches what you set when creating the .p12.

**"No provisioning profile" error**
- Ensure `APPLE_PROVISIONING_PROFILE_NAME` matches the exact name in Apple Developer Portal.
- Ensure the provisioning profile uses the same distribution certificate.

**"App icon missing" error**
- App Store Connect requires a 1024x1024 app icon. Add one to `Peptide/Resources/Assets.xcassets/AppIcon.appiconset/` before deploying.

**Upload succeeds but build not visible in TestFlight**
- New builds can take 15-30 minutes to process on Apple's side.
- Check App Store Connect → TestFlight → your app for processing status.
