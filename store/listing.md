# KeyComp — store listing copy

Canonical marketing copy for CurseForge (and reusable for Wago / WoWInterface /
GitHub). Paste **Summary** into the project's summary field and **Description**
into the page body. CurseForge's editor accepts pasted formatted text; headings,
bold, and lists map over cleanly.

---

## Summary (one line)

> See exactly what your Mythic+ group is missing — dispels, interrupts, Lust, battle rez — live as you invite, plus which applicant fills the gap.

**Alternates:**
- Stop forming blind. KeyComp shows your Mythic+ group's dispel and utility coverage in real time, and ranks applicants by the gap they fill.
- A live coverage panel for Mythic+ group leaders: who covers what, what's missing, and who to invite next.

---

## Description (page body)

# KeyComp

**Build better Mythic+ groups. See what your comp is missing — live, as you invite.**

You're forming a key in the Premade Group Finder. A dozen applicants, thirty seconds to decide. Who actually covers the Hex in Maisara Caverns? Do you have two interrupts? A Bloodlust? A battle rez? **KeyComp answers all of that at a glance — and updates the instant someone joins.**

KeyComp is a floating panel that reads your live group and the dungeon you're about to run, then shows your dispel and utility coverage in plain green / amber / red — plus a ranked, filterable list of your applicants with the one thing that matters when you're choosing: **what gap each one fills.**

It's **descriptive, not bossy.** KeyComp shows you the facts — coverage, gaps, who brings what — and lets *you* make the call. No auto-inviting, no "optimal comp" lectures, no damage meter.

## Three tabs

### Coverage
A live status strip for the selected dungeon:
- **Removals** — Magic, Disease, Curse, Poison, Bleed, Soothe (enrage) and Purge, each lit by whether *someone in the group* can actually handle it.
- **Interrupts, graded by quality** — short kicks (Pummel, Mind Freeze, Kick…) counted separately from long or forced interrupts, because two reliable kicks beat one 45‑second silence.
- **Bloodlust / Heroism**, **battle rez**, and **raid buffs** — who brings them, what's missing.
- A one‑line readout: *"You cover N/M removal types · dispel load: HIGH."*
- A clear **gaps** list: every removal or utility the dungeon demands that nobody in the group covers yet.

### Applicants
Your live Premade applicants, read straight from the Group Finder and made useful:
- Grouped Tank → DPS → Healer and collapsed to the **top few per class**, so you compare like‑for‑like (configurable).
- Columns: name, their group, the utility they bring, **Mythic+ score**, and **logged Mythic+ DPS** from Warcraft Logs.
- A **priority ranking** that blends Mythic+ score, item level, and logged key DPS.
- See the **gap each applicant fills** before you invite — and that value stays stable as you invite others, because it's measured against the group's real needs, not a moving target.
- One‑click **Invite / Decline** right in the panel, with applied and invited rows highlighted.

### Info
A per‑dungeon **mob → ability checklist** for all eight Midnight Season 1 dungeons — what casts what, what to interrupt, what to dispel — so you understand *why* each coverage type matters. Plus panel scale and per‑class display options.

## Logged DPS, shipped with the addon
WoW's API can't reach Warcraft Logs in‑game, so KeyComp ships a baked snapshot of top‑ladder Mythic+ DPS rankings (the same approach Raider.IO's addon uses) and refreshes it on a regular cadence. Ranked players show their best logged DPS; everyone else falls back to score and item level. It's a top‑ladder snapshot, not a live meter.

## Works for every class
KeyComp reads your real spec and the live group's specs, so coverage is computed correctly whether you're a Discipline Priest with no kick of your own or a Demon Hunter who covers half the dispel chart. Built by a Disc main who got tired of guessing whether the group had a Soothe.

## The eight dungeons (Midnight Season 1)
Magister's Terrace · Maisara Caverns · Windrunner Spire · Nexus‑Point Xenas · Pit of Saron · Seat of the Triumvirate · Skyreach · Algeth'ar Academy

## Commands
- `/kc` — toggle the panel
- `/kc auto` — toggle auto‑open while forming a group
- `/kc minimap` — show / hide the minimap button
- `/kc demo` — fill the panel with sample data to explore the UI (`/kc demo off` to clear)
- `/kc debug` — diagnostics

The minimap button: **left‑click** to toggle, **right‑click** for auto‑open, **drag** to reposition.

## Install
1. Download and extract into `World of Warcraft\_retail_\Interface\AddOns\`.
2. Make sure the folder is named `KeyComp`.
3. Relaunch or `/reload`, then type `/kc`.

No external libraries required.

## Compatibility
WoW Retail — **Midnight 12.0.7**.

## Early release
v0.1.0. The core is complete and the class and dungeon data were checked against method.gg and Wowhead, but this is a fresh release — **bug reports and feature requests are very welcome.** If something looks off for your class or a dungeon, tell me what and where.

## Credits
- Dungeon dispel / interrupt data compiled from **method.gg** (Tactyks' Midnight dungeon guides).
- Logged DPS rankings from **Warcraft Logs**.

---

## Changelog — v0.1.0 (initial release)

```
Initial release.

- Live Coverage panel: Magic / Disease / Curse / Poison / Bleed dispels, Soothe
  (enrage) and Purge, graded green / amber / red against your live group.
- Interrupt quality (short kicks vs. long interrupts), Bloodlust / Heroism,
  battle rez and raid-buff tracking, with a clear "what's missing" gap list.
- Applicants tab: live Premade applicants grouped by role and class, ranked by
  Mythic+ score, item level and logged Mythic+ DPS, with one-click Invite /
  Decline and the gap each applicant fills.
- Per-dungeon mob -> ability checklist for all 8 Midnight Season 1 dungeons.
- Minimap button. Slash: /kc, /kc auto, /kc minimap, /kc demo.
- Works for every class and spec, not just healers.
```
