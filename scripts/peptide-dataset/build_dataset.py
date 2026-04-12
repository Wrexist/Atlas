#!/usr/bin/env python3
"""
PeptideX Dataset Builder
========================
Builds a comprehensive peptide dataset for the PeptideX iOS app.

Pipeline per peptide:
  1. Claude API (claude-opus-4-6) -> all structured data in one call:
     - Core peptide info matching Peptide.swift model
     - Research citations (PMIDs, DOIs, journal refs)
     - Molecular data (formula, MW, SMILES, PubChem CID)
  2. Auto-validate category + field completeness
  3. Checkpoint after each peptide (resumable)

Usage:
  export ANTHROPIC_API_KEY=sk-ant-...
  python3 build_dataset.py              # full build
  python3 build_dataset.py --limit 5    # test run on 5 peptides
  python3 build_dataset.py --resume     # resume from checkpoint

Output:
  peptides.json              - final dataset (drop into app bundle)
  peptides.partial.json      - checkpoint after every peptide (resumable)
  build.log                  - detailed run log
"""

import argparse
import json
import logging
import os
import re
import sys
import time
from pathlib import Path
from typing import Any

import anthropic

from peptide_list import PEPTIDES_DEDUPED

# ─── Config ──────────────────────────────────────────────────────────────────

OUT_DIR = Path(__file__).parent
FINAL_PATH = OUT_DIR / "peptides.json"
PARTIAL_PATH = OUT_DIR / "peptides.partial.json"
LOG_PATH = OUT_DIR / "build.log"

CLAUDE_MODEL = "claude-opus-4-6"
CLAUDE_MAX_TOKENS = 4096

CATEGORIES = ["growth", "recovery", "cognitive", "antiAging", "immune", "metabolic"]

MAX_RETRIES = 3
RETRY_BASE_DELAY = 2  # seconds, doubles each retry

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


# ─── Claude extraction (all-in-one) ─────────────────────────────────────────

EXTRACTION_SYSTEM = """You are a scientific research assistant building an educational peptide database for a mobile app called PeptideX.

Rules:
1. Output ONLY valid JSON, no markdown fences, no preamble, no commentary.
2. If a fact is uncertain, use the string "Unknown" rather than inventing data.
3. Dosages are for EDUCATIONAL reference only — use ranges commonly cited in research literature, not prescriptions.
4. Keep descriptions factual and neutral. Do not make therapeutic claims.
5. Never recommend usage — describe what research has investigated.
6. For unapproved research peptides, note their regulatory status honestly.
7. For research citations, use REAL papers you are confident exist. Include accurate PMIDs and DOIs. If unsure of exact PMID/DOI, omit that citation rather than guessing.
8. For molecular data, provide accurate values from established databases. If the peptide is too large or complex for a simple molecular formula, note that.
"""

EXTRACTION_USER_TEMPLATE = """Extract comprehensive structured data for this peptide for our educational database.

Peptide: {name}
Common abbreviation hint: {abbreviation}
PubChem search term: {pubchem_query}

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
  "contraindications": ["Array", "of", "known", "contraindications"],
  "side_effects": ["Array", "of", "reported", "side", "effects"],
  "common_stacks": ["Other peptides", "it is commonly", "researched alongside"],
  "regulatory_status": "e.g. 'FDA-approved for X', 'Research chemical, not approved for human use', 'Cosmetic ingredient'",
  "sf_symbol": "Most-fitting SF Symbol name, e.g. 'cross.vial.fill', 'brain.head.profile.fill', 'flame.fill'",
  "research_links": [
    {{
      "title": "Exact paper title",
      "source": "Journal name",
      "year": 2023,
      "pmid": "12345678 or empty string if unknown",
      "doi": "10.xxxx/yyyy or empty string if unknown",
      "url": "https://pubmed.ncbi.nlm.nih.gov/12345678/ or relevant URL"
    }}
  ],
  "molecular": {{
    "cid": 12345,
    "molecular_formula": "C10H15N3O4 or 'Complex peptide' for large peptides",
    "molecular_weight": "245.25 or approximate weight as string",
    "smiles": "Canonical SMILES string or empty string for large peptides",
    "pubchem_url": "https://pubchem.ncbi.nlm.nih.gov/compound/12345 or empty string"
  }}
}}

Category guide:
- growth: muscle, tissue growth, GH-axis, IGF, healing factors
- recovery: wound healing, tendon/joint repair, anti-inflammatory, sleep
- cognitive: nootropic, neuroprotective, focus, memory, mood
- antiAging: longevity, telomere, mitochondrial, senolytic
- immune: antimicrobial, immunomodulating, antiviral, T-cell
- metabolic: fat loss, glucose, GLP-1, thermogenesis, appetite

Include 3-5 real, well-known research citations. Only include citations you are confident are real publications with correct details.

Return ONLY the JSON object."""


