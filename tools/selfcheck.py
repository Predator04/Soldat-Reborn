#!/usr/bin/env python3
"""Tracerfall self-check: does a dedicated server start and serve a real client?

Run it from anywhere (it finds the game folder from its own path); it is what
an unattended agent should run every few hours against the latest main:

  python tools/selfcheck.py --pull --report-github     (tools\\selfcheck.bat on Windows)
  python3 tools/selfcheck.py                           (local / gate: no pull, no GitHub)

Steps: [--pull] git pull --ff-only -> godot --headless --import (always: a
checkout that pulls new assets / class_name scripts and runs without importing
fails to parse them, #274 #275) -> pick a free UDP port pair (game + query) ->
dedicated server, wait up to --server-timeout s for "listening on port" ->
--smoke-join and --smoke-botfire against it -> kill every Godot it started
(whole process tree; also on errors / Ctrl-C, and a server left by a crashed
earlier run is killed on the next start).

The Godot runs use a private, fresh user dir under build/selfcheck/userdata
(never your own settings / stats / replays). Logs: build/selfcheck/<UTC
stamp>.log (summary, the first meaningful line, the last 30 lines of each
Godot log) next to the raw logs in build/selfcheck/<stamp>/; the newest 20
runs are kept.

--report-github keeps ONE open issue "[selfcheck] failing" (label "area: qa")
on the repo: opened on the first failure, commented on for later failures,
commented + closed by the next pass. Token: GITHUB_TOKEN / GH_TOKEN, else
`gh auth token`, else Git's stored credential (same as tools/github/sync.py).

Godot: --godot PATH, else $GODOT_BIN, else ..\\GodotEngine\\Godot_v4.7.2-stable_win64_console.exe
(Windows, next to the game folder) / ~/godot/Godot_v4.7.2-stable_linux.x86_64.

Prints one line `SELFCHECK PASS ok <sha>` / `SELFCHECK FAIL <kind> <sha>` /
`SELFCHECK ERROR <kind> <sha>`; exit code 0 pass, 1 fail, 2 checker error
(no Godot, git pull failed, GitHub report failed, crash in this script).
Stdlib only.
"""
import argparse, datetime, importlib.util, json, os, random, re, shutil, signal, socket
import subprocess, sys, time, traceback, urllib.error, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
WIN = os.name == "nt"
ISSUE_TITLE = "[selfcheck] failing"
ISSUE_LABEL = "area: qa"
# Same idea as release_gate.sh ERR_RE: lines that mean the game itself broke.
ERR_RE = re.compile(r"SCRIPT ERROR|Parse Error|Cannot load|Identifier not found|Invalid call|Cannot infer|"
                    r"Node not found|Invalid packet|Failed to get path|previously freed|Invalid access|"
                    r"Invalid get|Invalid set|Invalid assignment|Nonexistent function|out of bounds|"
                    r"No multiplayer peer is assigned|Lambda capture|while flushing queries")
FIRST_RE = [re.compile(p) for p in (r"DEDICATED-START-FAILED", r"SCRIPT ERROR", r"Parse Error", r"^ERROR:")]
KEEP_RUNS = 20
# #293: under release_gate.sh, GATE_LOAD (1 = quiet machine, <= 4) stretches
# the smoke clients' windows (net.gd _smoke_secs); the waits here stretch too.
# Unset on the owner's machine -> 1.
try:
    LOAD = min(4.0, max(1.0, float(os.environ.get("GATE_LOAD", "1"))))
except ValueError:
    LOAD = 1.0

_procs = []          # every Popen we started (killed in cleanup)


class CheckerError(Exception):
    def __init__(self, kind, msg):
        Exception.__init__(self, msg)
        self.kind = kind


# ── processes ────────────────────────────────────────────────────────────────

