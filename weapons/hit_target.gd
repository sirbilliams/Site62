class_name HitTarget
extends Node3D
## Anything the weapon service can hit: a set of local-space boxes (one may be tagged head).
## Host lag-comp tests rays analytically against a rewound pose; a StaticBody3D on the
## "hitbox" physics layer mirrors the boxes for ordinary physics queries (client hit markers).
## Zombies (Task 6) extend this and register with WeaponService.register_target.

const LAYER_HITBOX := 4          # physics layer 3 ("hitbox")

var target_id := 0
var alive := true
var boxes: Array = []            # [{aabb: AABB, head: bool}]
var body: StaticBody3D

func add_box(center: Vector3, size: Vector3, head := false) -> void:
	boxes.append({"aabb": AABB(center - size * 0.5, size), "head": head})

func build_physics() -> void:
	if body != null:
		body.queue_free()
	body = StaticBody3D.new()
	body.collision_layer = LAYER_HITBOX
	body.collision_mask = 0
	body.set_meta(&"target_id", target_id)
	for b in boxes:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = (b.aabb as AABB).size
		cs.shape = bs
		cs.position = (b.aabb as AABB).get_center()
		cs.set_meta(&"head", b.head)
		body.add_child(cs)
	add_child(body)

## Ray against the boxes placed at `xf`. Returns {} or {t: distance, head: bool}. Heads win ties.
func ray_at(xf: Transform3D, origin: Vector3, dir: Vector3) -> Dictionary:
	var inv := xf.affine_inverse()
	var o := inv * origin
	var d := (inv.basis * dir).normalized()
	var best := {}
	for b in boxes:
		var hit = (b.aabb as AABB).intersects_ray(o, d)
		if hit == null:
			continue
		var t: float = o.distance_to(hit)
		if best.is_empty() or t < best.t or (t == best.t and b.head):
			best = {"t": t, "head": b.head}
	return best

func is_head_shape(shape_index: int) -> bool:
	return shape_index >= 0 and shape_index < boxes.size() and boxes[shape_index].head
