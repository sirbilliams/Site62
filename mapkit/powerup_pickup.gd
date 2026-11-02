class_name PowerupPickup
extends Node3D
## A dropped power-up: a spinning orb with a label. Pure visual + data; PowerupService (host) decides pickup.

var pid := 0
var kind: StringName = &"double_points"
var life := 25.0               # host: seconds left before it despawns

func _ready() -> void:
	var mi := MeshInstance3D.new()
	var s := SphereMesh.new()
	s.radius = 0.3
	s.height = 0.6
	mi.mesh = s
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 1.0, 0.4)
	m.emission_enabled = true
	m.emission = Color(0.1, 0.8, 0.3)
	mi.material_override = m
	add_child(mi)
	var l := Label3D.new()
	l.text = String(kind).replace("_", " ")
	l.position.y = 0.6
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(l)

func _process(dt: float) -> void:
	rotate_y(dt * 2.0)
