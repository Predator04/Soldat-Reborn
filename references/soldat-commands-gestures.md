# Soldat in-game commands, gestures & movement tech

Sources: wiki.soldat.pl "In-game Commands" + "Comprehensive Movement Tutorial".

## Player gestures (/commands — trigger .poa anims we already ported)
- /VICTORY — cheer → anim "cieszy"
- /SMOKE — light/end cigar → anim "cigar"/"cygaro"
- /TABAC — chew tobacco
- /TAKEOFF — remove helmet → anim "wyrzuca"
- /KILL — harakiri (suicide)
- /BRUTALKILL — violent suicide (gib yourself)
- /MERCY — animated suicide
- /PAUSE / /UNPAUSE

## Taunts
- ALT + a..z / 1..0 → ready taunts from TAUNTS.TXT (chat macros).

## Host chat commands (shipped v1.33.0 — host / single player, typed in chat)
/ADDBOT [skill 1-5] [name], /KICK <name> (peers or bots, prefix match),
/BOTS <n>, /GAMEMODE <0-9|name>, /MAP <name|index>, /RESTART, /SAY <msg>, /FF.
Unimplemented from the original's set: /BAN, /NEXTMAP, /LIMIT, /TIMELIMIT,
/PASSWORD, /REALISTIC, /ADVANCE, /SURVIVAL as commands (the last three are
host panel toggles).

## Movement tech (Haste's tutorial — most is emergent from bunny-hop + jet, but)
- **Roll**: crouch (S) during horizontal movement → momentary speed burst roll.
- **Backflip**: while facing backward relative to side-jump dir, hold jump mid-air + tap jet → flip with height.
- **Kick jump**: tap W on ground contact each landing to build momentum (our bunny-hop does this).
- **Half jump / full jump / side jump**: jump-button hold duration scales jump height (we have coyote/jump-buffer; hold-scaling TBD).
- **Prone-cancel / superman / cannonball**: advanced chained tech (lower priority).

## Spawn / respawn
- **Ceasefire**: brief invulnerability counter after respawn (prevents spawn-kills).
- Arrow above respawned player (we have this).
