class_name FxWorld
extends Node2D
## Graphics Phase B (#271): the pooled combat-effects system. One per match
## (match_world.gd adds it under Main, before any soldier, so its back layer
## draws behind soldiers). COSMETIC ONLY: it reads soldier fields and does
## terrain ray-tests, and never writes game state, touches physics bodies or the
## network, or reads the global random stream (Gfx.rng only).
##
## Nothing here is instantiated per effect. Every effect is a slot in a
## fixed-size pool (structure-of-arrays, sized per quality when the match starts
## or the quality changes) and the whole lot is drawn by four canvas items:
##   Decals (z 0)  blood splats + scorch marks, a ring buffer that recycles the
##                 oldest; redrawn only when one is added or a few times a second
##                 while they dry / fade.
##   Back   (z 0)  smoke, dust, blood mist, droplets, debris, shell casings and
##                 gibs — tree-ordered before soldiers, so they sit behind them.
##   Add    (z 60) additive: glows, muzzle stars, sparks, embers.
##   Heat   (z 66) High only: screen-reading heat haze (explosion rings, jets).
## Pools (Low / Medium / High):  particles 0/420/1000 (with per-kind caps),
## gibs 0/28/72, casings 0/24/64, decals 0/96/256, heat rings 0/0/6,
## wound spurts 0/6/16, terrain-testing blood drops 0/16/48.
## Vehicles (#276 / #277) use the same particle kinds: wheel_dust, vehicle_sparks,
## vehicle_burn, vehicle_wreck, rotor_wash (no pools of their own).

const Gfx = preload("res://scripts/gfx.gd")
const Gostek = preload("res://scripts/gostek.gd")
const HEAT_SHADER = preload("res://scripts/gfx/heat_haze.gdshader")

enum { K_SPARK, K_EMBER, K_GLOW, K_STAR, K_SMOKE, K_DUST, K_MIST, K_DROP, K_DEBRIS, K_COUNT }
const ADD_KINDS := K_STAR       # kinds <= this draw on the additive layer

const CAP_PARTS := [0, 420, 1000]
const CAP_GIBS := [0, 28, 72]
const CAP_CASINGS := [0, 24, 64]
const CAP_DECALS := [0, 96, 256]
const CAP_HEAT := [0, 0, 6]
const CAP_SPURTS := [0, 6, 16]
const CAP_STICKY := [0, 16, 48]
# Per-kind caps inside the particle pool, [Low, Medium, High].
const KIND_CAP := [
	[0, 90, 220],    # spark
	[0, 60, 160],    # ember
	[0, 24, 40],     # glow   (Gfx.MAX_GLOWS on High)
	[0, 12, 24],     # muzzle star
	[0, 34, 60],     # smoke  (Gfx.MAX_SMOKE on High)
	[0, 40, 90],     # dust
	[0, 24, 48],     # blood mist
	[0, 140, 320],   # blood drop
	[0, 30, 80],     # debris
]
const GIB_LIFE := [0.0, 3.5, 7.0]
const CASING_LIFE := [0.0, 1.4, 3.0]
const DECAL_LIFE := [0.0, 45.0, 90.0]
const SCORCH_LIFE := 40.0
const NO_FLOOR := 1.0e9

static var current: FxWorld = null
var _splats: Array = []          # procedural splat masks, built once per match

var quality := -1
var spawned_total := 0          # every slot ever filled (tests)
var update_us := 0              # last _process cost (bench)
var draw_us := 0                # last frame's draw cost (bench)

var _decals_ci: Node2D
var _back_ci: Node2D
var _add_ci: Node2D
var _heat_ci: Node2D
var _q := PhysicsRayQueryParameters2D.new()
var _cam_c := Vector2.ZERO
var _cam_r := 1e9
var _draw_acc := 0

# ── particles (dense; swap-remove) ──
var _n := 0
var _cap := 0
var _kcap := PackedInt32Array()
var kind_live := PackedInt32Array()
var _p := PackedVector2Array()
var _v := PackedVector2Array()
var _age := PackedFloat32Array()
var _life := PackedFloat32Array()
var _sz := PackedFloat32Array()
var _rot := PackedFloat32Array()
var _spin := PackedFloat32Array()
var _aux := PackedFloat32Array()
var _c := PackedColorArray()
var _k := PackedByteArray()
var _fl := PackedByteArray()
var _sticky := 0
var _sticky_cap := 0

# ── gibs (ring) ──
var _gcap := 0
var _ghead := 0
var gib_live := 0
var _gp := PackedVector2Array()
var _gv := PackedVector2Array()
var _grot := PackedFloat32Array()
var _gspin := PackedFloat32Array()
var _gage := PackedFloat32Array()
var _glife := PackedFloat32Array()
var _gbleed := PackedFloat32Array()
var _gacc := PackedFloat32Array()
var _gflip := PackedFloat32Array()
var _gstate := PackedByteArray()     # 0 flying, 1 settled
var _gsplat := PackedByteArray()     # 1 = first-impact splat still to come
var _gser := PackedInt32Array()
var _gc := PackedColorArray()
var _gtex: Array = []
var _gwound: Array = []
var _gser_next := 1

# ── casings (ring) ──
var _ccap := 0
var _chead := 0
var _cp := PackedVector2Array()
var _cv := PackedVector2Array()
var _crot := PackedFloat32Array()
var _cspin := PackedFloat32Array()
var _cage := PackedFloat32Array()
var _clife := PackedFloat32Array()
var _cfloor := PackedFloat32Array()
var _clen := PackedFloat32Array()
var _cb := PackedByteArray()
var _cc := PackedColorArray()

# ── decals (ring) ──
var _dcap := 0
var _dhead := 0
var decal_count := 0
var decals_recycled := 0
var _dp := PackedVector2Array()
var _drot := PackedFloat32Array()
var _dsc := PackedVector2Array()
var _dage := PackedFloat32Array()
var _dlife := PackedFloat32Array()
var _dvar := PackedByteArray()       # 0..3 blood splat variant, 255 scorch
var _dc := PackedColorArray()
var _ddirty := false
var _dtick := 0.0

# ── heat rings (ring) ──
var _hcap := 0
var _hhead := 0
var _hp := PackedVector2Array()
var _hage := PackedFloat32Array()
var _hlife := PackedFloat32Array()
var _hrad := PackedFloat32Array()
var _jets := PackedVector3Array()    # this frame's jet plumes (x, y, facing)

# ── wound spurts (ring) ──
var _scap := 0
var _shead := 0
var _sgib := PackedInt32Array()
var _sser := PackedInt32Array()
var _sage := PackedFloat32Array()
var _slife := PackedFloat32Array()
var _sacc := PackedFloat32Array()
var _sdir := PackedVector2Array()


## The match's FX world (created under `parent` if a scene has none yet).
static func ensure(parent: Node) -> FxWorld:
	if current != null and is_instance_valid(current) and current.is_inside_tree():
		return current
	if parent == null or not parent.is_inside_tree():
		return null
	var w := FxWorld.new()
	w.name = "FxWorld"
	parent.add_child(w)
	return w


## Settings → Graphics quality changed: re-size every pool (drops live FX).
static func reconfigure() -> void:
	if current != null and is_instance_valid(current):
		current.configure()


static func level() -> int:
	if Net.is_dedicated:
		return 0
	return clampi(Gfx.q(), 0, 2)


func _enter_tree() -> void:
	current = self


func _exit_tree() -> void:
	if current == self:
		current = null


