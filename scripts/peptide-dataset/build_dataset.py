#!/usr/bin/env python3
"""
PeptideX Dataset Builder
========================
Builds a comprehensive peptide dataset for the PeptideX iOS app.

Pipeline per peptide:
  1. Claude API (claude-opus-4-6) -> structured extraction matching Peptide.swift model
  2. PubMed E-utilities -> real citations (title, journal, year, PMID, DOI)
  3. PubChem REST -> molecular data (CID, MW, formula, canonical SMILES)
  4. Auto-classify into one of 6 app categories
  5. Merge + validate -> write to peptides.json (bundle-ready)

Usage:
  export ANTHROPIC_API_KEY=sk-ant-...
  python3 build_dataset.py              # full build
  python3 build_dataset.py --limit 5    # test run on 5 peptides
  python3 build_dataset.py --resume     # resume from peptides.partial.json

Output:
  peptides.json              - final dataset (drop into app bundle)
  peptides.partial.json      - checkpoint after every peptide (resumable)
  build.log                  - detailed run log
"""

import argparse
import json
import logging
import os
import sys
import time
import urllib.parse
from pathlib import Path
from typing import Any

import anthropic  # pip install anthropic
import requests   # pip install requests

from peptide_list import PEPTIDES_DEDUPED

# ─── Config ──────────────────────────────────────────────────────────────────

OUT_DIR = Path(__file__).parent
FINAL_PATH = OUT_DIR / "peptides.json"
PARTIAL_PATH = OUT_DIR / "peptides.partial.json"
LOG_PATH = OUT_DIR / "build.log"

CLAUDE_MODEL = "claude-opus-4-6"
CLAUDE_MAX_TOKENS = 2500

PUBMED_BASE = "https://eutils.ncbi.nlm.nih.gov/entrez/eutils"
PUBCHEM_BASE = "https://pubchem.ncbi.nlm.nih.gov/rest/pug"

# NCBI asks for <= 3 req/sec without API key. Be polite.
NCBI_DELAY = 0.4
PUBMED_MAX_CITATIONS = 5

CATEGORIES = ["growth", "recovery", "cognitive", "antiAging", "immune", "metabolic"]

# ─── Logging ─────────────────────────────────────────────────────────────────

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)-7s %(message)s",
    handlers=[
        logging.FileHandler(LOG_PATH, mode="a"),
        logging.StreamHandler(sys.stdout),
    ],
)
log = logging.getLogger("peptidex")


# ─── Claude extraction ───────────────────────────────────────────────────────

EXTRACTION_SYSTEM = """You are a scientific research assistant building an educational peptide database for a mobile app called PeptideX.

Rules:
1. Output ONLY valid JSON, no markdown fences, no preamble, no commentary.
2. If a fact is uncertain, use the string "Unknown" rather than inventing data.
3. Dosages are for EDUCATIONAL reference only — use ranges commonly cited in research literature, not prescriptions.
4. Keep descriptions factual and neutral. Do not make therapeutic claims.
5. Never recommend usage — describe what research has investigated.
6. For unapproved research peptides, note their regulatory status honestly.
"""

EXTRACTION_USER_TEMPLATE = """Extract structured data for this peptide for our educational database.

Peptide: {name}
Common abbreviation hint: {abbreviation}

Return a JSON object with EXACTLY these fields:

{{
  "name": "Full scientific name",
  "abbreviation": "Short common name (max 15 chars)",
  "category": "ONE OF: growth | recovery | cognitive | antiAging | immune | metabolic",
  "description": "2-4 sentence factual overview. What it is, where it comes from, what research investigates.",
  "benefits": ["Array", "of", "3-6", "research-investigated", "effects"],
  "dosage_range": "Typical range cited in research, e.g. '250-500 mcg' or 'Unknown'",
  "frequency": "Typical cadence, e.g. '1-2x daily' or 'Unknown'",
  "half_life": "Half-life with units or 'Unknown'",
  "admin_route": "Subcutaneous | Intramuscular | Intranasal | Oral | Topical | Sublingual | Intravenous | Unknown",
  "mechanism": "1-2 sentences on mechanism of action",
  "contraindications": ["Array", "of", "known", "contraindications", "or", "['Unknown']"],
  "side_effects": ["Array", "of", "reported", "side", "effects", "or", "['Unknown']"],
  "common_stacks": ["Other peptides", "it is commonly", "researched alongside"],
  "regulatory_status": "e.g. 'FDA-approved for X', 'Research chemical, not approved for human use', 'Cosmetic ingredient'",
  "sf_symbol": "Most-fitting SF Symbol name, e.g. 'cross.vial.fill', 'brain.head.profile.fill', 'flame.fill'"
}}

Category guide:
- growth: muscle, tissue growth, GH-axis, IGF, healing factors
- recovery: wound healing, tendon/joint repair, anti-inflammatory, sleep
- cognitive: nootropic, neuroprotective, focus, memory, mood
- antiAging: longevity, telomere, mitochondrial, senolytic
- immune: antimicrobial, immunomodulating, antiviral, T-cell
- metabolic: fat loss, glucose, GLP-1, thermogenesis, appetite

Return ONLY the JSON object."""


