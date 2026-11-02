class_name Melee
extends RefCounted
## Host-side knife: a short cone check (pure statics) plus a per-player swing cooldown.

var last := -INF

func ready(now: float, cooldown: float, tolerance := 0.0) -> bool:
	return now >= last + cooldown * (1.0 - tolerance) - 1e-6

func swing(now: float) -> void:
	last = now

## Is `point` within `reach` of `eye` and inside the cone (half angle `cone_deg`) around the unit `dir`?
static func in_reach(eye: Vector3, dir: Vector3, point: Vector3, reach: float, cone_deg: float) -> bool:
	var to := point - eye
	var d := to.length()
	if d > reach:
		return false
	if d < 0.05:
		return true
	return dir.angle_to(to) <= deg_to_rad(cone_deg)

## Nearest candidate {id, points: [Vector3]} with a point in reach and not `blocked(from, to)` (walls); 0 if none.
static func pick(eye: Vector3, dir: Vector3, cands: Array, reach: float, cone_deg: float, blocked: Callable) -> int:
	var best := 0
	var best_d := INF
	for c in cands:
		for p: Vector3 in c.points:
			if not in_reach(eye, dir, p, reach, cone_deg):
				continue
			if blocked.is_valid() and blocked.call(eye, p):
				continue
			var d := eye.distance_to(p)
			if d < best_d:
				best_d = d
				best = c.id
	return best
