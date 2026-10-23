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


class HealthWriteTests(unittest.TestCase):
    def writes(self, source):
        return re.search(claims.HEALTH_WRITE_PATTERN, source) is not None

    def test_empty_share_set_is_read_only(self):
        for source in ["requestAuthorization(toShare: [], read: readTypes)",
                       "getRequestStatusForAuthorization(toShare: [ ], read: types)",
                       "requestAuthorization(toShare: nil, read: readTypes)"]:
            with self.subTest(source=source):
                self.assertFalse(self.writes(source))

    def test_non_empty_share_set_is_a_write(self):
        for source in ["requestAuthorization(toShare: nutritionWriteTypes, read: [])",
                       "requestAuthorization(\n    toShare: [HKQuantityType(.bodyMass)],\n    read: [])"]:
            with self.subTest(source=source):
                self.assertTrue(self.writes(source))


if __name__ == "__main__":
    unittest.main()
