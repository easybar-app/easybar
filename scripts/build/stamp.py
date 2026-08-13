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
SEMVER_PATTERN = re.compile(
    r"^(0|[1-9][0-9]*)\."
    r"(0|[1-9][0-9]*)\."
    r"(0|[1-9][0-9]*)"
    r"(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?"
    r"(?:\+([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$"
)


def replace_required(
    text: str,
    pattern: re.Pattern[str],
    replacement: str,
    description: str,
    expected_count: int = 1,
) -> tuple[str, bool]:
    updated, count = pattern.subn(lambda _: replacement, text)

    if count != expected_count:
        print(
            f"Expected {expected_count} {description} occurrence(s), found {count}",
            file=sys.stderr,
        )
        return text, False

    return updated, True


def semantic_version_core(version: str) -> tuple[str, str, str]:
    """Validate an artifact version and return its semantic-version core."""
    if version == "dev":
        return ("0", "0", "0")

    match = SEMVER_PATTERN.fullmatch(version)
    if match is None:
        raise ValueError(
            "version must be dev or a complete semantic version: "
            f"{version!r}"
        )

    prerelease = match.group(4)
    if prerelease is not None:
        for identifier in prerelease.split("."):
            if identifier.isdigit() and len(identifier) > 1 and identifier[0] == "0":
                raise ValueError(
                    "numeric prerelease identifiers must not contain leading zeros: "
                    f"{version!r}"
                )

    return (match.group(1), match.group(2), match.group(3))


def normalize_bundle_version(version: str) -> str:
    """Return the numeric three-component version required by Apple bundles."""
    return ".".join(semantic_version_core(version))


def stamp_lua_api(path: Path, version: str) -> int:
    try:
        semantic_version_core(version)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1

    if not path.is_file():
        print(f"Missing staged Lua API stub: {path}", file=sys.stderr)
        return 1

    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        print(f"Could not read staged Lua API stub {path}: {error}", file=sys.stderr)
        return 1

    text, ok = replace_required(
        text,
        LUA_API_HEADER_PATTERN,
        f"-- EasyBar Lua API stub version: {version}",
        f"Lua API version header in {path}",
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
    )
    if not ok:
        return 1

    try:
        path.write_text(text, encoding="utf-8")
    except OSError as error:
        print(f"Could not write staged Lua API stub {path}: {error}", file=sys.stderr)
        return 1

    return 0


def stamp_plist(
    plist: Path,
    version: str,
    executable: str,
    name: str,
    icon_file: str,
    bundle_id: str | None,
) -> int:
    if not plist.is_file():
        print(f"Missing Info.plist: {plist}", file=sys.stderr)
        return 1

    try:
        bundle_version = normalize_bundle_version(version)
    except ValueError as error:
        print(error, file=sys.stderr)
        return 1

    try:
        with plist.open("rb") as handle:
            values = plistlib.load(handle)
    except (OSError, plistlib.InvalidFileException) as error:
        print(f"Could not read Info.plist {plist}: {error}", file=sys.stderr)
        return 1

    if not isinstance(values, dict):
        print(f"Info.plist root is not a dictionary: {plist}", file=sys.stderr)
        return 1

    if bundle_id:
        values["CFBundleIdentifier"] = bundle_id

    values["CFBundleShortVersionString"] = bundle_version
    values["CFBundleVersion"] = bundle_version
    values["CFBundleExecutable"] = executable
    values["CFBundleName"] = name
    values["CFBundleDisplayName"] = name
    values["CFBundleIconFile"] = icon_file

    try:
        with plist.open("wb") as handle:
            plistlib.dump(values, handle, fmt=plistlib.FMT_XML, sort_keys=False)
    except OSError as error:
        print(f"Could not write Info.plist {plist}: {error}", file=sys.stderr)
        return 1

    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    bundle_version = subparsers.add_parser(
        "bundle-version",
        help="Print the Apple-compatible bundle version for an EasyBar version.",
    )
    bundle_version.add_argument("--version", required=True)

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

    if args.command == "bundle-version":
        try:
            print(normalize_bundle_version(args.version))
        except ValueError as error:
            print(error, file=sys.stderr)
            return 1
        return 0

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
