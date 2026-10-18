class_name SoldierDrawState
extends RefCounted
## Everything SoldierArt.draw_soldier needs to paint one soldier for one frame
## (#258: replaces its ~26 positional parameters). Callers keep one instance
## per drawing node and refill it in _draw(), so nothing is allocated per frame.
## Defaults match the old parameter defaults.

var body_color := Color.WHITE
var facing := 1.0
var aim_dir := Vector2.RIGHT
var vel := Vector2.ZERO
var jet_on := false
var dead := false
var weapon_color := Color.WHITE
var weapon_kind := "bullet"
var muzzle_t := 0.0
var health := 100.0
var fuel := 0.0
var show_fuel := false
var weapon_name := ""
var on_floor := true
var reloading := false
var crouching := false
var prone := false
var melee_swing := false
var gesture_anim := ""
var rolling := false
var ceasefire := false
var cosmetics: Dictionary = {}
# #60: drives the belt-grenade + back-slung weapon overlays and the blood
# damage layer. gostek.gd only reads these via the pose dict, so cosmetics
# stays a pure user-config dict.
var back_weapon_name := ""
var grenade_count := 0
var use_cluster := false
var is_local := false
var show_hp := true
# Phase B (#271) visual-only offsets, filled by SoldierFeel (squash-and-
# stretch, recoil). soldier_art.gd applies them to the DRAWN sprite about the
# feet; the node transform and collision shape never change.
var fx_scale := Vector2.ONE
var fx_offset := Vector2.ZERO
var fx_rot := 0.0
var fx_kick := 0.0