func _ready() -> void:
	_q.collision_mask = 1
	_q.collide_with_areas = false
	# A drop / gib that starts inside solid ground (a blast against a wall)
	# reports a zero-normal hit instead of falling through the polygon and
	# settling on a buried internal edge.
	_q.hit_from_inside = true
	_decals_ci = _layer("Decals", 0)
	_back_ci = _layer("Back", 0)
	_add_ci = _layer("Add", 60)
	_add_ci.material = Gfx.add_mat()
	_heat_ci = _layer("Heat", 66)
	var hm := ShaderMaterial.new()
	hm.shader = HEAT_SHADER
	_heat_ci.material = hm
	_decals_ci.draw.connect(_draw_decals)
	_back_ci.draw.connect(_draw_back)
	_add_ci.draw.connect(_draw_add)
	_heat_ci.draw.connect(_draw_heat)
	configure()


func _layer(nm: String, z: int) -> Node2D:
	var n := Node2D.new()
	n.name = nm
	n.z_index = z
	add_child(n)
	return n


func configure() -> void:
	var lv := level()
	quality = lv
	_cap = CAP_PARTS[lv]
	_n = 0
	_sticky = 0
	_sticky_cap = CAP_STICKY[lv]
	_kcap.resize(K_COUNT)
	kind_live.resize(K_COUNT)
	for k in K_COUNT:
		_kcap[k] = int(KIND_CAP[k][lv])
		kind_live[k] = 0
	_p.resize(_cap); _v.resize(_cap); _age.resize(_cap); _life.resize(_cap); _sz.resize(_cap)
	_rot.resize(_cap); _spin.resize(_cap); _aux.resize(_cap); _c.resize(_cap); _k.resize(_cap); _fl.resize(_cap)
	_gcap = CAP_GIBS[lv]
	_ghead = 0
	gib_live = 0
	_gp.resize(_gcap); _gv.resize(_gcap); _grot.resize(_gcap); _gspin.resize(_gcap); _gage.resize(_gcap)
	_glife.resize(_gcap); _gbleed.resize(_gcap); _gacc.resize(_gcap); _gflip.resize(_gcap); _gstate.resize(_gcap)
	_gsplat.resize(_gcap); _gser.resize(_gcap); _gc.resize(_gcap)
	_gtex.resize(_gcap); _gwound.resize(_gcap)
	for i in _gcap:
		_glife[i] = 0.0
		_gtex[i] = null
		_gwound[i] = null
	_ccap = CAP_CASINGS[lv]
	_chead = 0
	_cp.resize(_ccap); _cv.resize(_ccap); _crot.resize(_ccap); _cspin.resize(_ccap); _cage.resize(_ccap)
	_clife.resize(_ccap); _cfloor.resize(_ccap); _clen.resize(_ccap); _cb.resize(_ccap); _cc.resize(_ccap)
	for i in _ccap:
		_clife[i] = 0.0
	_dcap = CAP_DECALS[lv]
	_dhead = 0
	decal_count = 0
	_dp.resize(_dcap); _drot.resize(_dcap); _dsc.resize(_dcap); _dage.resize(_dcap); _dlife.resize(_dcap)
	_dvar.resize(_dcap); _dc.resize(_dcap)
	for i in _dcap:
		_dlife[i] = 0.0
	_hcap = CAP_HEAT[lv]
	_hhead = 0
	_hp.resize(_hcap); _hage.resize(_hcap); _hlife.resize(_hcap); _hrad.resize(_hcap)
	for i in _hcap:
		_hlife[i] = 0.0
	_scap = CAP_SPURTS[lv]
	_shead = 0
	_sgib.resize(_scap); _sser.resize(_scap); _sage.resize(_scap); _slife.resize(_scap); _sacc.resize(_scap); _sdir.resize(_scap)
	for i in _scap:
		_slife[i] = 0.0
	_sync_counters()
	_ddirty = true
	for ci in [_decals_ci, _back_ci, _add_ci, _heat_ci]:
		if ci != null:
			ci.queue_redraw()
	if lv > 0 and _splats.is_empty():
		_splats = _make_splats()


## Pool sizes + live counts (tests, tools/fx_bench.gd).
func stats() -> Dictionary:
	var casings := 0
	for i in _ccap:
		if _clife[i] > 0.0:
			casings += 1
	return {
		"quality": quality,
		"parts_cap": _cap, "parts": _n,
		"gibs_cap": _gcap, "gibs": gib_live,
		"casings_cap": _ccap, "casings": casings,
		"decals_cap": _dcap, "decals": decal_count, "decals_recycled": decals_recycled,
		"heat_cap": _hcap, "spurts_cap": _scap, "sticky_cap": _sticky_cap, "sticky": _sticky,
		"kinds": kind_live.duplicate(), "kind_caps": _kcap.duplicate(),
		"spawned_total": spawned_total,
	}


func live_total() -> int:
	return _n + gib_live + int(stats()["casings"])


# ── public effects (called through Gfx / Gore / ImpactFx) ──────────────────

func glow(at: Vector2, col: Color, radius: float, life: float) -> void:
	_spawn(K_GLOW, at, Vector2.ZERO, life, radius, col)


func smoke(at: Vector2, vel: Vector2, size: float, life: float, col: Color) -> void:
	if not _near(at, 200.0):
		return
	var i := _spawn(K_SMOKE, at, vel, life, size, col)
	if i >= 0:
		_spin[i] = Gfx.rf(-1.0, 1.0)


func dust(at: Vector2, strength: float) -> void:
	if not _near(at, 100.0):
		return
	var r := Gfx.rng
	var n := int(3 + strength * (4 if quality >= 2 else 2))
	for i in n:
		_spawn(K_DUST, at + Vector2(r.randf_range(-8, 8), -2), Vector2(r.randf_range(-80, 80) * strength, r.randf_range(-45, -8)),
			r.randf_range(0.45, 0.8), r.randf_range(6.0, 11.0) * (0.7 + strength * 0.4), Color(0.72, 0.66, 0.56, 0.32))
	# A few heavier grit specks that fall back down.
	if quality >= 2:
		for i in int(2 + strength * 3):
			var j := _spawn(K_DEBRIS, at + Vector2(r.randf_range(-6, 6), -2), Vector2(r.randf_range(-90, 90), r.randf_range(-140, -60)),
				0.6, r.randf_range(0.6, 1.1), Color(0.3, 0.27, 0.22, 0.9))
			if j >= 0:
				_aux[j] = at.y


func muzzle_star(at: Vector2, dir: Vector2, explosive: bool) -> void:
	if not _near(at, 60.0):
		return
	var r := Gfx.rng
	var i := _spawn(K_STAR, at + dir * 4.0, Vector2.ZERO, 0.05 if not explosive else 0.09, 22.0 if not explosive else 34.0,
		Color(1.0, 0.82, 0.5, 0.95))
	if i >= 0:
		_rot[i] = dir.angle()
	if quality >= 2:
		for s in (2 if not explosive else 5):
			var d := dir.rotated(r.randf_range(-0.35, 0.35))
			_spawn(K_SPARK, at, d * r.randf_range(260.0, 520.0), r.randf_range(0.05, 0.12), 1.1, Color(1.0, 0.86, 0.5, 1.0))
	if r.randf() < (0.35 if not explosive else 1.0):
		smoke(at + dir * 6.0, dir * r.randf_range(20.0, 40.0) + Vector2(0, -10), r.randf_range(7.0, 11.0) * (2.0 if explosive else 1.0),
			r.randf_range(0.35, 0.6), Color(0.55, 0.55, 0.55, 0.22))


