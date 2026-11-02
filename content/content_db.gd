extends Node
## Autoload "Content": loads all data resources and validates them.

const SUDS_EFFECTS := [&"max_hp", &"reload_mult", &"revive", &"fire_rate_mult"]
const POWERUP_KINDS := [&"double_points", &"max_ammo", &"purge", &"overload", &"fortify", &"voucher"]

var weapons: Dictionary = {}
var enemies: Dictionary = {}
var suds: Dictionary = {}
var powerups: Dictionary = {}
var throwables: Dictionary = {}
var curve: RoundCurve
var balance: Balance

func _init() -> void:
	curve = load("res://content/round_curve.tres")
	balance = load("res://content/balance.tres")
	_load_dir("res://content/weapons", weapons)
	_load_dir("res://content/enemies", enemies)
	_load_dir("res://content/suds", suds)
	_load_dir("res://content/powerups", powerups)
	_load_dir("res://content/throwables", throwables)

func _load_dir(path: String, into: Dictionary) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	var files := dir.get_files()
	files.sort()
	for f in files:
		var fn := f.trim_suffix(".remap")
		if not fn.ends_with(".tres"):
			continue
		var r = load(path + "/" + fn)
		if r != null and "id" in r:
			into[r.id] = r

func weapon(id: StringName) -> WeaponData:
	return weapons.get(id)

func throwable(id: StringName) -> ThrowableData:
	return throwables.get(id)

func validate() -> PackedStringArray:
	var errs := PackedStringArray()
	if curve == null:
		errs.append("round_curve missing")
	if balance == null:
		errs.append("balance missing")
	for w in weapons.values():
		errs.append_array(validate_weapon(w))
	for e in enemies.values():
		errs.append_array(validate_enemy(e))
	for s in suds.values():
		if s.cost < 0:
			errs.append("suds %s: cost < 0" % s.id)
		if not SUDS_EFFECTS.has(s.effect):
			errs.append("suds %s: unknown effect %s" % [s.id, s.effect])
	for t in throwables.values():
		if t.fuse_s <= 0.0 or t.radius <= 0.0 or t.damage <= 0.0:
			errs.append("throwable %s: fuse/radius/damage must be > 0" % t.id)
	for p in powerups.values():
		if not POWERUP_KINDS.has(p.kind):
			errs.append("powerup %s: unknown kind %s" % [p.id, p.kind])
	return errs

func validate_weapon(w: WeaponData) -> PackedStringArray:
	var errs := PackedStringArray()
	var n := "weapon %s" % w.id
	if w.cost < 0:
		errs.append("%s: cost < 0" % n)
	if w.ammo_cost < 0:
		errs.append("%s: ammo_cost < 0" % n)
	if w.refit == w:
		errs.append("%s: refit must not be itself" % n)
	elif w.refit != null and w.refit.refit != null:
		errs.append("%s: refit weapon must have refit == null" % n)
	if w.mag <= 0:
		errs.append("%s: mag must be > 0" % n)
	if w.recoil.is_empty():
		errs.append("%s: recoil is empty" % n)
	return errs

func validate_enemy(e: EnemyData) -> PackedStringArray:
	var errs := PackedStringArray()
	if e.speed_by_band.size() != 3:
		errs.append("enemy %s: speed_by_band must have 3 values" % e.id)
	return errs
