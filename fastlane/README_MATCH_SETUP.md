## iOS Signing + TestFlight (Fastlane Match)

This repo is configured to upload builds to TestFlight using **Fastlane Match**.

### Why this exists

Managing `*.p12` + base64 + keychain imports per repo is brittle. Match centralizes
certificates/profiles into one encrypted signing repo and makes CI deterministic.

### Required GitHub Secrets (repo)

- **`ASC_KEY_ID`**: App Store Connect API key id (10 chars)
- **`ASC_ISSUER_ID`**: issuer UUID (36 chars)
- **`ASC_KEY_P8`**: contents of the `.p8` private key (PEM)
- **`MATCH_PASSWORD`**: encryption password used by Match
- **`MATCH_GIT_URL`**: SSH URL for the Match signing repo, e.g. `git@github.com:Wrexist/ios-signing-match.git`
- **`MATCH_GIT_BASIC_AUTH`** (optional): base64 of `username:token` for HTTPS Match repo access. Prefer SSH if possible.

### One-time bootstrap (per app)

Run these **locally** (Windows is fine) after you’ve created the Match signing repo.

1. Install Ruby + Bundler, then:

```bash
bundle install
```

2. Export secrets as env vars and run Match in write mode:

```bash
export ASC_KEY_ID="…"
export ASC_ISSUER_ID="…"
export ASC_KEY_P8="$(cat AuthKey.p8)"
export MATCH_PASSWORD="…"
export MATCH_GIT_URL="git@github.com:Wrexist/ios-signing-match.git"

bundle exec fastlane match appstore --readonly false
```

This creates (or updates) **App Store** provisioning profiles and stores them
encrypted in the signing repo.

After bootstrap, CI uses `match --readonly` and will not mutate Apple state.

