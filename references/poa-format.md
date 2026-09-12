# .poa animation format — definitive spec

Verified against the original Soldat source (MIT):
- `shared/Anims.pas` (loader / parser)
- `client/GostekGraphics.pas` + `client/GostekGraphics.inc` (sprite → skeleton binding)

## File layout

Plain ASCII, one value per line, read with `PhysFS_ReadLN`. No header.

The parser reads a line `r1` and:

- If `r1 == "ENDFILE"` → done.
- Else if `r1 == "NEXTFRAME"` → increment frame counter, keep reading.
- Else `r1` is a **1-based part index** (`1..20`). Read three more lines
  `r2, r3, r4` = the three floats for this joint, then continue.

Per Soldat's constants: `MAX_POS_INDEX = 20`, `MAX_FRAMES_INDEX = 40`.
Frames are 1-indexed in Pascal; the file begins mid-frame-1 (no leading
`NEXTFRAME`). Every part-block is exactly 4 lines (id, x, y, z), so a
frame that lists all 20 joints is `20 * 4 = 80` lines, followed by
`NEXTFRAME` (or `ENDFILE` after the last frame).

Not every part index is required to appear in every frame — the parser
tolerates missing/duplicate indices and simply overwrites `Pos[id]`.

## What the three floats mean

From `Anims.pas.LoadFromFile`:

```pascal
const SCALE = 3;
...
Frames[NumFrames].Pos[p].X := -SCALE * StrToFloat(r2) / 1.1;
Frames[NumFrames].Pos[p].Y := -SCALE * StrToFloat(r4);
```

So the file's three floats are `(x, y, z)` but **only `x` and `z` are
loaded**. The middle value (`y`) is discarded — the rig is planar. The
loaded skeleton coordinates are:

| axis | formula                             | notes                       |
|------|-------------------------------------|-----------------------------|
| X    | `-SCALE * raw_x / 1.1`              | X flipped, squished by 1.1  |
| Y    | `-SCALE * raw_z`                    | Z flipped → Godot-Y (down+) |

`SCALE = 3` is a global scale factor for the skeleton geometry. In the
loaded frame, feet sit at Y ≈ 0 and the head top sits at Y ≈ -18,
matching a soldier ~18 units tall. Renderers typically apply an
additional pixel-scale.

## Frame playback

`TAnimation` carries `Speed` (ticks per frame), `Loop`, `NumFrames`,
`CurrFrame`. `DoAnimation`:

```pascal
Inc(Count);
if Count = Speed then begin
  Count := 0;
  Inc(CurrFrame);
  if CurrFrame > NumFrames then
    CurrFrame := (Loop ? 1 : NumFrames);
end;
```

So `Speed` is a divider on tick rate; the game runs its animation
counter at physics tick rate (~60 Hz in Soldat).

Anim table (from `Anims.pas.LoadAnimObjects`; `Speed` defaults to 1,
`Loop` to False):

| file (`.poa`)      | game name    | Speed | Loop |
|--------------------|--------------|:-----:|:----:|
| stoi               | Stand        |   3   |  yes |
| biega              | Run          |   1   |  yes |
| biegatyl           | RunBack      |   1   |  yes |
| skok               | Jump         |   1   |  no  |
| skokwbok           | JumpSide     |   1   |  no  |
| spada              | Fall         |   1   |  no  |
| kuca               | Crouch       |   1   |  no  |
| kucaidzie          | CrouchRun    |   2   |  yes |
| kucaidzietyl       | CrouchRunBk  |   2   |  yes |
| laduje             | Reload       |   2   |  no  |
| rzuca              | Throw        |   1   |  no  |
| odrzut             | Recoil       |   1   |  no  |
| odrzut2            | SmallRecoil  |   1   |  no  |
| shotgun            | Shotgun      |   1   |  no  |
| clipout            | ClipOut      |   3   |  no  |
| clipin             | ClipIn       |   3   |  no  |
| slideback          | SlideBack    |   2   |  yes |
| change             | Change       |   1   |  no  |
| wyrzuca            | ThrowWeapon  |   1   |  no  |
| bezbroni           | WeaponNone   |   3   |  no  |
| bije               | Punch        |   1   |  no  |
| strzala            | ReloadBow    |   1   |  no  |
| barret             | Barret       |   9   |  no  |
| skokdolobrot       | Roll         |   1   |  no  |
| skokdolobrottyl    | RollBack     |   1   |  no  |
| lezy               | Prone        |   1   |  no  |
| lezyidzie          | ProneMove    |   2   |  yes |
| wstaje             | GetUp        |   1   |  no  |
| celuje             | Aim          |   2   |  no  |
| celujeodrzut       | AimRecoil    |   1   |  no  |
| gora               | HandsUpAim   |   2   |  no  |
| goraodrzut         | HandsUpRcl   |   1   |  no  |
| takeoff            | TakeOff      |   2   |  no  |
| cigar/match/smoke/wipe/cieszy/cygar/krocze/szcza/samo/samo2/kolba/rucha | (idle chatter / poses) | 1–8 | no |

