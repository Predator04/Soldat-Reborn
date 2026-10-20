#!/usr/bin/env python3
"""Push the release builds to itch.io with butler (#224). Python 3 stdlib only;
works on Windows (the owner's release PC) and Linux.

  python tools/itch/push.py                 # push build/SoldatReborn.exe + .apk
  python tools/itch/push.py --pck           # ... and build/SoldatReborn.pck (server channel)
  python tools/itch/push.py --dry-run       # print the butler commands, run nothing
  python tools/itch/push.py --notes         # write build/itch_devlog_<version>.html
                                            # (CHANGELOG section as a devlog body)
  python tools/itch/push.py --optional      # release-pipeline mode: skip quietly when
                                            # butler / the config / the key is missing,
                                            # and ALWAYS exit 0 (never fails a release)
  python tools/itch/push.py --self-test     # check this script with a fake butler

Setup (once; docs/itch/README.md walks through it):
  1. tools/itch/itch.json: set "target" to "<itch user>/<project url name>",
     e.g. "predator04/tracerfall". Empty target = itch pushing is off.
  2. Install butler (https://itch.io/docs/butler/installing.html) and put it on
     PATH, or point BUTLER at butler.exe.
  3. Give it an API key: `butler login` once (stores it in your user profile),
     or set the BUTLER_API_KEY environment variable
     (https://itch.io/user/settings/api-keys). Never commit a key.

Channels (itch tags the platform from the channel name): SoldatReborn.exe ->
"windows", SoldatReborn.apk -> "android", SoldatReborn.pck -> "server". The
upload names stay SoldatReborn.* (the in-game updater and the dedicated server
expect them). --userversion is config/version from project.godot, so the itch
app shows the same version as the game; --if-changed skips identical builds.
"""
import argparse, html, json, os, re, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
CONFIG = os.path.join(HERE, "itch.json")

# kind -> (file in the build dir, default channel)
FILES = {
    "exe": ("SoldatReborn.exe", "windows"),
    "apk": ("SoldatReborn.apk", "android"),
    "pck": ("SoldatReborn.pck", "server"),
}


def log(msg):
    print("itch: " + msg, flush=True)


def project_version(root=ROOT):
    txt = open(os.path.join(root, "project.godot"), encoding="utf-8").read()
    m = re.search(r'^config/version="([^"]+)"', txt, re.M)
    if not m:
        raise SystemExit("itch: no config/version in project.godot")
    return m.group(1)


def load_config(path=CONFIG, target_override=None):
    """{"target": "user/game", "channels": {...}, "push_pck": bool} or None (off)."""
    cfg = {}
    if os.path.exists(path):
        with open(path, encoding="utf-8") as fh:
            cfg = json.load(fh)
    elif not target_override:
        return None
    target = str(target_override or cfg.get("target", "")).strip()
    if not target:
        return None
    if not re.fullmatch(r"[A-Za-z0-9_-]+/[A-Za-z0-9_-]+", target):
        raise SystemExit('itch: target %r in %s must look like "user/game"' % (target, path))
    ch = dict((k, v[1]) for k, v in FILES.items())
    ch.update({k: str(v).strip() for k, v in (cfg.get("channels") or {}).items() if k in FILES})
    return {"target": target, "channels": ch, "push_pck": bool(cfg.get("push_pck", False))}


def find_butler():
    exe = os.environ.get("BUTLER", "").strip()
    if exe and os.path.isfile(exe):
        return exe
    found = shutil.which("butler")
    if found:
        return found
    # Where the itch desktop app keeps its own copy (Windows / Linux).
    cands = []
    if os.environ.get("APPDATA"):
        cands.append(os.path.join(os.environ["APPDATA"], "itch", "broth", "butler", "versions"))
    cands.append(os.path.expanduser("~/.config/itch/broth/butler/versions"))
    for base in cands:
        if os.path.isdir(base):
            for ver in sorted(os.listdir(base), reverse=True):
                for name in ("butler.exe", "butler"):
                    p = os.path.join(base, ver, name)
                    if os.path.isfile(p):
                        return p
    return None


def has_credentials():
    if os.environ.get("BUTLER_API_KEY", "").strip():
        return True
    # `butler login` stores the key here (both OSes use ~/.config/itch).
    return os.path.isfile(os.path.expanduser("~/.config/itch/butler_creds"))


