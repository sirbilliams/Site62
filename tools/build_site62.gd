extends SceneTree
## Generates maps/site62/site62.tscn (+ site62_nav.res). Run:
##   flatpak run org.godotengine.Godot --headless --path . -s tools/build_site62.gd
## The committed .tscn loads standalone; this script is only the authoring tool.
## Layout (x east, z south, metres):
##   yard (outside, z -9..0) -- 2 barricaded windows -- entrance_lab (x -10..10, z 0..16)
##   entrance_lab -door x=14- cafeteria (x 18..38, z 0..16) -door z=20- offices (x 18..38, z 24..40)
##   offices -door x=14- reactor_wing (x -10..10, z 24..40) -door z=44- refit_chamber (x -10..10, z 48..62)

const H := 3.2
const T := 0.4
const TEX := "res://content/art/polyhaven/"

var map: Node3D
var mats := {}
var solids: Node3D
var props: Node3D
var ceilings: Node3D
var lights: Node3D

func _initialize() -> void:
	await process_frame
	map = Node3D.new()
	map.name = "Site62"
	get_root().add_child(map)
	_materials()
	solids = _group("Structure")
	props = _group("Props")
	ceilings = _group("Ceilings")
	lights = _group("Lights")
	_environment()
	_structure()
	_dressing()
	_kit()
	_bake()
	var ps := PackedScene.new()
	var err := ps.pack(map)
	if err == OK:
		err = ResourceSaver.save(ps, "res://maps/site62/site62.tscn")
	print("BUILD site62 ", "OK" if err == OK else "FAIL %d" % err)
	quit(0 if err == OK else 1)

func _group(n: String) -> Node3D:
	var g := Node3D.new()
	g.name = n
	map.add_child(g)
	g.owner = map
	return g

func _own(n: Node) -> void:
	n.owner = map

# ---------------------------------------------------------------- materials
func _tex(path: String) -> Texture2D:
	return load(TEX + path)

func _pbr(name: String, diff: String, nor: String, tint: Color, scale: float, rough := 0.85, metal := 0.0) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(diff)
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = _tex(nor)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.roughness = rough
	m.metallic = metal
	mats[name] = m

func _flat(name: String, c: Color, emissive := 0.0, rough := 0.7, metal := 0.0) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emissive > 0.0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emissive
	mats[name] = m

func _materials() -> void:
	_pbr("floor", "worn_tile_floor_diff_1k.jpg", "worn_tile_floor_nor_gl_1k.jpg", Color(0.85, 0.9, 0.88), 0.35)
	_pbr("wall", "concrete_wall_007_diff_1k.jpg", "concrete_wall_007_nor_gl_1k.jpg", Color(0.78, 0.82, 0.8), 0.3)
	_pbr("yard", "concrete_wall_007_diff_1k.jpg", "concrete_wall_007_nor_gl_1k.jpg", Color(0.45, 0.47, 0.5), 0.2)
	_pbr("ceil", "concrete_wall_007_diff_1k.jpg", "concrete_wall_007_nor_gl_1k.jpg", Color(0.6, 0.62, 0.6), 0.25)
	_pbr("metal", "metal_plate_diff_1k.jpg", "metal_plate_nor_gl_1k.jpg", Color(0.62, 0.68, 0.66), 0.5, 0.5, 0.5)
	_pbr("door", "metal_plate_diff_1k.jpg", "metal_plate_nor_gl_1k.jpg", Color(0.78, 0.55, 0.2), 0.5, 0.5, 0.4)
	_flat("wood", Color(0.45, 0.3, 0.17))
	_flat("teal", Color(0.12, 0.45, 0.45))
	_flat("mustard", Color(0.8, 0.6, 0.15))
	_flat("sign", Color(0.95, 0.9, 0.7), 1.5)
	_flat("strip", Color(0.85, 0.95, 1.0), 3.0)
	_flat("redglow", Color(1.0, 0.1, 0.05), 3.0)
	_flat("vent", Color(0.07, 0.07, 0.08), 0.0, 0.5, 0.6)
	_flat("board", Color(0.35, 0.22, 0.1))
	_flat("hazard", Color(0.9, 0.7, 0.05))

