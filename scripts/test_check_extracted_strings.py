"""Regression checks for check-extracted-strings.py."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("extracted", Path(__file__).with_name("check-extracted-strings.py"))
extracted = importlib.util.module_from_spec(spec)
spec.loader.exec_module(extracted)

CATALOG = {
    "sourceLanguage": "en",
    "strings": {
        "Today": {"localizations": {"sv": {"stringUnit": {"state": "translated", "value": "Idag"}}}},
        "Atlas": {"shouldTranslate": False},
    },
}


class GapTests(unittest.TestCase):
    def test_interpolatedKeyMissingFromCatalog_isReported(self):
        found = extracted.gaps({"Peptide": {"Today", "Added %@"}}, {"Peptide": CATALOG})
        self.assertEqual(found, ["  Peptide: sv: 'Added %@'"])

    def test_keyWithoutLetters_isNotReported(self):
        self.assertEqual(extracted.gaps({"Peptide": {"%lld", "%1$@ • %2$@"}}, {"Peptide": CATALOG}), [])

    def test_keyMarkedDoNotTranslate_isNotReported(self):
        self.assertEqual(extracted.gaps({"Peptide": {"Atlas"}}, {"Peptide": CATALOG}), [])

    def test_translatedKey_isNotReported(self):
        self.assertEqual(extracted.gaps({"Peptide": {"Today"}}, {"Peptide": CATALOG}), [])


class StringsdataTests(unittest.TestCase):
    def write(self, root: Path, source: Path) -> Path:
        path = root / "DD" / "Peptide.build" / "Debug-iphonesimulator" / "Peptide.build" / "View.stringsdata"
        path.parent.mkdir(parents=True)
        path.write_text(json.dumps({"source": str(source), "version": 1, "tables": {
            "Localizable": [{"key": "%@ lock", "comment": ""}],
            "InfoPlist": [{"key": "Ignored"}],
        }}))
        return path

    def test_targetFolder_mapsToItsCatalog(self):
        path = Path("/DD/Build/Intermediates.noindex/Peptide.build/Debug-watchsimulator/PeptideWatch.build/a.stringsdata")
        self.assertEqual(extracted.target_of(path), "PeptideWatch")

    def test_testTargetFolder_isIgnored(self):
        path = Path("/DD/Peptide.build/Debug-iphonesimulator/PeptideTests.build/a.stringsdata")
        self.assertIsNone(extracted.target_of(path))

    def test_existingSource_yieldsLocalizableKeysOnly(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            source = root / "View.swift"
            source.write_text("")
            self.assertEqual(extracted.extracted_keys(self.write(root, source), repo=root), {"%@ lock"})

    def test_deletedSource_yieldsNoKeys(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            self.assertEqual(extracted.extracted_keys(self.write(root, root / "Gone.swift"), repo=root), set())


if __name__ == "__main__":
    unittest.main()