def _popen(cmd, log_path, env=None):
    f = open(log_path, "wb")
    kw = {"stdout": f, "stderr": subprocess.STDOUT, "stdin": subprocess.DEVNULL, "cwd": ROOT, "env": env}
    if WIN:
        kw["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP | getattr(subprocess, "CREATE_NO_WINDOW", 0)
    else:
        kw["start_new_session"] = True     # own process group: killpg takes the whole tree
    p = subprocess.Popen(cmd, **kw)
    p._sc_log = f
    _procs.append(p)
    return p


def kill_tree(p):
    """Kill p and everything it started. Safe to call twice."""
    if p.poll() is None:
        try:
            if WIN:
                subprocess.run(["taskkill", "/F", "/T", "/PID", str(p.pid)], stdout=subprocess.DEVNULL,
                               stderr=subprocess.DEVNULL, timeout=30)
            else:
                try:
                    os.killpg(p.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    p.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(p.pid, signal.SIGKILL)
        except Exception:
            pass
        try:
            p.wait(timeout=10)
        except Exception:
            try:
                p.kill()
            except Exception:
                pass
    elif not WIN:
        # the leader exited; anything it left in its group still goes
        try:
            os.killpg(p.pid, signal.SIGKILL)
        except Exception:
            pass
    try:
        p._sc_log.close()
    except Exception:
        pass


def cleanup():
    while _procs:
        kill_tree(_procs.pop())


def run_logged(cmd, log_path, timeout, env=None):
    """Run to completion (killed as a tree after `timeout` s). Returns (rc or None on timeout)."""
    p = _popen(cmd, log_path, env)
    try:
        return p.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        return None
    finally:
        kill_tree(p)
        if p in _procs:
            _procs.remove(p)


def _pid_file(out):
    return os.path.join(out, "server.pid")


def kill_leftover_server(out):
    """A previous run that died hard (power loss, killed agent) may have left its
    server running and holding a port. Kill it if that PID is still a Godot."""
    pf = _pid_file(out)
    try:
        pid = int(open(pf).read().strip())
    except Exception:
        return
    try:
        os.remove(pf)
    except Exception:
        pass
    try:
        if WIN:
            r = subprocess.run(["tasklist", "/FI", "PID eq %d" % pid, "/FO", "CSV", "/NH"], capture_output=True,
                               text=True, timeout=30)
            if "godot" in r.stdout.lower():
                subprocess.run(["taskkill", "/F", "/T", "/PID", str(pid)], capture_output=True, timeout=30)
                print("selfcheck: killed a server left by an earlier run (pid %d)" % pid)
        else:
            cmd = open("/proc/%d/cmdline" % pid, "rb").read().decode(errors="replace")
            if "godot" in cmd.lower() and "--dedicated" in cmd:
                os.killpg(pid, signal.SIGKILL)
                print("selfcheck: killed a server left by an earlier run (pid %d)" % pid)
    except Exception:
        pass


# ── helpers ──────────────────────────────────────────────────────────────────

def find_godot(arg):
    explicit = arg or os.environ.get("GODOT_BIN")
    if explicit:   # asked for a specific binary: that one or nothing
        if os.path.isfile(explicit):
            return explicit
        raise CheckerError("no-godot", "Godot not found at %s (--godot / GODOT_BIN)" % explicit)
    cands = []
    if WIN:
        cands.append(os.path.join(os.path.dirname(ROOT), "GodotEngine", "Godot_v4.7.2-stable_win64_console.exe"))
    else:
        cands.append(os.path.expanduser("~/godot/Godot_v4.7.2-stable_linux.x86_64"))
    cands.append(shutil.which("godot"))
    for c in cands:
        if c and os.path.isfile(c):
            return c
    raise CheckerError("no-godot", "Godot not found (tried: %s); pass --godot or set GODOT_BIN"
                       % ", ".join(c for c in cands if c))


def git(*args, timeout=180):
    return subprocess.run(["git", "-C", ROOT] + list(args), capture_output=True, text=True, timeout=timeout)


def head_sha():
    try:
        r = git("rev-parse", "--short", "HEAD", timeout=30)
        return r.stdout.strip() or "unknown"
    except Exception:
        return "unknown"


def udp_free(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        if WIN and hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
            s.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        s.bind(("0.0.0.0", port))
        return True
    except OSError:
        return False
    finally:
        s.close()


def pick_port():
    """A free game port whose query port (+1) is free too."""
    rng = random.Random()
    for _ in range(200):
        p = rng.randrange(20000, 29990)
        if udp_free(p) and udp_free(p + 1):
            return p
    raise CheckerError("no-port", "no free UDP port pair found in 20000-29990")


def read(path):
    try:
        with open(path, "rb") as f:
            return f.read().decode("utf-8", errors="replace").replace("\r\n", "\n")
    except Exception:
        return ""


def first_meaningful(text):
    lines = text.splitlines()
    for rx in FIRST_RE:
        for ln in lines:
            if rx.search(ln):
                return ln.strip()
    return ""


def tail(text, n=30):
    return "\n".join(text.splitlines()[-n:])


def smoke_field(line, key):
    m = re.search(r"\b%s=(-?[0-9.]+)" % re.escape(key), line or "")
    return float(m.group(1)) if m else None


# ── the check ────────────────────────────────────────────────────────────────

def check(godot, out, args):
    """Returns (kind, detail, logs) — kind "ok" means pass. logs: [(name, path)]."""
    logs = []
    imp = os.path.join(out, "import.log")
    logs.append(("import", imp))
    rc = run_logged([godot, "--headless", "--path", ROOT, "--import"], imp, args.import_timeout)
    if rc is None:
        return "import-timeout", "godot --import did not finish in %d s" % args.import_timeout, logs
    t = read(imp)
    if re.search(r"Parse Error|SCRIPT ERROR", t):
        return "import-error", first_meaningful(t), logs

    # Private, fresh user dir for every game process (settings, stats, replays).
    ud = os.path.join(os.path.dirname(out), "userdata")
    shutil.rmtree(ud, ignore_errors=True)
    os.makedirs(ud, exist_ok=True)
    env = dict(os.environ)
    env["APPDATA" if WIN else "XDG_DATA_HOME"] = ud

    port = pick_port()
    srv_log = os.path.join(out, "server.log")
    logs.append(("server", srv_log))
    srv = _popen([godot, "--headless", "--path", ROOT, "--", "--dedicated", "--port", str(port),
                  "--map", args.map, "--mode", args.mode], srv_log, env)
    try:
        with open(_pid_file(os.path.dirname(out)), "w") as f:
            f.write(str(srv.pid))
    except Exception:
        pass
    deadline = time.time() + args.server_timeout * LOAD
    started = None
    while time.time() < deadline:
        t = read(srv_log)
        if "listening on port %d" % port in t:
            started = time.time()
            break
        if srv.poll() is not None:
            time.sleep(0.3)
            t = read(srv_log)
            return ("dedicated-start-failed" if "DEDICATED-START-FAILED" in t else "dedicated-exited",
                    first_meaningful(t) or "server exited with code %s before listening" % srv.returncode, logs)
        time.sleep(0.25)
    if started is None:
        t = read(srv_log)
        return "dedicated-timeout", first_meaningful(t) or "no \"listening on port %d\" line in %d s" % (
            port, args.server_timeout), logs
    # The server loads the match right after it starts listening; it says
    # "Dedicated match ready" once it has (#293; was a fixed 4 s sleep).
    ready_by = time.time() + 40 * LOAD
    while time.time() < ready_by and srv.poll() is None and "Dedicated match ready" not in read(srv_log):
        time.sleep(0.25)

    join_log = os.path.join(out, "join.log")
    logs.append(("join", join_log))
    run_logged([godot, "--headless", "--path", ROOT, "--", "--smoke-join", "--port", str(port)], join_log, int(60 * LOAD), env)
    fire_log = os.path.join(out, "botfire.log")
    logs.append(("botfire", fire_log))
    run_logged([godot, "--headless", "--path", ROOT, "--", "--smoke-botfire", "--port", str(port)], fire_log, int(90 * LOAD), env)
    alive = srv.poll() is None
    kill_tree(srv)
    _procs.remove(srv)
    try:
        os.remove(_pid_file(os.path.dirname(out)))
    except Exception:
        pass

    for name, path in logs[1:]:
        t = read(path)
        bad = [ln for ln in t.splitlines() if ERR_RE.search(ln)]
        if bad:
            return "script-error", "%s: %s" % (name, first_meaningful(t) or bad[0].strip()), logs
    if not alive:
        return "dedicated-died", "the server exited during the client checks: " + (
            first_meaningful(read(srv_log)) or "no error line"), logs
    jl = next((ln for ln in read(join_log).splitlines() if ln.startswith("SMOKE-JOIN ")), "")
    if not jl:
        return "join-failed", first_meaningful(read(join_log)) or "no SMOKE-JOIN line (client never got in)", logs
    if (smoke_field(jl, "players") or 0) < 1 or (smoke_field(jl, "bots_visible") or 0) <= 0:
        return "bot-replication", jl, logs
    fl = next((ln for ln in read(fire_log).splitlines() if ln.startswith("SMOKE-BOTFIRE ")), "")
    if not fl:
        return "botfire-failed", first_meaningful(read(fire_log)) or "no SMOKE-BOTFIRE line", logs
    if (smoke_field(fl, "bot_shots_seen") or 0) <= 0:
        return "bot-fire", fl, logs
    return "ok", "server port %d: %s | %s" % (port, jl[:100], fl[:120]), logs


# ── report ───────────────────────────────────────────────────────────────────

def write_report(path, summary, detail, logs):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(summary + "\n" + (detail or "") + "\n")
        for name, p in logs:
            f.write("\n===== %s (%s) — last 30 lines =====\n%s\n" % (name, p, tail(read(p))))


def prune(base):
    try:
        runs = sorted(d for d in os.listdir(base) if re.match(r"^\d{8}T\d{6}Z$", d))
        for d in runs[:-KEEP_RUNS]:
            shutil.rmtree(os.path.join(base, d), ignore_errors=True)
            try:
                os.remove(os.path.join(base, d + ".log"))
            except Exception:
                pass
    except Exception:
        pass


def _github_token():
    spec = importlib.util.spec_from_file_location("tf_sync", os.path.join(HERE, "github", "sync.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    try:
        return mod.token()
    except SystemExit as e:
        raise CheckerError("no-token", str(e))


def _gh(token, method, path, body=None):
    # SELFCHECK_GH_API: test hook (a fake GitHub on localhost); never set it in real use.
    api = os.environ.get("SELFCHECK_GH_API", "https://api.github.com").rstrip("/")
    req = urllib.request.Request(api + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None)
    req.add_header("Authorization", "Bearer " + token)
    req.add_header("Accept", "application/vnd.github+json")
    req.add_header("X-GitHub-Api-Version", "2022-11-28")
    if body is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raise CheckerError("github", "%s %s -> %d %s" % (method, path, e.code, e.read().decode(errors="replace")[:300]))
    except urllib.error.URLError as e:
        raise CheckerError("github", "%s %s -> %s" % (method, path, e))


def report_github(repo, passed, kind, sha, detail, report_path):
    token = _github_token()
    open_issue = None
    page = 1
    while open_issue is None:
        batch = _gh(token, "GET", "/repos/%s/issues?state=open&per_page=100&page=%d" % (repo, page))
        if not batch:
            break
        for i in batch:
            if "pull_request" not in i and i.get("title") == ISSUE_TITLE:
                open_issue = i
                break
        page += 1
    when = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
    if passed:
        if open_issue:
            _gh(token, "POST", "/repos/%s/issues/%d/comments" % (repo, open_issue["number"]),
                {"body": "Passing again at `%s` (%s): %s\n\nClosing." % (sha, when, detail)})
            _gh(token, "PATCH", "/repos/%s/issues/%d" % (repo, open_issue["number"]),
                {"state": "closed", "state_reason": "completed"})
            print("selfcheck: closed #%d" % open_issue["number"])
        return
    body = ("**%s** at `%s` (%s)\n\nFirst meaningful line:\n```\n%s\n```\n\n<details><summary>Log tails</summary>\n\n```\n%s\n```\n</details>\n\n"
            "Full logs on the checking machine: `%s`. Reproduce: `python tools/selfcheck.py`."
            % (kind, sha, when, detail or "(none)", read(report_path)[-6000:], os.path.relpath(report_path, ROOT)))
    if open_issue:
        _gh(token, "POST", "/repos/%s/issues/%d/comments" % (repo, open_issue["number"]), {"body": body})
        print("selfcheck: commented on #%d" % open_issue["number"])
    else:
        iss = _gh(token, "POST", "/repos/%s/issues" % repo, {
            "title": ISSUE_TITLE, "labels": [ISSUE_LABEL],
            "body": "The automated self-check (`tools/selfcheck.py`: import, dedicated server, a joining client and a "
                    "bot-fire client) is failing. This issue stays open, gets a comment per failing run and closes "
                    "itself on the next pass.\n\n" + body})
        print("selfcheck: opened #%d" % iss["number"])


# ── main ─────────────────────────────────────────────────────────────────────

def _on_sigterm(_sig, _frame):
    raise KeyboardInterrupt()


def main():
    ap = argparse.ArgumentParser(description="Tracerfall dedicated-server self-check")
    ap.add_argument("--pull", action="store_true", help="git pull --ff-only first")
    ap.add_argument("--report-github", action="store_true", help="keep the one '[selfcheck] failing' issue up to date")
    ap.add_argument("--godot", help="Godot binary (default: $GODOT_BIN, then the usual install spot)")
    ap.add_argument("--repo", default="Predator04/Tracerfall")
    ap.add_argument("--map", default="18", help="map name or index (default 18, as the gate's ctf case)")
    ap.add_argument("--mode", default="ctf")
    ap.add_argument("--server-timeout", type=int, default=60)
    ap.add_argument("--import-timeout", type=int, default=1200)
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "selfcheck"))
    args = ap.parse_args()

    for s in (sys.stdout, sys.stderr):
        try:   # a Windows console (cp1252) must not crash on a log line's characters
            s.reconfigure(errors="replace")
        except Exception:
            pass
    if not WIN:
        signal.signal(signal.SIGTERM, _on_sigterm)   # a supervisor's kill still cleans up
    base = os.path.abspath(args.out)
    os.makedirs(base, exist_ok=True)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    out = os.path.join(base, stamp)
    os.makedirs(out, exist_ok=True)
    report_path = os.path.join(base, stamp + ".log")
    sha = head_sha()
    kind, detail, logs, status = "error", "", [], "ERROR"
    try:
        kill_leftover_server(base)
        if args.pull:
            r = git("pull", "--ff-only", "-q")
            if r.returncode != 0:
                msg = (r.stderr or r.stdout or "").strip().splitlines()
                raise CheckerError("pull-failed", "git pull --ff-only: " + (msg[-1] if msg else "failed"))
            sha = head_sha()
        godot = find_godot(args.godot)
        kind, detail, logs = check(godot, out, args)
        status = "PASS" if kind == "ok" else "FAIL"
    except CheckerError as e:
        kind, detail, status = e.kind, str(e), "ERROR"
    except KeyboardInterrupt:
        kind, detail, status = "interrupted", "stopped (Ctrl-C / SIGTERM)", "ERROR"
    except Exception:
        kind, detail, status = "crash", traceback.format_exc().strip().splitlines()[-1], "ERROR"
        traceback.print_exc()
    finally:
        cleanup()
    summary = "SELFCHECK %s %s %s" % (status, kind, sha)
    write_report(report_path, summary, detail, logs)
    prune(base)
    if detail:
        print(detail)
    print("selfcheck: log %s" % report_path)
    code = {"PASS": 0, "FAIL": 1}.get(status, 2)
    if args.report_github and status in ("PASS", "FAIL"):
        try:
            report_github(args.repo, status == "PASS", kind, sha, detail, report_path)
        except CheckerError as e:
            print("selfcheck: GitHub report failed: %s" % e)
            code = 2
    print(summary)
    return code


if __name__ == "__main__":
    try:
        sys.exit(main())
    finally:
        cleanup()