def call_claude_with_retry(client: anthropic.Anthropic, name: str,
                           abbreviation: str, pubchem_query: str) -> dict[str, Any]:
    """Extract all peptide data via Claude API with retry logic."""
    for attempt in range(MAX_RETRIES):
        try:
            msg = client.messages.create(
                model=CLAUDE_MODEL,
                max_tokens=CLAUDE_MAX_TOKENS,
                system=EXTRACTION_SYSTEM,
                messages=[
                    {
                        "role": "user",
                        "content": EXTRACTION_USER_TEMPLATE.format(
                            name=name,
                            abbreviation=abbreviation,
                            pubchem_query=pubchem_query,
                        ),
                    }
                ],
            )
            text = msg.content[0].text.strip()

            # Strip markdown fences if the model slips
            if text.startswith("```"):
                match = re.match(r'```\w*\n?(.*?)\n?```', text, re.DOTALL)
                if match:
                    text = match.group(1).strip()
                else:
                    text = "\n".join(text.split("\n")[1:])

            data = json.loads(text)

            # Validate category
            if data.get("category") not in CATEGORIES:
                log.warning("Bad category '%s' for %s → defaulting to 'recovery'",
                            data.get("category"), name)
                data["category"] = "recovery"

            return data

        except json.JSONDecodeError as e:
            log.warning("JSON parse failed for %s (attempt %d/%d): %s",
                        name, attempt + 1, MAX_RETRIES, e)
            if attempt < MAX_RETRIES - 1:
                delay = RETRY_BASE_DELAY * (2 ** attempt)
                log.info("  Retrying in %ds...", delay)
                time.sleep(delay)
            else:
                log.error("All retries exhausted for %s, raw: %s", name, text[:300])
                raise

        except anthropic.RateLimitError:
            delay = RETRY_BASE_DELAY * (2 ** attempt) * 5
            log.warning("Rate limited on %s (attempt %d/%d), waiting %ds",
                        name, attempt + 1, MAX_RETRIES, delay)
            time.sleep(delay)

        except anthropic.APIError as e:
            log.warning("API error for %s (attempt %d/%d): %s",
                        name, attempt + 1, MAX_RETRIES, e)
            if attempt < MAX_RETRIES - 1:
                time.sleep(RETRY_BASE_DELAY * (2 ** attempt))
            else:
                raise

    raise RuntimeError(f"Failed to process {name} after {MAX_RETRIES} attempts")


# ─── Record building ────────────────────────────────────────────────────────

def build_record(idx: int, claude_data: dict[str, Any]) -> dict[str, Any]:
    """Build a clean, validated record from Claude's response."""
    # Extract and normalize research links
    raw_links = claude_data.get("research_links", [])
    research_links = []
    for link in raw_links:
        if not isinstance(link, dict):
            continue
        entry = {
            "title": str(link.get("title", "")).rstrip("."),
            "source": str(link.get("source", "")),
            "year": int(link.get("year", 0)) if link.get("year") else 0,
            "pmid": str(link.get("pmid", "")),
            "doi": str(link.get("doi", "")),
            "url": str(link.get("url", "")),
        }
        if entry["title"]:
            research_links.append(entry)

    # Extract and normalize molecular data
    raw_mol = claude_data.get("molecular", {})
    molecular = {}
    if isinstance(raw_mol, dict) and raw_mol:
        molecular = {
            "cid": raw_mol.get("cid", 0),
            "molecular_formula": str(raw_mol.get("molecular_formula", "")),
            "molecular_weight": str(raw_mol.get("molecular_weight", "")),
            "smiles": str(raw_mol.get("smiles", "")),
            "pubchem_url": str(raw_mol.get("pubchem_url", "")),
        }

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
        "researchLinks": research_links,
        "molecular": molecular,
    }


