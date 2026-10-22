#!/usr/bin/env python3
"""Total tools/zombie_watch.gd JSONL runs (#314): human / zombie round wins per map.

    python3 tools/zombie_report.py build/balance/zombie.jsonl [more.jsonl ...]
"""
import json
import sys
from collections import defaultdict


def main(paths):
    per = defaultdict(lambda: {"runs": 0, "rounds": 0, "human": 0, "why": defaultdict(int), "len": [], "turns": 0})
    for p in paths:
        with open(p) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                d = json.loads(line)
                key = d.get("level") or d.get("map", "?")
                e = per[key]
                e["runs"] += 1
                e["turns"] += int(d.get("turns", 0))
                for r in d.get("rounds", []):
                    e["rounds"] += 1
                    e["human"] += 1 if r.get("winner") == "human" else 0
                    e["why"][r.get("why", "?")] += 1
                    e["len"].append(float(r.get("secs", 0)))
    tot_r = tot_h = 0
    print("%-16s %4s %6s %7s %8s  %s" % ("map", "runs", "rounds", "human%", "avg len", "why"))
    for k in sorted(per):
        e = per[k]
        tot_r += e["rounds"]
        tot_h += e["human"]
        pct = 100.0 * e["human"] / e["rounds"] if e["rounds"] else 0.0
        avg = sum(e["len"]) / len(e["len"]) if e["len"] else 0.0
        print("%-16s %4d %6d %6.0f%% %7.0fs  %s" % (k, e["runs"], e["rounds"], pct, avg, dict(e["why"])))
    if tot_r:
        print("%-16s %4s %6d %6.0f%%" % ("TOTAL", "", tot_r, 100.0 * tot_h / tot_r))


if __name__ == "__main__":
    main(sys.argv[1:] or ["build/balance/zombie.jsonl"])
