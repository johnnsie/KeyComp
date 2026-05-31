# Publishing KeyComp to CurseForge

The Upload API can only add files to a project that **already exists**. So the
first publish is a one-time web setup; after that, updates are one command.

## Artifacts (ready in this repo)
- **Zip:** `dist/KeyComp-0.1.0.zip` — rebuild any time with `py -3.12 tools/package_addon.py`
- **Summary + description:** `store/listing.md`
- **Logo (avatar):** `store/logo/C_final-400.png` (400×400)
- **Game version:** WoW Retail **12.0.7** (CurseForge id `16238`)
- **Token:** `.secrets/curseforge.json` (also where the project id goes once it exists)

## One-time: create the project (web)
1. Go to **authors.curseforge.com** and sign in (CurseForge / Overwolf account).
2. **Create Project** → Game: **World of Warcraft** → Type: **Addon**.
3. **Name:** `KeyComp`. **Summary:** paste the one-liner from `store/listing.md`.
4. **Categories:** closest fits — *Combat*, *Buffs & Debuffs* (dispels), and/or *Map & Minimap* (minimap button). Pick 1–3.
5. **Avatar:** upload `store/logo/C_final-400.png`.
6. **Description:** paste the Description section from `store/listing.md` into the rich editor.
7. Save / create.

## First file upload (web, during or right after creation)
- Upload **`dist/KeyComp-0.1.0.zip`**.
- **Release type:** `Alpha` (untested in a live client — keep it alpha until smoke-tested).
- **Game version:** `12.0.7`.
- **Changelog:** the v0.1.0 block at the bottom of `store/listing.md`.

New projects are reviewed by CurseForge staff before they go live — expect a wait
(hours to a day or two). Submit, then check back.

## After approval: enable one-command updates
1. Open the project page; copy its **numeric Project ID** (shown in the About box
   and in the URL).
2. Put it in `.secrets/curseforge.json` → `"project_id": <number>`.
3. Validate the token and the API path:
   ```
   py -3.12 tools/cf_publish.py --check
   ```
4. Future releases (e.g. the daily WCL-refreshed build) — repackage then upload:
   ```
   py -3.12 tools/package_addon.py
   py -3.12 tools/cf_publish.py --zip dist/KeyComp-0.1.0.zip --release alpha \
        --display-name "KeyComp 0.1.0" --changelog-file store/listing.md
   ```
   (omit `--game-version` and it auto-targets the latest retail patch). Run with
   `--dry-run` first to print the exact metadata without uploading.

## Notes
- The token must belong to the **same account** that owns the project.
- Bumping for a new patch: edit `## Interface` in `KeyComp/KeyComp.toc`, repackage,
  upload tagged to the new game version.
- Same flow works for **KeyQueue** later (its own project + id).