## Skeleton — the 20 joints

Every frame provides positions for indices `1..20`. The renderer draws
each body-part sprite as an **oriented segment between two joints**
(see next section). Inferred joint roles, cross-checked against the
p1/p2 pairs used by every default sprite:

| id | joint                     | evidence (sprite p1/p2)                       |
|---:|---------------------------|-----------------------------------------------|
|  1 | right foot (ankle)        | RIGHT_LOWERLEG.p2, RIGHT_FOOT.p1              |
|  2 | left foot (ankle)         | LEFT_LOWERLEG.p2, LEFT_FOOT.p1                |
|  3 | left knee                 | LEFT_THIGH.p2, LEFT_LOWERLEG.p1               |
|  4 | right knee                | RIGHT_THIGH.p2, RIGHT_LOWERLEG.p1             |
|  5 | right hip                 | RIGHT_THIGH.p1, HIP.p1                        |
|  6 | left hip                  | LEFT_THIGH.p1, HIP.p2                         |
|  7 | (unused by default parts) |                                               |
|  8 | (unused by default parts) |                                               |
|  9 | head bottom / neck        | HEAD.p1, HAIR.*.p1                            |
| 10 | right shoulder / chest a  | RIGHT_ARM.p1, CHEST.p1                        |
| 11 | left shoulder / chest b   | LEFT_ARM.p1, CHEST.p2                         |
| 12 | head top                  | HEAD.p2                                       |
| 13 | right elbow               | RIGHT_ARM.p2, RIGHT_FOREARM.p1                |
| 14 | left elbow                | LEFT_ARM.p2, LEFT_FOREARM.p1                  |
| 15 | left wrist                | LEFT_FOREARM.p2, LEFT_HAND.p1, GRABBED.p1     |
| 16 | right wrist               | RIGHT_FOREARM.p2, RIGHT_HAND.p1, PRIMARY.p1   |
| 17 | right foot tip            | RIGHT_FOOT.p2, RIGHT_JETFOOT.p2               |
| 18 | left foot tip             | LEFT_FOOT.p2, LEFT_JETFOOT.p2                 |
| 19 | left hand tip             | LEFT_HAND.p2                                  |
| 20 | right hand tip / muzzle   | RIGHT_HAND.p2, PRIMARY.p2                     |

Points 7 and 8 exist in the file but no default sprite references
them — they act as intermediate spine / carry-anchor points used by
Soldat's physics skeleton, not by the visible sprites.

## Sprite → skeleton binding (GostekGraphics)

Every visible piece is one `Def(…)` in `GostekGraphics.inc`:

```pascal
Def(Name, Image, p1, p2, cx, cy, Visible, Flip, Team, Flex, Color, Alpha)
```

| field   | meaning                                                                 |
|---------|-------------------------------------------------------------------------|
| Image   | texture (GFX_GOSTEK_UDO → udo.png, GFX_GOSTEK_STOPA → stopa.png, …)     |
| p1, p2  | the two skeleton joints (1..20) the sprite hangs between                |
| cx, cy  | pivot inside the sprite, as a fraction of `(width, height)`             |
| Visible | 1 = shown by default (member of `GostekBase`)                           |
| Flip    | 1 = has a horizontally-mirrored sibling sprite (Tex+1) for facing left  |
| Team    | 1 = has a team-2 sibling sprite offset by `GFX_GOSTEK_TEAM2_STOPA - …`  |
| Flex    | 0 = draw at native size; >0 = stretch X so length ≈ dist(p1,p2)/Flex    |
| Color   | which player color modulates it: MAIN=shirt, PANTS, SKIN, HAIR, NONE    |
| Alpha   | BASE / BLOOD / NADES alpha bucket                                       |

`RenderGostek` (per sprite):

```
x1,y1 = skeleton[p1];  x2,y2 = skeleton[p2]
r     = atan2(y2 - y1, x2 - x1)          # bone angle
sx, sy = 1, 1
if soldier.direction != 1:               # facing left
  if gs.Flip: cy = 1 - cy; tex = tex + 1  # use mirror sprite
  else:      sy = -1                       # mirror in local Y
if gs.Flex > 0:
  sx = min(1.5, sqrt((x2-x1)^2 + (y2-y1)^2) / gs.Flex)
cx *= tex.width;  cy *= tex.height
# draw quad: anchor (x1, y1+1), rotate r, scale (sx, sy), pivot (cx, cy)
```

The transform matrix (from `DrawGostekSprite`) unrolled:

```
m = [ cos r * sx,  -sin r * sy,  x - cy·m3 - cx·m0 ]
    [ sin r * sx,   cos r * sy,  y - cy·m4 - cx·m1 ]
    [ 0,            0,            1                ]
```

i.e. rotate + scale, then translate so that the pivot `(cx, cy)` in
sprite-local pixels lands on `(x1, y1+1)`.

