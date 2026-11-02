class_name StallWatch
extends RefCounted
## Host-side stall detector for one zombie: true once it has moved less than `min_move` metres over `window` seconds
## while `active` (a live target, not meleeing or tearing a barricade). Inactive time resets the window.

var _ref := Vector3.ZERO
var _t := 0.0
var _have := false

func reset() -> void:
	_have = false
	_t = 0.0

func update(dt: float, pos: Vector3, active: bool, window: float, min_move: float) -> bool:
	if not active:
		_have = false
		_t = 0.0
		return false
	if not _have or pos.distance_to(_ref) >= min_move:
		_ref = pos
		_have = true
		_t = 0.0
		return false
	_t += dt
	if _t >= window:
		reset()
		return true
	return false
