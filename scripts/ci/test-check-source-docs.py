#!/usr/bin/env python3
"""Regression tests for the source documentation checker."""

from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).with_name("check-source-docs.py")
SPEC = importlib.util.spec_from_file_location("check_source_docs", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
CHECKER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(CHECKER)


class SourceDocumentationTests(unittest.TestCase):
    def check_sample(self, suffix: str, source: str, checker: object) -> list[str]:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / f"example{suffix}"
            path.write_text(source, encoding="utf-8")
            return checker(path)

    def test_swift_types_fields_and_functions_require_comments(self) -> None:
        source = (
            "/// Represents a documented view.\n"
            "struct View {\n"
            "  let missing: String\n"
            "  /// Renders the view.\n"
            "  func render() {}\n"
            "}\n"
        )
        errors = self.check_sample(".swift", source, CHECKER.check_swift)
        self.assertEqual(len(errors), 1)
        self.assertIn("missing ///", errors[0])

    def test_swift_annotations_can_follow_a_comment(self) -> None:
        source = (
            "/// Represents a main-actor controller.\n"
            "@MainActor\n"
            "class Controller {\n"
            "  /// Tracks current state.\n"
            "  @ObservedObject var state: State\n"
            "}\n"
        )
        self.assertEqual(self.check_sample(".swift", source, CHECKER.check_swift), [])

    def test_shell_functions_require_comments(self) -> None:
        errors = self.check_sample(".sh", "run() { :; }\n", CHECKER.check_shell)
        self.assertEqual(len(errors), 1)

    def test_python_functions_require_docstrings(self) -> None:
        errors = self.check_sample(".py", "def run():\n    pass\n", CHECKER.check_python)
        self.assertEqual(len(errors), 1)

    def test_lua_functions_require_comments(self) -> None:
        errors = self.check_sample(".lua", "local function run()\nend\n", CHECKER.check_lua)
        self.assertEqual(len(errors), 1)


if __name__ == "__main__":
    unittest.main()
