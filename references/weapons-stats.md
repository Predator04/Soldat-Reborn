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
