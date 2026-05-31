#!/usr/bin/env python3
"""Publish a packaged addon zip to an EXISTING CurseForge project.

The CurseForge Upload API cannot CREATE a project - you create it once on the
website (authors.curseforge.com), then either put its numeric id in
.secrets/curseforge.json as "project_id", or (in CI) supply it via env. After
that this script uploads new files (e.g. the daily WCL-refreshed build).

Credentials are read from the environment FIRST (for GitHub Actions), then from
.secrets/curseforge.json:
  CF_API_KEY     -> the upload-API token
  CF_PROJECT_ID  -> the numeric project id

Game version: by default the file is tagged for the WoW version(s) named in the
addon's own toc `## Interface` (matched to CurseForge via each version's
apiVersion), so the CurseForge tag always matches what the addon actually
targets. `--game-version <id>` overrides; if the toc can't be matched it falls
back to the latest retail patch.

  py -3.12 tools/cf_publish.py --check
  py -3.12 tools/cf_publish.py --zip dist/KeyComp-0.1.2.zip --release release \
        --display-name "KeyComp 0.1.2" --changelog "..."

Dependency-free (urllib only); multipart/form-data is built by hand.
"""
from __future__ import annotations

import argparse
import json
import mimetypes
import os
import re
import sys
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SECRETS = ROOT / ".secrets" / "curseforge.json"
BASE = "https://wow.curseforge.com/api"
RETAIL_TYPE = 517  # WoW Retail gameVersionTypeID (from /game/versions)


def load_creds():
    """Token + project id from env (CI) first, then .secrets/curseforge.json."""
    data = {}
    if SECRETS.exists():
        data = json.loads(SECRETS.read_text(encoding="utf-8"))
    token = os.environ.get("CF_API_KEY") or data.get("token")
    project_id = os.environ.get("CF_PROJECT_ID") or data.get("project_id")
    return token, project_id


def api_get(path: str, token: str):
    req = urllib.request.Request(BASE + path, headers={"X-Api-Token": token})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode("utf-8"))


def _vkey(v: dict):
    out = []
    for p in str(v.get("name", "0")).split("."):
        out.append(int(p) if p.isdigit() else 0)
    return out


def latest_retail_version(token: str):
    retail = [v for v in api_get("/game/versions", token)
              if v.get("gameVersionTypeID") == RETAIL_TYPE]
    retail.sort(key=_vkey)
    return retail[-1] if retail else None


def toc_interfaces(zip_path: Path):
    """The ## Interface value(s) from the addon's .toc inside the zip.
    Returns a list of numeric strings (a toc may list several, comma-separated)."""
    with zipfile.ZipFile(zip_path) as z:
        toc = next((n for n in z.namelist() if n.lower().endswith(".toc")), None)
        if not toc:
            return []
        text = z.read(toc).decode("utf-8-sig", "replace")
    for line in text.splitlines():
        m = re.match(r"^\s*##\s*Interface\s*:\s*(.+)$", line)
        if m:
            return [p.strip() for p in m.group(1).split(",") if p.strip().isdigit()]
    return []


def match_game_versions(token: str, interfaces):
    """CurseForge retail game-version ids whose apiVersion matches the toc Interface(s)."""
    if not interfaces:
        return []
    want = {str(i) for i in interfaces}
    return [v["id"] for v in api_get("/game/versions", token)
            if v.get("gameVersionTypeID") == RETAIL_TYPE and str(v.get("apiVersion")) in want]


def multipart(fields: dict, files: dict):
    boundary = "----curseforge" + os.urandom(12).hex()
    body = bytearray()
    for name, value in fields.items():
        body += f"--{boundary}\r\n".encode()
        body += f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode()
        body += value.encode("utf-8") + b"\r\n"
    for name, (filename, content) in files.items():
        ctype = mimetypes.guess_type(filename)[0] or "application/octet-stream"
        body += f"--{boundary}\r\n".encode()
        body += (f'Content-Disposition: form-data; name="{name}"; '
                 f'filename="{filename}"\r\n').encode()
        body += f"Content-Type: {ctype}\r\n\r\n".encode()
        body += content + b"\r\n"
    body += f"--{boundary}--\r\n".encode()
    return bytes(body), f"multipart/form-data; boundary={boundary}"


def upload(project_id, token: str, zip_path: Path, metadata: dict):
    body, ctype = multipart(
        {"metadata": json.dumps(metadata)},
        {"file": (zip_path.name, zip_path.read_bytes())},
    )
    url = f"{BASE}/projects/{project_id}/upload-file"
    req = urllib.request.Request(url, data=body, method="POST",
                                 headers={"X-Api-Token": token, "Content-Type": ctype})
    with urllib.request.urlopen(req, timeout=180) as r:
        return json.loads(r.read().decode("utf-8"))


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--zip")
    ap.add_argument("--release", choices=["alpha", "beta", "release"], default="alpha")
    ap.add_argument("--game-version", type=int, help="game version id override (default: match the addon toc ## Interface)")
    ap.add_argument("--display-name")
    ap.add_argument("--changelog", default="")
    ap.add_argument("--changelog-file")
    ap.add_argument("--changelog-type", default="markdown", choices=["text", "html", "markdown"])
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    token, project_id = load_creds()
    if not token:
        print("no CurseForge token (set CF_API_KEY env or .secrets/curseforge.json) — skipping upload")
        return

    if args.check:
        print("token OK. latest retail game version:", latest_retail_version(token))
        return

    if not args.zip:
        sys.exit("--zip required (or use --check)")
    zip_path = Path(args.zip)
    if not zip_path.is_absolute():
        zip_path = ROOT / zip_path
    if not zip_path.exists():
        sys.exit(f"zip not found: {zip_path}")

    if args.game_version:
        gvs = [args.game_version]
        print(f"game version (override): {gvs}")
    else:
        ifaces = toc_interfaces(zip_path)
        gvs = match_game_versions(token, ifaces)
        if gvs:
            print(f"game versions from toc Interface {ifaces}: {gvs}")
        else:
            v = latest_retail_version(token)
            gvs = [v["id"]]
            print(f"WARNING: toc Interface {ifaces} matched no CurseForge version; "
                  f"falling back to latest retail {v['name']} (id {v['id']})")

    changelog = args.changelog
    if args.changelog_file:
        cf = Path(args.changelog_file)
        if not cf.is_absolute():
            cf = ROOT / cf
        changelog = cf.read_text(encoding="utf-8")

    metadata = {
        "changelog": changelog or "See project page.",
        "changelogType": args.changelog_type,
        "releaseType": args.release,
        "gameVersions": gvs,
    }
    if args.display_name:
        metadata["displayName"] = args.display_name

    if not project_id:
        print("NO project_id set (CF_PROJECT_ID env or .secrets/curseforge.json) yet.")
        print("Create the project on authors.curseforge.com first, then add its numeric id.")
        print("\nWould upload this file + metadata:")
        print(f"  file: {zip_path.name} ({zip_path.stat().st_size:,} bytes)")
        print(json.dumps(metadata, indent=2))
        return
    if args.dry_run:
        print("DRY RUN -> POST", f"{BASE}/projects/{project_id}/upload-file")
        print(f"  file: {zip_path.name} ({zip_path.stat().st_size:,} bytes)")
        print(json.dumps(metadata, indent=2))
        return
    try:
        resp = upload(project_id, token, zip_path, metadata)
        print("uploaded OK. file id:", resp.get("id"))
        print(resp)
    except urllib.error.HTTPError as e:
        sys.exit(f"upload failed: HTTP {e.code}\n{e.read().decode('utf-8', 'replace')}")


if __name__ == "__main__":
    main()
