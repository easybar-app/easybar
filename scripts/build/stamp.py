#!/usr/bin/env python3
"""Stamp EasyBar staged resources and bundle Info.plist files."""

from __future__ import annotations

import argparse
import plistlib
import re
import sys
from pathlib import Path


LUA_API_HEADER_PATTERN = re.compile(
    r"^-- EasyBar Lua API stub version: .*$", re.MULTILINE
)
LUA_API_DOC_PATTERN = re.compile(
    r"EasyBar application version \(`[^`]*`\)"
)
LUA_API_VALUE_PATTERN = re.compile(
    r'^EasyBar\.version = "[^"]*"$', re.MULTILINE
)


def replace_required(
    text: str,
    pattern: re.Pattern[str],
    replacement: str,
    description: str,
    expected_count: int | None = None,
) -> tuple[str, bool]:
    updated, count = pattern.subn(lambda _: replacement, text)

    if count == 0:
        print(f"Could not find {description}", file=sys.stderr)
        return text, False
    if expected_count is not None and count != expected_count:
        print(
            f"Expected {expected_count} {description} occurrence(s), found {count}",
            file=sys.stderr,
        )
        return text, False

    return updated, True


def stamp_lua_api(path: Path, version: str) -> int:
    if not path.exists():
        print(f"Missing staged Lua API stub: {path}", file=sys.stderr)
        return 1

    text = path.read_text(encoding="utf-8")

    text, ok = replace_required(
        text,
        LUA_API_HEADER_PATTERN,
        f"-- EasyBar Lua API stub version: {version}",
        f"Lua API version header in {path}",
        expected_count=1,
    )
    if not ok:
        return 1

    text, ok = replace_required(
        text,
        LUA_API_DOC_PATTERN,
        f"EasyBar application version (`{version}`)",
        f"Lua API version documentation in {path}",
    )
    if not ok:
        return 1

    text, ok = replace_required(
        text,
        LUA_API_VALUE_PATTERN,
        f'EasyBar.version = "{version}"',
        f"EasyBar.version assignment in {path}",
        expected_count=1,
    )
    if not ok:
        return 1

    path.write_text(text, encoding="utf-8")
    return 0


def stamp_plist(
    plist: Path,
    version: str,
    executable: str,
    name: str,
    icon_file: str,
    bundle_id: str | None,
) -> int:
    if not plist.exists():
        print(f"Missing Info.plist: {plist}", file=sys.stderr)
        return 1

    try:
        with plist.open("rb") as handle:
            values = plistlib.load(handle)
    except Exception as error:  # noqa: BLE001 - print a useful CLI error.
        print(f"Could not read Info.plist {plist}: {error}", file=sys.stderr)
        return 1

    if not isinstance(values, dict):
        print(f"Info.plist root is not a dictionary: {plist}", file=sys.stderr)
        return 1

    if bundle_id:
        values["CFBundleIdentifier"] = bundle_id

    values["CFBundleShortVersionString"] = version
    values["CFBundleVersion"] = version
    values["CFBundleExecutable"] = executable
    values["CFBundleName"] = name
    values["CFBundleDisplayName"] = name
    values["CFBundleIconFile"] = icon_file

    try:
        with plist.open("wb") as handle:
            plistlib.dump(values, handle, fmt=plistlib.FMT_XML, sort_keys=False)
    except Exception as error:  # noqa: BLE001 - print a useful CLI error.
        print(f"Could not write Info.plist {plist}: {error}", file=sys.stderr)
        return 1

    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    lua_api = subparsers.add_parser(
        "lua-api", help="Stamp a staged Lua API stub."
    )
    lua_api.add_argument("--file", type=Path, required=True)
    lua_api.add_argument("--version", required=True)

    plist = subparsers.add_parser("plist", help="Stamp one Info.plist file.")
    plist.add_argument("--plist", type=Path, required=True)
    plist.add_argument("--bundle-id")
    plist.add_argument("--version", required=True)
    plist.add_argument("--executable", required=True)
    plist.add_argument("--name", required=True)
    plist.add_argument("--icon-file", required=True)

    return parser


def main() -> int:
    args = build_parser().parse_args()

    if args.command == "lua-api":
        return stamp_lua_api(args.file, args.version)

    if args.command == "plist":
        return stamp_plist(
            plist=args.plist,
            version=args.version,
            executable=args.executable,
            name=args.name,
            icon_file=args.icon_file,
            bundle_id=args.bundle_id,
        )

    raise AssertionError(f"unsupported command: {args.command}")


if __name__ == "__main__":
    raise SystemExit(main())
