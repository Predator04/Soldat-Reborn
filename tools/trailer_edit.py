#!/usr/bin/env python3
"""Cut the gameplay trailer from the director's beat renders (#263; dev tool).

tools/make_trailer.sh runs this after tools/trailer.gd has rendered every
beat (RAW/<beat>.avi + RAW/<beat>.json) and the title cards
(RAW/cards/card_<name>/f_####.png). It

  * picks the best window of each gameplay beat from the event log: kills,
    explosions, multi-kills, flag captures and wrecks that happened ON SCREEN,
    weighted towards the middle of the window (scripted beats - Maker, LEVELS,
    the end card backdrop - use their timeline marks);
  * cuts and crossfades the windows, lays the title cards over them, mixes the
    game's own sound with the soundtrack (assets/music/necro.ogg) and encodes
    H.264 / AAC MP4s: the 16:9 trailer and a 30 s 9:16 cut for phones;
  * exports key art (docs/screenshots/trailer-*.jpg) from the director's
    full-quality stills and the 630x500 itch.io cover (docs/media).

Everything is a pure function of the renders, so the same renders give the
same files.  --plan prints the shot list without encoding.
"""
import argparse
import json
import os
import shutil
import subprocess
import sys

FPS = 60
XFADE = 0.4

# (beat, seconds on screen incl. the crossfade into the next shot, card, card offset)
EDIT = [
    ("open", 6.4, "title", 0.5),
    ("jets", 4.6, None, 0),
    ("boom", 5.0, None, 0),
    ("multi", 5.0, None, 0),
    ("hd", 5.6, "ultrahd", 0.3),
    ("night", 4.6, None, 0),
    ("buggy", 4.0, None, 0),
    ("tank", 4.0, None, 0),
    ("heli", 4.6, None, 0),
    ("ctf", 5.4, "online", 2.2),
    ("maker", 10.4, "maker", 0.2),
    ("levels", 4.6, None, 0),
    ("end", 6.4, "end", 0.3),
]

VERTICAL = [
    ("open", 3.4), ("jets", 3.0), ("boom", 3.4), ("multi", 3.0), ("hd", 3.2),
    ("buggy", 2.6), ("heli", 3.0), ("ctf", 3.0), ("maker", 4.2), ("end", 3.6),
]

MUSIC = "assets/music/necro.ogg"
MUSIC_FROM = 18.0      # the track builds up; full band from ~29 s
BEAT = 60.0 / 110.0    # necro.ogg runs at 110 BPM ...
BEAT0 = 18.53          # ... with a beat at 18.53 s (onset autocorrelation)
KEY_ART = ["open", "boom", "hd", "night", "heli", "tank", "ctf", "multi", "jets", "maker"]


def ffmpeg_bin():
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    try:
        import imageio_ffmpeg
        return imageio_ffmpeg.get_ffmpeg_exe()
    except ImportError:
        sys.exit("trailer_edit: no ffmpeg (apt install ffmpeg, or pip install --break-system-packages imageio-ffmpeg)")


def load_beat(raw, beat):
    p = os.path.join(raw, beat + ".json")
    if not os.path.exists(p):
        sys.exit("trailer_edit: missing %s (render the beat first)" % p)
    with open(p) as f:
        return json.load(f)


def multi_kills(events):
    """Frames of kills that are the 2nd+ kill of one killer within 2.5 s."""
    out = set()
    kills = [e for e in events if e["kind"] == "kill" and e.get("killer") and e.get("killer") != e.get("victim")]
    for i, e in enumerate(kills):
        for o in kills[:i]:
            if o["killer"] == e["killer"] and 0 <= e["f"] - o["f"] <= 150:
                out.add(e["f"])
    return out


