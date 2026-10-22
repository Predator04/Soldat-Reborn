#!/usr/bin/env python3
"""Tables from tools/balance_watch.gd output (#310, dev only).

  python3 tools/balance_report.py duel  build/balance/duel.jsonl  [--tag=before] [--vs=after]
  python3 tools/balance_report.py match build/balance/match.jsonl [--tag=before]

Duel: median time-to-kill (s) per weapon x distance, standing / strafing
("x" = no kill in the majority of trials within the 10 s cap).
Match: per loadout, pick share (seconds held) vs kill share, kills per minute
held (all kills of bots holding it) and with the gun itself, K/D, average
time-to-kill / kill distance, damage per hit, self-kills; per vehicle kind,
lifetime, crewed minutes, kills, damage per crewed minute, what wrecks it.
"""
import json
import sys
from collections import defaultdict


def load(path, tag):
    rows = []
    with open(path) as f:
        for ln in f:
            ln = ln.strip()
            if not ln:
                continue
            d = json.loads(ln)
            if tag is None or d.get("tag") == tag:
                rows.append(d)
    return rows


def fmt_ttk(r):
    if r is None:
        return "?"
    if r["kills"] * 2 <= r["trials"]:
        return "x"
    return "%.2f" % r["ttk_med"]


def duel(rows, vs_rows=None):
    cells = {(r["weapon"], r["dist"], r["motion"]): r for r in rows}
    other = {(r["weapon"], r["dist"], r["motion"]): r for r in (vs_rows or [])}
    weapons = []
    for r in rows:
        if r["weapon"] not in weapons:
            weapons.append(r["weapon"])
    dists = sorted({r["dist"] for r in rows})
    head = "| Weapon | " + " | ".join("%d stand / strafe" % d for d in dists) + " | dmg/shot landed |"
    print(head)
    print("|" + "---|" * (len(dists) + 2))
    for w in weapons:
        parts = []
        for d in dists:
            cs = []
            for m in ("stand", "strafe"):
                c = cells.get((w, d, m))
                s = fmt_ttk(c)
                if other:
                    s = "%s -> %s" % (fmt_ttk(other.get((w, d, m))), s)
                cs.append(s)
            parts.append(" / ".join(cs))
        hits = [c for k, c in cells.items() if k[0] == w and c["hit_events"] > 0 and k[2] == "stand"]
        dph = sum(c["dmg"] for c in hits) / max(1, sum(c["hit_events"] for c in hits))
        print("| %s | %s | %.0f |" % (w, " | ".join(parts), dph))


def match(rows):
    W = defaultdict(lambda: defaultdict(float))
    V = defaultdict(lambda: defaultdict(float))
    VB = defaultdict(lambda: defaultdict(int))
    secs = 0.0
    for r in rows:
        secs += r["secs"]
        for w, s in r["weapons"].items():
            for k, v in s.items():
                W[w][k] += v
        for k, s in r["vehicles"].items():
            for kk, v in s.items():
                if kk == "wrecked_by":
                    for why, n in v.items():
                        VB[k][why] += n
                else:
                    V[k][kk] += v
    print("%d runs, %.0f match-minutes\n" % (len(rows), secs / 60.0))
    loads = [w for w in W if W[w]["alive_s"] > 0]
    tot_alive = sum(W[w]["alive_s"] for w in loads)
    tot_kills = sum(W[w]["kills_holder"] for w in loads)
    print("| Loadout | pick % | kill % (holders) | kills/min held | gun kills/min active | K/D | avg TTK s | avg kill dist | dmg/hit | self-kills |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for w in sorted(loads, key=lambda w: -W[w]["kills_holder"] / max(1, W[w]["alive_s"])):
        s = W[w]
        pick = 100.0 * s["alive_s"] / max(1, tot_alive)
        ks = 100.0 * s["kills_holder"] / max(1, tot_kills)
        kpm = s["kills_holder"] / max(1e-6, s["alive_s"] / 60.0)
        gpm = s["kills"] / max(1e-6, s["active_s"] / 60.0) if s["active_s"] > 0 else 0.0
        kd = s["kills_holder"] / max(1, s["deaths"])
        ttk = s["ttk_sum"] / s["ttk_n"] if s["ttk_n"] else 0.0
        dist = s["dist_sum"] / s["dist_n"] if s["dist_n"] else 0.0
        dph = s["dmg"] / s["hits"] if s["hits"] else 0.0
        print("| %s | %.1f | %.1f | %.2f | %.2f | %.2f | %.2f | %.0f | %.1f | %d |" % (
            w, pick, ks, kpm, gpm, kd, ttk, dist, dph, s["self"]))
    other = [w for w in W if W[w]["alive_s"] == 0 and (W[w]["kills"] or W[w]["self"])]
    if other:
        print("\nOther weapons (not a loadout): " + ", ".join(
            "%s %d kills (%d self)" % (w, W[w]["kills"], W[w]["self"]) for w in other))
    print("\n| Vehicle | lives | avg life s (wrecked) | crewed min | boardings | kills | kills/crewed min | dmg/crewed min | wrecks | crew deaths | wrecked by |")
    print("|---|---|---|---|---|---|---|---|---|---|---|")
    for k in sorted(V):
        s = V[k]
        cm = s["crewed_s"] / 60.0
        life = s["life_sum"] / s["wrecks"] if s["wrecks"] else 0.0
        by = ", ".join("%s %d" % (w, n) for w, n in sorted(VB[k].items(), key=lambda x: -x[1])[:5])
        print("| %s | %d | %.0f | %.1f | %d | %d | %.2f | %.0f | %d | %d | %s |" % (
            k, s["lives"], life, cm, s["boardings"], s["kills"], s["kills"] / max(1e-6, cm),
            s["dmg"] / max(1e-6, cm), s["wrecks"], s["crew_deaths"], by))


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    kind, path = sys.argv[1], sys.argv[2]
    tag = None
    vs = None
    for a in sys.argv[3:]:
        if a.startswith("--tag="):
            tag = a[6:]
        elif a.startswith("--vs="):
            vs = a[5:]
    rows = load(path, tag)
    if kind == "duel":
        duel(rows, load(path, vs) if vs else None)
    else:
        match(rows)
    return 0


if __name__ == "__main__":
    sys.exit(main())