Draw order matters — everything iterates `GOSTEK_FIRST..GOSTEK_LAST`
(back-to-front in inc order). Rough back-to-front layering:
secondary weapon on back → grenades → left leg → left arm → head/hair
→ chest+vest → hip → right leg → primary weapon → right arm.

## The "base visible" body parts (what to draw for a plain soldier)

Filtering `.inc` for `Visible=1` — the always-on skeleton pieces:

| Def constant             | file           | p1 | p2 | cx    | cy   | Flex | Color   |
|--------------------------|----------------|:--:|:--:|:-----:|:----:|:----:|---------|
| GOSTEK_LEFT_THIGH        | udo.png        |  6 |  3 | 0.20  | 0.50 |  5   | PANTS   |
| GOSTEK_LEFT_FOOT         | stopa.png      |  2 | 18 | 0.35  | 0.35 |  0   | NONE    |
| GOSTEK_LEFT_LOWERLEG     | noga.png       |  3 |  2 | 0.15  | 0.55 |  0   | PANTS   |
| GOSTEK_LEFT_ARM          | ramie.png      | 11 | 14 | 0.00  | 0.50 |  0   | MAIN    |
| GOSTEK_LEFT_FOREARM      | reka.png       | 14 | 15 | 0.00  | 0.50 |  5   | MAIN    |
| GOSTEK_LEFT_HAND         | dlon.png       | 15 | 19 | 0.00  | 0.40 |  0   | SKIN    |
| GOSTEK_RIGHT_THIGH       | udo.png        |  5 |  4 | 0.20  | 0.65 |  5   | PANTS   |
| GOSTEK_RIGHT_FOOT        | stopa.png      |  1 | 17 | 0.35  | 0.35 |  0   | NONE    |
| GOSTEK_RIGHT_LOWERLEG    | noga.png       |  4 |  1 | 0.15  | 0.55 |  0   | PANTS   |
| GOSTEK_CHEST             | klata.png      | 10 | 11 | 0.10  | 0.30 |  0   | MAIN    |
| GOSTEK_HIP               | biodro.png     |  5 |  6 | 0.25  | 0.60 |  0   | MAIN    |
| GOSTEK_HEAD              | morda.png      |  9 | 12 | 0.00  | 0.50 |  0   | SKIN    |
| GOSTEK_RIGHT_ARM         | ramie.png      | 10 | 13 | 0.00  | 0.60 |  0   | MAIN    |
| GOSTEK_RIGHT_FOREARM     | reka.png       | 13 | 16 | 0.00  | 0.60 |  5   | MAIN    |
| GOSTEK_RIGHT_HAND        | dlon.png       | 16 | 20 | 0.00  | 0.50 |  0   | SKIN    |

Extras toggled by game state (from `RenderGostek`):
- Jetpack firing → replace `LEFT/RIGHT_FOOT` with `LEFT/RIGHT_JETFOOT` (lecistopa.png)
- Dead → replace `HEAD` with `HEAD_DEAD` (same sprite, different pivot/alpha bucket)
- Helmet visible → add `GOSTEK_HELMET` (helm.png, p1=9, p2=12)
- Blood alpha > 0 → add `*_DMG` overlays

## Parse pseudocode (matches Anims.pas exactly)

```
SCALE = 3.0
frames = []                          # 1-based in Pascal → 0-based here
cur = {}                             # part_id -> Vector2
lines = read_all_lines(path)
i = 0
while i < len(lines):
    line = lines[i].strip()
    if line == "ENDFILE":
        frames.append(cur); break
    if line == "NEXTFRAME":
        frames.append(cur); cur = {}; i += 1; continue
    part_id = int(line);      i += 1
    raw_x   = float(lines[i]); i += 1
    _y      = lines[i];        i += 1     # discarded (planar rig)
    raw_z   = float(lines[i]); i += 1
    if 1 <= part_id <= 20:
        cur[part_id] = Vector2(-SCALE * raw_x / 1.1, -SCALE * raw_z)
```

Interior missing joints inherit from the previous frame in Soldat's
implementation (the array is never zeroed between frames). Ports may
either seed each new frame from the previous or track a per-joint
"last known value" — the shipped animations always list all 20 joints,
so in practice this doesn't matter for the base set.

## Status

- File structure, float semantics, part-id table: **verified against
  Anims.pas + GostekGraphics.pas/.inc**.
- Sprite bindings for the base visible body: **verified from
  GostekGraphics.inc** (see the table above).
- Extra state overlays (helmet, chains, cygar, weapons on back, etc.)
  are documented in `GostekGraphics.inc` — pull them in as needed.

## Body-part sprite files (assets/gostek-gfx)

Polish filenames from the original assets. Each has a `*2.png`
mirror-image variant used when the soldier is drawn facing left (per
`gostek-gfx/help.txt`, the `2` suffix is NOT a team marker — it is the
horizontally-flipped sprite).

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
