#!/usr/bin/env python3
"""Inspect the baked KeyComp WCL dataset (KeyComp/Data/WCLData.lua): print a
summary + a sample of the actual DPS rows. Read-only, no API calls."""
import argparse
import os
import re
import sys
import time
from collections import Counter

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

HERE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(os.path.dirname(HERE), "KeyComp", "Data", "WCLData.lua")

DUNGEON_NAME = {
    "ALGETHAR_ACADEMY": "Algeth'ar Academy",
    "MAGISTERS_TERRACE": "Magisters' Terrace",
    "MAISARA_CAVERNS": "Maisara Caverns",
    "NEXUS_POINT_XENAS": "Nexus-Point Xenas",
    "PIT_OF_SARON": "Pit of Saron",
    "SEAT_OF_THE_TRIUMVIRATE": "Seat of the Triumvirate",
    "SKYREACH": "Skyreach",
    "WINDRUNNER_SPIRE": "Windrunner Spire",
}
MEDAL = {"g": "gold", "s": "silver", "b": "bronze", "": "-"}

# Matches both the old single-file layout (`["EU"] = {`, `["key"]={...},`) and
# the sharded layout (`C["EU"] = C["EU"] or {}`, `R["key"]={...}`).
RE_REGION = re.compile(r'^(?:\[|C\[)"(US|EU|KR|TW|CN)"\]')
RE_CHAR = re.compile(
    r'^(?:R)?\["(?P<key>.+?)"\]=\{n="(?P<n>.*?)",rl="(?P<rl>.*?)",'
    r'cl="(?P<cl>.*?)",sp="(?P<sp>.*?)",bk=(?P<bk>\d+),bs=(?P<bs>\d+),d=\{(?P<d>.*)\}\},?$')
RE_DUN = re.compile(r'(\w+)=\{k=(\d+),dps=(\d+),sc=(\d+),md="(.*?)"\}')
RE_GEN = re.compile(r'generated\D*(\d+)')


def data_files():
    """Header + every shard beside it (sorted), so a sharded dataset reads whole."""
    d = os.path.dirname(DATA)
    shards = sorted(os.path.join(d, f) for f in os.listdir(d)
                    if re.match(r'^WCLData\d{2}\.lua$', f))
    return [DATA] + shards


def load():
    rows = []          # one per (char, dungeon run)
    generated = None
    for path in data_files():
        region = None
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                s = line.strip()
                if generated is None:
                    g = RE_GEN.search(s)
                    if g:
                        generated = int(g.group(1))
                rm = RE_REGION.match(s)
                if rm:
                    region = rm.group(1)
                cm = RE_CHAR.match(s)
                if not cm or region is None:
                    continue
                for dk, k, dps, sc, md in RE_DUN.findall(cm.group("d")):
                    rows.append({
                        "region": region, "name": cm.group("n"), "realm": cm.group("rl"),
                        "cls": cm.group("cl"), "spec": cm.group("sp"),
                        "dungeon": dk, "key": int(k), "dps": int(dps),
                        "score": int(sc), "medal": md,
                    })
    return rows, generated


def fmt_dps(n):
    return f"{n/1000:.0f}k" if n < 1_000_000 else f"{n/1_000_000:.2f}M"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--top", type=int, default=15, help="overall top-DPS rows to show")
    ap.add_argument("--per-dungeon", type=int, default=3, help="top rows per dungeon")
    args = ap.parse_args()

    rows, generated = load()
    chars = {(r["region"], r["name"], r["realm"]) for r in rows}
    age = ""
    if generated:
        days = (time.time() - generated) / 86400
        age = f"  (generated {days:.1f} days ago)"

    print(f"WCLData.lua - {len(chars)} unique characters, {len(rows)} dungeon runs{age}")
    byreg = {}
    for r in rows:
        byreg.setdefault(r["region"], set()).add((r["name"], r["realm"]))
    print("  by region: " + ", ".join(f"{k}={len(v)}" for k, v in sorted(byreg.items())))
    keyhist = Counter(r["key"] for r in rows)
    print("  by key level (runs): " + "  ".join(f"+{k}={keyhist[k]}" for k in sorted(keyhist)))
    print()

    print(f"=== Top {args.top} single-run DPS (any dungeon) ===")
    print(f"{'DPS':>7}  {'+key':>4} {'medal':<6} {'class/spec':<22} {'name-realm':<26} {'dungeon':<22} reg")
    for r in sorted(rows, key=lambda x: -x["dps"])[:args.top]:
        cs = f"{r['cls']}/{r['spec']}"
        nr = f"{r['name']}-{r['realm']}"
        print(f"{fmt_dps(r['dps']):>7}  {('+'+str(r['key'])):>4} {MEDAL.get(r['medal'],r['medal']):<6} "
              f"{cs:<22.22} {nr:<26.26} {DUNGEON_NAME.get(r['dungeon'],r['dungeon']):<22} {r['region']}")
    print()

    print(f"=== Top {args.per_dungeon} DPS per dungeon ===")
    for dk in DUNGEON_NAME:
        drows = sorted([r for r in rows if r["dungeon"] == dk], key=lambda x: -x["dps"])
        if not drows:
            continue
        print(f"-- {DUNGEON_NAME[dk]} ({len(drows)} logged) --")
        for r in drows[:args.per_dungeon]:
            cs = f"{r['cls']}/{r['spec']}"
            nr = f"{r['name']}-{r['realm']}"
            print(f"   {fmt_dps(r['dps']):>7}  +{r['key']:<3} {MEDAL.get(r['medal'],r['medal']):<6} "
                  f"{cs:<22.22} {nr:<24.24} {r['region']}")


if __name__ == "__main__":
    main()
