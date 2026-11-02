class_name WeaponState
extends RefCounted
## Pure ammo / fire-rate / reload state for one weapon. `now` is whatever clock the caller uses
## consistently (host uses lag-comp shot time). No node access, fully unit-testable.

const EPS := 1e-6

var data: WeaponData
var mag := 0
var reserve := 0
var last_fire := -INF
var reloading := false
var reload_end := 0.0

func _init(d: WeaponData) -> void:
	data = d
	refill()

func refill() -> void:
	mag = data.mag
	reserve = data.reserve
	reloading = false
	last_fire = -INF

func interval(rate_mult := 1.0) -> float:
	return 60.0 / (data.fire_rate_rpm * rate_mult)

## "" when the weapon may fire, else &"reload" / &"ammo" / &"rate".
func block_reason(now: float, rate_mult := 1.0) -> StringName:
	update(now)
	if reloading:
		return &"reload"
	if mag <= 0:
		return &"ammo"
	if now < last_fire + interval(rate_mult) - EPS:
		return &"rate"
	return &""

func can_fire(now: float, rate_mult := 1.0) -> bool:
	return block_reason(now, rate_mult) == &""

func fire(now: float, rate_mult := 1.0) -> bool:
	if not can_fire(now, rate_mult):
		return false
	mag -= 1
	last_fire = now
	return true

## `mult` > 1 reloads faster.
func start_reload(now: float, mult := 1.0) -> bool:
	update(now)
	if reloading or mag >= data.mag or reserve <= 0:
		return false
	reloading = true
	reload_end = now + data.reload_s / maxf(mult, 0.01)
	return true

func update(now: float) -> void:
	if reloading and now >= reload_end:
		var moved := mini(data.mag - mag, reserve)
		mag += moved
		reserve -= moved
		reloading = false

func damage_at(dist: float) -> float:
	if dist <= data.falloff_start:
		return data.damage
	if dist >= data.falloff_end:
		return data.damage * data.falloff_min_mult
	var k := (dist - data.falloff_start) / (data.falloff_end - data.falloff_start)
	return data.damage * lerpf(1.0, data.falloff_min_mult, k)
