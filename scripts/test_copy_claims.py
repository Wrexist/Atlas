"""Regression checks for check-copy-claims.py."""
import importlib.util
from pathlib import Path
import re
import unittest

spec = importlib.util.spec_from_file_location("claims", Path(__file__).with_name("check-copy-claims.py"))
claims = importlib.util.module_from_spec(spec)
spec.loader.exec_module(claims)


class StoreFacingCopyTests(unittest.TestCase):
    def test_marketing_page_and_social_images_are_scanned_for_retired_terms(self):
        scanned = {str(p.relative_to(claims.REPO)) for p in claims.store_facing_files()}
        self.assertIn("docs/index.html", scanned)
        self.assertIn("marketing/app-store/social/square-biology.html", scanned)
        self.assertIn("marketing/app-store/screens/07-biology.html", scanned)

    def test_retired_terms_match_performance_age_and_stack(self):
        for text in ["Track your Performance Age.", "your stack", "stacking"]:
            with self.subTest(text=text):
                self.assertRegex(text, claims.RETIRED_TERMS)
        self.assertNotRegex("Track your Biological Age.", claims.RETIRED_TERMS)

    def test_offer_countdown_copy_is_flagged(self):
        self.assertRegex("⚡ WELCOME OFFER ENDS IN", claims.COUNTDOWN_COPY)
        self.assertNotRegex("7 days free, then choose a plan", claims.COUNTDOWN_COPY)

    def test_dosing_directives_are_flagged_and_neutral_copy_is_not(self):
        for text in ["(recommended max: 2)", "Monitor liver enzymes (ALT, AST)",
                     "Growth + Recovery amplify tissue repair",
                     "don't eat for 30 min after injection"]:
            with self.subTest(text=text):
                self.assertRegex(text, claims.HEALTH_DIRECTIVES)
        self.assertNotRegex("Discuss liver monitoring with your clinician.", claims.HEALTH_DIRECTIVES)


class PhotosPurposeTests(unittest.TestCase):
    def required(self, source):
        return {key for key, pattern in claims.PHOTO_USAGE_PATTERNS.items() if re.search(pattern, source)}

    def test_add_only_export_requires_add_purpose(self):
        self.assertEqual(self.required("""
            PHPhotoLibrary.requestAuthorization(for: .addOnly)
            PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }
        """), {"NSPhotoLibraryAddUsageDescription"})

    def test_read_access_is_still_required(self):
        for source in ["PHAsset.fetchAssets()", "PHImageManager.default()",
                       "PHPhotoLibrary.requestAuthorization { status in }",
                       "PHPhotoLibrary.requestAuthorization(for: .readWrite)",
                       "PHPhotoLibrary.requestAuthorization(for: access)",
                       "PHPhotoLibrary.requestAuthorization( for: .readWrite)"]:
            with self.subTest(source=source):
                self.assertIn("NSPhotoLibraryUsageDescription", self.required(source))

    def test_mixed_read_and_add_requires_both(self):
        self.assertEqual(self.required("PHAsset.fetchAssets(); PHAssetCreationRequest.forAsset()"),
                         set(claims.PHOTO_USAGE_PATTERNS))


if __name__ == "__main__":
    unittest.main()
