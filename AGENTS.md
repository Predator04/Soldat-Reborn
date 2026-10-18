# AGENTS.md — Tracerfall (formerly Soldat Reborn)

Godot 4.7 project (GDScript). 2D jetpack shooter.

## Non-negotiable conventions

- **1x scale** — do NOT upscale art/assets (2x was explicitly rejected by William).
- **Movement is SLOWER than Godot defaults** — defaults were ~3x too fast; currently tuned ~10% slower per iteration. Do not restore default speeds or "fix" movement to feel faster.

## Architecture

- This repo = the Godot game only.
- Master/lobby server is a SEPARATE Go binary: repo `Predator04/soldat-master-server`, hosted on Oracle Cloud (`161.153.9.69:8080`, systemd `soldat-master`). Deploy with the update script in SERVER_HOSTING_NOTES.md (repo root's parent). It is NOT built in this project — don't try to add server logic here.
- The official game server ("Tracerfall Official") runs on the same box, auto-updating from this repo's latest GitHub release.

## Dev procedure

- See CLAUDE.md (the source of truth): verify command, smoke tests, release
  gate, release process. Releases are signed (`keys/` lives outside the repo,
  one level up) — build_release.sh signs, sync.py uploads and refuses an
  unsigned exe.
