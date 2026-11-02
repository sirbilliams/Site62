extends Node3D
## Throwaway screenshot tool (not committed): the Task 6 test arena with visible greybox meshes for every
## box/capsule collider, a few zombies, and the Task 9 machines, captured from two angles.
const OUT := "/home/bill/Projects/arena-assets/shots/site62"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	var env := WorldEnvironment.new(); env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.08, 0.09, 0.11)
	env.environment.ambient_light_color = Color(0.5, 0.5, 0.55); env.environment.ambient_light_energy = 0.6
	add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-55, 35, 0); sun.shadow_enabled = true; add_child(sun)
	var b = load("res://tests/net/zombie_map.gd").build(self)
	var zs: PackedScene = load("res://enemies/zombie.tscn")
	for i in 7:
		var z = zs.instantiate()
		z.set_physics_process(false); z.set_process(false)
		add_child(z)
		z.position = Vector3(-4.0 + i * 1.4, 0, 3.0 + (i % 3) * 1.6)
	var x := -8.0
	for p in ["suds_machine", "crate_spot", "refit_station", "power_switch", "wall_buy", "bulkhead_door", "powerup_pickup"]:
		var s = load("res://mapkit/%s.tscn" % p).instantiate()
		if s is Node: s.set_process(false); s.set_physics_process(false)
		add_child(s)
		s.position = Vector3(x, 0, -5.0); x += 2.6
	await get_tree().process_frame
	_skin(self)
	var cam := Camera3D.new(); add_child(cam); cam.current = true; cam.fov = 70
	for shot in [["arena", Vector3(9, 7, 14), Vector3(0, 0.5, 0)], ["machines", Vector3(0, 3.5, 2.5), Vector3(0, 0.8, -5)]]:
		cam.position = shot[1]; cam.look_at(shot[2])
		for i in 20: await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [OUT, shot[0]])
		print("saved ", shot[0])
	get_tree().quit()

func _skin(n: Node) -> void:   # visible placeholder mesh for colliders that have none
	for c in n.get_children():
		_skin(c)
	if n is CollisionShape3D and n.shape != null and not _has_mesh(n.get_parent()):
		var mi := MeshInstance3D.new(); var mat := StandardMaterial3D.new()
		if n.shape is BoxShape3D:
			var m := BoxMesh.new(); m.size = n.shape.size; mi.mesh = m
		elif n.shape is CapsuleShape3D:
			var m := CapsuleMesh.new(); m.radius = n.shape.radius; m.height = n.shape.height; mi.mesh = m
		elif n.shape is SphereShape3D:
			var m := SphereMesh.new(); m.radius = n.shape.radius; m.height = n.shape.radius * 2; mi.mesh = m
		else:
			return
		var y: float = n.global_position.y
		mat.albedo_color = Color(0.35, 0.37, 0.4) if y < 0 else Color(0.55, 0.52, 0.47)
		mi.material_override = mat
		n.add_child(mi)

func _has_mesh(p: Node) -> bool:
	for c in p.get_children():
		if c is MeshInstance3D or c is CSGShape3D: return true
	return false
