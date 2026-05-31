# KeyQueue

The **seeker-side companion to KeyComp**. Where KeyComp helps you *form* a Mythic+
group as the leader, KeyQueue helps you *get into* one as an applicant — it keeps
**auto-applying to Premade groups until you get invited**.

Built for the case where invites are scarce (non-meta spec, e.g. **Discipline
Priest**): you set a key level and KeyQueue fans out — keeping several applications
pending at once, refilling as they decline/expire, blacklisting anyone who declines
so it moves on, and **alarming (sound + screen flash) the moment a group invites
you** — then, if you turn that invite down, picking the search right back up.

It also only targets **dungeons you haven't completed at that key yet** (read from
your season-best per dungeon), so it never wastes applications on keys you already
have — and a dungeon drops off the list the instant you time it.

> **Mythic+ has no real matchmaking queue.** It runs through the Premade Group
> Finder (`C_LFGList`). "Queue" here means: search listings → rank by fit → apply,
> automatically and continuously, so it *feels* like a queue.

## Install

The `dungeon-finder` folder is the addon. Link or copy it into your AddOns dir:

```
World of Warcraft\_retail_\Interface\AddOns\dungeon-finder\
```

A directory junction lets you edit in the repo and have changes go live on
`/reload`. If it shows as out of date at character select, tick **Load out of date
AddOns** — the `## Interface` number (120000 / Midnight 12.0.0) just needs to match
your build.

## Usage

- `/kq` — toggle the panel
- `/kq start` — begin the queue (also: the big **Start auto-queue** button)
- `/kq stop` — stop it
- `/kq auto` — toggle auto-apply on/off (off = assisted: you click Apply yourself)
- `/kq find` — jump to the Listings tab
- `/kq debug` — print what the search/filter/progress engine currently sees
- Drag the panel body to move it (position saved).

## The three tabs

### Queue  *(the console)*
Everything for hands-off queueing in one place:
- **Apply as** — Tank / Heal / DPS (defaults to your spec's role: Heal for Disc).
- **Key level** — `+19` and an optional `up to +N` (both 19 = exactly +19).
- **Target dungeons** — eight chips, one per Midnight S1 dungeon. In **auto** mode
  the chips you still need (season-best below your target) are lit; ones you've
  done show a green check and drop out. Click any chip to switch to **manual** and
  hand-pick; **Auto: needed only** resets it.
- **Auto-apply** + **how many applications to keep pending** (default 5).
- **Start auto-queue / Stop**, then a live status block: state, counters
  (searched · matched · applied · pending · declined), the next-up target, and a
  recent-activity log. An **INVITED by X** banner + sound + flash on an invite —
  then accept it, or decline to resume searching where you left off.

### Listings
The current ranked Mythic+ listings that match your criteria, each with a
one-click **Apply** (works even with auto-apply off, or if Blizzard throttles
scripted applies). Columns: `Group +key · Leader (score) · T H D slots · age`.
Your open role slot is highlighted; rows you've applied to / been invited by are
tinted.

### Settings
Max applies per session, minimum leader score, blacklist duration, skip
rating-gated listings, apply-to-unreadable-key toggle, clear blacklist, panel
scale, and the auto-apply caveat.

## How it works

- **`Search.lua`** — discovers the LFG category + Mythic+ activities (by the
  `isMythicPlusActivity` flag, with a name fallback), drives `C_LFGList.Search`,
  and normalizes each result into `{ dungeon, keyLevel, leader, score, role-slots,
  age, … }`. Keystone level is **parsed from the listing title/comment** (`+19`),
  because it isn't cleanly exposed per result.
- **`Progress.lua`** — your **season-best key per dungeon** (`C_MythicPlus` /
  `C_ChallengeMode`), so the filter can drop dungeons you've already done at the
  target. Refreshes when you finish a key.
- **`Filter.lua`** — resolves your settings into a criteria set, decides which
  listings qualify (dungeon needed · key in range · your role slot open · not
  rating-gated · not blacklisted), and ranks the survivors. Ranking favours
  **near-full, fresh** listings — the ones that pop soonest.
- **`Queue.lua`** — the engine. Tracks + ranks listings continuously; you fire each
  application from a hardware event (the keybind / "Apply to next best") since scripted
  applies from a timer are blocked by Blizzard. It reads application statuses to drive
  the invite lifecycle — **invited** (alarm + hold, one-tap paused), **you accept**
  (stop), **you decline** (resume + skip that leader a while), **they decline**
  (blacklist) — and stops on a full group.
- **`Core.lua`** — saved vars, events, the 3 s ticker, slash commands.
- **`UI.lua`** — the panel.

## Limitations / verify in-client

Much of this was iterated **without a live client** (same caveat KeyComp carries).
If something errors on load, `/console scriptErrors 1` and check the first lines,
then `/kq debug`. The spots most worth confirming live:

- **`C_LFGList.Search` signature.** It has drifted across patches; `Search.lua`
  tries a few arities. If Listings stays empty with groups clearly up, this is the
  first suspect — `/kq debug` shows how many M+ activities/listings it sees.
- **Auto-apply is best-effort.** `C_LFGList.ApplyToGroup` from a script may be
  rate-limited or blocked by Blizzard. If auto-apply doesn't fire, the **Apply
  buttons on the Listings tab** still work (one real click each — always allowed).
- **Result fields** (`leaderOverallDungeonScore`, `requiredDungeonScore`, `age`,
  `name`, `comment`) and **member-count keys** (`TANK/HEALER/DAMAGER`) are the
  standard ones but unconfirmed for Midnight.
- **Keystone level** comes from parsing the listing text; a listing with no
  readable `+N` is skipped in auto mode by default (toggle in Settings).
- **Progress** read shapes vary by patch and are parsed tolerantly; if it can't
  load, every dungeon is treated as "needed" (so nothing is wrongly excluded) and
  the Queue tab says so.

## File layout

```
dungeon-finder/
  dungeon-finder.toc   load order + metadata (Title: KeyQueue)
  Dungeons.lua         8 Midnight S1 dungeons; name match + "+key" parse
  Progress.lua         season-best key per dungeon -> "needed at +N" set
  Search.lua           discover M+ activities; drive search; read results
  Filter.lua           criteria -> match + fit-ranking
  Queue.lua            auto-apply engine: fan out, detect invite, blacklist
  Core.lua             saved vars, events, 3s ticker, slash
  UI.lua               Queue / Listings / Settings panel
```
