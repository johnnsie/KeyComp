#!/usr/bin/env python3
"""
KeyComp WCL data builder.

Harvests Warcraft Logs Mythic+ DPS rankings for Midnight Season 1 (zone 47) and
bakes them into a SHARDED static data set under KeyComp/Data/ (WCLData.lua header
+ WCLData01..NN.lua) that the addon loads at runtime (no in-game internet needed).
Sharding keeps each Lua chunk under the 5.1 ~262k-constants/function limit — a
single literal of the full +10 population would overflow it and fail to load.
Run daily; ship the refreshed files via CurseForge.

Data source: WCL API v2 client-credentials grant. Reads creds from
    .secrets/wcl-credentials.json   (gitignored, outside the addon)

Usage:
    python tools/wcl_build.py                       # +10 up, all regions, unlimited pages
    python tools/wcl_build.py --regions US,EU
    python tools/wcl_build.py --min-key 15 --pages 30   # shallower/faster pull
    python tools/wcl_build.py --reshard             # re-emit existing data sharded, no API

A full +10 pull is large (tens of thousands of chars, ~12-24 MB) and spans
multiple hourly rate-limit windows — it paces itself (see Budget) and can take
hours. Each ranking row is one logged run; we keep each character's BEST (highest)
key per dungeon. Only the DPS metric is harvested, so tanks/healers and unlogged
players are absent by design (they read as "no data" in-client).
"""
import argparse
import base64
import json
import os
import re
import sys
import time
import zlib
import urllib.error
import urllib.parse
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
CREDS = os.path.join(REPO, ".secrets", "wcl-credentials.json")
GQL = "https://www.warcraftlogs.com/api/v2/client"
ZONE = 47
SEASON = "Midnight S1"

# Data is sharded across this many Lua files so each compiled chunk stays well
# under Lua 5.1's ~262143-constants-per-function ceiling (a single literal of
# the full +10 population would overflow it and fail to load). Fixed count keeps
# the .toc static; a stable hash spreads chars evenly, so each shard is small.
SHARDS = 24

# Stop sleeping for the rate-limit reset once fewer than this many points remain.
POINT_RESERVE = 80

# WCL encounter id -> KeyComp dungeon key (matches Dungeons.lua D.order)
ENCOUNTERS = {
    112526: "ALGETHAR_ACADEMY",
    12811:  "MAGISTERS_TERRACE",
    12874:  "MAISARA_CAVERNS",
    12915:  "NEXUS_POINT_XENAS",
    10658:  "PIT_OF_SARON",
    361753: "SEAT_OF_THE_TRIUMVIRATE",
    61209:  "SKYREACH",
    12805:  "WINDRUNNER_SPIRE",
}

MEDAL = {"gold": "g", "silver": "s", "bronze": "b"}


# --------------------------------------------------------------------- auth ---
def get_token():
    with open(CREDS, encoding="utf-8") as fh:
        o = json.load(fh)["oauth"]
    body = urllib.parse.urlencode({"grant_type": "client_credentials"}).encode()
    auth = base64.b64encode(f"{o['client_id']}:{o['client_secret']}".encode()).decode()
    req = urllib.request.Request(o["token_url"], data=body, method="POST")
    req.add_header("Authorization", "Basic " + auth)
    req.add_header("Content-Type", "application/x-www-form-urlencoded")
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)["access_token"]


def _is_rate_limit(msg):
    m = msg.lower()
    return "rate limit" in m or "exceeded" in m or "throttle" in m


