class_name HitHistory
extends RefCounted
## Short pose history per entity id (ints) for lag compensation. Keeps KEEP_S of history.

const KEEP_S := 0.25

var _h := {}      # id -> Array of [t, Transform3D, alive]
var _born := {}   # id -> time of first record

func record(now: float, id: int, xform: Transform3D, alive: bool) -> void:
	var a: Array = _h.get(id, [])
	a.append([now, xform, alive])
	# keep one entry older than the window so the window's start can be interpolated
	while a.size() > 2 and a[1][0] < now - KEEP_S:
		a.pop_front()
	_h[id] = a
	if not _born.has(id):
		_born[id] = now

func forget(id: int) -> void:
	_h.erase(id)
	_born.erase(id)

## Pose at time t: Transform3D, or null if the entity did not exist yet / was dead / is unknown.
## t is clamped to the retained range (older -> oldest pose, future -> newest).
func pose_at(id: int, t: float) -> Variant:
	var a: Array = _h.get(id, [])
	if a.is_empty() or t < _born[id]:
		return null
	if t <= a[0][0]:
		return a[0][1] if a[0][2] else null
	if t >= a[a.size() - 1][0]:
		var last: Array = a[a.size() - 1]
		return last[1] if last[2] else null
	for i in range(1, a.size()):
		if a[i][0] >= t:
			var p: Array = a[i - 1]
			var q: Array = a[i]
			if not p[2]:
				return null
			var k := clampf((t - p[0]) / maxf(q[0] - p[0], 1e-9), 0.0, 1.0)
			return (p[1] as Transform3D).interpolate_with(q[1], k)
	return null
