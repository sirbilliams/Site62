class_name Spread
extends RefCounted
## Deterministic shot spread. Host and client derive the same offset from (shooter id, shot seq);
## the client never sends a spread direction, only its aim.

static func cone_deg(data: WeaponData, ads: bool) -> float:
	return data.spread_ads_deg if ads else data.spread_hip_deg

## `dir` rotated by a seeded offset that stays inside a cone of `cone_deg` half-angle.
static func offset_dir(dir: Vector3, cone_deg: float, shooter: int, seq: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([shooter, seq])
	var ang := rng.randf() * TAU
	var r := deg_to_rad(cone_deg) * sqrt(rng.randf())
	var d := dir.normalized()
	var up := Vector3.UP if absf(d.y) < 0.99 else Vector3.RIGHT
	var right := d.cross(up).normalized()
	var u := right.cross(d)
	return (d * cos(r) + (right * cos(ang) + u * sin(ang)) * sin(r)).normalized()