## Brass ejected from the gun: arcs out, bounces on the floor below, settles,
## fades. One ray-test at spawn finds the floor.
func casing(at: Vector2, facing: float, shell: bool) -> void:
	if _ccap == 0 or not _near(at, 100.0):
		return
	var r := Gfx.rng
	var i := _chead
	_chead = (_chead + 1) % _ccap
	_cp[i] = at
	_cv[i] = Vector2(-facing * r.randf_range(60.0, 130.0), r.randf_range(-200.0, -120.0))
	_crot[i] = r.randf() * TAU
	_cspin[i] = r.randf_range(-22.0, 22.0)
	_cage[i] = 0.0
	_clife[i] = CASING_LIFE[quality] * r.randf_range(0.85, 1.15)
	_cfloor[i] = _floor_below(at, 90.0)
	_clen[i] = 3.4 if shell else 2.4
	_cb[i] = 0
	_cc[i] = Color(0.75, 0.2, 0.15) if shell else Color(0.92, 0.74, 0.32)
	spawned_total += 1
	_sync_counters()


## Bullet into terrain: hot ricochet sparks, a dust puff, a couple of chips.
func ricochet(at: Vector2, dir: Vector2) -> void:
	if not _near(at, 60.0):
		return
	var r := Gfx.rng
	var nrm := dir.normalized() if dir.length() > 0.01 else Vector2.UP
	var hi := quality >= 2
	for s in (7 if hi else 4):
		var d := nrm.rotated(r.randf_range(-1.1, 1.1))
		_spawn(K_SPARK, at, d * r.randf_range(140.0, 380.0), r.randf_range(0.12, 0.3), r.randf_range(0.9, 1.5), Color(1.0, 0.8, 0.42, 1.0))
	_spawn(K_GLOW, at, Vector2.ZERO, 0.05, 12.0, Color(1.0, 0.75, 0.4, 0.8))
	_spawn(K_DUST, at + nrm * 2.0, nrm * r.randf_range(20.0, 50.0), r.randf_range(0.3, 0.5), r.randf_range(5.0, 8.0), Color(0.7, 0.66, 0.6, 0.3))
	if hi:
		for s in 2:
			var j := _spawn(K_DEBRIS, at, nrm.rotated(r.randf_range(-0.8, 0.8)) * r.randf_range(80.0, 170.0), 0.5,
				r.randf_range(0.6, 1.1), Color(0.22, 0.2, 0.18, 1.0))
			if j >= 0:
				_spin[j] = r.randf_range(-20.0, 20.0)


## Bullet into a soldier: a spurt of droplets (mostly out the far side), a
## puff of mist; one or two drops ray-test terrain and leave a splat.
func blood_hit(at: Vector2, dir: Vector2) -> void:
	var dens := _blood()
	if dens <= 0.0 or not _near(at, 60.0):
		return
	var r := Gfx.rng
	var back := dir.normalized() if dir.length() > 0.01 else Vector2.UP
	var through := -back
	var n := int(round((6.0 if quality >= 2 else 4.0) * dens)) + 1
	for s in n:
		var d := (through if r.randf() < 0.7 else back).rotated(r.randf_range(-0.6, 0.6))
		_drop(at, d * r.randf_range(90.0, 260.0) + Vector2(0, -40), r.randf() < 0.3)
	_spawn(K_MIST, at, through * 30.0, r.randf_range(0.25, 0.4), r.randf_range(7.0, 11.0) * clampf(dens, 0.6, 1.3), _blood_col(0.4))


## Grenade / rocket / wreck: debris + smoke + embers + sparks + heat ring + scorch.
func explosion(at: Vector2, radius: float) -> void:
	var r := Gfx.rng
	var hi := quality >= 2
	var onscr := _near(at, radius * 2.0)
	var floor_y := _floor_below(at + Vector2(0, -6), radius * 0.8)
	if onscr:
		for i in (9 if hi else 5):
			var a := r.randf() * TAU
			smoke(at + Vector2.RIGHT.rotated(a) * r.randf_range(4.0, radius * 0.35),
				Vector2.RIGHT.rotated(a) * r.randf_range(20.0, 70.0) + Vector2(0, -30), r.randf_range(18.0, 34.0), r.randf_range(1.2, 2.4),
				Color(0.16, 0.15, 0.14, 0.55))
		for i in (12 if hi else 6):
			var d := Vector2.UP.rotated(r.randf_range(-1.4, 1.4))
			var j := _spawn(K_DEBRIS, at + d * 4.0, d * r.randf_range(160.0, 420.0) * clampf(radius / 90.0, 0.6, 1.4), r.randf_range(0.9, 1.6),
				r.randf_range(0.8, 1.8), Color(0.08, 0.07, 0.06, 1.0).lerp(Color(0.26, 0.22, 0.18, 1.0), r.randf()))
			if j >= 0:
				_aux[j] = floor_y
				_spin[j] = r.randf_range(-16.0, 16.0)
		for i in (10 if hi else 4):
			var d := Vector2.UP.rotated(r.randf_range(-1.7, 1.7))
			var j := _spawn(K_EMBER, at + d * r.randf_range(2.0, radius * 0.3), d * r.randf_range(80.0, 260.0), r.randf_range(0.5, 1.1),
				r.randf_range(1.1, 1.8), Color(1.0, 0.42, 0.12, 0.9).lerp(Color(1.0, 0.75, 0.35, 0.9), r.randf()))
			if j >= 0:
				_aux[j] = 1.0   # embers from a blast fall (jet embers rise)
		for i in (14 if hi else 6):
			var d := Vector2.RIGHT.rotated(r.randf() * TAU)
			var j := _spawn(K_SPARK, at, d * r.randf_range(240.0, 560.0), r.randf_range(0.18, 0.4), r.randf_range(1.0, 1.8), Color(1.0, 0.8, 0.45, 1.0))
			if j >= 0:
				_aux[j] = floor_y
		if _hcap > 0:
			var h := _hhead
			_hhead = (_hhead + 1) % _hcap
			_hp[h] = at
			_hage[h] = 0.0
			_hlife[h] = 0.5
			_hrad[h] = radius * 1.5
			_heat_ci.queue_redraw()
	scorch(at, radius)


func scorch(at: Vector2, radius: float) -> void:
	var hit := _ray(at + Vector2(0, -6), at + Vector2(0, radius * 0.7))
	if hit.is_empty() or (hit.normal as Vector2) == Vector2.ZERO:
		return
	var nrm: Vector2 = hit.normal
	var r := Gfx.rng
	_decal((hit.position as Vector2) - nrm * 5.0, nrm, Vector2(radius / 32.0 * 1.2, radius / 32.0 * 0.42), 255,
		Color(0.05, 0.04, 0.03, 0.62), SCORCH_LIFE + r.randf_range(-4.0, 4.0))


# ── vehicles (#276 / #277) ─────────────────────────────────────────────

## Dust kicked back by a wheel / track / skid at speed `vx` (strength 0..1).
func wheel_dust(at: Vector2, vx: float, strength: float, col := Color(0.62, 0.56, 0.46, 0.3)) -> void:
	if not _near(at, 80.0):
		return
	var r := Gfx.rng
	_spawn(K_DUST, at + Vector2(r.randf_range(-4, 4), -2), Vector2(-vx * r.randf_range(0.12, 0.3) + r.randf_range(-20, 20), r.randf_range(-55, -15) * (0.5 + strength)),
		r.randf_range(0.5, 0.95), r.randf_range(7.0, 13.0) * (0.6 + strength * 0.6), col)
	if quality >= 2 and r.randf() < 0.4 * strength:
		var j := _spawn(K_DEBRIS, at + Vector2(0, -2), Vector2(-vx * r.randf_range(0.2, 0.45), r.randf_range(-150, -60)), 0.55,
			r.randf_range(0.6, 1.0), Color(0.28, 0.25, 0.2, 0.9))
		if j >= 0:
			_aux[j] = at.y