def call_claude(client: anthropic.Anthropic, name: str, abbreviation: str) -> dict[str, Any]:
    """Extract structured peptide data via Claude API."""
    msg = client.messages.create(
        model=CLAUDE_MODEL,
        max_tokens=CLAUDE_MAX_TOKENS,
        system=EXTRACTION_SYSTEM,
        messages=[
            {
                "role": "user",
                "content": EXTRACTION_USER_TEMPLATE.format(
                    name=name, abbreviation=abbreviation
                ),
            }
        ],
    )
    text = msg.content[0].text.strip()

    # Defensive: strip markdown fences if the model slips
    if text.startswith("```"):
        lines = text.split("\n")
        text = "\n".join(lines[1:-1] if lines[-1].startswith("```") else lines[1:])

    try:
        data = json.loads(text)
    except json.JSONDecodeError as e:
        log.error("JSON parse failed for %s: %s", name, e)
        log.error("Raw text: %s", text[:500])
        raise

    # Validate category
    if data.get("category") not in CATEGORIES:
        log.warning("Bad category '%s' for %s, defaulting to 'recovery'",
                    data.get("category"), name)
        data["category"] = "recovery"

    return data


# ─── PubMed enrichment ───────────────────────────────────────────────────────

def fetch_pubmed_citations(query: str, max_results: int = PUBMED_MAX_CITATIONS) -> list[dict[str, Any]]:
    """Get real PubMed citations via E-utilities."""
    citations: list[dict[str, Any]] = []
    try:
        # Step 1: esearch for PMIDs, recent first
        search_url = f"{PUBMED_BASE}/esearch.fcgi"
        params = {
            "db": "pubmed",
            "term": query,
            "retmax": max_results,
            "retmode": "json",
            "sort": "pub_date",
        }
        r = requests.get(search_url, params=params, timeout=15)
        r.raise_for_status()
        pmids = r.json().get("esearchresult", {}).get("idlist", [])
        if not pmids:
            return []

        time.sleep(NCBI_DELAY)

        # Step 2: esummary for metadata
        summary_url = f"{PUBMED_BASE}/esummary.fcgi"
        params = {"db": "pubmed", "id": ",".join(pmids), "retmode": "json"}
        r = requests.get(summary_url, params=params, timeout=15)
        r.raise_for_status()
        result = r.json().get("result", {})

        for pmid in pmids:
            item = result.get(pmid)
            if not item:
                continue
            # Extract DOI if present
            doi = ""
            for article_id in item.get("articleids", []):
                if article_id.get("idtype") == "doi":
                    doi = article_id.get("value", "")
                    break

            # Year from pubdate like "2023 May 15"
            pubdate = item.get("pubdate", "")
            year = 0
            for tok in pubdate.split():
                if tok.isdigit() and len(tok) == 4:
                    year = int(tok)
                    break

            citations.append({
                "title": item.get("title", "").rstrip("."),
                "source": item.get("fulljournalname") or item.get("source", ""),
                "year": year,
                "pmid": pmid,
                "doi": doi,
                "url": f"https://pubmed.ncbi.nlm.nih.gov/{pmid}/",
            })
    except Exception as e:
        log.warning("PubMed failed for '%s': %s", query, e)

    return citations


# ─── PubChem enrichment ──────────────────────────────────────────────────────

def fetch_pubchem_data(query: str) -> dict[str, Any]:
    """Get molecular data from PubChem."""
    try:
        # Get CID from name
        cid_url = f"{PUBCHEM_BASE}/compound/name/{urllib.parse.quote(query)}/cids/JSON"
        r = requests.get(cid_url, timeout=15)
        if r.status_code != 200:
            return {}
        cids = r.json().get("IdentifierList", {}).get("CID", [])
        if not cids:
            return {}
        cid = cids[0]

        time.sleep(NCBI_DELAY)

        # Get properties
        props_url = (
            f"{PUBCHEM_BASE}/compound/cid/{cid}/property/"
            f"MolecularFormula,MolecularWeight,CanonicalSMILES/JSON"
        )
        r = requests.get(props_url, timeout=15)
        if r.status_code != 200:
            return {"cid": cid}
        props = r.json().get("PropertyTable", {}).get("Properties", [{}])[0]

        return {
            "cid": cid,
            "molecular_formula": props.get("MolecularFormula", ""),
            "molecular_weight": props.get("MolecularWeight", ""),
            "smiles": props.get("CanonicalSMILES", ""),
            "pubchem_url": f"https://pubchem.ncbi.nlm.nih.gov/compound/{cid}",
        }
    except Exception as e:
        log.warning("PubChem failed for '%s': %s", query, e)
        return {}


