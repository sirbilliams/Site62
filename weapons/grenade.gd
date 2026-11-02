class_name Grenade
extends RigidBody3D
## A thrown frag: a physics sphere (placeholder art). Host and clients each simulate one from the same throw;
## only the host's explodes for damage. Clients drop theirs on the host's explode event.

signal exploded(gid: int, thrower: int, pos: Vector3)

var gid := 0
var thrower := 0
var data: ThrowableData
var fuse := 2.5
var is_host := false
var _done := false

## Damage at distance `d` from the centre: linear falloff to zero at the radius.
static func damage_at(d: float, t: ThrowableData) -> float:
	if d >= t.radius:
		return 0.0
	return t.damage * (1.0 - maxf(d, 0.0) / t.radius)

## targets: [{id, pos}]. Returns [{id, dmg}] for those inside the radius with a clear line (`blocked(from, to)` false).
static func blast(center: Vector3, targets: Array, t: ThrowableData, blocked: Callable) -> Array:
	var out: Array = []
	for tg in targets:
		var d := center.distance_to(tg.pos)
		if d >= t.radius:
			continue
		if blocked.is_valid() and blocked.call(center, tg.pos):
			continue
		out.append({"id": tg.id, "dmg": damage_at(d, t)})
	return out

func launch(id: int, by: int, d: ThrowableData, at: Vector3, velocity: Vector3, host: bool) -> void:
	gid = id
	thrower = by
	data = d
	fuse = d.fuse_s
	is_host = host
	position = at
	linear_velocity = velocity

func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	mass = 0.4
	linear_damp = 0.3
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.3
	pm.friction = 0.8
	physics_material_override = pm
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.1
	cs.shape = sh
	add_child(cs)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.1
	sm.height = 0.2
	mi.mesh = sm
	add_child(mi)

func _physics_process(dt: float) -> void:
	if not is_host or _done:
		return
	fuse -= dt
	if fuse <= 0.0:
		_done = true
		exploded.emit(gid, thrower, global_position)
