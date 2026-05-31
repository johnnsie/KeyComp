# Releasing KeyComp

**Status: live and automated.** KeyComp is published on CurseForge (project
**1559421** — https://www.curseforge.com/wow/addons/keycomp) and via GitHub
Releases. Pushing a version tag builds and publishes everything — nobody uploads
a file by hand.

## Quick release — the only steps you take
1. Bump `## Version:` in `KeyComp/KeyComp.toc` to the new version (it must match the tag).
2. Commit it.
3. Tag and push:
   ```
   git tag -a v0.1.2 -m "what changed"
   git push origin main --tags
   ```
GitHub Actions does the rest: build → CurseForge upload → GitHub Release.

## How it works — manual vs automated

**You (local `git`):** bump the version, commit, push a tag. The **tag push is the
trigger**. None of this touches CurseForge directly.

**GitHub Actions (cloud — `.github/workflows/release.yml`):** on a `v*` tag, a
GitHub-hosted runner:
1. checks out the repo, sets up Python 3.12,
2. **guards** that the tag matches `KeyComp.toc`'s `## Version:` (fails the run if not),
3. `python tools/package_addon.py KeyComp` → builds `dist/KeyComp-<ver>.zip` (forward-slash paths, single `KeyComp/` root),
4. `python tools/cf_publish.py … --release release` → **POSTs the zip to the CurseForge upload API** using the repo secrets,
5. `gh release create` → publishes a GitHub Release with the zip attached.

```
you (local):   edit toc version → commit → git push --tags
                                                   │  (tag triggers)
GitHub Actions:  build zip → cf_publish.py ──POST──▶ CurseForge upload API
                          └→ gh release create ────▶ GitHub Release
```

The CurseForge upload runs **inside CI**, calling CurseForge's API with a secret
token — that is why files land on CurseForge without anyone opening the website.

## One-time setup (already done — kept for reference / new machine / new addon)
1. **GitHub repo** — code pushed: https://github.com/johnnsie/KeyComp
2. **CurseForge project** — created on the website (the API cannot create one); see
   `store/DEPLOY.md`. Project ID **1559421**.
3. **Repo secrets** — GitHub → Settings → Secrets and variables → Actions:
   - `CF_API_KEY` = CurseForge upload token
   - `CF_PROJECT_ID` = `1559421`

   `gh secret set CF_API_KEY --repo johnnsie/KeyComp --body <token>`
4. **Workflow permissions** — read/write (for the Release step):

   `gh api --method PUT repos/johnnsie/KeyComp/actions/permissions/workflow -f default_workflow_permissions=write`

If the secrets are absent the workflow still makes the GitHub Release and just
**skips** the CurseForge step.

## The moving parts
- `.github/workflows/release.yml` — the tag-triggered CI workflow.
- `tools/package_addon.py` — builds the spec-correct zip from `KeyComp/`.
- `tools/cf_publish.py` — uploads to CurseForge. Reads `CF_API_KEY`/`CF_PROJECT_ID`
  from the environment in CI, or `.secrets/curseforge.json` locally. Auto-targets
  the latest retail game version unless `--game-version` is passed.

## CurseForge visibility (read this if "it uploaded but I can't see it")
A returned **file id** means the API accepted the upload — it is **not** the same
as the file being publicly visible. New files pass through CurseForge's
processing/approval queue before they show on the public page and in the app.
**Authoritative status:** authors.curseforge.com → KeyComp → **Files** (each file
shows Under Review / Approved / Rejected). The public page and the desktop app lag
and cache behind that.

## Local manual fallback (rarely needed)
Same upload without CI (reads `.secrets/curseforge.json`):
```
py -3.12 tools/package_addon.py KeyComp
py -3.12 tools/cf_publish.py --zip dist/KeyComp-<ver>.zip --release release --display-name "KeyComp <ver>"
```
`--dry-run` prints the request without uploading; `--check` validates the token.

## Troubleshooting
- **Run fails on the version guard** → tag `vX.Y.Z` ≠ toc `## Version:`. Bump the toc, re-tag.
- **Ran but nothing on CurseForge** → secrets not set; the CF step skipped with a message.
- **Uploaded but not visible** → CurseForge processing/approval queue (above); check the dashboard.
- **GitHub Release fails "Resource not accessible"** → workflow permissions aren't read/write (setup #4).
- **Rotated the CF token** → `gh secret set CF_API_KEY --repo johnnsie/KeyComp --body <new-token>` (and update `.secrets/curseforge.json` for local use).
- **KeyQueue** → identical flow; it just needs its own CurseForge project + a second workflow.

## History
- **v0.1.1** (2026-05-31) — first automated **Release**. Tag `v0.1.1` → CI built
  `KeyComp-0.1.1.zip`, uploaded to CurseForge (file id 8174740, game 12.0.7) and
  cut GitHub Release v0.1.1. (v0.1.0 was a manual alpha during project setup.)
