class_name TargetDummy
extends HitTarget
## Test target: a box-person that slides side to side. Motion is a pure function of host time.

const SPEED := 3.0
const SPAN := 14.0
const START_X := -4.0
const Z := -10.0

static func pos_at(t: float) -> Vector3:
	return Vector3(START_X + pingpong(t * SPEED, SPAN), 0.0, Z)

func _init() -> void:
	add_box(Vector3(0, 0.8, 0), Vector3(0.9, 1.6, 0.5))
	add_box(Vector3(0, 1.8, 0), Vector3(0.45, 0.45, 0.45), true)
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = Vector3(0.9, 1.6, 0.5)
	mi.mesh = m
	mi.position.y = 0.8
	add_child(mi)

func _ready() -> void:
	build_physics()
