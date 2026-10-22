#!/usr/bin/env python3
"""Tracerfall dedicated server updater (#320). Python 3 standard library only;
Windows and Linux. Lives in the server folder next to the server program.

  python3 update_server.py           # install the latest release if it is newer
  python3 update_server.py --check   # only tell (exit 10 = an update is available)
  python3 update_server.py --force   # reinstall the latest release even if not newer

What it does:
  1. asks GitHub for the latest release of Predator04/Tracerfall and compares
     its version with VERSION.txt here - nothing happens unless it is newer;
  2. downloads TracerfallServer-windows.zip / TracerfallServer-linux.tar.gz and
     its .sig, and has the INSTALLED server program check the signature against
     the release key built into it (a download that isn't signed by the game's
     release key is refused);
  3. unpacks it, checks the new VERSION.txt (and the new program's --version)
     really is that newer version;
  4. swaps the files in, keeping the old ones in _update/previous/. Your
     server.cfg and logs/ are never touched.
Stop the server first (on Windows the running program can't be replaced; on
Linux the old version keeps running until you restart it).

Test / dev options: --api-url URL (another releases/latest JSON), --godot
"CMD ..." (program used for the signature check), --pubkey PEM (another
signing key, tests only), --dir DIR (server folder), --no-binary-check.
"""
import argparse, json, os, shlex, shutil, subprocess, sys, tarfile, urllib.request, zipfile

REPO = "Predator04/Tracerfall"
API_URL = "https://api.github.com/repos/%s/releases/latest" % REPO
UA = {"User-Agent": "TracerfallServerUpdater", "Accept": "application/vnd.github+json"}
WINDOWS = os.name == "nt"
ASSET = "TracerfallServer-windows.zip" if WINDOWS else "TracerfallServer-linux.tar.gz"
BINARY = "TracerfallServer.console.exe" if WINDOWS else "TracerfallServer.x86_64"
TOP = "TracerfallServer"
KEEP = {"server.cfg", "logs", "_update"}


def say(msg):
    print("UPDATE " + msg, flush=True)


def parse_version(v):
    out = []
    for p in str(v).strip().lstrip("v").split("."):
        out.append(int(p) if p.isdigit() else 0)
    return (out + [0, 0, 0])[:3]


def newer(remote, local):
    return parse_version(remote) > parse_version(local)


def url_ok(u, api_url):
    """Release files must come from GitHub over https (a local test server may
    use plain http on 127.0.0.1 / localhost when --api-url points there too)."""
    host = u.split("://", 1)[-1].split("/", 1)[0].lower()
    if u.startswith("https://"):
        return host == "github.com" or host.endswith(".github.com") or host.endswith(".githubusercontent.com")
    if u.startswith("http://") and api_url.startswith("http://"):
        return host.split(":")[0] in ("127.0.0.1", "localhost")
    return False


def local_version(d):
    p = os.path.join(d, "VERSION.txt")
    if os.path.exists(p):
        return open(p, encoding="utf-8").read().strip()
    return "0.0.0"


def fetch_json(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
        return json.loads(r.read().decode("utf-8"))


def download(url, dest, size=None):
    with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA["User-Agent"]}), timeout=60) as r, open(dest, "wb") as f:
        shutil.copyfileobj(r, f, 1 << 20)
    got = os.path.getsize(dest)
    if size is not None and got != size:
        raise RuntimeError("download incomplete: %d of %d bytes" % (got, size))
    return got


def program_cmd(args, d):
    if args.godot:
        return shlex.split(args.godot, posix=not WINDOWS)
    return [os.path.join(d, BINARY)]


def verify(args, d, archive, sig):
    cmd = program_cmd(args, d) + ["--", "--verify-update=" + archive, "--update-sig=" + sig]
    if args.pubkey:
        cmd.append("--update-pubkey=" + os.path.abspath(args.pubkey))
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired) as e:
        return False, "could not run %s (%s)" % (cmd[0], e)
    line = next((l for l in r.stdout.splitlines() if l.startswith("UPDATE-VERIFY ")), "")
    return (r.returncode == 0 and line.startswith("UPDATE-VERIFY OK")), (line or "no answer from %s" % cmd[0])


def safe_members(names):
    for n in names:
        n2 = n.replace("\\", "/")
        if n2.startswith("/") or ".." in n2.split("/") or not (n2 == TOP or n2.startswith(TOP + "/")):
            raise RuntimeError("unexpected path in the archive: %s" % n)


def unpack(archive, into):
    if archive.endswith(".zip"):
        with zipfile.ZipFile(archive) as z:
            safe_members(z.namelist())
            z.extractall(into)
    else:
        with tarfile.open(archive, "r:gz") as t:
            mem = t.getmembers()
            safe_members([m.name for m in mem])
            for m in mem:
                if not (m.isfile() or m.isdir()):
                    raise RuntimeError("unexpected entry in the archive: %s" % m.name)
            if hasattr(tarfile, "data_filter"):
                t.extractall(into, filter="data")
            else:
                t.extractall(into)
    return os.path.join(into, TOP)


