extends Object
## MapGen — procedural map generator. Produces the same map-dict shape as
## MAPS entries in main.gd so generated maps feed the exact same play + save
## path as hand-authored ones (issue #32).
##
## Strategy: seed a horizontal-band skeleton so verticals stay within jump/jet
## range, add a few near-ground cover platforms, and pick bot spawns from
## platforms on the right half so play flows left → right.

const MAP_W := 4800.0
const MAP_H := 2000.0
const GROUND_Y := 1900.0


static func generate(seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var platforms: Array = []
	# Bands: five staggered horizontal strata, each with 2–4 platforms.
	# Vertical spacing 190–260 stays within jet-boot climb range.
	var band_ys: PackedFloat32Array = PackedFloat32Array()
	var y := GROUND_Y - 190.0
	while y > 320.0:
		band_ys.append(y)
		y -= rng.randf_range(200.0, 260.0)
	for by in band_ys:
		var count := rng.randi_range(2, 4)
		var xs: PackedFloat32Array = PackedFloat32Array()
		var tries := 0
		while xs.size() < count and tries < 40:
			var candidate := rng.randf_range(400.0, MAP_W - 400.0)
			var ok := true
			for x in xs:
				if abs(x - candidate) < 500.0:
					ok = false
					break
			if ok:
				xs.append(candidate)
			tries += 1
		for xx in xs:
			var w := rng.randf_range(180.0, 300.0)
			platforms.append({"p": Vector2(xx, by), "s": Vector2(w, 22)})
	# Cover: a few short platforms just above the ground for hiding + boosting.
	var cover_count := rng.randi_range(3, 5)
	for i in cover_count:
		var xx := rng.randf_range(400.0, MAP_W - 400.0)
		var w := rng.randf_range(140.0, 220.0)
		platforms.append({"p": Vector2(xx, GROUND_Y - rng.randf_range(80.0, 130.0)), "s": Vector2(w, 22)})
	# Player spawns far left on the ground; bots on right, prefer platform tops.
	var player_spawn := Vector2(220.0, GROUND_Y - 125.0)
	var candidates: Array = []
	for pl in platforms:
		if pl["p"].x > MAP_W * 0.45:
			candidates.append(pl["p"] + Vector2(0, -50.0))
	_shuffle(rng, candidates)
	var bot_spawns: Array = []
	for c in candidates:
		if bot_spawns.size() >= 4:
			break
		bot_spawns.append(c)
	while bot_spawns.size() < 4:
		bot_spawns.append(Vector2(MAP_W - 400.0 - float(bot_spawns.size()) * 220.0, GROUND_Y - 125.0))
	return {
		"name": "Generated %d" % (seed if seed >= 0 else -seed),
		"platforms": platforms,
		"player_spawn": player_spawn,
		"bot_spawns": bot_spawns,
	}


static func _shuffle(rng: RandomNumberGenerator, arr: Array) -> void:
	# Fisher-Yates using the seeded RNG so generation is deterministic per seed.
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