def score_window(events, a, n, multi):
    s = 0.0
    for e in events:
        if not e.get("rendering"):
            continue
        rel = (e["f"] - 1 - a) / float(n)
        if rel < 0.08 or rel > 0.92:
            continue
        mid = 1.0 - abs(rel - 0.55) * 0.9
        on = e.get("on", False)
        k = e["kind"]
        w = 0.0
        if k == "kill":
            w = 3.0 if on else 0.4
            if e["f"] in multi and on:
                w += 5.0
        elif k == "explosion":
            w = 2.2 if on else 0.2
        elif k == "flag_capture":
            w = 14.0 if on else 3.0
        elif k in ("flag_grab", "flag_return"):
            w = 3.0 if on else 0.5
        elif k == "wreck":
            w = 7.0 if on else 1.0
        s += w * mid
    return s


def pick_window(info, secs):
    """First movie frame (0-based) and frame count of the best window."""
    n = int(round(secs * FPS))
    beat = info["beat"]
    r0 = info["render_start"] - 1           # movie frame index = director frame - 1
    r1 = info["render_end"] - 1
    marks = {name: f - 1 for f, name in info.get("timeline", [])}
    if beat == "maker":
        a = marks.get("build", r0) + 2
        return a, min(n, r1 - a), "build -> PLAY -> match"
    if beat in ("levels", "end"):
        a = r0 + 2
        return a, min(n, r1 - a), "scripted"
    lo = r0 + 18                            # let the camera settle after the cut-in
    hi = max(lo, r1 - n)
    multi = multi_kills(info["events"])
    best, best_a = -1.0, lo
    for a in range(lo, hi + 1, 3):
        sc = score_window(info["events"], a, n, multi)
        if sc > best + 1e-6:
            best, best_a = sc, a
    return best_a, min(n, r1 - best_a), "score %.1f" % best


def describe(info, a, n):
    multi = multi_kills(info["events"])
    bits = []
    for e in info["events"]:
        if e.get("rendering") and e.get("on") and a <= e["f"] - 1 < a + n:
            k = e["kind"]
            if k == "kill":
                k = "multi-kill" if e["f"] in multi else "kill (%s)" % e.get("weapon", "")
            bits.append(k)
    out = {}
    for b in bits:
        out[b] = out.get(b, 0) + 1
    return ", ".join("%s x%d" % (k, v) if v > 1 else k for k, v in out.items()) or "-"


def run(cmd):
    print("+ " + " ".join(cmd[:6]) + (" ..." if len(cmd) > 6 else ""), flush=True)
    r = subprocess.run(cmd)
    if r.returncode != 0:
        sys.exit("trailer_edit: ffmpeg failed (%d)" % r.returncode)


def on_beat(edit, music_from, last_free=True):
    """Shot lengths nudged (by under half a beat) so every crossfade is centred
    on a beat of the soundtrack."""
    out = []
    t = 0.0
    for i, row in enumerate(edit):
        secs = row[1]
        if i < len(edit) - 1 or not last_free:
            mid = t + secs - XFADE * 0.5 + music_from - BEAT0
            k = round(mid / BEAT)
            secs += k * BEAT - mid
        out.append((row[0], secs) + tuple(row[2:]))
        t += secs - XFADE
    return out


