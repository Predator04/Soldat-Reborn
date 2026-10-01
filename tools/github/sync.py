#!/usr/bin/env python3
"""GitHub housekeeping for Soldat Reborn (stdlib only).

  python tools/github/sync.py labels                  # create / update the label set
  python tools/github/sync.py backlog FILE.json       # file already-fixed issues, then close them
  python tools/github/sync.py release v1.16.0         # release + upload build/SoldatReborn.exe/.apk
  python tools/github/sync.py all                     # labels + every backlog_*.json + release of the
                                                      # version in project.godot

Auth: GITHUB_TOKEN / GH_TOKEN, else `gh auth token`, else the token Git already
stores for github.com (`git credential fill`, i.e. Git Credential Manager).
Everything is idempotent: existing labels / issues (same title) / releases are
reused, so re-running is safe.
"""
import json, os, re, subprocess, sys, urllib.request, urllib.error

REPO = "Predator04/Soldat-Reborn"
API = "https://api.github.com"
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))

LABELS = {
    "bug": ("d73a4a", "Something is broken"),
    "enhancement": ("a2eeef", "New feature or improvement"),
    "area: gameplay": ("0e8a16", "Rules, modes, weapons, movement"),
    "area: bots": ("5319e7", "Bot AI and navigation"),
    "area: multiplayer": ("1d76db", "Networking, hosting, joining"),
    "area: ui": ("fbca04", "Menus, HUD, text"),
    "area: input": ("c5def5", "Keyboard, mouse, gamepad bindings"),
    "area: editor": ("bfd4f2", "Map editor"),
    "area: maps": ("006b75", "Map data, nav graphs"),
    "area: qa": ("ededed", "Tests, release gate, tooling"),
    "area: audio": ("f9d0c4", "Sound effects, music, ambience"),
    "area: graphics": ("c2e0c6", "Rendering, art, visual glitches"),
    "area: platform": ("d4c5f9", "Export, builds, OS specifics"),
    "platform: android": ("3ddc84", "Phones / touch"),
    "needs repro": ("e4e669", "Can't reproduce yet"),
}


def token():
    for k in ("GITHUB_TOKEN", "GH_TOKEN"):
        if os.environ.get(k):
            return os.environ[k]
    try:
        t = subprocess.run(["gh", "auth", "token"], capture_output=True, text=True, timeout=20).stdout.strip()
        if t:
            return t
    except Exception:
        pass
    try:
        out = subprocess.run(["git", "credential", "fill"], input="protocol=https\nhost=github.com\n\n",
                             capture_output=True, text=True, timeout=60).stdout
        m = re.search(r"^password=(.+)$", out, re.M)
        if m:
            return m.group(1).strip()
    except Exception:
        pass
    sys.exit("No GitHub token: set GITHUB_TOKEN, log in with `gh auth login`, or push once with git so it stores one.")


TOKEN = None


def call(method, path, body=None, url=None, data=None, ctype="application/json"):
    req = urllib.request.Request(url or (API + path), method=method,
                                 data=data if data is not None else (json.dumps(body).encode() if body is not None else None))
    req.add_header("Authorization", "Bearer " + TOKEN)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if data is not None or body is not None:
        req.add_header("Content-Type", ctype)
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        msg = e.read().decode(errors="replace")
        if e.code == 404 and method == "GET":
            return None
        sys.exit("%s %s -> %d %s" % (method, path or url, e.code, msg[:400]))


def labels():
    have = {l["name"]: l for l in call("GET", "/repos/%s/labels?per_page=100" % REPO)}
    for name, (color, desc) in LABELS.items():
        if name in have:
            if have[name]["color"] != color or (have[name].get("description") or "") != desc:
                call("PATCH", "/repos/%s/labels/%s" % (REPO, urllib.request.quote(name)), {"color": color, "description": desc})
        else:
            call("POST", "/repos/%s/labels" % REPO, {"name": name, "color": color, "description": desc})
            print("label +", name)


def all_issue_titles():
    titles, page = {}, 1
    while True:
        batch = call("GET", "/repos/%s/issues?state=all&per_page=100&page=%d" % (REPO, page))
        if not batch:
            return titles
        for i in batch:
            if "pull_request" not in i:
                titles[i["title"]] = i["number"]
        page += 1


