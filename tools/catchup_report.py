#!/usr/bin/env python3
"""Summarise tools/catchup_watch.gd JSONL files (#315): OFF vs ON.

    python3 tools/catchup_report.py build/catchup/even.jsonl build/catchup/weak.jsonl

even: blue's (team 1) share of the kills per run, kills per minute, how many
      hits the catch-up cut. weak: "Bot 1"'s kill share, K:D and deaths per
      minute, plus the same figures for the other bots.
"""
import json
import statistics as st
import sys


def mean_sd(xs):
    if not xs:
        return "-"
    return "%.3f ± %.3f (n=%d)" % (st.mean(xs), st.stdev(xs) if len(xs) > 1 else 0.0, len(xs))


def main(paths):
    recs = []
    for p in paths:
        with open(p) as f:
            recs += [json.loads(l) for l in f if l.startswith("{")]
    for case in ("even", "weak"):
        rs = [r for r in recs if r["case"] == case]
        if not rs:
            continue
        print("== %s (%d runs)" % (case, len(rs)))
        for on in (False, True):
            sub = [r for r in rs if r["on"] == on]
            kpm = [r["total"] / max(1.0, r["secs"]) * 60 for r in sub]
            cut = [r["cut_hits"] for r in sub]
            line = "  %-3s kills/min %s  cut hits/run %s" % ("ON" if on else "OFF", mean_sd(kpm), mean_sd(cut))
            if case == "even":
                share = [r["team_kills"].get("1", 0) / max(1, r["team_kills"].get("1", 0) + r["team_kills"].get("2", 0)) for r in sub]
                line += "\n      blue kill share %s" % mean_sd(share)
            else:
                ws, kd, wd, ok, od = [], [], [], [], []
                for r in sub:
                    k, d = r["kills"], r["deaths"]
                    tot = max(1, sum(k.values()))
                    ws.append(k.get("Bot 1", 0) / tot)
                    kd.append(k.get("Bot 1", 0) / max(1, d.get("Bot 1", 0)))
                    others = [n for n in d if n != "Bot 1"]
                    ok.append(st.mean([k.get(n, 0) / max(1, d.get(n, 0)) for n in others]) if others else 0)
                    wd.append(d.get("Bot 1", 0) / max(1.0, r["secs"]) * 60)
                    od.append(st.mean([d.get(n, 0) for n in others]) / max(1.0, r["secs"]) * 60 if others else 0)
                line += "\n      weak kill share %s  weak K:D %s  weak deaths/min %s\n      others K:D %s  others deaths/min %s" % (
                    mean_sd(ws), mean_sd(kd), mean_sd(wd), mean_sd(ok), mean_sd(od))
            print(line)


if __name__ == "__main__":
    main(sys.argv[1:])
