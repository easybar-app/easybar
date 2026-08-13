#!/usr/bin/env python3
"""Tests for the bundle resource stamping helpers."""

from __future__ import annotations

import plistlib
import tempfile
import unittest
from pathlib import Path

import stamp


class NormalizeBundleVersionTests(unittest.TestCase):
    def test_normalizes_supported_versions(self) -> None:
        cases = {
            "dev": "0.0.0",
            "1.2.3": "1.2.3",
            "1.2.3-beta.1": "1.2.3",
            "1.2.3+build.4": "1.2.3",
            "1.2.3-dev.abc123.kit.def456-dirty": "1.2.3",
        }

        for version, expected in cases.items():
            with self.subTest(version=version):
                self.assertEqual(stamp.normalize_bundle_version(version), expected)

    def test_rejects_versions_without_a_semantic_core(self) -> None:
        for version in ("", "next", "1.2", "01.2.3", "1.2.3.4"):
            with self.subTest(version=version):
                with self.assertRaises(ValueError):
                    stamp.normalize_bundle_version(version)


class StampTests(unittest.TestCase):
    def test_stamps_lua_api_version_fields(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "easybar_api.lua"
            path.write_text(
                "\n".join(
                    [
                        "-- EasyBar Lua API stub version: dev",
                        "--- EasyBar application version (`dev`)",
                        'EasyBar.version = "dev"',
                        "",
                    ]
                ),
                encoding="utf-8",
            )

            self.assertEqual(stamp.stamp_lua_api(path, "1.2.3-beta.1"), 0)
            self.assertEqual(
                path.read_text(encoding="utf-8"),
                "\n".join(
                    [
                        "-- EasyBar Lua API stub version: 1.2.3-beta.1",
                        "--- EasyBar application version (`1.2.3-beta.1`)",
                        'EasyBar.version = "1.2.3-beta.1"',
                        "",
                    ]
                ),
            )

    def test_stamps_plist_with_numeric_bundle_versions(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "Info.plist"
            with path.open("wb") as handle:
                plistlib.dump({"CFBundleIdentifier": "old.id"}, handle)

            result = stamp.stamp_plist(
                plist=path,
                version="2.4.6-dev.abc123",
                executable="EasyBar",
                name="EasyBar",
                icon_file="EasyBar",
                bundle_id="io.github.gi8lino.easybar",
            )

            self.assertEqual(result, 0)
            with path.open("rb") as handle:
                values = plistlib.load(handle)
            self.assertEqual(values["CFBundleShortVersionString"], "2.4.6")
            self.assertEqual(values["CFBundleVersion"], "2.4.6")
            self.assertEqual(
                values["CFBundleIdentifier"], "io.github.gi8lino.easybar"
            )
            self.assertEqual(values["CFBundleExecutable"], "EasyBar")
            self.assertEqual(values["CFBundleName"], "EasyBar")
            self.assertEqual(values["CFBundleDisplayName"], "EasyBar")
            self.assertEqual(values["CFBundleIconFile"], "EasyBar")


if __name__ == "__main__":
    unittest.main()
