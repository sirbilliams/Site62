class_name Recoil
extends RefCounted
## Client camera kick. Each shot in a burst takes the next WeaponData.recoil entry (x = yaw deg,
## y = pitch deg; the last entry repeats). The burst resets after RESET_S without firing.
## The accumulated kick recovers at RECOVER_DEG_S; recover() returns how much to take back off the camera.

const RESET_S := 0.35
const RECOVER_DEG_S := 12.0

var pattern := PackedVector2Array()
var index := 0
var last_shot := -INF
var accum := Vector2.ZERO

func _init(p := PackedVector2Array()) -> void:
	pattern = p

func kick(now: float) -> Vector2:
	if now - last_shot > RESET_S:
		index = 0
	var k := Vector2.ZERO
	if pattern.size() > 0:
		k = pattern[mini(index, pattern.size() - 1)]
	index += 1
	last_shot = now
	accum += k
	return k

func recover(dt: float) -> Vector2:
	var before := accum
	accum = accum.move_toward(Vector2.ZERO, RECOVER_DEG_S * dt)
	return before - accum
