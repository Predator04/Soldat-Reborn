# .poa animation format — reverse-engineered notes

`.poa` files (assets/anims/*.poa) describe the frame-by-frame joint
positions of Soldat's gostek (soldier) rig. They are plain ASCII, one
number per line, no header — the parser must walk the file top-to-bottom
until it hits `ENDFILE`.

## File layout

```
<part_id_1>
<float A>
<float B>
<float C>
<part_id_2>
<float A>
<float B>
<float C>
...
<part_id_20>
<float A>
<float B>
<float C>
NEXTFRAME
<part_id_1>
...
ENDFILE
```

Every frame is exactly **20 parts × 4 lines = 80 lines**, followed by a
literal `NEXTFRAME` marker. After the final frame the file terminates
with `ENDFILE` instead of `NEXTFRAME`.

### Frame count sanity check

For any file, `(total_lines) / 81` gives the frame count exactly:

| file            | lines | frames |
|-----------------|------:|-------:|
| stoi.poa        |  1377 |     17 |
| celuje.poa      |   567 |      7 |
| laduje.poa      |  1134 |     14 |
| skok.poa        |  2997 |     37 |
| biega.poa       |  3078 |     38 |

## The three floats

Each of the 20 part blocks stores three floats. Empirically:

- **Float A** — X position (horizontal). Range roughly `-2.4 .. +1.7`.
- **Float B** — always `0`, or near-zero noise (`~1e-11` in stoi,
  literally `0` in celuje). The rig is planar; this axis is unused.
- **Float C** — Y/Z position (vertical, positive-down in the model
  frame). Range roughly `-0.03 .. +6.15`.

Units appear to be an internal engine scale (not pixels); a runtime port
needs a per-project constant to map them to screen space. The
coordinate frame origin sits somewhere near the pelvis (parts 17/18
report ~0 on the vertical axis while standing, consistent with feet on
the ground).

## Part index guesses

The 20-part mapping is not spelled out in the asset drop; it lives in
Soldat's source. From what stays put across every frame of `stoi.poa`
(idle standing) vs what moves in `biega.poa` (running), a first-pass
guess is:

| id | inferred role                              | evidence                    |
|---:|--------------------------------------------|-----------------------------|
| 1  | head / neck top                            | small oscillation in idle   |
| 2  | neck / upper spine                         | stable near torso           |
| 3–4| torso corners                              | moderate motion             |
| 5–6| hip / pelvis anchors                       | small motion                |
| 7–8| upper leg endpoints                        | large swing in `biega`      |
| 9–10| lower leg endpoints                       | swing follows 7–8           |
| 11–12| upper arm endpoints                      | swings with running         |
| 13–14| lower arm endpoints                      | swings with running         |
| 15–16| hand / weapon-grip anchors               | tracks aim in `celuje`      |
| 17–18| left / right foot ground contact         | vertical ≈ 0 in `stoi`      |
| 19–20| accessory / tip anchors (backpack, hat?) | stable at large offset      |

The last two rows are the most speculative — a definitive mapping needs
the Soldat gostek.pas source at github.com/Soldat/soldat.

## Parse pseudocode

```
lines = read_all_lines(path)
frames = []
i = 0
while i < len(lines):
    if lines[i] == "ENDFILE":
        break
    frame = {}
    for _ in range(20):
        part_id = int(lines[i]); i += 1
        x       = float(lines[i]); i += 1
        _y      = float(lines[i]); i += 1   # always 0, ignored
        z       = float(lines[i]); i += 1
        frame[part_id] = (x, z)
    assert lines[i] in ("NEXTFRAME", "ENDFILE")
    if lines[i] == "ENDFILE":
        frames.append(frame); break
    i += 1
    frames.append(frame)
```

## Body-part sprites (assets/gostek-gfx)

Polish filenames from the original assets. Each has a `*2.png`
mirror-image variant used when the soldier is drawn facing left (per
`gostek-gfx/help.txt`, the `2` suffix is NOT a team marker — it is the
flipped sprite).

| file          | meaning                    |
|---------------|----------------------------|
| klata.png     | chest / torso              |
| morda.png     | face / head                |
| helm.png      | helmet                     |
| kap.png       | cap                        |
| kamizelka.png | bulletproof vest           |
| biodro.png    | hip / pelvis               |
| udo.png       | thigh                      |
| noga.png      | shin                       |
| stopa.png     | foot                       |
| lecistopa.png | foot while jet is firing   |
| ramie.png     | upper arm / shoulder       |
| reka.png      | forearm                    |
| dlon.png      | hand / palm                |
| dred.png, hair1..4.png | hair variants     |
| badge.png     | Rambo band                 |
| cygaro.png    | cigarette                  |
| lancuch.png / zlotylancuch.png | dogtag chain / gold chain |
| metal.png / zloto.png | dogtag / gold link |
| para.png, para-rope.png | parachute       |

## Status

- Format structure: **confirmed**.
- X/Y/Z semantics: **confirmed** (middle axis unused, first is
  horizontal, third is vertical).
- Part-id → body-part mapping: **inferred, not verified**. The static
  gostek pose ships now uses hand-tuned pixel offsets rather than the
  `.poa` positions. The animation rig that consumes these frames is a
  follow-up.