# ─── Merge + output ──────────────────────────────────────────────────────────

def build_record(
    idx: int,
    claude_data: dict[str, Any],
    citations: list[dict[str, Any]],
    pubchem: dict[str, Any],
) -> dict[str, Any]:
    """Combine all sources into a single clean record."""
    return {
        "id": idx,
        "name": claude_data.get("name", ""),
        "abbreviation": claude_data.get("abbreviation", ""),
        "category": claude_data.get("category", "recovery"),
        "description": claude_data.get("description", ""),
        "benefits": claude_data.get("benefits", []),
        "dosageRange": claude_data.get("dosage_range", "Unknown"),
        "frequency": claude_data.get("frequency", "Unknown"),
        "halfLife": claude_data.get("half_life", "Unknown"),
        "adminRoute": claude_data.get("admin_route", "Unknown"),
        "mechanism": claude_data.get("mechanism", ""),
        "contraindications": claude_data.get("contraindications", []),
        "sideEffects": claude_data.get("side_effects", []),
        "commonStacks": claude_data.get("common_stacks", []),
        "regulatoryStatus": claude_data.get("regulatory_status", "Unknown"),
        "imageSystemName": claude_data.get("sf_symbol", "cross.vial.fill"),
        "researchLinks": citations,
        "molecular": pubchem,
    }


def load_partial() -> list[dict[str, Any]]:
    if PARTIAL_PATH.exists():
        with PARTIAL_PATH.open() as f:
            return json.load(f)
    return []


def save_partial(records: list[dict[str, Any]]) -> None:
    with PARTIAL_PATH.open("w") as f:
        json.dump(records, f, indent=2, ensure_ascii=False)


def save_final(records: list[dict[str, Any]]) -> None:
    payload = {
        "version": 1,
        "generated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "count": len(records),
        "disclaimer": (
            "This dataset is for educational purposes only. It does not constitute "
            "medical advice. Many peptides listed are research chemicals not approved "
            "for human use. Always consult a qualified healthcare provider."
        ),
        "peptides": records,
    }
    with FINAL_PATH.open("w") as f:
        json.dump(payload, f, indent=2, ensure_ascii=False)


# ─── Main ────────────────────────────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--limit", type=int, default=None,
                        help="Only process first N peptides (for testing)")
    parser.add_argument("--resume", action="store_true",
                        help="Resume from peptides.partial.json")
    parser.add_argument("--skip-pubmed", action="store_true")
    parser.add_argument("--skip-pubchem", action="store_true")
    args = parser.parse_args()

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        log.error("ANTHROPIC_API_KEY not set")
        sys.exit(1)

    client = anthropic.Anthropic(api_key=api_key)

    records = load_partial() if args.resume else []
    done_abbrevs = {r["abbreviation"].lower() for r in records}
    log.info("Starting build. Already done: %d", len(records))

    todo = PEPTIDES_DEDUPED[: args.limit] if args.limit else PEPTIDES_DEDUPED

    for idx, (name, abbreviation, pubchem_query) in enumerate(todo):
        if abbreviation.lower() in done_abbrevs:
            log.info("[%d/%d] SKIP (already done): %s", idx + 1, len(todo), abbreviation)
            continue

        log.info("[%d/%d] Processing: %s", idx + 1, len(todo), name)

        try:
            claude_data = call_claude(client, name, abbreviation)
        except Exception as e:
            log.error("Claude extraction failed for %s: %s", name, e)
            time.sleep(5)
            continue

        citations: list[dict[str, Any]] = []
        pubchem: dict[str, Any] = {}

        if not args.skip_pubmed:
            citations = fetch_pubmed_citations(name)
            time.sleep(NCBI_DELAY)

        if not args.skip_pubchem:
            pubchem = fetch_pubchem_data(pubchem_query)
            time.sleep(NCBI_DELAY)

        record = build_record(len(records), claude_data, citations, pubchem)
        records.append(record)

        # Checkpoint every peptide — resumable on crash
        save_partial(records)
        log.info("  ✓ %s | cat=%s | %d citations | PubChem CID=%s",
                 record["abbreviation"], record["category"],
                 len(citations), pubchem.get("cid", "—"))

    save_final(records)
    log.info("DONE. %d peptides written to %s", len(records), FINAL_PATH)


if __name__ == "__main__":
    main()
