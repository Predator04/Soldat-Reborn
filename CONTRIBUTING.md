# Contributing

## Prerequisites

- Godot 4.7.2 (GL Compatibility renderer — the project targets `gl_compatibility`)
- Git

## Build & run

```sh
# Open in editor and run
godot --path .          # or open project.godot in the Godot editor, then F5

# Headless verify — MUST print zero lines matching error|invalid|nil|failed|attempt
godot --headless --path . --quit-after 900

# Windows export
godot --headless --export-release "Windows Desktop" build/SoldatReborn.exe
```

## Workflow rules

1. Preserve the Soldat **feel** — bunny-hop momentum, jet fuel management, weapon balance.
2. After **any** code change, run the headless verify. **Zero errors before you move on.**
3. Then export, then commit.
4. **Never commit code that fails the verify command.**
5. Update `ROADMAP.md` (check off what you did, add bugs to *Known bugs*) and
   `CHANGELOG.md` where behavior changed.

## Headless gotchas

- Headless mode skips `_draw()` — rendering bugs won't surface in verify. Inspect
  draw/transform math by reading, and confirm visually in the editor or exported build.
- Single-player has **no multiplayer peer**; `is_multiplayer_authority()` returns
  `false` in that case, so every authority check must guard
  `multiplayer.multiplayer_peer == null or` first.

## Project conventions

- `.tscn` files are minimal (root node + script only). Build shapes, visuals, and
  cameras in `_ready()` with code.
- Prefer `_draw()` for procedural art; use the standard signatures
  `draw_rect(Rect2, Color)`, `draw_circle(Vector2, float, Color)`,
  `draw_polygon(PackedVector2Array, PackedColorArray)`.
- GDScript 4 only (not Godot 3): `@export`/`@onready`, `CharacterBody2D.velocity` +
  `move_and_slide()`, `is_on_floor()`.

## Licensing

- Code you write: MIT.
- Assets: CC BY 4.0 (from `github.com/Soldat/base`) — do not strip the attribution
  in `CREDITS.md` when reusing or modifying them.