def gql(token, query, retries=10):
    """POST a GraphQL query. Survives rate-limit windows: HTTP 429 honours the
    Retry-After header (a full +10 pull spends multiple hourly budgets), and a
    GraphQL-level rate-limit error backs off rather than crashing. Other 5xx get
    a short exponential backoff. Proactive pacing (see Budget) keeps us from
    hitting these in the common case; this is the safety net."""
    payload = json.dumps({"query": query}).encode()
    for attempt in range(retries):
        req = urllib.request.Request(GQL, data=payload, method="POST")
        req.add_header("Authorization", "Bearer " + token)
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=60) as r:
                data = json.load(r)
            errs = data.get("errors")
            if errs:
                msg = json.dumps(errs)
                if _is_rate_limit(msg) and attempt < retries - 1:
                    wait = min(2 ** attempt * 5, 300)
                    print("  GraphQL rate-limit; backoff %ds" % wait, file=sys.stderr)
                    time.sleep(wait)
                    continue
                raise RuntimeError(msg)
            return data
        except urllib.error.HTTPError as e:
            if e.code == 429 and attempt < retries - 1:
                ra = e.headers.get("Retry-After")
                wait = int(ra) if (ra and ra.isdigit()) else min(2 ** attempt * 5, 300)
                print("  HTTP 429; sleeping %ds (Retry-After=%s)" % (wait, ra), file=sys.stderr)
                time.sleep(wait)
                continue
            if e.code in (500, 502, 503, 504) and attempt < retries - 1:
                wait = 2 ** attempt * 3
                print("  HTTP %d; backoff %ds" % (e.code, wait), file=sys.stderr)
                time.sleep(wait)
                continue
            raise
    raise RuntimeError("exhausted retries")


def rate_limit(token):
    """(limitPerHour, pointsSpentThisHour, pointsResetIn) or None on failure."""
    q = "{ rateLimitData { limitPerHour pointsSpentThisHour pointsResetIn } }"
    try:
        d = gql(token, q)["data"]["rateLimitData"]
        return d["limitPerHour"], d["pointsSpentThisHour"], d["pointsResetIn"]
    except Exception:
        return None


class Budget:
    """Proactive pacing against WCL's hourly point budget. Before risky work we
    ask the API how many points are left and, if under POINT_RESERVE, sleep until
    the window resets — so a multi-hour pull glides through windows instead of
    triggering 429 storms."""
    def __init__(self, token):
        self.token = token

    def wait(self):
        info = rate_limit(self.token)
        if not info:
            return
        limit, spent, reset_in = info
        remaining = limit - spent
        if remaining <= POINT_RESERVE:
            nap = max(int(reset_in) + 3, 5)
            print("  [budget] %d/%d points left; sleeping %ds for reset"
                  % (remaining, limit, nap), file=sys.stderr)
            time.sleep(nap)


# ---------------------------------------------------------------- normalize ---
def _ascii_lower(s):
    """ASCII-only lowercasing, matching WoW's C-locale string.lower so keys
    computed here match keys computed in-client. Non-ASCII chars pass through."""
    out = []
    for ch in s:
        o = ord(ch)
        out.append(chr(o + 32) if 65 <= o <= 90 else ch)
    return "".join(out)


def norm(s):
    """Strip spaces + apostrophes + hyphens, ASCII-lower. Run identically on both
    sides so the in-client lookup reproduces the key from an in-game Name-Realm:
    WCL's server.name, its slug, and GetNormalizedRealmName() all collapse to the
    same token (e.g. "twistingnether"). Non-Latin realms (RU/KR/CN/TW) are the
    only case this can't reconcile — they'd need a per-region realm-name map."""
    for ch in (" ", "'", "-", "’"):
        s = s.replace(ch, "")
    return _ascii_lower(s)


def char_key(name, realm):
    return norm(name) + "-" + norm(realm)