# ─── Checkpoint I/O ─────────────────────────────────────────────────────────

def load_checkpoint() -> list[dict[str, Any]]:
    if PARTIAL_PATH.exists():
        try:
            with PARTIAL_PATH.open() as f:
                data = json.load(f)
            if isinstance(data, list):
                return data
            peptides = data.get("peptides", [])
            return peptides if isinstance(peptides, list) else []
        except (json.JSONDecodeError, ValueError) as e:
            log.warning("Checkpoint corrupted (%s), backing up and starting fresh", e)
            PARTIAL_PATH.rename(PARTIAL_PATH.with_suffix(".json.bak"))
            return []
    return []


def save_checkpoint(records: list[dict[str, Any]]) -> None:
    with PARTIAL_PATH.open("w") as f:
        json.dump(records, f, indent=2, ensure_ascii=False)


def save_final(records: list[dict[str, Any]]) -> None:
    # Re-index all records sequentially
    for i, rec in enumerate(records):
        rec["id"] = i

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
    parser = argparse.ArgumentParser(description="Build PeptideX dataset")
    parser.add_argument("--limit", type=int, default=None,
                        help="Only process first N peptides (for testing)")
    parser.add_argument("--resume", action="store_true",
                        help="Resume from peptides.partial.json checkpoint")
    args = parser.parse_args()

    api_key = os.environ.get("ANTHROPIC_API_KEY")
    if not api_key:
        log.error("ANTHROPIC_API_KEY not set. Export it and retry.")
        sys.exit(1)

    client = anthropic.Anthropic(api_key=api_key)

    # Load checkpoint if resuming
    records = load_checkpoint() if args.resume else []
    done_abbrevs = {r["abbreviation"].lower() for r in records}

    todo = PEPTIDES_DEDUPED[:args.limit] if args.limit else PEPTIDES_DEDUPED
    total = len(todo)
    skipped = 0
    failed = 0

    log.info("═" * 60)
    log.info("PeptideX Dataset Builder")
    log.info("Model: %s | Peptides: %d | Checkpoint: %d done",
             CLAUDE_MODEL, total, len(records))
    log.info("═" * 60)

    for idx, (name, abbreviation, pubchem_query) in enumerate(todo):
        if abbreviation.lower() in done_abbrevs:
            skipped += 1
            continue

        progress = f"[{idx + 1}/{total}]"
        log.info("%s Processing: %s (%s)", progress, name, abbreviation)

        try:
            claude_data = call_claude_with_retry(client, name, abbreviation, pubchem_query)
            record = build_record(len(records), claude_data)
            records.append(record)
            done_abbrevs.add(abbreviation.lower())

            # Checkpoint immediately
            save_checkpoint(records)

            n_links = len(record["researchLinks"])
            has_mol = bool(record["molecular"])
            log.info("%s  ✓ %s | cat=%s | %d citations | mol=%s",
                     progress, record["abbreviation"], record["category"],
                     n_links, "yes" if has_mol else "no")

        except Exception as e:
            failed += 1
            log.error("%s  ✗ FAILED %s: %s", progress, name, e)
            continue

    # Write final output
    save_final(records)

    log.info("═" * 60)
    log.info("BUILD COMPLETE")
    log.info("  Total: %d | Success: %d | Skipped: %d | Failed: %d",
             total, len(records), skipped, failed)
    log.info("  Output: %s", FINAL_PATH)
    log.info("═" * 60)


if __name__ == "__main__":
    main()
