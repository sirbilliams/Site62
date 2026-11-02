class_name Motor
extends RefCounted
## Pure, deterministic movement. State: {pos: Vector3, vy: float, grounded: bool}.
## space == null -> flat floor at y = 0 (unit tests). World collision uses layer 1 only.

const WORLD_MASK := 1
const BODY_RADIUS := 0.35

static func initial_state(pos: Vector3) -> Dictionary:
	return {"pos": pos, "vy": 0.0, "grounded": true}

static func step(state: Dictionary, f: InputFrame, dt: float, space: PhysicsDirectSpaceState3D, bal: Balance) -> Dictionary:
	var pos: Vector3 = state.pos
	var vy: float = state.vy
	var grounded: bool = state.grounded
	var speed := bal.walk_speed
	if f.buttons & InputFrame.CROUCH:
		speed = bal.crouch_speed
	elif (f.buttons & InputFrame.SPRINT) and f.move.y > 0.0:
		speed = bal.sprint_speed
	var m := f.move.limit_length(1.0)
	var dir := Basis(Vector3.UP, f.look_yaw) * Vector3(m.x, 0.0, -m.y)
	var delta := dir * speed * dt
	if space != null and delta.length() > 0.0:
		delta = _slide(pos, delta, space)
	pos += delta
	if space != null and delta.length() > 0.0:
		pos += _push_out(pos, space)
	if grounded and (f.buttons & InputFrame.JUMP) and not (f.buttons & InputFrame.CROUCH):
		vy = bal.jump_speed
		grounded = false
	vy -= bal.gravity * dt
	var new_y := pos.y + vy * dt
	grounded = false
	if vy <= 0.0:
		var floor_y := _floor_height(pos, new_y, space)
		if not is_nan(floor_y) and floor_y >= new_y - 0.02:
			new_y = floor_y
			vy = 0.0
			grounded = true
	pos.y = new_y
	return {"pos": pos, "vy": vy, "grounded": grounded}

static func _floor_height(pos: Vector3, new_y: float, space: PhysicsDirectSpaceState3D) -> float:
	if space == null:
		return 0.0
	var q := PhysicsRayQueryParameters3D.create(Vector3(pos.x, pos.y + 0.5, pos.z), Vector3(pos.x, new_y - 0.05, pos.z), WORLD_MASK)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return NAN
	return (hit.position as Vector3).y

static func _slide(pos: Vector3, delta: Vector3, space: PhysicsDirectSpaceState3D) -> Vector3:
	var from := pos + Vector3.UP * 0.9
	var q := PhysicsRayQueryParameters3D.create(from, from + delta.normalized() * (delta.length() + BODY_RADIUS), WORLD_MASK)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return delta
	var n: Vector3 = hit.normal
	n.y = 0.0
	if n.length() < 0.001:
		return Vector3.ZERO
	n = n.normalized()
	var allowed := (hit.position as Vector3).distance_to(from) - BODY_RADIUS
	if allowed >= delta.length():
		return delta
	# remove the component pushing into the wall
	return delta - n * minf(delta.dot(n), 0.0)

## Grazing a wall for many steps (or a crack between two collision boxes) lets the centre ray miss; eight short rays around the
## body push the player back out so a bot or a player cannot slip through a wall corner into the void.
const _RING := [Vector3(1, 0, 0), Vector3(0.7071, 0, 0.7071), Vector3(0, 0, 1), Vector3(-0.7071, 0, 0.7071),
	Vector3(-1, 0, 0), Vector3(-0.7071, 0, -0.7071), Vector3(0, 0, -1), Vector3(0.7071, 0, -0.7071)]

static func _push_out(pos: Vector3, space: PhysicsDirectSpaceState3D) -> Vector3:
	var push := Vector3.ZERO
	var from := pos + Vector3.UP * 0.9
	for d: Vector3 in _RING:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + d * BODY_RADIUS, WORLD_MASK))
		if not hit.is_empty():
			push -= d * (BODY_RADIUS - (hit.position as Vector3).distance_to(from))
	push.y = 0.0
	return push.limit_length(BODY_RADIUS)
