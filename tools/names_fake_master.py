#!/usr/bin/env python3
"""Stand-in for the master server's reserved-names API (#318), stdlib only.

Gate F `names` / C `names` run game builds against it instead of the Go
binary, so the cases don't depend on which master build SERVER_DIR holds.
Same routes, JSON shapes and core rules as master-server `names.go`
(normalisation = filterNorm, one name per profile, taken / cooldown /
short / blocked); the real server's rules are unit-tested there (go test).
Every other path (/register, /report, ...) answers 200 {"ok": true}.

    python3 tools/names_fake_master.py --port 18123 [--reserve Alice=<32 hex id>]...

Prints "NAMES-FAKE listening on <port>" once it accepts requests, and one
"NAMES-FAKE <METHOD> <path>" line per request.
"""
import argparse
import hashlib
import json
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

LEET = {"0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "8": "b",
        "9": "g", "@": "a", "$": "s", "!": "i", "|": "i", "+": "t", "€": "e",
        "¡": "i", "à": "a", "á": "a", "â": "a", "ä": "a", "å": "a", "è": "e",
        "é": "e", "ê": "e", "ë": "e", "ì": "i", "í": "i", "î": "i", "ï": "i",
        "ò": "o", "ó": "o", "ô": "o", "ö": "o", "ù": "u", "ú": "u", "û": "u",
        "ü": "u", "ñ": "n", "ç": "c", "ß": "s"}
COOLDOWN = 72 * 3600
by_key = {}   # key -> {"owner", "name", "set"}
by_owner = {}


def strip_tag(n):
    n = n.strip()
    if n.startswith("«") and "»" in n:
        n = n[n.index("»") + 1:].strip()
    return n


def norm(s):
    out = []
    for ch in s.lower():
        ch = LEET.get(ch, ch)
        if "a" <= ch <= "z":
            out.append(ch)
    return "".join(out)


def key_of(n):
    return norm(strip_tag(n))


def owner_of(raw):
    return hashlib.sha256(raw.lower().encode()).hexdigest()


def problem(name):
    k = key_of(name)
    if len(k) < 3:
        return "short"
    if k.startswith("player") or k in ("server", "host", "admin"):
        return "blocked"
    return ""


def reserve(owner, name):
    cur = by_owner.get(owner)
    if name == "":
        if cur and cur.get("name"):
            by_key.pop(key_of(cur["name"]), None)
            cur["name"], cur["set"] = "", time.time()
        return 200, {"status": "released"}
    p = problem(name)
    if p:
        return 400, {"status": p}
    k = key_of(name)
    other = by_key.get(k)
    if other and other["owner"] != owner:
        return 409, {"status": "taken", "taken_by": other["name"]}
    if cur and cur.get("name") and key_of(cur["name"]) == k:
        cur["name"] = name
        return 200, {"status": "reserved"}
    if cur and time.time() - cur["set"] < COOLDOWN:
        return 429, {"status": "cooldown", "cooldown_s": int(COOLDOWN - (time.time() - cur["set"])) + 1}
    if cur is None:
        cur = {"owner": owner, "name": "", "set": 0}
        by_owner[owner] = cur
    elif cur.get("name"):
        by_key.pop(key_of(cur["name"]), None)
    cur["name"], cur["set"] = name, time.time()
    by_key[k] = cur
    return 200, {"status": "reserved"}


def mine(owner):
    cur = by_owner.get(owner) or {}
    left = int(COOLDOWN - (time.time() - cur.get("set", 0))) + 1 if cur else 0
    return {"name": cur.get("name", ""), "owner": owner, "cooldown_s": max(0, left) if cur else 0}


class H(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def _send(self, code, obj):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        print("NAMES-FAKE GET " + self.path, flush=True)
        u = urlparse(self.path)
        if u.path != "/names/check":
            return self._send(200, {"ok": True, "servers": [], "count": 0})
        q = parse_qs(u.query)
        name = q.get("name", [""])[0]
        pid = q.get("pid", [""])[0].lower()
        k = key_of(name)
        out = {"name": name, "key": k, "reserved": False}
        r = by_key.get(k)
        if r:
            out.update({"reserved": True, "owner": r["owner"], "display": r["name"]})
        if len(pid) == 64:
            out["status"] = "mine" if r and r["owner"] == pid else "taken" if r else ("invalid" if problem(name) else "free")
        self._send(200, out)

    def do_POST(self):
        print("NAMES-FAKE POST " + self.path, flush=True)
        n = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(n) if n > 0 else b"{}"
        try:
            req = json.loads(raw.decode() or "{}")
        except ValueError:
            return self._send(400, {"error": "bad json"})
        path = urlparse(self.path).path
        if path not in ("/names/reserve", "/names/mine"):
            return self._send(200, {"ok": True})
        rid = str(req.get("id", "")).lower()
        if len(rid) != 32 or any(c not in "0123456789abcdef" for c in rid):
            return self._send(400, {"error": "bad id"})
        owner = owner_of(rid)
        if path == "/names/mine":
            out = mine(owner)
            out["ok"] = True
            return self._send(200, out)
        name = "" if req.get("release") else strip_tag(str(req.get("name", "")))[:24]
        code, res = reserve(owner, name)
        out = mine(owner)
        out.update(res)
        out["ok"] = code == 200
        self._send(code, out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--reserve", action="append", default=[], help="Name=<32 hex profile id>")
    ap.add_argument("--secs", type=float, default=600.0, help="exit after this long")
    a = ap.parse_args()
    for spec in a.reserve:
        name, rid = spec.split("=", 1)
        code, res = reserve(owner_of(rid), name)
        by_owner[owner_of(rid)]["set"] = 0   # pre-seeded: no cooldown
        if code != 200:
            print("NAMES-FAKE seed failed %s: %s" % (spec, res), flush=True)
            sys.exit(2)
    srv = ThreadingHTTPServer(("127.0.0.1", a.port), H)
    srv.timeout = 0.5
    print("NAMES-FAKE listening on %d" % a.port, flush=True)
    end = time.time() + a.secs
    while time.time() < end:
        srv.handle_request()


if __name__ == "__main__":
    main()
