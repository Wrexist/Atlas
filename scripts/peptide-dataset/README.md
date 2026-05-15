# Atlas Dataset Builder

Builds a comprehensive ~210-peptide dataset for the Atlas iOS app.

## What it produces

`peptides.json` — a bundle-ready JSON file with this shape:

```json
{
  "version": 1,
  "generated_at": "2026-04-12T...",
  "count": 210,
  "disclaimer": "Educational purposes only...",
  "peptides": [
    {
      "id": 0,
      "name": "Body Protection Compound-157",
      "abbreviation": "BPC-157",
      "category": "recovery",
      "description": "...",
      "benefits": ["Tissue Repair", "Gut Healing", ...],
      "dosageRange": "250-500 mcg",
      "frequency": "1-2x daily",
      "halfLife": "4 hours",
      "adminRoute": "Subcutaneous",
      "mechanism": "...",
      "contraindications": [...],
      "sideEffects": [...],
      "commonStacks": ["TB-500", "GHK-Cu"],
      "regulatoryStatus": "Research chemical, not FDA-approved",
      "imageSystemName": "cross.vial.fill",
      "researchLinks": [
        {
          "title": "...",
          "source": "Current Pharmaceutical Design",
          "year": 2023,
          "pmid": "12345678",
          "doi": "10.2174/...",
          "url": "https://pubmed.ncbi.nlm.nih.gov/12345678/"
        }
      ],
      "molecular": {
        "cid": 108101,
        "molecular_formula": "C62H98N16O22",
        "molecular_weight": "1419.55",
        "smiles": "...",
        "pubchem_url": "https://pubchem.ncbi.nlm.nih.gov/compound/108101"
      }
    }
  ]
}
```

## Setup

```bash
cd peptide-dataset
python3 -m venv .venv
source .venv/bin/activate
pip install anthropic

export ANTHROPIC_API_KEY=sk-ant-your-key-here
```

## Run it

**Test on 5 peptides first** (cheap, ~30 seconds):
```bash
python3 build_dataset.py --limit 5
```

Check `peptides.partial.json` — verify the structure looks right, descriptions are accurate on ones you know (BPC-157, Semax, etc.), and PubMed citations resolved.

**Full run** (~210 peptides, ~15-25 minutes, roughly $5-15 in Claude API tokens):
```bash
python3 build_dataset.py
```

**Resume after a crash or network hiccup:**
```bash
python3 build_dataset.py --resume
```

Every peptide is checkpointed to `peptides.partial.json` immediately after processing, so you never lose work.

## Cost estimate

- **Claude Opus 4.6**: ~1.5k input + ~800 output tokens per peptide = roughly $0.03-0.05 per peptide at current pricing
- 210 peptides × $0.04 ≈ **$8-10 total**
If you want to cut cost, swap `CLAUDE_MODEL = "claude-opus-4-6"` to `"claude-sonnet-4-6"` in `build_dataset.py`. Still very good quality, ~5x cheaper.

## Integrate into the iOS app

1. **Copy `peptides.json` into your Xcode project:**
   ```
   Peptide/Resources/peptides.json
   ```

2. **Add to `project.yml`** — it's already covered by `sources: - path: Peptide` so XcodeGen will pick it up automatically on the next `xcodegen generate`. Just confirm it's not in the excludes list.

3. **Copy `PeptideDatabase.swift`** into:
   ```
   Peptide/Data/PeptideDatabase.swift
   ```

4. **Update `DataStore.swift`** — replace the hardcoded mock list. In `MockPeptides.swift`, change:
   ```swift
   static let all: [Peptide] = [bpc157, tb500, ...]
   ```
   to:
   ```swift
   static let all: [Peptide] = PeptideDatabase.load()
   ```
   The loader falls back to the hardcoded mocks if the JSON is missing, so existing previews keep working.

5. **Extend the `Peptide` model** (optional, recommended) to surface the new fields:
   ```swift
   struct Peptide: Identifiable, Hashable {
       // ...existing fields...
       let mechanism: String
       let contraindications: [String]
       let sideEffects: [String]
       let commonStacks: [String]
       let regulatoryStatus: String
   }
   ```
   Then update `PeptideDatabase.map(_:)` to populate them, and add new sections to `PeptideDetailView` to display contraindications, side effects, and the "Commonly stacked with" list.

## Important: review before shipping

The LLM does the heavy lifting, but **manually review the top 20-30 peptides people will search for** before App Store submission:

- BPC-157, TB-500, Semaglutide, Tirzepatide, Retatrutide
- CJC-1295, Ipamorelin, GHK-Cu, Epitalon
- Semax, Selank, Dihexa
- MOTS-c, Humanin, SS-31
- PT-141, MT-II, Tesamorelin, AOD-9604

Open `peptides.json`, find each, and spot-check:
- Description is factually accurate
- Dosage ranges match published research (cross-check with examine.com or r/Peptides wiki)
- Category makes sense
- At least 2-3 PubMed citations resolved

## Legal / App Store notes

- The `disclaimer` field in the output should be displayed prominently in the app (e.g., on first launch and in the About section).
- For App Store review, frame the app as **tracking and education**, never dosing guidance. Apple has rejected peptide apps in the past.
- Many peptides in this dataset are **research chemicals not approved for human use**. The `regulatoryStatus` field captures this — surface it in the UI on every peptide detail page.
- Consider adding an age gate (17+) and a one-time "I understand this is educational only" acknowledgment on first launch.

## Files in this folder

- `peptide_list.py` — the 210 peptide master list (edit to add/remove)
- `build_dataset.py` — the main script
- `PeptideDatabase.swift` — drop-in loader for the iOS app
- `peptides.json` — **output** (generated)
- `peptides.partial.json` — **checkpoint** (generated, resumable)
- `build.log` — run log (generated)
