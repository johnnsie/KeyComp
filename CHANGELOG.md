# KeyComp changelog

## v0.2.5
- **Warcraft Logs data refreshed** to the current EU + US Mythic+ ladder.
- **Shaman curse dispel corrected** — Elemental / Enhancement can remove Curse via the Cleanse Spirit talent, so it now shows as a *potential* ("maybe") dispel instead of Resto-only.

## v0.2.4
- **Warcraft Logs data refreshed** to the current EU + US Mythic+ ladder.

## v0.2.3
- Maintenance: updated the addon author handle.

## v0.2.2
- **Fixed the tank / heal / dps role icons** on nested premade members and the Coverage role-composition recap — they now use Midnight's role atlases instead of a texture path that rendered blank.
- **Applicant M+ rating tiers**: scores now show **gold at 3700+** and **platinum at 4000+**, above the game's normal rarity colors.

## v0.2.1
WCL data refresh + a clarity pass on the Advanced coverage panel.

- **Advanced panel reworked.** It now leads with **Your Job** — the dispels (and interrupt) your *spec* is on the hook for in this dungeon — then **Every Cast** as a scannable covered / gap checklist with you shown as "You", then **Raid Buffs & Debuffs** with clear have / missing marks.
- **Fixed missing glyphs.** Several status marks and the nested premade-member connector were rendering as empty boxes in the default game font; they now use proper textures (green check / red X) and safe characters.
- **Warcraft Logs data refreshed** to the current EU + US Mythic+ ladder.

## v0.2.0
Applicants + Coverage redesign.

- **Premade applicants** now show their group members nested under the leader (one Invite takes the whole group), each with a tank / healer / dps role icon.
- Extra same-class applicants collapse behind a **"+N more"** toggle instead of stacking.
- **Applicant spec** is read straight from the group finder, so feral vs balance, elemental vs resto, etc. are told apart — and that feeds the dispel / interrupt coverage.
- **Coverage condensed to two tabs**: the old Info tab is folded into a collapsible **Advanced** section. The main view is a minimalist recap — the ability strip, kick / lust / battle-rez cells, and a role-composition row (lit = filled, dim = still needed).
- **Coverage roster shows item level + M+ rating**, cached from each applicant's sign-up (no inspect needed).
- Applicant columns are color-graded by M+ score rarity, item level, and logged Warcraft Logs DPS (gold / silver / bronze); rows highlight on hover.

## v0.1.3
- Minimap button hover highlight fix (grey box → soft glow).

## v0.1.1
- First automated release (CurseForge + GitHub Release via CI).