## Hot sparks off damaged / scraping metal.
func vehicle_sparks(at: Vector2, dir: Vector2, n: int) -> void:
	if not _near(at, 60.0):
		return
	var r := Gfx.rng
	var d0 := dir.normalized() if dir.length() > 0.01 else Vector2.UP
	for s in n:
		var d := d0.rotated(r.randf_range(-0.9, 0.9))
		_spawn(K_SPARK, at, d * r.randf_range(120.0, 340.0), r.randf_range(0.12, 0.32), r.randf_range(0.9, 1.5), Color(1.0, 0.8, 0.42, 1.0))
	_spawn(K_GLOW, at, Vector2.ZERO, 0.06, 10.0, Color(1.0, 0.7, 0.35, 0.7))


## A burning hull, called a few times a second: rising embers, a flickering
## glow, a gout of dark smoke. `strength` 0..1.
func vehicle_burn(at: Vector2, strength: float) -> void:
	if not _near(at, 120.0):
		return
	var r := Gfx.rng
	for i in (3 if quality >= 2 else 1):
		var j := _spawn(K_EMBER, at + Vector2(r.randf_range(-6, 6), r.randf_range(-3, 3)), Vector2(r.randf_range(-30, 30), r.randf_range(-120, -50)),
			r.randf_range(0.5, 1.1), r.randf_range(1.0, 1.8), Color(1.0, 0.5, 0.15, 0.9).lerp(Color(1.0, 0.8, 0.4, 0.9), r.randf()))
		if j >= 0:
			_aux[j] = 0.0   # rises
	_spawn(K_GLOW, at + Vector2(0, -6), Vector2.ZERO, r.randf_range(0.12, 0.22), r.randf_range(26.0, 40.0) * (0.6 + strength * 0.5), Color(1.0, 0.5, 0.18, 0.55))
	smoke(at + Vector2(r.randf_range(-4, 4), -10), Vector2(r.randf_range(-12, 12), r.randf_range(-70, -40)), r.randf_range(14.0, 22.0) * (0.7 + strength * 0.5),
		r.randf_range(1.2, 2.0), Color(0.07, 0.065, 0.06, 0.5))


## A vehicle blowing apart (on top of Gfx.explosion): heavy hull panels
## tumbling out and bouncing, burning bits, a tall smoke column.
func vehicle_wreck(at: Vector2, radius: float, paint: Color) -> void:
	if not _near(at, radius * 2.0):
		return
	var r := Gfx.rng
	var hi := quality >= 2
	var floor_y := _floor_below(at + Vector2(0, -10), radius)
	for i in (12 if hi else 6):
		var d := Vector2.UP.rotated(r.randf_range(-1.3, 1.3))
		var col := paint.darkened(r.randf_range(0.2, 0.6)) if r.randf() < 0.6 else Color(0.1, 0.09, 0.08, 1.0)
		col.a = 1.0
		var j := _spawn(K_DEBRIS, at + d * 6.0 + Vector2(0, -10), d * r.randf_range(220.0, 560.0), r.randf_range(1.6, 2.6), r.randf_range(2.2, 4.6), col)
		if j >= 0:
			_aux[j] = floor_y
			_spin[j] = r.randf_range(-12.0, 12.0)
	for i in (8 if hi else 3):
		var d2 := Vector2.UP.rotated(r.randf_range(-1.2, 1.2))
		var k := _spawn(K_EMBER, at + Vector2(0, -8), d2 * r.randf_range(160.0, 380.0), r.randf_range(0.9, 1.6), r.randf_range(1.4, 2.2), Color(1.0, 0.55, 0.18, 0.95))
		if k >= 0:
			_aux[k] = 1.0
	for i in (6 if hi else 3):
		smoke(at + Vector2(r.randf_range(-radius * 0.25, radius * 0.25), r.randf_range(-30, -6)), Vector2(r.randf_range(-20, 20), r.randf_range(-90, -45)),
			r.randf_range(30.0, 48.0), r.randf_range(2.4, 3.6), Color(0.06, 0.055, 0.05, 0.6))


## Rotor wash: dust blown out along the ground both ways from `at` (the spot
## under the rotor). `strength` 0..1 grows as the helicopter gets lower.
func rotor_wash(at: Vector2, strength: float, spread: float, col := Color(0.66, 0.6, 0.5, 0.3)) -> void:
	if not _near(at, spread):
		return
	var r := Gfx.rng
	for side: float in [-1.0, 1.0]:
		var x := at.x + side * r.randf_range(spread * 0.15, spread * 0.6)
		_spawn(K_DUST, Vector2(x, at.y - 3), Vector2(side * r.randf_range(160.0, 330.0) * (0.5 + strength * 0.6), r.randf_range(-40, -6)),
			r.randf_range(0.45, 0.85), r.randf_range(9.0, 16.0) * (0.6 + strength * 0.6), Color(col.r, col.g, col.b, col.a * (0.5 + strength * 0.6)))


