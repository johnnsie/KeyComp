# wow-addons

WoW addons. First up: **KeyComp**.

---

# KeyComp

A floating, tabbed panel you keep open **while forming a Mythic+ group** as a
**Discipline Priest**. You (Disc) cover Magic + Disease dispels and Magic purge;
KeyComp reads your live party, works out what utility the rest of the comp is
missing for the chosen dungeon, and ranks the people applying to your group by
how well they fill those gaps.

It auto-opens while you're forming a group (grouped or advertising a Premade
listing, not full, not inside an instance) and refreshes every ~3s.

## Install

The repo's `KeyComp` folder is the addon. Link or copy it into your AddOns dir:

```
World of Warcraft\_retail_\Interface\AddOns\KeyComp\
```

A directory junction lets you edit in the repo and have changes go live on
`/reload` (this repo is already junctioned on the dev machine). If KeyComp shows
as out of date at character select, tick **Load out of date AddOns** — the
`## Interface` number (120000 / Midnight 12.0.0) just needs to match your build.

## Usage

- `/kc` or `/keycomp` — toggle the panel
- `/kc show` / `/kc hide`
- `/kc auto` — toggle auto-open-while-forming
- `/kc debug` — print what the dungeon auto-detector currently sees (for diagnosing a missed match)
- Drag the panel body to move it (position saved). `<` `>` cycle dungeons.
- **Auto-detect** follows the dungeon you're inside, or the one your Premade
  listing is for.

## The three tabs

### Coverage
- **Status strip** — one icon per removal type (Magic / Disease / Curse / Poison
  / Bleed / Soothe / Purge), tinted **green = covered**, **amber = maybe**
  (spec/talent/pet unconfirmed), **red = missing** (desaturated). Hover an icon
  for who covers it and what to bring.
- **Group** — your party; hover a name for that member's full capabilities.
- **Utility** — short **Kicks** (wants 2; long interrupts like Shadow Silence /
  Quell / Solar Beam shown as "+N long"), **Lust**, **Battle rez**.
- **Gaps** — everything still missing in one line.
- **Buffs missing** — raid buffs the group lacks, each tagged with the class icon
  that brings it (Intellect=Mage, Stamina=Priest, Attack Power=Warrior,
  Versatility=Druid, Chaos Brand=DH, Mystic Touch=Monk, Skyfury=Shaman).

### Applicants
Live people applying to your Premade listing, **grouped by role** (Tanks → DPS →
Healers) in coloured boxes, **collapsed to the top N per class** (N configurable,
default 3 — the class-comparison view). Each row is columned for alignment:

`Name (+ group/"+N" badge) · M+ score · WCL DPS · Abilities (gap-fill icons) · [Invite] [X]`

Columns are headed **M+ / DPS / Brings** so multiple applicants of a class line up
as a clean table under the lead row.

- **WCL DPS** (purple) — the applicant's logged Mythic+ DPS for the selected
  dungeon, from a baked Warcraft Logs dataset (see "WCL data" below). Shows their
  best logged key (grey `+N`) if they're in the dataset but have no log for this
  dungeon, and blank if they're not in it at all (the dataset is top-ladder
  only). Hover a row for the full per-dungeon breakdown (key / dps / run score /
  medal) and the data's age.
- A condensed recap of what's still missing sits on top.
- **+N** (blue) after a class's lead name = N more applicants of that class not
  shown; hover lists them (with M+ / ilvl).
- **G{n}** (orange) after a name flags a premade group of n members — inviting one
  invites all; the hover spells out every member.
- **Invite** highlights the row green immediately and stays until they join or you
  decline; cancelled / expired / declined / timed-out applicants drop within ~3s.
- Ranking within a class uses the priority formula (below).

### Info
Per-dungeon **utility checklist**: every notable mob → ability, colour-coded
**green = you (Disc) cover it** vs **red = needs another class** (with the type),
and a kick marker on interrupt-first casts. Also holds the **Panel scale** and
**Applicants per class** sliders.

## How it works

- **Capability matrix** (`Capabilities.lua`) — what every class/spec can do:
  magic/disease/poison/curse dispels, purge, soothe, bleed, short-kick vs long
  interrupt, lust, battle rez. Resolved from a teammate's class + **assigned
  role** (reliable for the healer-only magic case) or exact spec for yourself.
  Verified against Warcraft Wiki + Wowhead for Midnight 12.0.x.
- **Coverage engine** (`Coverage.lua`) — combines the live roster against the
  dungeon's needs into the green/amber/red status, utility counts, gaps, and buffs.
- **Priority formula** (`Applicants.lua` → `PriorityScore`, tunable `WEIGHTS`) —
  ranks applicants of a class by **M+ score (≈RIO) + item level + best logged key
  for the selected dungeon**. The best-key term is now sourced from the baked WCL
  data (`WCL.lua` → `GetBestKey`); applicants not in the dataset contribute 0
  there and rank on M+ score + ilvl as before.

## Data sources

Per-dungeon dispel/purge/soothe/bleed and the Info checklist come from the *Disc
Priest Dispel & Purge Guide — WoW Midnight S1* (method.gg by Tactyks, + Wowhead
and the Midnight S1 debuffs list by Gerrit Alex). The class capability matrix is
the standard WoW dispel/interrupt data, verified against Warcraft Wiki + Wowhead
(May 2026, Midnight 12.0.x).

## WCL data (Warcraft Logs M+ DPS)

WoW addons can't reach the internet, so KeyComp can't query Warcraft Logs live.
Instead — same trick the RaiderIO addon uses for its score database — the data is
**baked into a Lua file and shipped with the addon**, refreshed by re-publishing:

1. `tools/wcl_build.py` authenticates to the **WCL API v2** (client-credentials;
   creds in `.secrets/wcl-credentials.json`, gitignored, outside the addon) and
   harvests the Midnight S1 **Mythic+ DPS rankings** (zone 47) across all 8
   dungeons, **per key-level bracket from +10 up** (WCL's `bracket` arg is offset
   by one: `bracket = keyLevel - 1`). It pages each bracket to WCL's own end and
   keeps each character's highest key per dungeon, writing the **sharded** data
   set under `KeyComp/Data/` (keyed `chars[REGION][name-realm]`). De-duplication
   is keyed by **(region, name-realm)** — realm names repeat across regions
   (Ragnaros, Ravencrest, Kil'jaeden, … exist in both US and EU), so a region-less
   key would let one region's character clobber the other's on a multi-region pull.
2. Ship the refreshed files via a CurseForge update; players get them on addon update.
3. In-client, `WCL.lua` looks up each applicant by name-realm and the Applicants
   tab shows their DPS + feeds their logged key into the priority formula.

Run it with `python tools/wcl_build.py --regions US,EU` (options: `--min-key`
(default **10**), `--max-key`, `--pages` per bracket (default **0 = unlimited**,
page to WCL's end), `--out PATH`). Inspect the result with `python tools/wcl_show.py`.
To re-emit an existing dataset into the sharded layout **without** hitting the API
(e.g. after a layout change), run `python tools/wcl_build.py --reshard`.

**Sharded output (why):** a single Lua file compiles into one function, and Lua
5.1 caps a function at **~262 143 constants**. The full +10 population (tens of
thousands of characters) blows past that as one literal and silently **fails to
load**. So the builder writes a tiny `WCLData.lua` header plus
`WCLData01.lua … WCLData24.lua` shards (chars spread by a stable CRC hash); each
shard is its own chunk with its own constant budget. All files are
non-destructive (`x = x or {}`), so `.toc` load order can't corrupt the merged
`KeyCompWCL.chars`, and `WCL.lua` reads it unchanged. RaiderIO shards its DB the
same way and for the same reason.

**Scale & cost.** A +10 pull is far bigger than the old +18 floor: expect on the
order of 50k–100k characters and a **~12–24 MB** baked data set (the +18-only set
was ~2.4 MB / 10.5k chars). Lower keys hold most of the logged population, so the
pull spans **multiple hourly rate-limit windows** (the WCL free budget is
3600 points/hr) and can take **hours** of wall-clock — run it detached. The tool
paces itself: it polls `rateLimitData` and sleeps until reset when points run low,
and `gql()` honours `Retry-After` / backs off on rate-limit errors rather than
crashing, so a long pull resumes through each window. Climbing stops automatically
once a bracket comes back empty (population only thins as keys rise).

**Why bracket-by-bracket:** plain top-DPS pages skew to the highest keys and WCL's
ranking lists end well before page 50, so paging down never reaches the floor.
Querying each key bracket directly gives even coverage from +10 up. It still only
covers players who **upload logs** — applicants who don't log read blank (a
RaiderIO-score baseline would be the fix for universal coverage).

**Realm matching** is by symmetric normalisation, not a slug table, *by design*.
Both sides run the same `norm()` — strip spaces / apostrophes / hyphens, then
ASCII-lowercase — so the WCL `server.name` ("Twisting Nether"), the WCL slug
("twisting-nether"), and the in-client `GetNormalizedRealmName()` ("TwistingNether")
all collapse to the same `"twistingnether"` key. A slug table would buy nothing for
Latin realms (you can't recover a slug's hyphen positions from the in-client string
anyway). The only residual gap is **non-Latin realms** (RU Cyrillic, KR/CN/TW)
where WCL's stored name and the client string can differ in script — a per-region
realm-name map is the fix there, and only there.

Other known limitations: DPS metric only (tanks/healers absent); manual publish for
now (daily automation is a later step).

## File layout

```
KeyComp/
  KeyComp.toc       load order + metadata
  Capabilities.lua  class/spec/role -> utility matrix; raid buffs
  Dungeons.lua      8 dungeons: discCovers / required / abilities checklist
  Roster.lua        read the live party
  Coverage.lua      compute coverage + utility + buffs
  Recommend.lua     per-removal-type "who brings this" hint text
  Data/WCLData.lua  baked WCL data HEADER (generated/season/zone; auto-generated)
  Data/WCLData01..24.lua  baked WCL M+ DPS shards (auto-generated; shipped)
  WCL.lua           look up an applicant's baked WCL data (name-realm -> record)
  Applicants.lua    read/score live LFG applicants (priority formula)
  Core.lua          events, saved vars, slash, 3s refresh ticker
  UI.lua            the tabbed panel
tools/
  wcl_build.py      builds Data/WCLData*.lua from the Warcraft Logs API (run daily)
  wcl_show.py       inspect the baked dataset (summary + DPS sample)
```

## Limitations / notes

- **Untested caveat:** much of this was iterated without an in-client lint. If
  something errors on load, `/console scriptErrors 1` and check the first lines.
- Teammate spec is inferred from assigned role; your own spec is read exactly.
  Spec names in the matrix are enUS.
- Applicant data depends on the `C_LFGList` API; status is read from
  `applicationStatus` / `pendingApplicationStatus`.
- The **Warcraft Logs** integration (above) harvests **+10 and up** and shards the
  output so it loads in-client; it's still **DPS-metric only** (tanks/healers
  absent) and **manually published** (automated daily publishing is the next step).
- A future **RaiderIO** integration could add near-universal M+ score coverage as
  a baseline for applicants who don't appear in the WCL dataset (non-loggers).
