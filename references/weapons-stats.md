# Soldat weapon stats (from server/configs/weapons.ini, v1.7.1)

Source: ~/soldat-base/server/configs/weapons.ini (OpenSoldat). 60 ticks = 1 sec.
Damage is a multiplier: final = Damage × CurrentSpeed × HitboxModifier.
Our game uses flat damage on a 100 HP soldier — convert ≈ Damage × Speed (chest).

| Weapon | Dmg | FireInt | Ammo | Reload | Speed | Style | Spread | Notes |
|---|---|---|---|---|---|---|---|---|
| Desert Eagles | 1.81 | 24 | 7 | 87 | 19 | 1 | 0.15 | semi |
| HK MP5 | 1.01 | 6 | 30 | 105 | 18.9 | 1 | 0.14 | auto |
| AK-74 | 1.11 | 11 | 40 | 150 | 24 | 1 | 0.09 | auto |
| Steyr AUG | 0.71 | 7 | 25 | 125 | 26 | 1 | 0.075 | auto |
| Spas-12 | 1.22 | 32 | 7 | 175 | 14 | 3 | 0.8 | shotgun |
| Ruger 77 | 2.49 | 39 | 4 | 84 | 33 | 1 | 0 | semi, high dmg |
| M79 | 1550 | 6 | 1 | 178 | 10.7 | 4 | 0 | explosive |
| Barrett M82A1 | 4.45 | 225 | 10 | 70 | 55 | 1 | 0 | sniper, StartUp=19, Bink=65 |
| FN Minimi | 0.85 | 9 | 50 | 250 | 27 | 1 | 0.064 | auto LMG |
| XM214 Minigun | 0.468 | 3 | 100 | 480 | 29 | 1 | 0.3 | StartUp=25 |
| USSOCOM | 1.49 | 10 | 14 | 60 | 18 | 1 | 0 | pistol |
| Combat Knife | 2150 | 6 | 1 | 3 | 6 | 11 | 0 | melee |
| Chainsaw | 50 | 2 | 200 | 110 | 8 | 11 | 0 | melee |
| M72 LAW | 1550 | 6 | 1 | 300 | 23 | 12 | 0 | explosive, StartUp=13 |
| Punch | 330 | 6 | 1 | 3 | 5 | 6 | 0 | melee |
| Stationary Gun | 1.8 | 10 | 100 | 366 | 36 | 14 | 0 | M2 MG |

Hitbox modifiers (default): Head 1.1, Chest 0.95, Legs 0.85.
(Exceptions: Ruger 1.2/1.05/1.0, Barrett 1.0/1.0/1.0.)

Bullet styles: 1=bullet, 3=shotgun, 4=M79 nade, 11=knife/chainsaw, 12=LAW missile.

Weapon sprite filenames (assets/weapons-gfx/):
Steyr AUG=steyraug.png, Ruger 77=ruger77.png, M79=m79.png, Barrett=barretm82.png,
FN Minimi=m249.png, Minigun=minigun.png, USSOCOM=colt1911.png, Knife=knife.png,
Chainsaw=chainsaw.png, LAW=law.png.

## Tracerfall values (#310) — what differs from classic and why

The game's numbers live in ONE place: `scripts/player.gd` `PRIMARY_WEAPONS` /
`SECONDARY_WEAPONS` (bots read them through `bot.gd gun_stats()`, which keeps
only the bot fire cadence `rate` of its own). Flat damage on 100 HP, no
hitbox multipliers (the Realistic setting makes head hits lethal instead).

| Weapon | Dmg | Rate s | Mag | Reload s | Spread rad | Speed px/s | vs classic |
|---|---|---|---|---|---|---|---|
| Deagles | 34 | 0.30 | 14 | 1.5 | 0.02 | 1200 | ≈ classic (dmg 1.81×19) |
| MP5 | **15** | 0.075 | 32 | 1.8 | 0.085 | 950 | #310: 13 → 15. Classic 19 dmg at 0.1 s; ours fires faster, so less per bullet — at 13 the SMG lost to the AK even at 100 px (0.83 s vs 0.53 s to kill) |
| AK-74 | 22 | 0.11 | 30 | 2.0 | 0.055 | 1050 | faster + tighter than classic (26.6 at 0.183 s, 0.09); the default rifle |
| Steyr AUG | 18 | 0.117 | 25 | 2.08 | **0.05** | 1150 | #310: spread 0.075 → 0.05. Classic AUG is the accurate rifle (0.075 vs the AK's 0.09); with our tighter AK it was worse than the AK at every range (0.87 / 1.30 / 2.90 / 7.6 s vs 0.53 / 0.97 / 2.18 / 3.27 at 100 / 300 / 600 / 1000 px). Now: AK wins up close, AUG at range |
| Spas-12 | **11** ×8 | 0.6 | 8 | 2.5 | 0.26 | 850 | #310: pellet 9 → 11. Classic Spas is the close-range king; at 9 it took 1.28 s at 100 px (every auto rifle was faster) |
| Ruger 77 | 82 | 0.65 | 4 | 1.4 | 0 | 1450 | = classic (2.49×33) |
| M79 | **115** splash 130 | 0.10 | 1 | 2.97 | 0 | **640** | #310: 90 → 115 (a direct hit kills, as in classic, where it shares the LAW's explosive damage) and 470 → 640 px/s = classic 10.7 px/tick: at 470 with 980 gravity the shell could not reach 230 px on flat ground |
| Barrett | 245 | 3.75 | 10 | 1.17 | 0 | 2400 | ≈ classic, wind-up 0.32 s; one shot, one kill |
| Minimi | 23 | 0.15 | 50 | 4.17 | 0.064 | 1180 | = classic |
| Minigun | 13 | 0.05 | 100 | 8.0 | **0.24** | 1275 | #310: spread 0.3 → 0.24 (classic 0.3; classic spread is not radians). At 0.3 it was the slowest bullet gun to kill at 100 px (1.27 s) |
| Flamethrower | 19 | 0.06 | 200 | 5.0 | 0.12 | 420 (0.35 s life) | bonus-style; ~150 px reach |
| Rambo Bow | 100 | 1.0 | 1 | 2.5 | 0 | 900 (240 gravity) | one-shot kill by design (Rambomatch) |
| USSOCOM | 27 | 0.167 | 14 | 1.0 | 0 | 800 | = classic (1.49×18) |
| Knife / Chainsaw | 55 / 9 | 0.5 / 0.1 | | | | melee | |
| LAW | **115** splash 130 | 1.1 | 1 | 3.0 | 0 | 720 | #310: 90 → 115. Splash falls off from the soldier's feet, so a 90 rocket into the chest did ~83 and never killed (4.2–5.5 s to kill at any range, the slowest gun); 115 makes a body hit lethal like classic, a near miss still isn't |

Measured with `tools/balance_watch.gd` (duel harness + forced-loadout bot
matches, `tools/balance_report.py`); before / after tables are in issue #310.
Vehicles (#310): tank explosives multiplier 0.8 → 1.0 (never wrecked in 60
bot match-minutes; ~13 direct LAW hits before, 8 now).
