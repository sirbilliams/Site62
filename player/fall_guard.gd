class_name FallGuard
extends RefCounted
## Host-side kill plane for one player: remembers a recent grounded position and says when the player fell below
## `kill_y` (the caller teleports them back to `safe`; no death).

var safe: Vector3
var _since := 0.0

func _init(start: Vector3 = Vector3.ZERO) -> void:
	safe = start

## True when `pos` is below the kill plane. Otherwise a grounded `pos` becomes the safe spot at most every `interval` s.
func step(dt: float, pos: Vector3, grounded: bool, kill_y: float, interval: float) -> bool:
	if pos.y < kill_y:
		return true
	_since += dt
	if grounded and _since >= interval:
		_since = 0.0
		safe = pos
	return false
