#!/usr/bin/env python3
"""Check single-line source documentation for non-test declarations."""

from __future__ import annotations

import ast
import re
import sys
from pathlib import Path


SWIFT_DECLARATION = re.compile(
    r"^  (?:(?:@\w+|private|fileprivate|internal|public|open|static|"
    r"class|final|override|lazy|weak|unowned|required|convenience)\s+)*"
    r"(?:func\s+|init\s*\(|(?:var|let)\s+)[A-Za-z_]*"
)
SWIFT_TYPE = re.compile(r"^\s*(?:(?:final|public|private|open)\s+)*(?:struct|class|enum)\s+\w+")
SHELL_FUNCTION = re.compile(r"^[a-zA-Z_][a-zA-Z_0-9]*\(\)\s*\{")
LUA_FUNCTION = re.compile(r"^local function [a-zA-Z_][a-zA-Z_0-9]*\(")


def has_comment(lines: list[str], index: int, prefix: str) -> bool:
    """Find a one-line documentation comment before a declaration and attributes."""
    preceding = index - 1
    while preceding >= 0 and lines[preceding].strip().startswith("@"):
        preceding -= 1
    return preceding >= 0 and lines[preceding].strip().startswith(prefix) and bool(
        lines[preceding].strip()[len(prefix):].strip()
    )


def check_swift(path: Path) -> list[str]:
    """Report undocumented Swift types, functions, and top-level type fields."""
    errors = []
    lines = path.read_text(encoding="utf-8").splitlines()
    for index, line in enumerate(lines):
        if SWIFT_TYPE.match(line) or SWIFT_DECLARATION.match(line):
            if not has_comment(lines, index, "///"):
                errors.append(f"{path}:{index + 1}: missing /// documentation")
    return errors


def check_shell(path: Path) -> list[str]:
    """Report undocumented named shell functions outside test scripts."""
    lines = path.read_text(encoding="utf-8").splitlines()
    return [
        f"{path}:{index + 1}: missing # documentation"
        for index, line in enumerate(lines)
        if SHELL_FUNCTION.match(line) and not has_comment(lines, index, "#")
    ]


def check_lua(path: Path) -> list[str]:
    """Report undocumented named Lua example functions."""
    lines = path.read_text(encoding="utf-8").splitlines()
    return [
        f"{path}:{index + 1}: missing --- documentation"
        for index, line in enumerate(lines)
        if LUA_FUNCTION.match(line) and not has_comment(lines, index, "---")
    ]


def check_python(path: Path) -> list[str]:
    """Report undocumented Python functions and classes outside tests."""
    tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
    return [
        f"{path}:{node.lineno}: missing docstring"
        for node in ast.walk(tree)
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef))
        and not ast.get_docstring(node)
    ]


def main() -> int:
    """Validate documentation in the editable app and helper-script sources."""
    root = Path(__file__).resolve().parents[2]
    checks = (
        (root / "Sources", "*.swift", check_swift),
        (root / "scripts", "*.sh", check_shell),
        (root / "scripts", "*.py", check_python),
        (root / "examples", "*.lua", check_lua),
    )
    errors = []
    for directory, pattern, checker in checks:
        for path in sorted(directory.rglob(pattern)):
            if path.name.startswith("test-") or "/Tests/" in str(path):
                continue
            errors.extend(checker(path))
    if errors:
        print("\n".join(errors), file=sys.stderr)
        return 1
    print("Source documentation OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