# ------------------------------------------------------------------ harvest ---
def harvest(token, enc_id, label, min_key, max_key, max_pages, regions, budget=None):
    """Best run per character for one encounter, scanning key-level brackets
    min_key..max_key. WCL's bracket arg is offset by one (bracket B -> key B+1),
    so key K is bracket K-1. Each bracket is paged to WCL's own end (hasMorePages),
    or to max_pages when max_pages > 0 (0 = unlimited). Keeps each character's
    HIGHEST key, tie-broken by higher dps. Climbing stops once a bracket comes
    back empty: the logged population only thins as keys rise, so an empty bracket
    means every higher one is empty too.

    Keyed by (region, char_key): realm names repeat across regions (Ragnaros,
    Ravencrest, Kil'jaeden, ... exist in both US and EU), so a region-less key
    would let one region's character clobber the other's on a multi-region pull."""
    best = {}  # (region, char_key) -> record
    for klvl in range(min_key, max_key + 1):
        bracket = klvl - 1
        if budget:
            budget.wait()
        page = 1
        rows_seen = 0
        while max_pages <= 0 or page <= max_pages:
            if budget and page % 25 == 0:
                budget.wait()
            q = ('{ worldData { encounter(id: %d) { characterRankings('
                 'metric: dps, bracket: %d, page: %d) } } }') % (enc_id, bracket, page)
            cr = gql(token, q)["data"]["worldData"]["encounter"]["characterRankings"]
            if not isinstance(cr, dict):
                break
            rankings = cr.get("rankings") or []
            if not rankings:
                break
            rows_seen += len(rankings)
            for row in rankings:
                server = row.get("server") or {}
                region = (server.get("region") or "").upper()
                if regions and region not in regions:
                    continue
                name = row.get("name") or ""
                realm = server.get("name") or ""
                if not name or not realm:
                    continue
                ck = char_key(name, realm)
                key_level = int(row.get("hardModeLevel") or row.get("bracketData") or klvl)
                dps = int(round(row.get("amount") or 0))
                rec = best.get((region, ck))
                if rec and (rec["key"] > key_level or (rec["key"] == key_level and rec["dps"] >= dps)):
                    continue  # already have a better (higher key, then higher dps) run
                best[(region, ck)] = {
                    "region": region, "name": name, "realm": realm,
                    "class": row.get("class") or "", "spec": row.get("spec") or "",
                    "dps": dps, "key": key_level,
                    "score": int(round(row.get("score") or 0)),
                    "medal": MEDAL.get(row.get("medal"), ""),
                }
            if not cr.get("hasMorePages"):
                break
            page += 1
        print("  [%-26s +%2d] %3d page(s) %6d rows  (chars %d)"
              % (label, klvl, page, rows_seen, len(best)), file=sys.stderr)
        if rows_seen == 0:
            break  # empty bracket -> every higher key is empty too; stop climbing
    return best


# --------------------------------------------------------------- lua output ---
def lua_str(s):
    out = []
    for ch in s:
        o = ord(ch)
        if ch == "\\":
            out.append("\\\\")
        elif ch == '"':
            out.append('\\"')
        elif o < 32:
            out.append("\\%d" % o)
        else:
            out.append(ch)
    return '"' + "".join(out) + '"'


def shard_path(out_path, i):
    """tools pass the header path as out_path; shard i lives beside it."""
    out_dir = os.path.dirname(out_path) or "."
    return os.path.join(out_dir, "WCLData%02d.lua" % i)


def shard_of(region, key):
    """Stable, balanced 1..SHARDS bucket for a char (crc32 so it's reproducible
    across runs -> deterministic diffs for git / CurseForge)."""
    return zlib.crc32(("%s/%s" % (region, key)).encode("utf-8")) % SHARDS + 1


def _entry_value(r):
    dparts = []
    for dk in sorted(r["d"]):
        d = r["d"][dk]
        dparts.append("%s={k=%d,dps=%d,sc=%d,md=%s}" % (
            dk, d["key"], d["dps"], d["score"], lua_str(d["medal"])))
    return "{n=%s,rl=%s,cl=%s,sp=%s,bk=%d,bs=%d,d={%s}}" % (
        lua_str(r["name"]), lua_str(r["realm"]), lua_str(r["class"]),
        lua_str(r["spec"]), r["bestKey"], r["bestScore"], ",".join(dparts))