## Death: the body comes apart — pooled limb gibs (the soldier's own gostek
## body-part sprites, tinted, bloody), a burst of droplets + mist, wound spurts
## pulsing from the torso and neck for a moment, splats where blood lands.
func gib(at: Vector2, base_vel: Vector2, body: Color, cos: Dictionary, explosive: bool, facing: float) -> void:
	var dens := _blood()
	if dens <= 0.0:
		return
	var r := Gfx.rng
	if not _near(at, 120.0):
		# Off screen: no particles, but the floor still gets stained.
		for s in 2:
			var hit := _ray(at + Vector2(r.randf_range(-20, 20), -10), at + Vector2(r.randf_range(-20, 20), 80))
			if not hit.is_empty() and (hit.normal as Vector2) != Vector2.ZERO:
				_splat(hit.position, hit.normal, r.randf_range(12.0, 20.0))
		return
	var hi := quality >= 2
	var skin: Color = Gostek.Custom.SKIN_TONES.get(str(cos.get("skin", "")), Gostek.SKIN)
	var pants := body.darkened(0.35)
	if Gostek.Custom.PANTS.has(str(cos.get("pants", ""))):
		pants = Gostek.Custom.PANTS[str(cos.get("pants", ""))]
	var head_key := str(cos.get("head", "helm"))
	if not Gostek.HEAD_KEYS.has(head_key) or head_key == "none":
		head_key = "morda"
	# [texture key, local offset from the feet, tint kind, wound key]
	var parts: Array = [
		["klata", Vector2(0, -13), 0, "klata"],
		[head_key, Vector2(1, -20), 2 if head_key.begins_with("hair") or head_key == "morda" else 3, "morda" if head_key == "morda" else ""],
		["biodro", Vector2(0, -7), 0, "biodro"],
		["udo", Vector2(-2, -5), 1, "udo"],
		["ramie", Vector2(3, -14), 0, "ramie"],
		["noga", Vector2(2, -2), 1, "noga"],
		["reka", Vector2(-4, -11), 0, "reka"],
		["udo", Vector2(2, -5), 1, "udo"],
		["ramie", Vector2(-3, -14), 0, "ramie"],
		["noga", Vector2(-2, -2), 1, "noga"],
		["reka", Vector2(4, -11), 0, "reka"],
		["stopa", Vector2(3, 0), 4, ""],
		["stopa", Vector2(-3, 0), 4, ""],
	]
	var count := parts.size() if hi else 6
	if dens < 0.5:
		count = maxi(2, count / 2)
	var power := 1.0 if explosive else 0.45
	var blood := _blood_col(1.0)
	var centre := at + Vector2(0, -10)
	var torso := -1
	var head := -1
	for idx in count:
		var spec: Array = parts[idx]
		var tex := Gostek._tex(str(spec[0]), false)
		if tex == null:
			continue
		var off: Vector2 = spec[1]
		off.x *= facing
		var pos := at + off
		var out := (pos - centre).normalized() if pos.distance_to(centre) > 0.5 else Vector2.UP
		var vel := base_vel * 0.6 + out * r.randf_range(80.0, 260.0) * power * 2.0 \
			+ Vector2(r.randf_range(-90.0, 90.0), -r.randf_range(140.0, 380.0) * (0.6 + power))
		var tint: Color = [body, pants, skin, body.darkened(0.35), Color(0.55, 0.5, 0.48)][int(spec[2])]
		# Torn and bloodied: team colour pulled toward dark blood, so the pieces
		# read as gore and not confetti.
		tint = tint.lerp(blood, 0.38).darkened(0.12)
		tint.a = 1.0
		var wound: Texture2D = Gostek._tex("ranny/" + str(spec[3]), false) if str(spec[3]) != "" else null
		var gi := _gib(pos, vel, r.randf_range(-14.0, 14.0) * (1.0 + power), tex, wound, tint, facing)
		if idx == 0:
			torso = gi
		elif idx == 1:
			head = gi
	# Burst of droplets: arcs out, a third of them stick where they land.
	var nd := int(round((26.0 if hi else 12.0) * dens * (1.3 if explosive else 1.0)))
	for s in nd:
		var d := Vector2.UP.rotated(r.randf_range(-1.6, 1.6))
		_drop(centre + Vector2(r.randf_range(-4, 4), r.randf_range(-6, 6)), d * r.randf_range(120.0, 420.0) * (0.7 + power * 0.5) + base_vel * 0.4,
			r.randf() < 0.35, r.randf_range(1.6, 3.2))
	for s in (4 if hi else 2):
		_spawn(K_MIST, centre + Vector2(r.randf_range(-6, 6), r.randf_range(-8, 4)), Vector2(r.randf_range(-40, 40), r.randf_range(-50, -10)),
			r.randf_range(0.4, 0.7), r.randf_range(12.0, 20.0) * clampf(dens, 0.6, 1.3), _blood_col(0.45))
	# A few frames of arterial spurt from the wounds, riding the torso / head.
	_spurt(torso, Vector2.UP.rotated(r.randf_range(-0.5, 0.5)), r.randf_range(0.35, 0.55))
	if head >= 0 and hi:
		_spurt(torso if torso >= 0 else head, Vector2.UP.rotated(r.randf_range(-0.3, 0.3) + facing * 0.4), r.randf_range(0.3, 0.45))
	# Pooled floor stain under the body straight away.
	var hit := _ray(at + Vector2(0, -8), at + Vector2(0, 60))
	if not hit.is_empty() and (hit.normal as Vector2) != Vector2.ZERO:
		_splat(hit.position, hit.normal, r.randf_range(24.0, 34.0) * clampf(dens, 0.7, 1.2))


# ── frame ───────────────────────────────────────────────────────────────

func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	var dt := minf(delta, 0.05)
	var cam := get_viewport().get_camera_2d() if is_inside_tree() else null
	if cam != null:
		_cam_c = cam.get_screen_center_position()
		var vs := get_viewport().get_visible_rect().size / maxf(0.05, cam.zoom.x)
		_cam_r = vs.length() * 0.5 + 160.0
	else:
		_cam_r = 1e9
	_tick_jets(dt)
	_tick_parts(dt)
	_tick_spurts(dt)
	_tick_gibs(dt)
	_tick_casings(dt)
	_tick_decals(dt)
	_tick_heat(dt)
	_sync_counters()
	if _n > 0 or gib_live > 0 or _any_casing:
		_back_ci.queue_redraw()
		_add_ci.queue_redraw()
	elif _was_live:
		_back_ci.queue_redraw()
		_add_ci.queue_redraw()
	_was_live = _n > 0 or gib_live > 0 or _any_casing
	update_us = Time.get_ticks_usec() - t0
	draw_us = _draw_acc
	_draw_acc = 0


var _was_live := false
var _any_casing := false


func _tick_parts(dt: float) -> void:
	var space: PhysicsDirectSpaceState2D = null
	if _sticky > 0 and is_inside_tree():
		space = get_world_2d().direct_space_state
	var i := 0
	while i < _n:
		var a := _age[i] + dt
		if a >= _life[i]:
			_kill(i)
			continue
		_age[i] = a
		var k := _k[i]
		var p := _p[i]
		var v := _v[i]
		if k == K_DROP:
			v.y += 900.0 * dt
			var np := p + v * dt
			if (_fl[i] & 1) != 0 and space != null:
				_q.from = p
				_q.to = np
				var hit := space.intersect_ray(_q)
				if not hit.is_empty():
					if (hit.normal as Vector2) != Vector2.ZERO:
						_splat(hit.position, hit.normal, _sz[i] * Gfx.rf(4.5, 7.5))
					_kill(i)
					continue
			p = np
		elif k == K_SPARK:
			v.y += 620.0 * dt
			v *= 1.0 - 1.2 * dt
			p += v * dt
			if p.y > _aux[i] and v.y > 0.0:
				p.y = _aux[i]
				v.y *= -0.3
				v.x *= 0.55
		elif k == K_SMOKE:
			p += v * dt
			v *= 1.0 - minf(1.0, dt * 2.2)
			v.y -= 12.0 * dt
			_rot[i] += _spin[i] * dt
		elif k == K_DUST:
			p += v * dt
			v *= 1.0 - minf(1.0, dt * 3.5)
			v.y += 18.0 * dt
		elif k == K_EMBER:
			if _aux[i] > 0.5:
				v.y += 260.0 * dt
			else:
				v.y -= 40.0 * dt
			v *= 1.0 - 1.6 * dt
			p += v * dt
			p.x += sin(a * 9.0 + float(i)) * 8.0 * dt
		elif k == K_DEBRIS:
			v.y += 980.0 * dt
			p += v * dt
			_rot[i] += _spin[i] * dt
			if p.y > _aux[i] and v.y > 0.0:
				p.y = _aux[i]
				v.y *= -0.32
				v.x *= 0.6
				_spin[i] *= 0.5
		elif k == K_MIST:
			p += v * dt
			v *= 1.0 - minf(1.0, dt * 5.0)
			v.y += 30.0 * dt
		_p[i] = p
		_v[i] = v
		i += 1


func _tick_spurts(dt: float) -> void:
	for s in _scap:
		if _slife[s] <= 0.0:
			continue
		_sage[s] += dt
		var g := _sgib[s]
		if _sage[s] >= _slife[s] or g < 0 or g >= _gcap or _gser[g] != _sser[s] or _glife[g] <= 0.0:
			_slife[s] = 0.0
			continue
		var k := _sage[s] / _slife[s]
		# Pulsing arterial rate, tailing off.
		_sacc[s] += dt * 70.0 * (1.0 - k) * (0.55 + 0.45 * sin(_sage[s] * 34.0))
		var d := _sdir[s].rotated(_grot[g] * 0.25)
		while _sacc[s] >= 1.0:
			_sacc[s] -= 1.0
			_drop(_gp[g], d.rotated(Gfx.rf(-0.25, 0.25)) * Gfx.rf(140.0, 280.0) * (1.0 - k * 0.5) + _gv[g] * 0.6,
				Gfx.rng.randf() < 0.12, Gfx.rf(1.3, 2.4))


