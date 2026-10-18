extends RefCounted
## Bullet impact effects: ricochet sparks + dust + chips off terrain (kind
## "wall"), or a blood spurt + mist when a soldier is hit (kind "blood").
## Phase B (#271): no node per hit any more — both route into the pooled
## FxWorld (scripts/gfx/fx_world.gd), capped per quality. Lo-fi / Low: none;
## Blood slider 0: no blood.


static func spawn(parent: Node, at: Vector2, dir: Vector2, k: String) -> void:
	if parent == null or Settings.lofi:
		return
	if k == "blood" and float(Settings.blood_intensity) <= 0.0:
		return
	var w := FxWorld.ensure(parent)
	if w == null:
		return
	if k == "blood":
		w.blood_hit(at, dir)
	else:
		w.ricochet(at, dir)
