"""Regression checks for add-only vs read/write Photos purpose strings."""
import importlib.util
from pathlib import Path
import re
import unittest

spec = importlib.util.spec_from_file_location("claims", Path(__file__).with_name("check-copy-claims.py"))
claims = importlib.util.module_from_spec(spec)
spec.loader.exec_module(claims)


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