func _tick_gibs(dt: float) -> void:
	if gib_live == 0:
		return
	var space: PhysicsDirectSpaceState2D = get_world_2d().direct_space_state if is_inside_tree() else null
	for i in _gcap:
		if _glife[i] <= 0.0:
			continue
		_gage[i] += dt
		if _gage[i] >= _glife[i]:
			_glife[i] = 0.0
			gib_live -= 1
			continue
		if _gstate[i] != 0:
			continue
		var p := _gp[i]
		var v := _gv[i]
		v.y += 980.0 * dt
		v *= 1.0 - 0.2 * dt
		var np := p + v * dt
		var hit: Dictionary = {}
		if space != null:
			_q.from = p
			_q.to = np
			hit = space.intersect_ray(_q)
		if not hit.is_empty() and (hit.normal as Vector2) == Vector2.ZERO:
			# Started inside solid ground: drop it.
			_glife[i] = 0.0
			gib_live -= 1
			continue
		if not hit.is_empty():
			var n: Vector2 = hit.normal
			var speed := v.length()
			if _gsplat[i] == 1 and speed > 110.0:
				_gsplat[i] = 0
				_splat(hit.position, n, Gfx.rf(14.0, 24.0))
				for s in 2:
					_drop(hit.position + n * 2.0, (n * Gfx.rf(60.0, 140.0)).rotated(Gfx.rf(-0.9, 0.9)), false, Gfx.rf(1.2, 2.0))
			var vn := v.dot(n)
			if vn < 0.0:
				v -= n * vn * 1.35
			v *= 0.62
			_gspin[i] = _gspin[i] * 0.45 + v.x * 0.02
			np = (hit.position as Vector2) + n * 1.5
			if n.y < -0.6 and v.length() < 70.0:
				_gstate[i] = 1
				v = Vector2.ZERO
		_grot[i] += _gspin[i] * dt
		_gp[i] = np
		_gv[i] = v
		# Blood trail while it flies.
		if _gbleed[i] > 0.0:
			_gbleed[i] -= dt
			_gacc[i] += dt * 26.0
			while _gacc[i] >= 1.0:
				_gacc[i] -= 1.0
				_drop(np, v * 0.15 + Vector2(Gfx.rf(-30, 30), Gfx.rf(-30, 10)), Gfx.rng.randf() < 0.1, Gfx.rf(1.0, 1.8))


func _tick_casings(dt: float) -> void:
	_any_casing = false
	for i in _ccap:
		if _clife[i] <= 0.0:
			continue
		_cage[i] += dt
		if _cage[i] >= _clife[i]:
			_clife[i] = 0.0
			continue
		_any_casing = true
		if _cb[i] >= 4:
			continue
		var v := _cv[i]
		var p := _cp[i]
		v.y += 900.0 * dt
		p += v * dt
		_crot[i] += _cspin[i] * dt
		if p.y >= _cfloor[i] and v.y > 0.0:
			p.y = _cfloor[i]
			_cb[i] += 1
			v.y *= -0.38
			v.x *= 0.55
			_cspin[i] *= 0.5
			if _cb[i] >= 3 or absf(v.y) < 40.0:
				_cb[i] = 4
				v = Vector2.ZERO
				_crot[i] = 0.0 if absf(wrapf(_crot[i], -PI, PI)) < PI * 0.5 else PI
		_cp[i] = p
		_cv[i] = v


func _tick_decals(dt: float) -> void:
	if decal_count == 0:
		return
	var fresh := false
	for i in _dcap:
		if _dlife[i] <= 0.0:
			continue
		_dage[i] += dt
		if _dage[i] >= _dlife[i]:
			_dlife[i] = 0.0
			decal_count -= 1
			_ddirty = true
		elif _dage[i] < 3.0:
			fresh = true
	_dtick -= dt
	if _ddirty or _dtick <= 0.0:
		_dtick = 0.08 if fresh else 0.5
		_ddirty = false
		_decals_ci.queue_redraw()


func _tick_heat(dt: float) -> void:
	var any := not _jets.is_empty()
	for i in _hcap:
		if _hlife[i] <= 0.0:
			continue
		_hage[i] += dt
		if _hage[i] >= _hlife[i]:
			_hlife[i] = 0.0
		else:
			any = true
	if _heat_ci != null:
		_heat_ci.visible = any
		if any:
			_heat_ci.queue_redraw()


## Jetpack exhaust upgrade: embers / sparks shed by every flying soldier on
## screen (Medium+), heat shimmer under the nozzle (High).
func _tick_jets(dt: float) -> void:
	_jets.clear()
	if quality <= 0 or not is_inside_tree():
		return
	var r := Gfx.rng
	var rate := 34.0 if quality >= 2 else 12.0
	for s in get_tree().get_nodes_in_group("soldier"):
		var n2 := s as Node2D
		if n2 == null or not bool(s.get("jet_on")) or bool(s.get("dead")) or not n2.visible:
			continue
		var gp := n2.global_position
		if gp.distance_to(_cam_c) > _cam_r:
			continue
		var f := float(s.get("facing")) if s.get("facing") != null else 1.0
		var nozzle := gp + Vector2(-f * 3.3, 3.0)
		if quality >= 2:
			_jets.append(Vector3(nozzle.x, nozzle.y, f))
		var cos = s.get("cosmetics")
		var base: Color = Gostek.Custom.JET_COLORS.get(str(cos.get("jet", "")) if typeof(cos) == TYPE_DICTIONARY else "", Color(1.0, 0.45, 0.15))
		var cnt := int(rate * dt + r.randf())
		for c in cnt:
			var j := _spawn(K_EMBER, nozzle + Vector2(r.randf_range(-1.5, 1.5), r.randf_range(0, 3)),
				Vector2(r.randf_range(-40, 40), r.randf_range(90, 200)), r.randf_range(0.18, 0.4), r.randf_range(1.0, 1.9),
				base.lerp(Color(1.0, 0.95, 0.7), r.randf_range(0.2, 0.6)))
			if j >= 0:
				_aux[j] = 1.0


# ── pool internals ──────────────────────────────────────────────────────

func _spawn(k: int, at: Vector2, vel: Vector2, life: float, size: float, col: Color) -> int:
	if _n >= _cap or kind_live[k] >= _kcap[k]:
		return -1
	var i := _n
	_n += 1
	kind_live[k] += 1
	_k[i] = k
	_p[i] = at
	_v[i] = vel
	_age[i] = 0.0
	_life[i] = maxf(0.01, life)
	_sz[i] = size
	_c[i] = col
	_rot[i] = 0.0
	_spin[i] = 0.0
	_aux[i] = NO_FLOOR
	_fl[i] = 0
	spawned_total += 1
	return i


func _kill(i: int) -> void:
	kind_live[_k[i]] -= 1
	if (_fl[i] & 1) != 0:
		_sticky -= 1
	var last := _n - 1
	if i != last:
		_k[i] = _k[last]; _p[i] = _p[last]; _v[i] = _v[last]; _age[i] = _age[last]; _life[i] = _life[last]
		_sz[i] = _sz[last]; _c[i] = _c[last]; _rot[i] = _rot[last]; _spin[i] = _spin[last]; _aux[i] = _aux[last]; _fl[i] = _fl[last]
	_n = last


