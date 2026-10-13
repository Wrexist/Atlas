#!/usr/bin/env python3
"""Push the store listing in this repo to App Store Connect.

APP_STORE_METADATA.md and marketing/app-store/ are the source of truth for
the listing; this copies them into App Store Connect for one version:

- creates the App Store version if it doesn't exist yet,
- sets the en-US description and What's New,
- fills every Apple Watch screenshot slot there's a render for, replacing
  what's there unless it already matches,
- sets the en-US description of each subscription and in-app purchase that
  isn't live (a live one is reported, since only the web UI can change it),
- attaches the newest processed build of that version, if there is one.

It never submits for review. Without --apply it only reads App Store
Connect and prints what it would change.

    ASC_KEY_ID=… ASC_ISSUER_ID=… ASC_KEY_P8="$(cat key.p8)" \\
        python3 scripts/asc_store_sync.py --version 1.4.0 [--apply]

    python3 scripts/asc_store_sync.py --version 1.4.0 --offline
        parses the repo and prints the inputs without touching the network.
"""
from __future__ import annotations

import argparse
import hashlib
import os
import re
import sys
import time
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
METADATA = REPO / "APP_STORE_METADATA.md"
SHOTS = REPO / "marketing" / "app-store"
API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.peptidesai.app"
LOCALE = "en-US"
SCREENSHOTS_PER_SET = 10
PROCESSING_TIMEOUT = 300  # seconds to wait for Apple to process new screenshots

# Versions in these states accept metadata edits.
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED",
            "METADATA_REJECTED", "INVALID_BINARY"}

# Watch screenshot slot → folder rendered at that slot's size.
WATCH_SLOTS = {
    "APP_WATCH_ULTRA": "screenshots-watch",          # 410 × 502
    "APP_WATCH_SERIES_10": "screenshots-watch-s10",  # 416 × 496
    "APP_WATCH_SERIES_7": "screenshots-watch-s9",    # 396 × 484
    "APP_WATCH_SERIES_4": "screenshots-watch-s6",    # 368 × 448
}

# Localizations of a product that is on sale can't be edited through the API.
LIVE_LOCALIZATION_STATES = {"ACTIVE", "APPROVED", "WAITING_FOR_REVIEW", "IN_REVIEW"}

PRODUCTS = {  # product ID → display name in the "Localization copy" section
    "com.peptidesai.app.pro.monthly": "Atlas Pro Monthly",
    "com.peptidesai.app.pro.annual": "Atlas Pro Annual",
    "com.peptidesai.app.pro.lifetime": "Atlas Pro Lifetime",
}
IAP_DESCRIPTION_LIMIT = 45


# MARK: - Repo inputs

def section(md: str, heading: str) -> str:
    m = re.search(rf"^## {re.escape(heading)}.*?$(.*?)(?=^## )", md, re.M | re.S)
    if not m:
        sys.exit(f"no '## {heading}' section in {METADATA.name}")
    return m.group(1)


def fenced(body: str) -> str:
    m = re.search(r"```[a-z]*\n(.*?)```", body, re.S)
    if not m:
        sys.exit("section has no fenced block")
    return m.group(1).rstrip("\n")


def product_descriptions(md: str) -> dict[str, str]:
    copy = section(md, "Subscriptions")
    found = {}
    for product_id, name in PRODUCTS.items():
        m = re.search(rf"\*\*{re.escape(name)}\*\*.*?- Description: `([^`]+)`", copy, re.S)
        if not m:
            sys.exit(f"no Description for {name} under Localization copy")
        text = m.group(1)
        if len(text) > IAP_DESCRIPTION_LIMIT:
            sys.exit(f"{name} description is {len(text)} characters; the limit is {IAP_DESCRIPTION_LIMIT}")
        found[product_id] = text
    return found


def watch_shots(slot: str) -> list[Path]:
    files = sorted((SHOTS / WATCH_SLOTS[slot]).glob("*.png"))
    if not files:
        sys.exit(f"no screenshots in {WATCH_SLOTS[slot]}/ (run `node render.mjs --watch`)")
    return files


# MARK: - App Store Connect client

