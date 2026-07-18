import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock

import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "src"))

import find_cached


class FindCachedTests(unittest.TestCase):
    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory()
        self.cache_dir = Path(self.temp_dir.name)

    def tearDown(self):
        self.temp_dir.cleanup()

    def make_file(
        self,
        model_cache_name: str,
        snapshot: str,
        repo_path: str,
        mtime: float | None = None,
    ) -> Path:
        path = (
            self.cache_dir
            / model_cache_name
            / "snapshots"
            / snapshot
            / repo_path
        )
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"test")
        if mtime is not None:
            os.utime(path.parent, (mtime, mtime))
        return path

    def test_preserves_exact_mixed_case_cache_name(self):
        expected = self.make_file(
            "models--Owner--MixedCase-GGUF", "commit", "model.gguf"
        )
        actual = find_cached.find_model_path(
            "Owner/MixedCase-GGUF", "model.gguf", self.cache_dir
        )
        self.assertEqual(expected, actual)

    def test_finds_case_insensitive_existing_cache_directory(self):
        expected = self.make_file(
            "models--owner--MIXEDcase-gguf", "commit", "model.gguf"
        )
        actual = find_cached.find_model_path(
            "Owner/MixedCase-GGUF", "model.gguf", self.cache_dir
        )
        self.assertEqual(expected, actual)

    def test_selects_newest_snapshot_that_contains_requested_file(self):
        old = time.time() - 100
        new = time.time()
        older_file = self.make_file(
            "models--Owner--Repo", "old", "projector.gguf", old
        )
        newer_file = self.make_file(
            "models--Owner--Repo", "new", "projector.gguf", new
        )
        actual = find_cached.find_model_path(
            "Owner/Repo", "projector.gguf", self.cache_dir
        )
        self.assertEqual(newer_file, actual)
        self.assertNotEqual(older_file, actual)

    def test_skips_newest_snapshot_when_file_is_absent(self):
        expected = self.make_file(
            "models--Owner--Repo", "old", "projector.gguf", time.time() - 100
        )
        newer = self.cache_dir / "models--Owner--Repo" / "snapshots" / "new"
        newer.mkdir(parents=True)
        os.utime(newer, None)
        actual = find_cached.find_model_path(
            "Owner/Repo", "projector.gguf", self.cache_dir
        )
        self.assertEqual(expected, actual)

    def test_returns_none_for_missing_file(self):
        self.make_file("models--Owner--Repo", "commit", "other.gguf")
        self.assertIsNone(
            find_cached.find_model_path(
                "Owner/Repo", "missing.gguf", self.cache_dir
            )
        )

    def test_rejects_paths_outside_snapshot(self):
        with self.assertRaises(ValueError):
            find_cached.find_model_path(
                "Owner/Repo", "../secret", self.cache_dir
            )

    def test_cache_dir_environment_override(self):
        with mock.patch.dict(
            os.environ, {"RUNPOD_HF_CACHE_DIR": str(self.cache_dir)}
        ):
            self.assertEqual(self.cache_dir, find_cached.get_cache_dir())


if __name__ == "__main__":
    unittest.main()