def plan(cfg, version, build_dir, with_pck, only=None):
    """[(kind, path, "user/game:channel", argv-tail)] for the files that exist."""
    out = []
    for kind, (name, _) in FILES.items():
        if only and kind not in only:
            continue
        if kind == "pck" and not (with_pck or cfg["push_pck"]):
            continue
        channel = cfg["channels"].get(kind, "")
        if not channel:
            continue
        path = os.path.join(build_dir, name)
        if not os.path.isfile(path):
            log("skip %s (no %s)" % (kind, path))
            continue
        spec = "%s:%s" % (cfg["target"], channel)
        out.append((kind, path, spec, ["push", path, spec, "--userversion", version, "--if-changed"]))
    return out


def push(args):
    cfg = load_config(args.config, args.target)
    if cfg is None:
        log("off (no target in %s)" % os.path.relpath(args.config, ROOT))
        return 0 if args.optional else 2
    version = project_version()
    jobs = plan(cfg, version, args.build_dir, args.pck, set(args.only.split(",")) if args.only else None)
    if not jobs:
        log("nothing to push (build the release first: tools/build_release.sh)")
        return 0 if args.optional else 1
    butler = find_butler()
    if args.dry_run:
        for _, _, _, tail in jobs:
            print("butler " + " ".join('"%s"' % a if " " in a else a for a in tail))
        return 0
    if butler is None:
        log("butler not found (install it, or set BUTLER) - skipped")
        return 0 if args.optional else 1
    if not has_credentials():
        log("no API key: run `butler login` once or set BUTLER_API_KEY - skipped")
        return 0 if args.optional else 1
    failed = 0
    for kind, path, spec, tail in jobs:
        log("pushing %s -> %s (v%s)" % (os.path.basename(path), spec, version))
        try:
            r = subprocess.run([butler] + tail, timeout=args.timeout)
            if r.returncode != 0:
                failed += 1
                log("butler failed for %s (exit %d)" % (kind, r.returncode))
        except Exception as e:  # timeout, permissions, ...
            failed += 1
            log("butler failed for %s: %s" % (kind, e))
    if failed == 0:
        log("done: https://%s.itch.io/%s" % tuple(cfg["target"].split("/", 1)))
        log("status: butler status %s" % cfg["target"])
    return 0 if (failed == 0 or args.optional) else 1


# ── devlog / release notes ───────────────────────────────────────────────

