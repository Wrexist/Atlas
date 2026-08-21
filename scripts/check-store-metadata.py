#!/usr/bin/env python3
"""Hold the App Store listing to Guideline 3.1.2.

Build 1.2.0 (135) was rejected under 3.1.2 for offering auto-renewable
subscriptions "without a functional link to the Terms of Use (EULA) in the
app's metadata". Nothing in the binary was wrong — the paywall linked to
Apple's standard EULA all along. The App Description did not, and the
description *is* the metadata Apple means, because App Store Connect has no
Terms of Use field for the standard EULA.

That is a whole review cycle lost to a listing field, and the description is
edited far more often than the code it describes: any pass that trims copy
for a new feature can drop the two links again and nothing would notice
until the next rejection.

So the links are pinned here. Both URLs must be in the description, the
paywall, and the onboarding trial offer; every auto-renewable product's
price and period must be in the description; and the description must still
fit in 4 000 characters with the links present.

    python3 scripts/check-store-metadata.py
"""

from __future__ import annotations

import pathlib
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
METADATA = REPO / "APP_STORE_METADATA.md"
EULA = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
DESCRIPTION_LIMIT = 4000

# Every surface that offers the subscription has to carry both links.
PURCHASE_SURFACES = [
    "Peptide/Features/Profile/Components/PaywallView.swift",
    "Peptide/Features/Onboarding/Components/TrialOfferView.swift",
]


def section(md: str, heading_prefix: str) -> str:
    """The body of the `## <heading_prefix>...` section, up to the next `## `."""
    m = re.search(rf"^## {re.escape(heading_prefix)}.*?$(.*?)(?=^## )", md, re.M | re.S)
    if not m:
        raise SystemExit(f"could not find a '## {heading_prefix}' section in {METADATA.name}")
    return m.group(1)


def fenced_block(body: str) -> str:
    m = re.search(r"```\n(.*?)\n```", body, re.S)
    if not m:
        raise SystemExit("expected a fenced copy block in the section")
    return m.group(1)


def privacy_url(md: str) -> str:
    m = re.search(r"\| Privacy Policy URL \| `(\S+)` \|", md)
    if not m:
        raise SystemExit("no Privacy Policy URL row in the URLs table")
    return m.group(1)


def auto_renewable_products(md: str) -> list[tuple[str, str]]:
    """(display name, price) for each Auto-Renewable row in the IAP table."""
    rows = re.findall(
        r"^\| ([^|]+?) \| `[^`]+` \| Auto-Renewable \| ([^|]+?) \|", section(md, "Subscriptions"), re.M
    )
    return [(name.strip(), price.strip()) for name, price in rows]


def main() -> int:
    failures: list[str] = []

    def check(ok: bool, label: str, detail: str = "") -> None:
        print(f"  {'ok  ' if ok else 'FAIL'} {label}")
        if not ok:
            if detail:
                print(f"         {detail}")
            failures.append(label)

    md = METADATA.read_text()
    description = fenced_block(section(md, "Description"))
    privacy = privacy_url(md)

    print("App Store description")
    check(EULA in description,
          "Terms of Use (EULA) link present",
          f"the description must contain {EULA} as plain text — "
          "Guideline 3.1.2 and the reason 1.2.0 (135) was rejected")
    check(privacy in description,
          "Privacy Policy link present",
          f"the description must contain {privacy}")
    check(len(description) <= DESCRIPTION_LIMIT,
          f"description fits the {DESCRIPTION_LIMIT}-character limit",
          f"it is {len(description)} characters — trim copy, never the links")

    stated = re.search(r"\*\((\d[\d\s ]*) / 4[\s ]?000", md)
    if stated:
        claimed = int(re.sub(r"\D", "", stated.group(1)))
        check(claimed == len(description),
              "stated character count matches the description",
              f"the doc says {claimed}, the block is {len(description)}")

    products = auto_renewable_products(md)
    check(bool(products), "auto-renewable products found in the IAP table")
    for name, price in products:
        amount = re.search(r"\$[\d.]+", price)
        check(bool(amount) and amount.group(0) in description,
              f"{name}: price {price} disclosed in the description",
              "3.1.2 wants title, length, and price per period in the description")

    check(re.search(r"renews (monthly|yearly)", description) is not None,
          "renewal period disclosed in the description")

    print("\nIn-app purchase surfaces")
    for rel in PURCHASE_SURFACES:
        source = (REPO / rel).read_text()
        name = rel.split("/")[-1]
        check(EULA in source, f"{name} links to the Terms of Use (EULA)")
        check(privacy in source, f"{name} links to the Privacy Policy")

    print("\nMarketing site")
    terms = REPO / "docs" / "terms.html"
    check(terms.exists() and EULA in terms.read_text(),
          "docs/terms.html exists and points at the Apple standard EULA")

    if failures:
        print(f"\n{len(failures)} App Store metadata requirement(s) unmet")
        return 1
    print("\nApp Store metadata satisfies Guideline 3.1.2")
    return 0


if __name__ == "__main__":
    sys.exit(main())