def build_trailer(ff, raw, out, plan, url_note, preview=False):
    inputs = []
    t = 0.0
    shots = []
    for i, (beat, secs, card, card_at) in enumerate(on_beat(EDIT, MUSIC_FROM)):
        info = load_beat(raw, beat)
        a, n, why = pick_window(info, secs)
        dur = n / float(FPS)
        inputs += ["-ss", "%.4f" % (a / float(FPS)), "-t", "%.4f" % dur, "-i", os.path.join(raw, beat + ".avi")]
        shots.append({"beat": beat, "start": t, "dur": dur, "map": info.get("map", ""), "src": a, "why": why,
                      "trigger": info.get("trigger", ""), "card": card, "card_at": card_at,
                      "what": describe(info, a, n)})
        t += dur - (XFADE if i < len(EDIT) - 1 else 0.0)
    total = t
    if plan:
        return shots, total
    nb = len(EDIT)
    scale = "scale=1280:720:flags=lanczos," if preview else ""
    fc = []
    for i in range(nb):
        fc.append("[%d:v]%sfps=%d,format=yuv420p,setpts=PTS-STARTPTS[v%d]" % (i, scale, FPS, i))
        fc.append("[%d:a]aresample=48000,asetpts=PTS-STARTPTS[a%d]" % (i, i))
    cur_v, cur_a = "v0", "a0"
    off = 0.0
    for i in range(1, nb):
        off += shots[i - 1]["dur"] - XFADE
        fc.append("[%s][v%d]xfade=transition=fade:duration=%.3f:offset=%.4f[x%d]" % (cur_v, i, XFADE, off, i))
        fc.append("[%s][a%d]acrossfade=d=%.3f:c1=tri:c2=tri[y%d]" % (cur_a, i, XFADE, i))
        cur_v, cur_a = "x%d" % i, "y%d" % i
    # Title cards.
    k = nb
    for s in shots:
        if not s["card"]:
            continue
        cdir = os.path.join(raw, "cards", "card_" + s["card"])
        inputs += ["-framerate", str(FPS), "-i", os.path.join(cdir, "f_%04d.png")]
        at = s["start"] + s["card_at"]
        cs = "scale=1280:720," if preview else ""
        fc.append("[%d:v]%sformat=rgba,setpts=PTS-STARTPTS+%.4f/TB[c%d]" % (k, cs, at, k))
        fc.append("[%s][c%d]overlay=0:0:eof_action=pass:format=auto[o%d]" % (cur_v, k, k))
        cur_v = "o%d" % k
        k += 1
    # Soundtrack under the game's own sound.
    inputs += ["-ss", "%.3f" % MUSIC_FROM, "-t", "%.3f" % (total + 0.5), "-i", MUSIC]
    fc.append("[%d:a]aresample=48000,volume=0.62,afade=t=in:d=0.8,afade=t=out:st=%.3f:d=3.2[mus]" % (k, total - 3.4))
    fc.append("[%s]volume=0.9,afade=t=out:st=%.3f:d=2.0[sfx]" % (cur_a, total - 2.2))
    fc.append("[sfx][mus]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.9,"
              "loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000[aout]")
    fc.append("[%s]format=yuv420p[vout]" % cur_v)
    dst = os.path.join(out, "tracerfall-trailer%s.mp4" % ("-preview" if preview else ""))
    cmd = [ff, "-y", "-v", "error", "-stats"] + inputs + [
        "-filter_complex", ";".join(fc), "-map", "[vout]", "-map", "[aout]",
        "-c:v", "libx264", "-preset", "veryfast" if preview else "medium", "-crf", "26" if preview else "18",
        "-profile:v", "high", "-pix_fmt", "yuv420p", "-r", str(FPS), "-threads", "2",
        "-c:a", "aac", "-b:a", "192k", "-movflags", "+faststart",
        "-metadata", "title=Tracerfall - gameplay trailer", "-metadata", "comment=" + url_note,
        "-t", "%.3f" % total, dst]
    run(cmd)
    return shots, total