class ASC:
    def __init__(self, apply: bool):
        import jwt  # PyJWT
        import requests
        self.apply = apply
        self.http = requests.Session()
        key_id, issuer, key = (os.environ.get(k) for k in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_P8"))
        if not (key_id and issuer and key):
            sys.exit("ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8 must be set")
        now = int(time.time())
        token = jwt.encode(
            {"iss": issuer, "iat": now, "exp": now + 19 * 60, "aud": "appstoreconnect-v1"},
            key.replace("\\n", "\n"), algorithm="ES256", headers={"kid": key_id, "typ": "JWT"},
        )
        self.http.headers["Authorization"] = f"Bearer {token}"

    def call(self, method: str, path: str, **kw):
        r = self.http.request(method, path if path.startswith("http") else API + path, timeout=60, **kw)
        if r.status_code >= 400:
            sys.exit(f"{method} {path} → {r.status_code}\n{r.text[:2000]}")
        return r.json() if r.content else {}

    def get(self, path: str, **params):
        return self.call("GET", path, params=params)

    def all(self, path: str, **params) -> list[dict]:
        out, page = [], self.get(path, **params)
        while True:
            out += page["data"]
            nxt = page.get("links", {}).get("next")
            if not nxt:
                return out
            page = self.call("GET", nxt)

    def write(self, method: str, path: str, body: dict | None, summary: str):
        """Perform a write, or only describe it on a dry run."""
        print(f"  {'→' if self.apply else '·'} {summary}")
        if self.apply:
            return self.call(method, path, json=body) if body is not None else self.call(method, path)
        return None


# MARK: - Steps

def find_version(asc: ASC, app_id: str, version: str) -> dict | None:
    versions = asc.all(f"/v1/apps/{app_id}/appStoreVersions", **{"filter[platform]": "IOS", "limit": 50})
    print("App Store versions:")
    for v in versions[:6]:
        print(f"  {v['attributes']['versionString']:>8}  {v['attributes']['appStoreState']}")
    return next((v for v in versions if v["attributes"]["versionString"] == version), None)


def ensure_version(asc: ASC, app_id: str, version: str) -> dict | None:
    existing = find_version(asc, app_id, version)
    if existing:
        state = existing["attributes"]["appStoreState"]
        if state not in EDITABLE:
            sys.exit(f"{version} is {state}; its metadata can't be edited now")
        print(f"\n{version} exists ({state}).")
        return existing
    print(f"\n{version} does not exist yet.")
    created = asc.write("POST", "/v1/appStoreVersions", {"data": {
        "type": "appStoreVersions",
        "attributes": {"platform": "IOS", "versionString": version},
        "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
    }}, f"create App Store version {version} (copies the previous version's listing)")
    return created["data"] if created else None


def sync_text(asc: ASC, version: dict, description: str, whats_new: str) -> str | None:
    locs = asc.all(f"/v1/appStoreVersions/{version['id']}/appStoreVersionLocalizations")
    loc = next((l for l in locs if l["attributes"]["locale"] == LOCALE), None)
    if not loc:
        sys.exit(f"{version['attributes']['versionString']} has no {LOCALE} localization")
    attrs, changes = loc["attributes"], {}
    if (attrs.get("description") or "").strip() != description.strip():
        changes["description"] = description
    if (attrs.get("whatsNew") or "").strip() != whats_new.strip():
        changes["whatsNew"] = whats_new
    print("\nListing text:")
    if changes:
        asc.write("PATCH", f"/v1/appStoreVersionLocalizations/{loc['id']}", {"data": {
            "type": "appStoreVersionLocalizations", "id": loc["id"], "attributes": changes,
        }}, f"set {', '.join(changes)} ({', '.join(f'{len(v)} chars' for v in changes.values())})")
    else:
        print("  description and What's New already match")
    return loc["id"]


def upload_screenshot(asc: ASC, set_id: str, path: Path) -> str:
    import requests
    data = path.read_bytes()
    reserved = asc.call("POST", "/v1/appScreenshots", json={"data": {
        "type": "appScreenshots",
        "attributes": {"fileName": path.name, "fileSize": len(data)},
        "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}},
    }})["data"]
    for op in reserved["attributes"]["uploadOperations"]:
        headers = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        chunk = data[op["offset"]:op["offset"] + op["length"]]
        # The upload URLs are pre-signed: Apple rejects a request that also carries the JWT,
        # so this goes through a bare request rather than the authenticated session.
        r = requests.request(op["method"], op["url"], data=chunk, headers=headers, timeout=120)
        if r.status_code >= 400:
            sys.exit(f"upload of {path.name} failed: {r.status_code} {r.text[:500]}")
    asc.call("PATCH", f"/v1/appScreenshots/{reserved['id']}", json={"data": {
        "type": "appScreenshots", "id": reserved["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()},
    }})
    return reserved["id"]


def await_processing(asc: ASC, shot_ids: list[str]) -> list[str]:
    """Wait for Apple to process the uploads; returns the ids that failed."""
    pending, failed = set(shot_ids), []
    deadline = time.time() + PROCESSING_TIMEOUT
    while pending and time.time() < deadline:
        time.sleep(5)
        for shot_id in sorted(pending):
            attrs = asc.get(f"/v1/appScreenshots/{shot_id}")["data"]["attributes"]
            state = (attrs.get("assetDeliveryState") or {}).get("state")
            if state == "COMPLETE":
                pending.discard(shot_id)
            elif state == "FAILED":
                errors = (attrs.get("assetDeliveryState") or {}).get("errors") or []
                print(f"  ! {attrs.get('fileName', shot_id)} failed processing: "
                      f"{'; '.join(e.get('description', '') for e in errors) or 'no reason given'}")
                pending.discard(shot_id)
                failed.append(shot_id)
    return failed + sorted(pending)


def replace_screenshots(asc: ASC, slot: str, set_id: str, old: list[dict], files: list[Path]) -> None:
    """Upload the new set before deleting the old one, so a failed upload never empties the listing."""
    # A set holds at most SCREENSHOTS_PER_SET, so make just enough room for the new uploads first.
    room = max(0, len(old) + len(files) - SCREENSHOTS_PER_SET)
    for shot in old[:room]:
        asc.call("DELETE", f"/v1/appScreenshots/{shot['id']}")
    new_ids = [upload_screenshot(asc, set_id, f) for f in files]
    failed = await_processing(asc, new_ids)
    if failed:
        for shot_id in new_ids:
            asc.call("DELETE", f"/v1/appScreenshots/{shot_id}")
        sys.exit(f"{slot}: {len(failed)} of {len(new_ids)} new screenshots did not process; "
                 f"removed the new uploads and kept the {len(old) - room} existing ones")
    for shot in old[room:]:
        asc.call("DELETE", f"/v1/appScreenshots/{shot['id']}")
    print(f"  {slot}: {len(new_ids)} new screenshots processed, old ones removed")


def sync_watch_screenshots(asc: ASC, loc_id: str | None) -> None:
    print("\nApple Watch screenshots:")
    if not loc_id:
        for slot, folder in WATCH_SLOTS.items():
            print(f"  · upload {len(watch_shots(slot))} to {slot} from {folder}/ once the version exists")
        return
    sets = asc.all(f"/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")
    watch_sets = {s["attributes"]["screenshotDisplayType"]: s for s in sets
                  if s["attributes"]["screenshotDisplayType"].startswith("APP_WATCH")}
    unknown = set(watch_sets) - set(WATCH_SLOTS)
    if unknown:
        print(f"  ! leaving {', '.join(sorted(unknown))} alone: no render at that size")
    for slot in WATCH_SLOTS:
        files = watch_shots(slot)
        if slot in watch_sets:
            old = asc.all(f"/v1/appScreenshotSets/{watch_sets[slot]['id']}/appScreenshots")
            if sorted(o["attributes"].get("sourceFileChecksum") or "" for o in old) == \
                    sorted(hashlib.md5(f.read_bytes()).hexdigest() for f in files):
                print(f"  {slot}: already matches {WATCH_SLOTS[slot]}/")
                continue
            print(f"  {slot}: {len(old)} on the listing, replacing with {len(files)} from {WATCH_SLOTS[slot]}/")
            print(f"  {'→' if asc.apply else '·'} upload {', '.join(f.name for f in files)}, "
                  f"then delete the old {len(old)} once Apple has processed them")
            if asc.apply:
                replace_screenshots(asc, slot, watch_sets[slot]["id"], old, files)
            continue
        print(f"  {slot}: none on the listing, adding {len(files)} from {WATCH_SLOTS[slot]}/")
        created = asc.write("POST", "/v1/appScreenshotSets", {"data": {
            "type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": slot},
            "relationships": {"appStoreVersionLocalization": {
                "data": {"type": "appStoreVersionLocalizations", "id": loc_id}}},
        }}, f"create the {slot} screenshot set")
        print(f"  {'→' if asc.apply else '·'} upload {', '.join(f.name for f in files)}")
        if created:
            new_ids = [upload_screenshot(asc, created["data"]["id"], f) for f in files]
            if await_processing(asc, new_ids):
                sys.exit(f"{slot}: some new screenshots did not process; check App Store Connect")


def set_localized_description(asc: ASC, locs: list[dict], resource: str, name: str, text: str) -> None:
    loc = next((l for l in locs if l["attributes"]["locale"] == LOCALE), None)
    if not loc:
        print(f"  ! {name}: no {LOCALE} localization, skipped")
        return
    current = loc["attributes"].get("description") or ""
    if current == text:
        print(f"  {name}: already “{text}”")
        return
    state = loc["attributes"].get("state")
    if state in LIVE_LOCALIZATION_STATES:
        print(f"  ! {name} is {state}, so the API can't change it: edit “{current}” → “{text}” "
              f"in App Store Connect (it goes to review with the next version)")
        return
    asc.write("PATCH", f"/v1/{resource}/{loc['id']}", {"data": {
        "type": resource, "id": loc["id"], "attributes": {"description": text},
    }}, f"{name}: “{current}” → “{text}”")


def sync_products(asc: ASC, app_id: str, descriptions: dict[str, str]) -> None:
    print("\nIn-app purchase descriptions:")
    seen = set()
    for group in asc.all(f"/v1/apps/{app_id}/subscriptionGroups"):
        for sub in asc.all(f"/v1/subscriptionGroups/{group['id']}/subscriptions"):
            pid = sub["attributes"]["productId"]
            if pid in descriptions:
                seen.add(pid)
                locs = asc.all(f"/v1/subscriptions/{sub['id']}/subscriptionLocalizations")
                set_localized_description(asc, locs, "subscriptionLocalizations", PRODUCTS[pid], descriptions[pid])
    for iap in asc.all(f"/v1/apps/{app_id}/inAppPurchasesV2"):
        pid = iap["attributes"]["productId"]
        if pid in descriptions:
            seen.add(pid)
            locs = asc.all(f"/v2/inAppPurchases/{iap['id']}/inAppPurchaseLocalizations")
            set_localized_description(asc, locs, "inAppPurchaseLocalizations", PRODUCTS[pid], descriptions[pid])
    for pid in sorted(set(descriptions) - seen):
        print(f"  ! {pid} not found in App Store Connect")


def attach_build(asc: ASC, app_id: str, version: dict | None, version_string: str) -> None:
    print("\nBuild:")
    builds = asc.get("/v1/builds", **{
        "filter[app]": app_id, "filter[preReleaseVersion.version]": version_string,
        "filter[processingState]": "VALID", "sort": "-uploadedDate", "limit": 1,
    })["data"]
    if not builds:
        print(f"  no processed {version_string} build yet; attach one when TestFlight finishes processing")
        return
    build = builds[0]
    if not version:
        print(f"  · attach build {build['attributes']['version']} once the version exists")
        return
    current = asc.get(f"/v1/appStoreVersions/{version['id']}/relationships/build").get("data")
    if current and current["id"] == build["id"]:
        print(f"  build {build['attributes']['version']} already attached")
        return
    asc.write("PATCH", f"/v1/appStoreVersions/{version['id']}/relationships/build",
              {"data": {"type": "builds", "id": build["id"]}},
              f"attach build {build['attributes']['version']} ({version_string})")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--version", required=True, help="App Store version, e.g. 1.4.0")
    ap.add_argument("--apply", action="store_true", help="write to App Store Connect (default: dry run)")
    ap.add_argument("--offline", action="store_true", help="only parse the repo inputs")
    args = ap.parse_args()

    md = METADATA.read_text()
    description = fenced(section(md, "Description"))
    whats_new = fenced(section(md, '"What\'s New"'))
    products = product_descriptions(md)

    print(f"Repo inputs for {args.version}:")
    print(f"  description {len(description)} chars, What's New {len(whats_new)} chars")
    for pid, text in products.items():
        print(f"  {PRODUCTS[pid]}: “{text}” ({len(text)})")
    for slot, folder in WATCH_SLOTS.items():
        print(f"  {slot}: {len(watch_shots(slot))} screenshots in {folder}/")
    if args.offline:
        return 0

    asc = ASC(apply=args.apply)
    print(f"\n{'APPLYING' if args.apply else 'DRY RUN (nothing is written)'}\n")
    apps = asc.get("/v1/apps", **{"filter[bundleId]": BUNDLE_ID})["data"]
    if not apps:
        sys.exit(f"no app with bundle ID {BUNDLE_ID}")
    app_id = apps[0]["id"]

    version = ensure_version(asc, app_id, args.version)
    loc_id = sync_text(asc, version, description, whats_new) if version else None
    if not version:
        print("\nListing text:\n  · set description and What's New once the version exists")
    sync_watch_screenshots(asc, loc_id)
    sync_products(asc, app_id, products)
    attach_build(asc, app_id, version, args.version)
    print("\nNot submitted for review." + ("" if args.apply else " Re-run with --apply to write these changes."))
    return 0


if __name__ == "__main__":
    sys.exit(main())