def install(new, d, prev):
    """Move everything from `new` into `d`, old copies into `prev`. All or
    nothing: on an error the files moved so far are put back."""
    if os.path.isdir(prev):
        shutil.rmtree(prev)
    os.makedirs(prev)
    done = []
    try:
        for name in sorted(os.listdir(new)):
            if name in KEEP:
                continue
            dst = os.path.join(d, name)
            had = os.path.exists(dst)
            if had:
                os.replace(dst, os.path.join(prev, name))
            done.append((name, had))
            os.replace(os.path.join(new, name), dst)
    except OSError as e:
        for name, had in reversed(done):
            dst = os.path.join(d, name)
            try:
                if os.path.exists(dst):
                    if os.path.isdir(dst):
                        shutil.rmtree(dst)
                    else:
                        os.remove(dst)
                if had:
                    os.replace(os.path.join(prev, name), dst)
            except OSError:
                pass
        raise RuntimeError("could not replace %s (%s) - is the server still running? Stop it and try again." % (getattr(e, "filename", "?"), e.strerror))
    if not WINDOWS:
        for name in os.listdir(d):
            if name == BINARY or name.endswith(".sh") or name.endswith(".py"):
                p = os.path.join(d, name)
                os.chmod(p, os.stat(p).st_mode | 0o755)
    return len(done)


def main(argv=None):
    ap = argparse.ArgumentParser(description="Update this Tracerfall dedicated server from GitHub releases.")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--dir", default=os.path.dirname(os.path.abspath(__file__)))
    ap.add_argument("--api-url", default=API_URL)
    ap.add_argument("--godot", default="")
    ap.add_argument("--pubkey", default="")
    ap.add_argument("--no-binary-check", action="store_true")
    args = ap.parse_args(argv)
    d = os.path.abspath(args.dir)
    have = local_version(d)
    try:
        rel = fetch_json(args.api_url)
    except Exception as e:
        say("FAIL could not ask GitHub for the latest release (%s)" % e)
        return 1
    tag = str(rel.get("tag_name", "")).lstrip("v")
    if not tag:
        say("FAIL unexpected reply from GitHub")
        return 1
    if not newer(tag, have) and not args.force:
        say("up to date: installed %s, latest release %s" % (have, tag))
        return 0
    if args.check:
        say("available: %s (installed %s)" % (tag, have))
        return 10
    assets = {a.get("name"): a for a in rel.get("assets", []) if isinstance(a, dict)}
    a, s = assets.get(ASSET), assets.get(ASSET + ".sig")
    if a is None:
        say("FAIL release %s has no %s" % (tag, ASSET))
        return 1
    if s is None:
        say("FAIL release %s has no %s.sig - refusing an unsigned update" % (tag, ASSET))
        return 1
    for u in (a.get("browser_download_url", ""), s.get("browser_download_url", "")):
        if not url_ok(u, args.api_url):
            say("FAIL download is not on GitHub: %s" % u)
            return 1
    work = os.path.join(d, "_update")
    os.makedirs(work, exist_ok=True)
    arc = os.path.join(work, ASSET)
    sig = arc + ".sig"
    new_root = os.path.join(work, "new")
    try:
        say("downloading %s %s (%d MB) ..." % (ASSET, tag, int(a.get("size", 0)) // (1 << 20)))
        download(a["browser_download_url"], arc, int(a.get("size", 0)) or None)
        download(s["browser_download_url"], sig)
        ok, line = verify(args, d, arc, sig)
        if not ok:
            raise RuntimeError("signature check failed: %s" % line)
        say("signature OK")
        if os.path.isdir(new_root):
            shutil.rmtree(new_root)
        new = unpack(arc, new_root)
        got = local_version(new)
        if got != tag:
            raise RuntimeError("the download says it is %s, the release says %s" % (got, tag))
        if not newer(got, have) and not args.force:
            raise RuntimeError("the download (%s) is not newer than %s" % (got, have))
        if not args.no_binary_check:
            nb = os.path.join(new, BINARY)
            if not WINDOWS:
                os.chmod(nb, os.stat(nb).st_mode | 0o755)
            r = subprocess.run([nb, "--", "--version"], capture_output=True, text=True, timeout=120)
            if tag not in r.stdout:
                raise RuntimeError("the new server program reports '%s', expected %s" % (r.stdout.strip().splitlines()[-1:] or "nothing", tag))
        n = install(new, d, os.path.join(work, "previous"))
    except Exception as e:
        say("FAIL %s" % e)
        return 1
    finally:
        for p in (arc, sig):
            if os.path.exists(p):
                os.remove(p)
        if os.path.isdir(new_root):
            shutil.rmtree(new_root, ignore_errors=True)
    say("installed %s (was %s): %d files replaced, old files in _update/previous. Restart the server to run it." % (tag, have, n))
    return 0


if __name__ == "__main__":
    sys.exit(main())