def emit_lua(chars_by_region, out_path, stats):
    """Write a header file (out_path) + SHARDS data files beside it. The header
    sets generated/season/zone and ensures KeyCompWCL.chars; each shard appends
    its slice. All files are non-destructive (`x or {}`), so TOC load order can't
    corrupt the merged table, and each is its own Lua chunk with its own constant
    budget. In-client WCL.lua reads the merged KeyCompWCL.chars unchanged."""
    generated = stats.get("generated") or int(time.time())
    out_dir = os.path.dirname(out_path) or "."
    os.makedirs(out_dir, exist_ok=True)

    hdr = [
        "-- KeyComp WCL Mythic+ data HEADER (auto-generated by tools/wcl_build.py)",
        "-- DO NOT EDIT BY HAND. Source: Warcraft Logs API v2, zone %d (%s)." % (ZONE, SEASON),
        "-- generated=%d  unique_chars=%d  rows=%d  shards=%d" %
        (generated, stats["chars"], stats["rows"], SHARDS),
        "-- Data is sharded across WCLData01..%02d.lua so each Lua chunk stays" % SHARDS,
        "-- under the 5.1 compiler's ~262k-constants-per-function ceiling.",
        "local _, ns = ...",
        "KeyCompWCL = KeyCompWCL or { chars = {} }",
        "KeyCompWCL.generated = %d" % generated,
        "KeyCompWCL.season = %s" % lua_str(SEASON),
        "KeyCompWCL.zone = %d" % ZONE,
        "KeyCompWCL.chars = KeyCompWCL.chars or {}",
        "if ns then ns.WCLData = KeyCompWCL end",
        "",
    ]
    with open(out_path, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(hdr))

    # buckets[i] = { region -> { key -> rec } }
    buckets = [dict() for _ in range(SHARDS)]
    for region in sorted(chars_by_region):
        for key, rec in chars_by_region[region].items():
            buckets[shard_of(region, key) - 1].setdefault(region, {})[key] = rec

    for i in range(SHARDS):
        lines = [
            "-- KeyComp WCL data shard %02d/%d (auto-generated; DO NOT EDIT)." % (i + 1, SHARDS),
            "local _, ns = ...",
            "KeyCompWCL = KeyCompWCL or { chars = {} }",
            "KeyCompWCL.chars = KeyCompWCL.chars or {}",
            "local C = KeyCompWCL.chars",
        ]
        for region in sorted(buckets[i]):
            chars = buckets[i][region]
            lines.append("C[%s] = C[%s] or {}" % (lua_str(region), lua_str(region)))
            lines.append("do local R = C[%s]" % lua_str(region))
            for key in sorted(chars):
                lines.append("R[%s]=%s" % (lua_str(key), _entry_value(chars[key])))
            lines.append("end")
        lines.append("")
        with open(shard_path(out_path, i + 1), "w", encoding="utf-8", newline="\n") as fh:
            fh.write("\n".join(lines))


# --------------------------------------------------------------- reshard (no API)
# Re-emit an existing baked dataset into the sharded layout offline — used to
# migrate the current single-file data and to verify emit without the API.
RE_REGION = re.compile(r'^(?:\[|C\[)"(US|EU|KR|TW|CN)"\]')
RE_ENTRY = re.compile(
    r'^(?:R)?\["(?P<key>.+?)"\]=\{n="(?P<n>.*?)",rl="(?P<rl>.*?)",'
    r'cl="(?P<cl>.*?)",sp="(?P<sp>.*?)",bk=(?P<bk>\d+),bs=(?P<bs>\d+),d=\{(?P<d>.*)\}\},?$')
RE_DUN = re.compile(r'(\w+)=\{k=(\d+),dps=(\d+),sc=(\d+),md="(.*?)"\}')
RE_GEN = re.compile(r'generated\D*(\d+)')


def load_flat(files):
    """Parse one or more baked WCLData files (old single-file or new sharded)
    back into a {region: {key: rec}} structure. Returns (by_region, generated,
    n_rows)."""
    by_region, generated, n_rows = {}, None, 0
    region = None
    for path in files:
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
                em = RE_ENTRY.match(s)
                if not em or region is None:
                    continue
                d = {}
                for dk, k, dps, sc, md in RE_DUN.findall(em.group("d")):
                    d[dk] = {"key": int(k), "dps": int(dps), "score": int(sc), "medal": md}
                n_rows += len(d)
                by_region.setdefault(region, {})[em.group("key")] = {
                    "name": em.group("n"), "realm": em.group("rl"),
                    "class": em.group("cl"), "spec": em.group("sp"),
                    "bestKey": int(em.group("bk")), "bestScore": int(em.group("bs")), "d": d,
                }
    return by_region, generated, n_rows