func _drop(at: Vector2, vel: Vector2, sticky: bool, size := 2.0) -> void:
	var i := _spawn(K_DROP, at, vel, Gfx.rf(0.5, 0.9) if not sticky else 2.5, size, _blood_col(0.95))
	if i >= 0 and sticky and _sticky < _sticky_cap and _dcap > 0:
		_fl[i] = 1
		_sticky += 1


func _gib(pos: Vector2, vel: Vector2, spin: float, tex: Texture2D, wound: Texture2D, tint: Color, facing: float) -> int:
	if _gcap == 0:
		return -1
	var i := _ghead
	_ghead = (_ghead + 1) % _gcap
	if _glife[i] <= 0.0:
		gib_live += 1
	_gp[i] = pos
	_gv[i] = vel
	_grot[i] = Gfx.rf(-0.6, 0.6)
	_gspin[i] = spin
	_gage[i] = 0.0
	_glife[i] = GIB_LIFE[quality] * Gfx.rf(0.85, 1.15)
	_gbleed[i] = Gfx.rf(0.5, 1.3)
	_gacc[i] = 0.0
	_gflip[i] = -1.0 if facing < 0.0 else 1.0
	_gstate[i] = 0
	_gsplat[i] = 1
	_gser[i] = _gser_next
	_gser_next += 1
	_gc[i] = tint
	_gtex[i] = tex
	_gwound[i] = wound
	spawned_total += 1
	return i


func _spurt(gib_i: int, dir: Vector2, life: float) -> void:
	if _scap == 0 or gib_i < 0:
		return
	var s := _shead
	_shead = (_shead + 1) % _scap
	_sgib[s] = gib_i
	_sser[s] = _gser[gib_i]
	_sage[s] = 0.0
	_slife[s] = life
	_sacc[s] = 0.0
	_sdir[s] = dir


func _splat(at: Vector2, nrm: Vector2, size: float) -> void:
	if _blood() <= 0.0:
		return
	var r := Gfx.rng
	var sc := size / 64.0
	_decal(at - nrm * 1.5, nrm, Vector2(sc, sc * r.randf_range(0.45, 0.65)), r.randi() % 4, _blood_col(r.randf_range(0.75, 0.92)),
		DECAL_LIFE[quality] * r.randf_range(0.85, 1.1))


func _decal(at: Vector2, nrm: Vector2, sc: Vector2, variant: int, col: Color, life: float) -> void:
	if _dcap == 0:
		return
	var i := _dhead
	_dhead = (_dhead + 1) % _dcap
	if _dlife[i] > 0.0:
		decals_recycled += 1
	else:
		decal_count += 1
	_dp[i] = at
	_drot[i] = nrm.angle() + PI * 0.5
	_dsc[i] = sc
	_dage[i] = 0.0
	_dlife[i] = life
	_dvar[i] = variant
	_dc[i] = col
	_ddirty = true
	spawned_total += 1


func _sync_counters() -> void:
	if kind_live.size() < K_COUNT:
		return
	Gfx.live_glows = kind_live[K_GLOW]
	Gfx.live_smoke = kind_live[K_SMOKE]
	var c := 0
	for i in _ccap:
		if _clife[i] > 0.0:
			c += 1
	Gfx.live_casings = c


func _near(at: Vector2, margin: float) -> bool:
	return at.distance_to(_cam_c) < _cam_r + margin


func _blood() -> float:
	return clampf(float(Settings.blood_intensity), 0.0, 1.5) if float(Settings.blood_intensity) > 0.01 else 0.0


func _blood_col(a: float) -> Color:
	var c := Color(0.44, 0.015, 0.03, a) if Settings.visual_style == "cinematic" else Color(0.62, 0.04, 0.04, a)
	var j := Gfx.rf(-0.06, 0.05)
	return Color(clampf(c.r + j, 0.0, 1.0), c.g, c.b, a)


func _ray(from: Vector2, to: Vector2) -> Dictionary:
	if not is_inside_tree():
		return {}
	_q.from = from
	_q.to = to
	return get_world_2d().direct_space_state.intersect_ray(_q)


func _floor_below(at: Vector2, depth: float) -> float:
	var hit := _ray(at, at + Vector2(0, depth))
	if hit.is_empty() or (hit.normal as Vector2) == Vector2.ZERO:
		return NO_FLOOR
	return (hit.position as Vector2).y


# ── drawing ─────────────────────────────────────────────────────────────

func _draw_add() -> void:
	var t0 := Time.get_ticks_usec()
	var ci := _add_ci
	var gt := Gfx.glow_tex()
	var dt := Gfx.dot_tex()
	var xf := false
	for i in _n:
		var k := _k[i]
		if k > ADD_KINDS:
			continue
		var f := _age[i] / _life[i]
		var p := _p[i]
		var col := _c[i]
		if k == K_SPARK:
			col.a *= 1.0 - f
			var v := _v[i]
			var tail := v * 0.016
			if tail.length() < 1.5:
				tail = v.normalized() * 1.5
			ci.draw_line(p - tail, p, col, _sz[i])
		elif k == K_EMBER:
			col.a *= (1.0 - f) * (0.7 + 0.3 * sin(_age[i] * 40.0 + float(i)))
			var s := _sz[i]
			ci.draw_texture_rect(dt, Rect2(p.x - s, p.y - s, s * 2.0, s * 2.0), false, col)
		elif k == K_GLOW:
			var r := _sz[i] * (0.85 + 0.3 * f)
			col.a *= (1.0 - f) * (1.0 - f)
			ci.draw_texture_rect(gt, Rect2(p.x - r, p.y - r, r * 2.0, r * 2.0), false, col)
		elif k == K_STAR:
			col.a *= 1.0 - f * f
			var s2 := _sz[i] * (1.0 + 0.5 * f)
			ci.draw_set_transform(p, _rot[i], Vector2(s2, s2 * 0.22))
			ci.draw_texture_rect(gt, Rect2(-1.0, -1.0, 2.0, 2.0), false, col)
			ci.draw_set_transform(p, _rot[i] + PI * 0.5, Vector2(s2 * 0.35, s2 * 0.12))
			ci.draw_texture_rect(gt, Rect2(-1.0, -1.0, 2.0, 2.0), false, col)
			xf = true
	if xf:
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_acc += Time.get_ticks_usec() - t0