def backlog(path):
    items = json.load(open(path, encoding="utf-8"))
    have = all_issue_titles()
    for it in items:
        if it["title"] in have:
            print("exists #%d %s" % (have[it["title"]], it["title"]))
            continue
        sha = it.get("commit", "")
        if it.get("open"):
            iss = call("POST", "/repos/%s/issues" % REPO, {"title": it["title"], "body": it["body"] + "\n\n_Seen in v%s; still open._" % it.get("version", "?"), "labels": it.get("labels", [])})
            print("filed (open) #%d %s" % (iss["number"], it["title"]))
            continue
        body = it["body"] + "\n\n_Filed after the fact to keep the tracker complete; fixed in %s (v%s)._" % (sha, it.get("version", "?"))
        iss = call("POST", "/repos/%s/issues" % REPO, {"title": it["title"], "body": body, "labels": it.get("labels", [])})
        n = iss["number"]
        call("POST", "/repos/%s/issues/%d/comments" % (REPO, n), {"body": "Fixed in %s, released in v%s." % (sha, it.get("version", "?"))})
        call("PATCH", "/repos/%s/issues/%d" % (REPO, n), {"state": "closed", "state_reason": "completed"})
        print("filed + closed #%d %s" % (n, it["title"]))


def project_version():
    txt = open(os.path.join(ROOT, "project.godot"), encoding="utf-8").read()
    return "v" + re.search(r'config/version="([^"]+)"', txt).group(1)


def changelog_section(ver):
    txt = open(os.path.join(ROOT, "CHANGELOG.md"), encoding="utf-8").read()
    m = re.search(r"^## \[%s\].*?$(.*?)(?=^## \[)" % re.escape(ver.lstrip("v")), txt, re.S | re.M)
    return m.group(1).strip() if m else "See CHANGELOG.md."


def release(tag):
    rel = call("GET", "/repos/%s/releases/tags/%s" % (REPO, tag))
    if rel is None:
        rel = call("POST", "/repos/%s/releases" % REPO, {
            "tag_name": tag, "target_commitish": "main", "name": "Soldat Reborn " + tag,
            "body": changelog_section(tag) + "\n\n**Downloads:** `SoldatReborn.exe` (Windows) and `SoldatReborn.apk` (Android). `SoldatReborn.pck` is the game pack for dedicated servers."})
        print("release created", tag)
    else:
        # Keep the release notes in step with CHANGELOG.md (a version can gain
        # entries after its first publish).
        body = changelog_section(tag) + "\n\n**Downloads:** `SoldatReborn.exe` (Windows) and `SoldatReborn.apk` (Android). `SoldatReborn.pck` is the game pack for dedicated servers."
        if (rel.get("body") or "") != body:
            call("PATCH", "/repos/%s/releases/%d" % (REPO, rel["id"]), {"body": body})
            print("release notes updated")
    have = {a["name"]: a for a in rel.get("assets", [])}
    for f, ctype in (("SoldatReborn.exe", "application/vnd.microsoft.portable-executable"),
                     ("SoldatReborn.apk", "application/vnd.android.package-archive"),
                     ("SoldatReborn.pck", "application/octet-stream")):
        p = os.path.join(ROOT, "build", f)
        if not os.path.exists(p):
            print("asset skip", f, "(no build)")
            continue
        if f in have:
            # Same size = same build. A rebuilt binary replaces the old one.
            if int(have[f].get("size", -1)) == os.path.getsize(p):
                print("asset skip", f, "(already up to date)")
                continue
            print("replacing", f, "(newer build)")
            call("DELETE", "/repos/%s/releases/assets/%d" % (REPO, have[f]["id"]))
        up = rel["upload_url"].split("{")[0] + "?name=" + f
        print("uploading", f, os.path.getsize(p) // (1024 * 1024), "MB ...")
        with open(p, "rb") as fh:
            call("POST", None, url=up, data=fh.read(), ctype=ctype)
    print("release:", rel.get("html_url"))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    TOKEN = token()
    cmd = sys.argv[1]
    if cmd == "labels":
        labels()
    elif cmd == "backlog":
        backlog(sys.argv[2])
    elif cmd == "release":
        release(sys.argv[2] if len(sys.argv) > 2 else project_version())
    elif cmd == "all":
        labels()
        for f in sorted(os.listdir(HERE)):
            if f.startswith("backlog_") and f.endswith(".json"):
                backlog(os.path.join(HERE, f))
        release(project_version())
    else:
        sys.exit(__doc__)
