# Soldat Reborn — Godot 4 prototype

A Godot 4.7 rebuild of the classic Soldat *feel*: run-and-gun with jet boots, bunny hopping, and gibs.

## Run it

**Easiest — double-click the build:**
`game\build\SoldatReborn.exe`

**Or in the editor (to iterate):**
1. Open `game\GodotEngine\Godot_v4.7.2-stable_win64.exe` (the editor, in the GodotEngine folder)
2. Import/Open the `game` folder as a project
3. Press **F5** to run

## Controls

| Key | Action |
|-----|--------|
| A / D | Move left / right |
| SPACE / W | Jump (ground) · jet boots (hold in air) |
| Mouse | Aim |
| Left click | Shoot |

## What's in it

- **Soldier** — run, jump, bunny hop (ground jumps give a speed boost), jet boots with a fuel bar that regens on ground
- **3 AI bots** — chase you, jet up to reach you, shoot
- **Bullets** — hit opposing team, die on terrain, muzzle recoil
- **Gibs** — blood particle burst on death, auto-respawn
- **Arena** — gradient sky + stars, ground, platforms, walls

## Project layout

- `scenes/` — main, player, bullet, bot scenes
- `scripts/` — main.gd (arena builder), player.gd, bot.gd, bullet.gd, sky.gd
- `build/` — exported Windows .exe

## Next steps (ideas)

- Proper sprites/art (currently programmer-art rectangles)
- Weapon variety + reload
- Real maps (larger, camera follow)
- Multiplayer (Godot high-level ENet)
- Jetpack flame particles + screen shake + sound
