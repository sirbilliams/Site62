class_name WeaponView
extends Node3D
## Client-side visuals: muzzle flash, tracer, hit markers. Predicted markers wait for the host's verdict.

const LIFE_S := 0.12
var _markers := {}       # key -> MeshInstance3D (predicted, awaiting host)

func _mesh(size: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material = mat
	mi.mesh = m
	return mi

func _expire(n: Node, secs: float) -> void:
	get_tree().create_timer(secs).timeout.connect(func(): if is_instance_valid(n): n.queue_free())

func muzzle_flash(pos: Vector3) -> void:
	var f := _mesh(Vector3(0.15, 0.15, 0.15), Color(1, 0.8, 0.3))
	add_child(f)
	f.global_position = pos
	_expire(f, LIFE_S)

func tracer(from: Vector3, to: Vector3) -> void:
	var len := from.distance_to(to)
	if len < 0.1:
		return
	var t := _mesh(Vector3(0.02, 0.02, len), Color(1, 0.95, 0.6))
	add_child(t)
	t.global_position = (from + to) * 0.5
	var up := Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT
	t.look_at(to, up)
	_expire(t, LIFE_S)

## Predicted hit marker; `key` identifies the shot (its client time stamp).
func predicted_marker(key: float, pos: Vector3, head: bool) -> void:
	var m := _mesh(Vector3.ONE * (0.3 if head else 0.2), Color(1, 0.2, 0.2) if head else Color(1, 1, 1))
	add_child(m)
	m.global_position = pos
	_markers[key] = m
	_expire(m, 1.0)          # safety net if the verdict is lost

## Host verdict: keep the marker briefly if it hit, otherwise drop it.
func resolve(key: float, hit: bool) -> void:
	var m = _markers.get(key)
	_markers.erase(key)
	if m == null or not is_instance_valid(m):
		return
	if hit:
		_expire(m, 0.15)
	else:
		m.queue_free()

func pending_markers() -> int:
	return _markers.size()