def changelog_section(ver, root=ROOT):
    txt = open(os.path.join(root, "CHANGELOG.md"), encoding="utf-8").read()
    m = re.search(r"^## \[%s\](.*?)$(.*?)(?=^## \[)" % re.escape(ver), txt, re.S | re.M)
    if not m:
        return "", ""
    # "## [1.37.0] — 2026-10-19 — Maker" -> "Maker"
    parts = [p.strip() for p in re.split(r"\s[—–-]\s", " " + m.group(1) + " ") if p.strip()]
    parts = [p for p in parts if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", p)]
    return " — ".join(parts), m.group(2).strip()


def _inline(s):
    s = html.escape(s, quote=False)
    s = re.sub(r"\*\*(.+?)\*\*", r"<strong>\1</strong>", s)
    s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
    s = re.sub(r"\(#(\d+)\)", r'(<a href="https://github.com/Predator04/Tracerfall/issues/\1">#\1</a>)', s)
    return s


def md_to_html(md):
    """The tiny Markdown subset CHANGELOG.md uses -> itch rich-text HTML."""
    out, in_list = [], False
    for line in md.splitlines():
        t = line.strip()
        if t.startswith("- "):
            if not in_list:
                out.append("<ul>")
                in_list = True
            out.append("<li>%s</li>" % _inline(t[2:]))
            continue
        if in_list:
            out.append("</ul>")
            in_list = False
        if t.startswith("### "):
            out.append("<h3>%s</h3>" % _inline(t[4:]))
        elif t:
            out.append("<p>%s</p>" % _inline(t))
    if in_list:
        out.append("</ul>")
    return "\n".join(out)


def notes(args):
    version = project_version()
    title, body = changelog_section(version)
    tpl = open(os.path.join(ROOT, "docs", "itch", "release-notes-template.html"), encoding="utf-8").read()
    tpl = re.sub(r"^\s*<!--.*?-->\s*", "", tpl, flags=re.S)   # the how-to comment
    page = (tpl.replace("{{VERSION}}", version)
               .replace("{{TITLE}}", html.escape(title or "Update"))
               .replace("{{CHANGES}}", md_to_html(body) if body else "<p>See CHANGELOG.md.</p>"))
    os.makedirs(os.path.join(ROOT, "build"), exist_ok=True)
    dest = os.path.join(ROOT, "build", "itch_devlog_%s.html" % version)
    with open(dest, "w", encoding="utf-8") as fh:
        fh.write(page)
    log("devlog body written: %s (devlog title: Tracerfall %s%s)" % (dest, version, " — " + title if title else ""))
    return 0


# ── self-test (gate A) ───────────────────────────────────────────────────

def self_test():
    tmp = tempfile.mkdtemp(prefix="itch_selftest_")
    try:
        build = os.path.join(tmp, "build")
        os.makedirs(build)
        for n in ("SoldatReborn.exe", "SoldatReborn.apk", "SoldatReborn.pck"):
            open(os.path.join(build, n), "wb").write(b"x")
        cfgp = os.path.join(tmp, "itch.json")
        json.dump({"target": "tester/tracerfall"}, open(cfgp, "w"))
        rec = os.path.join(tmp, "calls.txt")
        if os.name == "nt":
            fake = os.path.join(tmp, "butler.bat")
            open(fake, "w").write('@echo %%*>>"%s"\r\n' % rec)
        else:
            fake = os.path.join(tmp, "butler")
            open(fake, "w").write('#!/bin/sh\necho "$@" >> "%s"\n' % rec)
            os.chmod(fake, 0o755)
        env = dict(os.environ, BUTLER=fake, BUTLER_API_KEY="dummy-test-key")
        me = os.path.abspath(__file__)
        v = project_version()

        def run(*extra, envx=env):
            return subprocess.run([sys.executable, me, "--config", cfgp, "--build-dir", build] + list(extra),
                                  env=envx, capture_output=True, text=True, timeout=60)
        r = run()
        calls = open(rec).read().splitlines() if os.path.exists(rec) else []
        want = ["push %s tester/tracerfall:windows --userversion %s --if-changed" % (os.path.join(build, "SoldatReborn.exe"), v),
                "push %s tester/tracerfall:android --userversion %s --if-changed" % (os.path.join(build, "SoldatReborn.apk"), v)]
        assert r.returncode == 0, r.stdout + r.stderr
        assert [c.strip() for c in calls] == want, calls
        os.remove(rec)
        r = run("--pck")
        calls = open(rec).read().splitlines()
        assert len(calls) == 3 and "tester/tracerfall:server" in calls[2], calls
        os.remove(rec)
        # No key -> skipped; --optional never fails; no target -> off.
        noenv = {k: val for k, val in env.items() if k != "BUTLER_API_KEY"}
        noenv["HOME"] = noenv["USERPROFILE"] = tmp
        r = run("--optional", envx=noenv)
        assert r.returncode == 0 and not os.path.exists(rec) and "no API key" in r.stdout, r.stdout
        json.dump({"target": ""}, open(cfgp, "w"))
        r = run("--optional")
        assert r.returncode == 0 and "off" in r.stdout and not os.path.exists(rec), r.stdout
        json.dump({"target": "bad target"}, open(cfgp, "w"))
        r = run("--optional")
        assert r.returncode == 0, r.stdout + r.stderr
        # The committed config parses (and ships with pushing off until the owner fills it in).
        load_config(CONFIG)
        assert "<li>" in md_to_html("- **a** `b` (#1)")
        print("ITCH-SELFTEST ok (windows + android channels, --pck, --userversion %s, skip without key / target)" % v)
        return 0
    except AssertionError as e:
        print("ITCH-SELFTEST FAIL %s" % e)
        return 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--config", default=CONFIG)
    ap.add_argument("--build-dir", default=os.path.join(ROOT, "build"))
    ap.add_argument("--target", help='override the config target ("user/game")')
    ap.add_argument("--only", help="comma list of exe,apk,pck")
    ap.add_argument("--pck", action="store_true", help="also push SoldatReborn.pck to the server channel")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--optional", action="store_true", help="never fail (release pipeline step)")
    ap.add_argument("--timeout", type=int, default=1800, help="seconds per butler push")
    ap.add_argument("--notes", action="store_true", help="write the devlog body for this version")
    ap.add_argument("--self-test", action="store_true")
    args = ap.parse_args(argv)
    if args.self_test:
        return self_test()
    if args.notes:
        return notes(args)
    if args.optional:
        try:
            return push(args)
        except BaseException as e:  # SystemExit from a bad config included
            log("skipped: %s" % e)
            return 0
    return push(args)


if __name__ == "__main__":
    sys.exit(main())