def build_vertical(ff, raw, out):
    """30 s 1080x1920: the centre 1080x1080 of each shot (native pixels) over a
    blurred, darkened copy, the logo above and the call to action below."""
    inputs = []
    fc = []
    t = 0.0
    shots = []
    for i, (beat, secs) in enumerate(on_beat(VERTICAL, MUSIC_FROM + 10.0)):
        info = load_beat(raw, beat)
        a, n, _why = pick_window(info, secs)
        # Hold the action: start the vertical cut at the same highlight but trim
        # to its own length around the middle of the 16:9 window.
        full_a, full_n, _ = pick_window(info, next(e[1] for e in on_beat(EDIT, MUSIC_FROM) if e[0] == beat))
        a = full_a + max(0, (full_n - n) // 2) if beat not in ("maker", "end") else full_a + (full_n - n if beat == "maker" else 0)
        dur = n / float(FPS)
        inputs += ["-ss", "%.4f" % (a / float(FPS)), "-t", "%.4f" % dur, "-i", os.path.join(raw, beat + ".avi")]
        shots.append((beat, t, dur))
        t += dur - (XFADE if i < len(VERTICAL) - 1 else 0.0)
    total = t
    nb = len(VERTICAL)
    for i in range(nb):
        fc.append("[%d:v]fps=%d,setpts=PTS-STARTPTS,split[s%d][t%d]" % (i, FPS, i, i))
        fc.append("[s%d]scale=3414:1920,crop=1080:1920,boxblur=28:2,eq=brightness=-0.16:saturation=0.8[bg%d]" % (i, i))
        fc.append("[t%d]crop=1080:1080:(iw-1080)/2:0[fg%d]" % (i, i))
        fc.append("[bg%d][fg%d]overlay=0:440,format=yuv420p[v%d]" % (i, i, i))
        fc.append("[%d:a]aresample=48000,asetpts=PTS-STARTPTS[a%d]" % (i, i))
    cur_v, cur_a = "v0", "a0"
    off = 0.0
    for i in range(1, nb):
        off += shots[i - 1][2] - XFADE
        fc.append("[%s][v%d]xfade=transition=fade:duration=%.3f:offset=%.4f[x%d]" % (cur_v, i, XFADE, off, i))
        fc.append("[%s][a%d]acrossfade=d=%.3f:c1=tri:c2=tri[y%d]" % (cur_a, i, XFADE, i))
        cur_v, cur_a = "x%d" % i, "y%d" % i
    k = nb
    # Static header + footer for the whole cut, the vertical end card at the end.
    for name, at, dur in (("v_head", 0.0, total - 3.4), ("v_foot", 0.6, total - 4.0), ("v_end", total - 3.6, 3.6)):
        cdir = os.path.join(raw, "cards", "card_" + name)
        if name == "v_end":
            inputs += ["-framerate", str(FPS), "-i", os.path.join(cdir, "f_%04d.png")]
            fade = ""
        else:   # a still: loop it, fade in / out
            inputs += ["-loop", "1", "-framerate", str(FPS), "-t", "%.3f" % dur, "-i", os.path.join(cdir, "f_0000.png")]
            fade = ",fade=t=in:st=0:d=0.5:alpha=1,fade=t=out:st=%.3f:d=0.4:alpha=1" % (dur - 0.4)
        fc.append("[%d:v]format=rgba%s,setpts=PTS-STARTPTS+%.4f/TB[c%d]" % (k, fade, at, k))
        fc.append("[%s][c%d]overlay=0:0:eof_action=pass:format=auto[o%d]" % (cur_v, k, k))
        cur_v = "o%d" % k
        k += 1
    inputs += ["-ss", "%.3f" % (MUSIC_FROM + 10.0), "-t", "%.3f" % (total + 0.5), "-i", MUSIC]
    fc.append("[%d:a]aresample=48000,volume=0.62,afade=t=in:d=0.4,afade=t=out:st=%.3f:d=2.4[mus]" % (k, total - 2.6))
    fc.append("[%s]volume=0.9,afade=t=out:st=%.3f:d=1.6[sfx]" % (cur_a, total - 1.8))
    fc.append("[sfx][mus]amix=inputs=2:duration=first:normalize=0,alimiter=limit=0.9,"
              "loudnorm=I=-14:TP=-1.5:LRA=11,aresample=48000[aout]")
    fc.append("[%s]format=yuv420p[vout]" % cur_v)
    dst = os.path.join(out, "tracerfall-trailer-vertical.mp4")
    run([ff, "-y", "-v", "error", "-stats"] + inputs + [
        "-filter_complex", ";".join(fc), "-map", "[vout]", "-map", "[aout]",
        "-c:v", "libx264", "-preset", "medium", "-crf", "20", "-profile:v", "high", "-pix_fmt", "yuv420p",
        "-r", str(FPS), "-threads", "2", "-c:a", "aac", "-b:a", "160k", "-movflags", "+faststart",
        "-t", "%.3f" % total, dst])
    return total


def export_art(raw, shots, shot_dir, media_dir):
    """Key art: per beat, the director's still nearest the middle of the shot
    that made the cut (full-quality 1920x1080 PNG -> JPG)."""
    from PIL import Image
    os.makedirs(shot_dir, exist_ok=True)
    os.makedirs(media_dir, exist_ok=True)
    chosen = []
    by_beat = {s["beat"]: s for s in shots}
    for beat in KEY_ART:
        if len(chosen) >= 8 or beat not in by_beat:
            continue
        info = load_beat(raw, beat)
        s = by_beat[beat]
        a = s["src"]
        n = int(s["dur"] * FPS)
        stills = [st for st in info.get("stills", []) if os.path.exists(os.path.join(raw, st["path"]))]
        if not stills:
            continue
        inside = [st for st in stills if a <= st["f"] - 1 < a + n] or stills
        mid = a + n * 0.5
        pref = {"explosion": 0, "kill": 1, "wreck": 0, "flag_capture": 0, "periodic": 2}
        inside.sort(key=lambda st: (pref.get(st["tag"].split("_")[0], 1), abs(st["f"] - 1 - mid)))
        src = os.path.join(raw, inside[0]["path"])
        dst = os.path.join(shot_dir, "trailer-%s.jpg" % beat)
        Image.open(src).convert("RGB").save(dst, "JPEG", quality=90, optimize=True, progressive=True)
        chosen.append((beat, dst, src))
    # Cover (itch.io 630x500): the HD close-up or the opener, cropped to 1.26:1,
    # with the cover card (logo + line) on top.
    cover_src = None
    for want in ("hd", "open", "night", "boom"):
        for beat, dst, src in chosen:
            if beat == want:
                cover_src = src
                break
        if cover_src:
            break
    if cover_src:
        im = Image.open(cover_src).convert("RGB")
        w, h = im.size
        cw = int(h * 630 / 500)
        x0 = (w - cw) // 2
        im = im.crop((x0, 0, x0 + cw, h)).resize((630, 500), Image.LANCZOS)
        card = os.path.join(raw, "cards", "card_cover", "f_0000.png")
        if os.path.exists(card):
            ov = Image.open(card).convert("RGBA")
            im = Image.alpha_composite(im.convert("RGBA"), ov).convert("RGB")
        im.save(os.path.join(media_dir, "cover-630x500.png"), optimize=True)
    return chosen


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--raw", default="build/trailer/raw")
    ap.add_argument("--out", default="build/trailer")
    ap.add_argument("--plan", action="store_true", help="print the shot list only")
    ap.add_argument("--preview", action="store_true", help="fast 720p encode of the 16:9 cut only")
    ap.add_argument("--no-vertical", action="store_true")
    ap.add_argument("--no-art", action="store_true")
    ap.add_argument("--shots-dir", default="docs/screenshots")
    ap.add_argument("--media-dir", default="docs/media")
    ap.add_argument("--url", default="github.com/Predator04/Tracerfall")
    a = ap.parse_args()
    ff = ffmpeg_bin()
    os.makedirs(a.out, exist_ok=True)
    shots, total = build_trailer(ff, a.raw, a.out, a.plan or False, a.url, a.preview)
    lines = ["Tracerfall trailer - shot list (%.1f s)" % total]
    for s in shots:
        lines.append("%5.1f-%5.1f  %-7s %-11s %-9s %s%s" % (
            s["start"], s["start"] + s["dur"], s["beat"], s["map"], s["trigger"], s["what"],
            "  [card: %s @ %.1f s]" % (s["card"], s["start"] + s["card_at"]) if s["card"] else ""))
    print("\n".join(lines))
    if a.plan:
        return
    with open(os.path.join(a.out, "shotlist.txt"), "w") as f:
        f.write("\n".join(lines) + "\n")
    if a.preview:
        return
    if not a.no_vertical:
        vt = build_vertical(ff, a.raw, a.out)
        print("vertical cut %.1f s" % vt)
    if not a.no_art:
        for beat, dst, _src in export_art(a.raw, shots, a.shots_dir, a.media_dir):
            print("key art", dst)
        print("cover", os.path.join(a.media_dir, "cover-630x500.png"))


if __name__ == "__main__":
    main()