func _draw_back() -> void:
	var t0 := Time.get_ticks_usec()
	var ci := _back_ci
	var st := Gfx.soft_tex()
	# Soft stuff first (smoke / dust / mist), then solids on top.
	for i in _n:
		var k := _k[i]
		if k != K_SMOKE and k != K_DUST and k != K_MIST:
			continue
		var f := _age[i] / _life[i]
		var p := _p[i]
		var col := _c[i]
		var h := _sz[i] * 0.5 * (1.0 + f * (1.6 if k == K_SMOKE else 1.2))
		col.a *= 1.0 - f
		ci.draw_texture_rect(st, Rect2(p.x - h, p.y - h, h * 2.0, h * 2.0), false, col)
	var xf := false
	for i in _n:
		var k := _k[i]
		var p := _p[i]
		if k == K_DROP:
			var f := _age[i] / _life[i]
			var col := _c[i]
			col.a *= 1.0 - f * f
			var v := _v[i]
			var tail := v * 0.012
			if tail.length() < 1.0:
				tail = Vector2(0, -1.0)
			ci.draw_line(p - tail, p, col, _sz[i])
		elif k == K_DEBRIS:
			var f2 := _age[i] / _life[i]
			var col2 := _c[i]
			col2.a *= 1.0 - maxf(0.0, f2 - 0.6) / 0.4
			var s := _sz[i]
			ci.draw_set_transform(p, _rot[i], Vector2.ONE)
			ci.draw_rect(Rect2(-s, -s * 0.7, s * 2.0, s * 1.4), col2)
			xf = true
	# Shell casings.
	for i in _ccap:
		if _clife[i] <= 0.0:
			continue
		var a := 1.0 - maxf(0.0, _cage[i] - (_clife[i] - 0.5)) / 0.5
		var col3 := _cc[i]
		col3.a = a
		var ln := _clen[i]
		ci.draw_set_transform(_cp[i], _crot[i], Vector2.ONE)
		ci.draw_rect(Rect2(-ln * 0.5, -0.7, ln, 1.4), col3)
		ci.draw_rect(Rect2(-ln * 0.5, -0.7, ln, 0.5), Color(1.0, 0.95, 0.75, 0.6 * a))
		xf = true
	# Gibs: the soldier's own body-part sprite, tinted, wound overlay, a torn end.
	var blood := _blood_col(1.0)
	for i in _gcap:
		if _glife[i] <= 0.0:
			continue
		var tex: Texture2D = _gtex[i]
		if tex == null:
			continue
		var a := 1.0 - maxf(0.0, _gage[i] - (_glife[i] - 1.0))
		var w := float(tex.get_width()) * Gostek.SPRITE_SCALE * 1.1
		var hh := float(tex.get_height()) * Gostek.SPRITE_SCALE * 1.1
		var col4 := _gc[i]
		col4.a = a
		ci.draw_set_transform(_gp[i], _grot[i], Vector2(1.0, _gflip[i]))
		ci.draw_texture_rect(tex, Rect2(-w * 0.5, -hh * 0.5, w, hh), false, col4)
		var wt: Texture2D = _gwound[i]
		if wt != null:
			ci.draw_texture_rect(wt, Rect2(-w * 0.5, -hh * 0.5, w, hh), false, Color(1, 1, 1, 0.9 * a))
		var b := blood
		b.a = 0.9 * a
		ci.draw_circle(Vector2(-w * 0.5, 0.0), 1.4, b)
		xf = true
	if xf:
		ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_acc += Time.get_ticks_usec() - t0


func _draw_decals() -> void:
	var t0 := Time.get_ticks_usec()
	if decal_count == 0 or _splats.is_empty():
		return
	var ci := _decals_ci
	var st := Gfx.soft_tex()
	for i in _dcap:
		if _dlife[i] <= 0.0:
			continue
		var age := _dage[i]
		var life := _dlife[i]
		var col := _dc[i]
		var v := _dvar[i]
		var tex: Texture2D = st if v == 255 else _splats[v % _splats.size()]
		if v != 255:
			# Wet → dried: darker and a touch browner over the first seconds.
			var dry := clampf(age / 3.0, 0.0, 1.0)
			col = Color(col.r * (1.0 - 0.32 * dry), col.g + 0.012 * dry, col.b * (1.0 - 0.2 * dry), col.a)
		col.a *= 1.0 - smoothstep(life * 0.55, life, age)
		ci.draw_set_transform(_dp[i], _drot[i], _dsc[i])
		ci.draw_texture_rect(tex, Rect2(-32, -32, 64, 64), false, col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_draw_acc += Time.get_ticks_usec() - t0


func _draw_heat() -> void:
	var ci := _heat_ci
	const SEG := 20
	var uvs := PackedVector2Array([Vector2(0, 0.5), Vector2(1, 0.5), Vector2(1, 0.5), Vector2(0, 0.5)])
	for i in _hcap:
		if _hlife[i] <= 0.0:
			continue
		var k := _hage[i] / _hlife[i]
		var e := 1.0 - (1.0 - k) * (1.0 - k)
		var rr := _hrad[i] * (0.25 + 0.95 * e)
		var band := 10.0 + 26.0 * (1.0 - k)
		var s := pow(1.0 - k, 1.5)
		var c := _hp[i]
		for g in SEG:
			var a0 := TAU * float(g) / SEG
			var a1 := TAU * float(g + 1) / SEG
			var d0 := Vector2.RIGHT.rotated(a0)
			var d1 := Vector2.RIGHT.rotated(a1)
			var c0 := Color(0.5 + 0.5 * d0.x, 0.5 + 0.5 * d0.y, 0.0, s)
			var c1 := Color(0.5 + 0.5 * d1.x, 0.5 + 0.5 * d1.y, 0.0, s)
			ci.draw_primitive(PackedVector2Array([c + d0 * (rr - band), c + d0 * (rr + band), c + d1 * (rr + band), c + d1 * (rr - band)]),
				PackedColorArray([c0, c0, c1, c1]), uvs)
	# Jet shimmer: a wobbling plume under each nozzle.
	var juv := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	var jc := Color(0.5, 0.5, 1.0, 0.0)
	var jcols := PackedColorArray([jc, jc, jc, jc])
	for j in _jets:
		var o := Vector2(j.x, j.y)
		ci.draw_primitive(PackedVector2Array([o + Vector2(-4, 0), o + Vector2(4, 0), o + Vector2(7, 26), o + Vector2(-7, 26)]), jcols, juv)


# ── splat textures ──────────────────────────────────────────────────────

## Four procedural blood-splat alpha masks (64×64): an irregular core,
## satellite drops and drag streaks along the surface (x) axis. Built once.
static func _make_splats() -> Array:
	var out: Array = []
	var r := RandomNumberGenerator.new()
	r.seed = 271
	for v in 4:
		var img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 0))
		var shapes: Array = []   # [cx, cy, rx, ry]
		for b in r.randi_range(3, 5):
			shapes.append([32.0 + r.randf_range(-6, 6), 32.0 + r.randf_range(-4, 4), r.randf_range(6.0, 11.0), r.randf_range(5.0, 9.0)])
		for b in r.randi_range(7, 13):
			var ang := r.randf_range(-0.5, 0.5) + (PI if r.randf() < 0.5 else 0.0)
			var dist := r.randf_range(13.0, 28.0)
			var rad := r.randf_range(0.9, 2.6)
			shapes.append([32.0 + cos(ang) * dist, 32.0 + sin(ang) * dist * 0.6, rad, rad])
		for b in r.randi_range(1, 3):
			var sx := 1.0 if r.randf() < 0.5 else -1.0
			shapes.append([32.0 + sx * r.randf_range(10.0, 16.0), 32.0 + r.randf_range(-3, 3), r.randf_range(8.0, 13.0), r.randf_range(1.2, 2.2)])
		for sh in shapes:
			var cx: float = sh[0]
			var cy: float = sh[1]
			var rx: float = sh[2]
			var ry: float = sh[3]
			for y in range(maxi(0, int(cy - ry - 2)), mini(64, int(cy + ry + 3))):
				for x in range(maxi(0, int(cx - rx - 2)), mini(64, int(cx + rx + 3))):
					var dx := (float(x) + 0.5 - cx) / rx
					var dy := (float(y) + 0.5 - cy) / ry
					var d := sqrt(dx * dx + dy * dy)
					var a := clampf((1.0 - d) * minf(rx, ry) * 0.9, 0.0, 1.0)
					if a <= 0.0:
						continue
					var old := img.get_pixel(x, y)
					var na := maxf(old.a, a)
					# Darker rim, lighter wet centre.
					var lum := 0.78 + 0.22 * clampf(1.0 - d, 0.0, 1.0)
					img.set_pixel(x, y, Color(maxf(old.r if old.a > 0.0 else 0.0, lum), maxf(old.g if old.a > 0.0 else 0.0, lum), maxf(old.b if old.a > 0.0 else 0.0, lum), na))
		out.append(ImageTexture.create_from_image(img))
	return out
