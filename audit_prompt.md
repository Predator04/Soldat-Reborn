# Soldat Reborn — runtime-correctness audit + fix pass

Work in `/mnt/c/Users/Admin/Desktop/soldat reborn/game`. Godot 4.7 (GL Compatibility), ENet multiplayer, GDScript. Read CLAUDE.md first for the architecture map and hard rules.

This is a CORRECTNESS review (not style). The parse check already passes clean — I want RUNTIME bugs the compiler can't see. Audit these areas specifically:

1. **Netcode / replication gaps** — anything like the MTU oversize in `_broadcast_bot_state` (recently fixed): other RPC payloads that may exceed ENet MTU (~1392 bytes), unreliable packets that should be reliable (or vice versa), state that isn't replicated to late-joiners or remote peers.
2. **Multiplayer authority guard violations** — code paths that mutate shared state without `is_multiplayer_authority()` / `multiplayer.multiplayer_peer == null or ...` guards, which would desync or break single-player.
3. **Node / resource leaks** — nodes added but never freed, timers/HTTPRequests that outlive their owner (like the master-heartbeat leak that was fixed), ObjectDB leak sources. Especially in round-reset, map-change, and leave/quit paths.
4. **Edge cases in the recent fixes (#89–#103)** — bot ladders, GG scoreboard, weapon pickup pre-check, custom-map sync, grab_focus guards, net_bot_state positional array. Look for off-by-one, null derefs, dictionary key misses.

For each real bug you find:
- File it with `gh issue create --repo Predator04/Soldat-Reborn --title "..." --body "..."` (concise, with evidence/file:line).
- Then fix it. Work one at a time, commit + push each with `git add -A` (include `.gd.uid` files).
- Close with `gh issue close <n> -c "Done in <sha>"`.

## Hard rules
- Preserve ALL existing behavior — do NOT regress #89–#103 or earlier fixes.
- Keep all authority guards intact; single-player must keep working.
- Don't touch balance/movement constants.
- Verify after EVERY fix:
```
~/godot/Godot_v4.7.2-stable_linux.x86_64 --headless --quit-after 700 res://scenes/main.tscn 2>&1 | grep -iE "SCRIPT ERROR|Parse Error|Cannot load|Identifier not found|Invalid call|Cannot infer"
```
(Zero lines = pass.) For netcode changes, also re-run a dedicated server + `--smoke-join` to confirm bot replication still works.

Report at the end: list of issues found + fixed (with SHAs), and any real bugs you found but did NOT fix (with reason).