# ---------------------------------------------------------------- primitives
## Box from (x1,z1) to (x2,z2) between heights y0..y1.
func _box(parent: Node3D, name: String, x1: float, z1: float, x2: float, z2: float, y0: float, y1: float,
		mat: String, collide := true) -> Node3D:
	var size := Vector3(absf(x2 - x1), y1 - y0, absf(z2 - z1))
	var center := Vector3((x1 + x2) / 2.0, (y0 + y1) / 2.0, (z1 + z2) / 2.0)
	var holder: Node3D
	if collide:
		var sb := StaticBody3D.new()
		sb.collision_layer = 1
		sb.collision_mask = 0
		holder = sb
	else:
		holder = Node3D.new()
	holder.name = name
	holder.position = center
	parent.add_child(holder)
	_own(holder)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mats[mat]
	mi.name = "Mesh"
	holder.add_child(mi)
	_own(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.name = "Shape"
		holder.add_child(cs)
		_own(cs)
	return holder

func _floor(name: String, x1: float, z1: float, x2: float, z2: float, mat := "floor") -> void:
	_box(solids, "Floor_" + name, x1, z1, x2, z2, -0.3, 0.0, mat)
	_box(ceilings, "Ceil_" + name, x1, z1, x2, z2, H, H + 0.2, "ceil", false)

## Wall along the X axis at z, from xa to xb, with gaps [[a,b],...]. Gap kinds: "door" (lintel only) or "window".
func _wall_x(z: float, xa: float, xb: float, gaps: Array = [], tag := "W") -> void:
	var cur := xa
	var i := 0
	for g in gaps:
		if g[0] > cur:
			_box(solids, "%s_%d_%d_%d" % [tag, int(z), int(cur), i], cur - (T / 2.0 if cur == xa else 0.0), z - T / 2.0, g[0], z + T / 2.0, 0.0, H, "wall")
		_gap_fill(g, z, true)
		cur = g[1]
		i += 1
	if cur < xb:
		_box(solids, "%s_%d_%d_end" % [tag, int(z), int(cur)], cur, z - T / 2.0, xb + (T / 2.0 if true else 0.0), z + T / 2.0, 0.0, H, "wall")

func _wall_z(x: float, za: float, zb: float, gaps: Array = [], tag := "W") -> void:
	var cur := za
	var i := 0
	for g in gaps:
		if g[0] > cur:
			_box(solids, "%s_%d_%d_%d" % [tag, int(x), int(cur), i], x - T / 2.0, cur - (T / 2.0 if cur == za else 0.0), x + T / 2.0, g[0], 0.0, H, "wall")
		_gap_fill(g, x, false)
		cur = g[1]
		i += 1
	if cur < zb:
		_box(solids, "%s_%d_%d_end" % [tag, int(x), int(cur)], x - T / 2.0, cur, x + T / 2.0, zb + T / 2.0, 0.0, H, "wall")

func _gap_fill(g: Array, axis: float, along_x: bool) -> void:
	var kind: String = g[2] if g.size() > 2 else "door"
	var n := "Gap_%s_%d_%d" % ["x" if along_x else "z", int(axis), int(g[0])]
	var a: float = g[0]
	var b: float = g[1]
	var lo := axis - T / 2.0
	var hi := axis + T / 2.0
	if kind == "window":
		if along_x:
			_box(solids, n + "_sill", a, lo, b, hi, 0.0, 1.0, "wall")         # solid sill: blocks the baked mesh and players, not bullets
			_box(solids, n + "_head", a, lo, b, hi, 2.3, H, "wall", false)
		else:
			_box(solids, n + "_sill", lo, a, hi, b, 0.0, 1.0, "wall")
			_box(solids, n + "_head", lo, a, hi, b, 2.3, H, "wall", false)
	else:
		if along_x:
			_box(solids, n + "_head", a, lo, b, hi, 2.8, H, "wall", false)
		else:
			_box(solids, n + "_head", lo, a, hi, b, 2.8, H, "wall", false)

func _obstacle(name: String, cx: float, cz: float, sx: float, sz: float, h: float, mat := "metal") -> void:
	_box(props, name, cx - sx / 2.0, cz - sz / 2.0, cx + sx / 2.0, cz + sz / 2.0, 0.0, h, mat)

func _deco(name: String, x1: float, z1: float, x2: float, z2: float, y0: float, y1: float, mat: String) -> void:
	_box(props, name, x1, z1, x2, z2, y0, y1, mat, false)

func _sign(text: String, pos: Vector3, rot_y: float, size := 60, color := Color(0.12, 0.08, 0.04), board := Color(0.95, 0.88, 0.62), w := 1.8) -> void:
	var plate := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(w, 0.55, 0.05)
	plate.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = board
	m.emission_enabled = true
	m.emission = board
	m.emission_energy_multiplier = 0.9
	plate.material_override = m
	plate.position = pos
	plate.rotation.y = rot_y
	plate.name = "Sign_" + text.substr(0, 8).validate_node_name()
	props.add_child(plate)
	_own(plate)
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.004
	l.modulate = color
	l.outline_size = 0
	l.position = Vector3(0, 0, 0.03)
	l.width = w * 230.0
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	plate.add_child(l)
	_own(l)

func _light(pos: Vector3, color: Color, energy: float, rng: float, shadow := false, spot := false) -> void:
	var l := OmniLight3D.new()
	l.position = pos
	l.light_color = color
	l.light_energy = energy
	l.omni_range = rng
	l.shadow_enabled = shadow
	l.name = "Light_%d_%d" % [int(pos.x), int(pos.z)]
	lights.add_child(l)
	_own(l)

func _strip(cx: float, cz: float, along_x: bool, col := "strip") -> void:
	var len := 2.6
	if along_x:
		_deco("Strip_%d_%d" % [cx, cz], cx - len / 2.0, cz - 0.1, cx + len / 2.0, cz + 0.1, H - 0.12, H - 0.02, col)
	else:
		_deco("Strip_%d_%d" % [cx, cz], cx - 0.1, cz - len / 2.0, cx + 0.1, cz + len / 2.0, H - 0.12, H - 0.02, col)

func _vent(x: float, z: float, facing: Vector2) -> void:
	# a wall grille with dark slats; facing is the room-side direction
	if absf(facing.x) > 0.0:
		_deco("Vent_%d_%d" % [x, z], x - 0.1 * signf(facing.x) - 0.04, z - 0.9, x + 0.1 * signf(facing.x) + 0.04, z + 0.9, 0.5, 1.5, "vent")
	else:
		_deco("Vent_%d_%d" % [x, z], x - 0.9, z - 0.1 * signf(facing.y) - 0.04, x + 0.9, z + 0.1 * signf(facing.y) + 0.04, 0.5, 1.5, "vent")

# ---------------------------------------------------------------- structure
func _structure() -> void:
	# floors: rooms, corridors, yard
	_floor("A", -10, 0, 10, 16)
	_floor("B", 18, 0, 38, 16)
	_floor("C", 18, 24, 38, 40)
	_floor("D", -10, 24, 10, 40)
	_floor("E", -10, 48, 10, 62)
	_floor("c1", 10, 6, 18, 10)
	_floor("c2", 26, 16, 30, 24)
	_floor("c3", 10, 30, 18, 34)
	_floor("c4", -2, 40, 2, 48)
	_box(solids, "Floor_yard", -14, -9, 14, 0, -0.3, 0.0, "yard")
	# yard perimeter (also a short stub of wall each side of the lab front)
	_wall_x(-9, -14, 14, [], "Yard")
	_wall_z(-14, -9, 0, [], "YardW")
	_wall_z(14, -9, 0, [], "YardE")
	_wall_x(0, -14, -10, [], "YardS1")
	_wall_x(0, 10, 14, [], "YardS2")
	# A entrance_lab: N windows at x=-5, 5; E opening to c1
	_wall_x(0, -10, 10, [[-6, -4, "window"], [4, 6, "window"]], "A_N")
	_wall_z(10, 0, 16, [[6, 10]], "A_E")
	_wall_x(16, -10, 10, [], "A_S")
	_wall_z(-10, 0, 16, [], "A_W")
	# B cafeteria
	_wall_x(0, 18, 38, [], "B_N")
	_wall_z(38, 0, 16, [], "B_E")
	_wall_x(16, 18, 38, [[26, 30]], "B_S")
	_wall_z(18, 0, 16, [[6, 10]], "B_W")
	# C offices
	_wall_x(24, 18, 38, [[26, 30]], "C_N")
	_wall_z(38, 24, 40, [], "C_E")
	_wall_x(40, 18, 38, [], "C_S")
	_wall_z(18, 24, 40, [[30, 34]], "C_W")
	# D reactor_wing
	_wall_x(24, -10, 10, [], "D_N")
	_wall_z(10, 24, 40, [[30, 34]], "D_E")
	_wall_x(40, -10, 10, [[-2, 2]], "D_S")
	_wall_z(-10, 24, 40, [], "D_W")
	# E refit_chamber
	_wall_x(48, -10, 10, [[-2, 2]], "E_N")
	_wall_z(10, 48, 62, [], "E_E")
	_wall_x(62, -10, 10, [], "E_S")
	_wall_z(-10, 48, 62, [], "E_W")
	# corridors (side walls) with a door frame pinching the opening to 2 m at the door line
	_wall_x(6, 10, 18, [], "c1_N")
	_wall_x(10, 10, 18, [], "c1_S")
	_wall_z(14, 6, 10, [[7, 9]], "c1_door")
	_wall_z(26, 16, 24, [], "c2_W")
	_wall_z(30, 16, 24, [], "c2_E")
	_wall_x(20, 26, 30, [[27, 29]], "c2_door")
	_wall_x(30, 10, 18, [], "c3_N")
	_wall_x(34, 10, 18, [], "c3_S")
	_wall_z(14, 30, 34, [[31, 33]], "c3_door")
	_wall_z(-2, 40, 48, [], "c4_W")
	_wall_z(2, 40, 48, [], "c4_E")
	_wall_x(44, -2, 2, [[-1, 1]], "c4_door")

# ---------------------------------------------------------------- dressing: props, signs, lights
func _dressing() -> void:
	# --- A entrance_lab: warm sodium + a fluorescent strip, lab benches
	_obstacle("A_Bench", 0, 7.5, 8, 1.5, 1.0, "teal")
	_obstacle("A_Locker1", -8.8, 3, 1.2, 4.0, 2.0)
	_obstacle("A_Locker2", 8.8, 13, 1.2, 4.0, 2.0)
	_light(Vector3(-5, 2.7, 8), Color(1.0, 0.72, 0.38), 2.2, 13, true)
	_light(Vector3(5, 2.7, 8), Color(1.0, 0.72, 0.38), 2.2, 13)
	_light(Vector3(0, 2.8, 13), Color(0.8, 0.9, 1.0), 1.4, 11)
	_strip(0, 3, true)
	_strip(0, 12, true)
	_sign("SITE 62\nAUTHORISED PERSONNEL", Vector3(0, 2.4, 15.75), PI, 52, Color(0.1, 0.1, 0.1), Color(0.95, 0.88, 0.62), 3.2)
	_sign("BULKHEAD 1 >", Vector3(9.78, 2.4, 3.0), -PI / 2.0, 44, Color(0.1, 0.1, 0.1), Color(0.95, 0.88, 0.62), 1.8)
	# --- B cafeteria: tables, pillar
	_obstacle("B_Table1", 24.5, 5, 5, 1.5, 1.0, "wood")
	_obstacle("B_Table2", 31.5, 5, 5, 1.5, 1.0, "wood")
	_obstacle("B_Pillar", 28, 11, 1.2, 1.2, H, "wall")
	_obstacle("B_Counter", 34, 14.6, 6, 1.2, 1.0, "mustard")
	_light(Vector3(24, 2.7, 8), Color(1.0, 0.72, 0.38), 2.0, 12, true)
	_light(Vector3(32, 2.7, 8), Color(1.0, 0.72, 0.38), 2.0, 12)
	_light(Vector3(28, 2.8, 13), Color(0.8, 0.9, 1.0), 1.2, 10)
	_strip(24, 12, true)
	_strip(32, 12, true)
	_sign("CAFETERIA", Vector3(18.22, 2.4, 11.5), PI / 2.0, 64, Color(0.1, 0.1, 0.1), Color(0.95, 0.88, 0.62), 2.2)
	_sign("COFFEE - 5c", Vector3(28, 2.4, 0.22), 0.0, 52, Color(0.1, 0.1, 0.1), Color(0.5, 0.8, 0.8), 2.0)
	# --- C offices: desks, filing cabinets
	_obstacle("C_Desk1", 24, 29, 4, 1.6, 0.9, "wood")
	_obstacle("C_Desk2", 32, 29, 4, 1.6, 0.9, "wood")
	_obstacle("C_Desk3", 28, 36, 6, 1.6, 0.9, "wood")
	_obstacle("C_Filing", 23, 39.2, 5, 0.8, 1.6, "metal")
	_light(Vector3(24, 2.7, 32), Color(1.0, 0.72, 0.38), 2.0, 12)
	_light(Vector3(32, 2.7, 32), Color(0.8, 0.9, 1.0), 1.6, 12, true)
	_strip(24, 36, true)
	_strip(32, 36, true)
	_strip(28, 27, false)
	_sign("OFFICES - LEVEL B", Vector3(28, 2.4, 24.22), 0.0, 52, Color(0.1, 0.1, 0.1), Color(0.95, 0.88, 0.62), 2.6)
	# --- D reactor_wing: central reactor core, red emergency lights
	_obstacle("D_Core", 0, 32, 6, 6, H, "metal")
	_deco("D_CoreRing", -3.2, 28.8, 3.2, 35.2, 1.4, 1.7, "redglow")
	_obstacle("D_Panel", 8.8, 26.5, 1.2, 3.5, 2.2, "metal")
	_light(Vector3(-6, 2.8, 28), Color(1.0, 0.1, 0.05), 2.6, 11)
	_light(Vector3(6, 2.8, 37), Color(1.0, 0.1, 0.05), 2.6, 11)
	_light(Vector3(0, 2.8, 32), Color(1.0, 0.2, 0.1), 2.0, 10, true)
	_light(Vector3(-6, 2.8, 37), Color(1.0, 0.72, 0.38), 1.2, 9)
	_strip(-6, 25, true, "redglow")
	_strip(6, 25, true, "redglow")
	_sign("REACTOR WING\nAUTHORISED ONLY", Vector3(9.78, 2.4, 27.0), -PI / 2.0, 46, Color(0.95, 0.9, 0.9), Color(0.7, 0.08, 0.05), 2.4)
	# --- E refit_chamber: cold, clean
	_obstacle("E_Crates1", -5, 53, 2, 2, 2.0, "wood")
	_obstacle("E_Crates2", 5, 53, 2, 2, 2.0, "wood")
	_obstacle("E_Plinth", 0, 61.0, 3.2, 1.6, 0.3, "mustard")
	_light(Vector3(-5, 2.8, 52), Color(0.75, 0.9, 1.0), 2.4, 12, true)
	_light(Vector3(5, 2.8, 52), Color(0.75, 0.9, 1.0), 2.4, 12)
	_light(Vector3(0, 2.8, 58), Color(1.0, 0.75, 0.45), 2.0, 11)
	_strip(0, 52, true)
	_strip(0, 58, true)
	_sign("ISOTOPE REFIT", Vector3(0, 2.4, 61.75), PI, 64, Color(0.05, 0.1, 0.1), Color(0.55, 0.9, 0.9), 3.0)
	# --- corridors
	_light(Vector3(14, 2.8, 8), Color(1.0, 0.72, 0.38), 1.4, 7)
	_light(Vector3(28, 2.8, 20), Color(1.0, 0.72, 0.38), 1.4, 7)
	_light(Vector3(14, 2.8, 32), Color(1.0, 0.72, 0.38), 1.4, 7)
	_light(Vector3(0, 2.8, 44), Color(1.0, 0.2, 0.1), 1.6, 7)
	# --- yard: moonlit courtyard, wrecked vehicle barriers
	_obstacle("Yard_Barrier1", -8, -4.5, 3, 0.8, 1.0, "metal")
	_obstacle("Yard_Barrier2", 8, -4.5, 3, 0.8, 1.0, "metal")
	_light(Vector3(0, 4.5, -4), Color(0.55, 0.65, 1.0), 3.0, 22)
	_light(Vector3(-9, 3, -2), Color(1.0, 0.72, 0.38), 2.4, 9)
	_light(Vector3(9, 3, -2), Color(1.0, 0.72, 0.38), 2.4, 9)
	# floor hazard stripes at each bulkhead
	for p in [Vector3(14, 0, 8), Vector3(14, 0, 32)]:
		_deco("Hazard_%d_%d" % [p.x, p.z], p.x - 0.5, p.z - 2, p.x + 0.5, p.z + 2, 0.0, 0.02, "hazard")
	for p in [Vector3(28, 0, 20), Vector3(0, 0, 44)]:
		_deco("Hazard_%d_%d" % [p.x, p.z], p.x - 2, p.z - 0.5, p.x + 2, p.z + 0.5, 0.0, 0.02, "hazard")
	# spawn vents (behind-the-grille spawns)
	_vent(37.8, 13, Vector2(-1, 0))
	_vent(37.8, 2.5, Vector2(-1, 0))
	_vent(37.8, 26, Vector2(-1, 0))
	_vent(37.8, 38, Vector2(-1, 0))
	_vent(-9.8, 26, Vector2(1, 0))
	_vent(-9.8, 38, Vector2(1, 0))
	_vent(9.8, 52, Vector2(-1, 0))
	_vent(-9.8, 60, Vector2(1, 0))

# ---------------------------------------------------------------- map kit
func _inst(path: String, name: String, pos: Vector3, rot_y := 0.0) -> Node3D:
	var n: Node3D = load(path).instantiate()
	n.name = name
	n.position = pos
	n.rotation.y = rot_y
	map.add_child(n)
	_own(n)
	return n

func _kit() -> void:
	var zones := {&"entrance_lab": Vector3(0, 0, 11), &"cafeteria": Vector3(24, 0, 13), &"offices": Vector3(28, 0, 32),
		&"reactor_wing": Vector3(-6, 0, 27), &"refit_chamber": Vector3(0, 0, 53)}
	for zid in zones:
		var z := Zone.new()
		z.name = "Zone_" + zid
		z.zone_id = zid
		z.open = zid == &"entrance_lab"
		z.position = zones[zid]
		map.add_child(z)
		_own(z)
	var spawns := {
		&"entrance_lab": [Vector3(-9, 0.2, -5), Vector3(9, 0.2, -5), Vector3(0, 0.2, -7)],
		&"cafeteria": [Vector3(37, 0.2, 13), Vector3(37, 0.2, 2.5), Vector3(20, 0.2, 1.5)],
		&"offices": [Vector3(37, 0.2, 26), Vector3(37, 0.2, 38), Vector3(20, 0.2, 26)],
		&"reactor_wing": [Vector3(-9, 0.2, 26), Vector3(-9, 0.2, 38), Vector3(8, 0.2, 38.5)],
		&"refit_chamber": [Vector3(9, 0.2, 52), Vector3(-9, 0.2, 60), Vector3(9, 0.2, 60)]}
	for zid in spawns:
		var i := 0
		for p in spawns[zid]:
			var s := _inst("res://mapkit/spawn_zone.tscn", "Spawn_%s_%d" % [zid, i], p)
			s.zone_id = zid
			i += 1
	# 4 player starts in the entrance lab
	for i in 4:
		var m := Marker3D.new()
		m.name = "PlayerStart%d" % (i + 1)
		m.position = Vector3(-4.5 + i * 3.0, 0.2, 13)
		m.add_to_group(&"player_starts", true)
		map.add_child(m)
		_own(m)
	# barricades on the two windows (local +Z = outside = north)
	_inst("res://mapkit/barricade.tscn", "Barricade_W", Vector3(-5, 0, 0), PI)
	_inst("res://mapkit/barricade.tscn", "Barricade_E", Vector3(5, 0, 0), PI)
	for x in [-5.0, 5.0]:
		_deco("Boards_%d" % x, x - 0.9, -0.12, x + 0.9, 0.12, 1.1, 1.9, "board")
	# doors
	var d1 := _inst("res://mapkit/bulkhead_door.tscn", "Door_cafeteria", Vector3(14, 0, 8), PI / 2.0)
	d1.cost = 750
	d1.unlocks.append(&"cafeteria")
	var d2 := _inst("res://mapkit/bulkhead_door.tscn", "Door_offices", Vector3(28, 0, 20))
	d2.cost = 1000
	d2.unlocks.append(&"offices")
	var d3 := _inst("res://mapkit/bulkhead_door.tscn", "Door_reactor", Vector3(14, 0, 32), PI / 2.0)
	d3.cost = 1250
	d3.unlocks.append(&"reactor_wing")
	var d4 := _inst("res://mapkit/bulkhead_door.tscn", "Door_refit", Vector3(0, 0, 44))
	d4.cost = 1500
	d4.unlocks.append(&"refit_chamber")
	for d in [d1, d2, d3, d4]:
		var slab := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2, 3.0, 0.3)
		slab.mesh = bm
		slab.material_override = mats["door"]
		slab.position = Vector3(0, 1.5, 0)
		slab.name = "Slab"
		d.get_node("Blocker").add_child(slab)
		_own(slab)
	# wall buy: Sentinel .45 on the west wall of the lab
	var wb := _inst("res://mapkit/wall_buy.tscn", "WallBuy_Sentinel", Vector3(-9.4, 0, 8), PI / 2.0)
	wb.weapon_id = &"sentinel_45"
	_deco("Sentinel_Board", -9.8, 6.8, -9.55, 9.2, 1.0, 2.0, "board")
	_deco("Sentinel_Gun", -9.55, 7.7, -9.45, 8.3, 1.45, 1.65, "vent")
	# suds machines
	var suds := {"B": ["snapback_fizz", Vector3(22, 0, 0.6), 0.0], "C": ["grape_bulwark", Vector3(22, 0, 39.4), PI],
		"D": ["second_wind_root_beer", Vector3(-6, 0, 24.6), 0.0], "E": ["overclock_orange", Vector3(-9.4, 0, 55), PI / 2.0]}
	for k in suds:
		var sm := _inst("res://mapkit/suds_machine.tscn", "Suds_" + k, suds[k][1], suds[k][2])
		sm.suds = load("res://content/suds/%s.tres" % suds[k][0])
	# crates, power switch, refit
	var c1 := _inst("res://mapkit/crate_spot.tscn", "Crate_B", Vector3(37, 0, 8), -PI / 2.0)
	c1.active = true
	_inst("res://mapkit/crate_spot.tscn", "Crate_C", Vector3(37, 0, 32), -PI / 2.0)
	_inst("res://mapkit/crate_spot.tscn", "Crate_D", Vector3(9.4, 0, 26), -PI / 2.0)
	for n in ["Crate_B", "Crate_C", "Crate_D"]:
		var cn: Node3D = map.get_node(n)
		var crate := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = Vector3(1.0, 0.7, 0.7)
		crate.mesh = bm2
		crate.material_override = mats["wood"]
		crate.position = Vector3(0, 0.35, 0)
		crate.name = "CrateMesh"
		cn.add_child(crate)
		_own(crate)
	_inst("res://mapkit/power_switch.tscn", "PowerSwitch", Vector3(-9.4, 0, 31), PI / 2.0)
	_deco("Switch_Box", -9.8, 30, -9.5, 32, 1.0, 1.9, "mustard")
	_inst("res://mapkit/refit_station.tscn", "Refit", Vector3(0, 0.3, 61.0), PI)
	_deco("Refit_Body", -1.0, 60.4, 1.0, 61.6, 0.3, 1.6, "teal")
	_deco("Refit_Glow", -0.7, 60.2, 0.7, 60.4, 1.0, 1.4, "strip")

# ---------------------------------------------------------------- environment + nav
func _environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.02, 0.025, 0.04)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.45, 0.5, 0.6)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.1, 0.12, 0.15)
	env.fog_density = 0.004
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	map.add_child(we)
	_own(we)

func _bake() -> void:
	var region := NavigationRegion3D.new()
	region.name = "Nav"
	map.add_child(region)
	_own(region)
	var nm := NavigationMesh.new()
	nm.agent_radius = 0.5
	nm.agent_height = 1.75
	nm.agent_max_climb = 0.25
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	var data := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(nm, data, map)
	NavigationServer3D.bake_from_source_geometry_data(nm, data)
	print("BAKE polygons ", nm.get_polygon_count(), " vertices ", nm.get_vertices().size())
	ResourceSaver.save(nm, "res://maps/site62/site62_nav.res")
	region.navigation_mesh = load("res://maps/site62/site62_nav.res")
