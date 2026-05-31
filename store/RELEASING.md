# Releasing KeyComp (automated)

Push a version tag → GitHub Actions builds the zip and publishes to CurseForge
+ a GitHub Release. Workflow: `.github/workflows/release.yml` (drives the same
`tools/package_addon.py` + `tools/cf_publish.py` you can run locally).

## One-time setup
1. **Create the public GitHub repo** and push (see below).
2. **Create the CurseForge project** on the website — see `store/DEPLOY.md` —
   and note its numeric **Project ID**.
3. GitHub repo → **Settings → Secrets and variables → Actions** → add:
   - `CF_API_KEY` = your CurseForge upload token *(rotate the one pasted in chat first)*
   - `CF_PROJECT_ID` = the numeric project id
4. **Settings → Actions → General → Workflow permissions → Read and write**
   (else the GitHub Release step fails with "Resource not accessible").

## First push to GitHub
Create an **empty** repo on github.com (Public, no README/.gitignore/license), then:
```
git remote add origin https://github.com/<you>/<repo>.git
git push -u origin main
```
(The initial commit is already made locally; secrets are gitignored and audited out.)

## Cut a release
1. Bump `## Version:` in `KeyComp/KeyComp.toc` so it **matches the tag** (the
   workflow fails the release if they differ).
2. Commit the change.
3. Tag and push:
   ```
   git tag -a v0.1.0 -m "Initial release"
   git push origin main --tags
   ```
The workflow builds `dist/KeyComp-<ver>.zip`, uploads it to CurseForge as an
**alpha** for the latest retail patch, and attaches it to a GitHub Release.
Without the CF secrets set, it still makes the GitHub Release and skips CurseForge.

## Notes
- Release type is `alpha` in the workflow until you've smoke-tested in a live
  client — change `--release` to `release` when ready.
- Local manual publish (same result, no CI): `py -3.12 tools/cf_publish.py --zip
  dist/KeyComp-0.1.0.zip --release alpha` (reads `.secrets/curseforge.json`).
- KeyQueue can reuse this exact flow later (its own CF project + a second workflow).