def report(out_path, by_region, n_chars, n_rows):
    total = os.path.getsize(out_path)
    for i in range(1, SHARDS + 1):
        p = shard_path(out_path, i)
        if os.path.exists(p):
            total += os.path.getsize(p)
    print("\nwrote %s + %d shards" % (out_path, SHARDS))
    print("  regions: %s" % ", ".join("%s=%d" % (r, len(by_region[r])) for r in sorted(by_region)))
    print("  unique chars: %d | dungeon runs: %d | total size: %.2f MB" %
          (n_chars, n_rows, total / 1048576.0))


def do_reshard(src, out_path):
    d = os.path.dirname(os.path.abspath(src))
    files = [src] + sorted(
        os.path.join(d, f) for f in os.listdir(d)
        if re.match(r'^WCLData\d{2}\.lua$', f) and os.path.join(d, f) != os.path.abspath(src))
    seen, uniq = set(), []
    for f in files:
        a = os.path.abspath(f)
        if a not in seen and os.path.exists(f):
            seen.add(a)
            uniq.append(f)
    print("resharding from: %s" % ", ".join(os.path.basename(f) for f in uniq))
    by_region, generated, n_rows = load_flat(uniq)
    n_chars = sum(len(v) for v in by_region.values())
    emit_lua(by_region, out_path, {"chars": n_chars, "rows": n_rows, "generated": generated})
    report(out_path, by_region, n_chars, n_rows)


# ---------------------------------------------------------------------- main --
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--min-key", type=int, default=10, help="lowest key level to harvest (bracket = key-1)")
    ap.add_argument("--max-key", type=int, default=30, help="highest key level to scan (an empty bracket stops the climb)")
    ap.add_argument("--pages", type=int, default=0, help="max pages per key bracket; 0 = unlimited (page to WCL's end)")
    ap.add_argument("--regions", default="", help="comma list e.g. US,EU (blank = all)")
    ap.add_argument("--out", default=os.path.join(REPO, "KeyComp", "Data", "WCLData.lua"))
    ap.add_argument("--reshard", nargs="?", const="", metavar="SRC",
                    help="skip the API: re-emit existing baked data (SRC, or --out) into the sharded layout")
    args = ap.parse_args()

    if args.reshard is not None:
        do_reshard(args.reshard or args.out, args.out)
        return

    regions = set(x.strip().upper() for x in args.regions.split(",") if x.strip())
    token = get_token()
    budget = Budget(token)
    print("authenticated. harvesting %d dungeons, keys %d-%d, pages=%s%s" %
          (len(ENCOUNTERS), args.min_key, args.max_key,
           ("unlimited" if args.pages <= 0 else args.pages),
           (" [regions: %s]" % ",".join(sorted(regions))) if regions else ""))

    # merge per-character across dungeons, keyed by region then char_key
    by_region = {}
    total_rows = 0
    for enc_id, dkey in ENCOUNTERS.items():
        best = harvest(token, enc_id, dkey, args.min_key, args.max_key, args.pages, regions, budget)
        total_rows += len(best)
        for (region, ck), rec in best.items():
            bucket = by_region.setdefault(region, {})
            c = bucket.get(ck)
            if not c:
                c = {"name": rec["name"], "realm": rec["realm"], "class": rec["class"],
                     "spec": rec["spec"], "bestKey": 0, "bestScore": 0, "d": {}}
                bucket[ck] = c
            c["d"][dkey] = {"key": rec["key"], "dps": rec["dps"],
                            "score": rec["score"], "medal": rec["medal"]}
            if rec["key"] > c["bestKey"]:
                c["bestKey"] = rec["key"]
            if rec["score"] > c["bestScore"]:
                c["bestScore"] = rec["score"]
        print("  %-26s %5d chars" % (dkey, len(best)))

    n_chars = sum(len(v) for v in by_region.values())
    emit_lua(by_region, args.out, {"chars": n_chars, "rows": total_rows})
    report(args.out, by_region, n_chars, total_rows)


if __name__ == "__main__":
    main()
