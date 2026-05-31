#!/usr/bin/env python3
"""Package a WoW addon folder into a CurseForge-ready zip.

Why this exists: Windows PowerShell 5.1's Compress-Archive writes ZIP entry
paths with backslashes (KeyComp\\Core.lua), which violates the ZIP spec - some
extractors then create a single flat file with a literal backslash in its name
instead of a KeyComp/ folder. Python's zipfile lets us force forward-slash
arcnames, so the archive extracts cleanly into Interface\\AddOns\\<Addon>\\.

Reads the version from the addon's .toc (## Version:). Output:
  dist/<AddonFolder>-<version>.zip   with <AddonFolder>/ as the single root.

Usage:
  py -3.12 tools/package_addon.py                     # KeyComp
  py -3.12 tools/package_addon.py KeyComp dungeon-finder
"""
from __future__ import annotations

import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"

# files that should never ship inside an addon zip
SKIP_NAMES = {".DS_Store", "Thumbs.db"}
SKIP_SUFFIXES = {".bak", ".swp", ".orig"}


def toc_version(addon_dir: Path) -> str:
    candidates = [addon_dir / f"{addon_dir.name}.toc", *sorted(addon_dir.glob("*.toc"))]
    for toc in candidates:
        if toc.exists():
            for line in toc.read_text(encoding="utf-8", errors="replace").splitlines():
                m = re.match(r"^\s*##\s*Version:\s*(.+?)\s*$", line)
                if m:
                    return m.group(1)
    return "0.0.0"


def should_skip(p: Path) -> bool:
    return p.name in SKIP_NAMES or p.suffix.lower() in SKIP_SUFFIXES


def package(addon: str) -> Path:
    addon_dir = (ROOT / addon).resolve()
    if not addon_dir.is_dir():
        sys.exit(f"not a directory: {addon_dir}")
    folder = addon_dir.name  # zip root = the addon folder name
    ver = toc_version(addon_dir)
    DIST.mkdir(exist_ok=True)
    out = DIST / f"{folder}-{ver}.zip"

    files = sorted(p for p in addon_dir.rglob("*") if p.is_file() and not should_skip(p))
    # "w" mode truncates/overwrites any existing archive -- no delete needed.
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for p in files:
            arc = f"{folder}/" + p.relative_to(addon_dir).as_posix()  # forward slashes
            z.write(p, arc)

    with zipfile.ZipFile(out) as z:
        names = z.namelist()
    bad = [n for n in names if "\\" in n]
    if bad:
        sys.exit(f"FAIL: {len(bad)} entries still have backslashes, e.g. {bad[0]!r}")
    roots = sorted({n.split("/")[0] for n in names})
    toc_in = f"{folder}/{folder}.toc" in names
    print(f"{out.relative_to(ROOT)}  ({out.stat().st_size / 1e6:.2f} MB)  {len(names)} files")
    print(f"  root(s): {roots}   {folder}/{folder}.toc present: {toc_in}")
    if roots != [folder] or not toc_in:
        sys.exit("FAIL: archive root/toc layout is wrong")
    return out


if __name__ == "__main__":
    for a in (sys.argv[1:] or ["KeyComp"]):
        package(a)
