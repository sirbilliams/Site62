extends TestCase

const MAP := "res://maps/site62/site62.tscn"
const ZONES: Array[StringName] = [&"entrance_lab", &"cafeteria", &"offices", &"reactor_wing", &"refit_chamber"]

func _load() -> Node3D:
	var ps: PackedScene = load(MAP)
	assert_true(ps != null, "map scene loads")
	if ps == null:
		return null
	var m: Node3D = ps.instantiate()
	(Engine.get_main_loop() as SceneTree).root.add_child(m)
	return m

func _all(n: Node, out: Array) -> Array:
	out.append(n)
	for c in n.get_children():
		_all(c, out)
	return out

func _count(nodes: Array, script_class: String) -> int:
	var k := 0
	for n in nodes:
		var s: Script = n.get_script()
		if s != null and s.get_global_name() == script_class:
			k += 1
	return k

func test_map_has_required_nodes() -> void:
	var m := _load()
	if m == null:
		return
	var nodes := _all(m, [])
	assert_eq(_count(nodes, "Zone"), 5, "zones")
	assert_eq(_count(nodes, "Barricade"), 2, "barricades")
	assert_eq(_count(nodes, "BulkheadDoor"), 4, "doors")
	assert_eq(_count(nodes, "WallBuy"), 1, "wall buy")
	assert_eq(_count(nodes, "SudsMachine"), 4, "suds machines")
	assert_eq(_count(nodes, "CrateSpot"), 3, "crate spots")
	assert_eq(_count(nodes, "PowerSwitch"), 1, "power switch")
	assert_eq(_count(nodes, "RefitStation"), 1, "refit")
	var starts := 0
	for n in nodes:
		if n.is_in_group(&"player_starts"):
			starts += 1
	assert_eq(starts, 4, "player starts")
	var open_ids := {}
	var costs := {}
	for n in nodes:
		if n is Zone:
			assert_true(n.zone_id in ZONES, "zone id " + str(n.zone_id))
			if n.open:
				open_ids[n.zone_id] = true
		elif n is BulkheadDoor:
			costs[n.unlocks[0]] = n.cost
		elif n is WallBuy:
			assert_eq(n.weapon_id, &"sentinel_45", "wall buy weapon")
		elif n is SudsMachine:
			assert_true(n.suds != null, "machine has suds")
	assert_eq(open_ids.keys(), [&"entrance_lab"], "only the start zone is open")
	assert_eq(costs, {&"cafeteria": 750, &"offices": 1000, &"reactor_wing": 1250, &"refit_chamber": 1500}, "door costs")
	var per := {}
	var active_crates := 0
	for n in nodes:
		if n is SpawnZone:
			per[n.zone_id] = int(per.get(n.zone_id, 0)) + 1
		elif n is CrateSpot and n.active:
			active_crates += 1
	for z in ZONES:
		assert_true(int(per.get(z, 0)) >= 2, "spawn zones in " + str(z))
	assert_eq(active_crates, 1, "one active crate")
	m.free()

func _reach(m: Node3D, map: RID, from: Vector3, to: Vector3) -> bool:
	var p := NavigationServer3D.map_get_path(map, from, to, true)
	if p.is_empty():
		return false
	var e: Vector3 = p[p.size() - 1]
	return Vector2(e.x - to.x, e.z - to.z).length() < 1.0

## Builds a private NavigationServer3D map from the scene (the unit runner has no frame loop, so the scene's own
## region/links are mirrored onto RIDs by hand). Returns {map, links: [[RID, NavigationLink3D, Transform3D]]}.
func _nav_of(m: Node3D) -> Dictionary:
	var map := NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(map, true)
	var links := []
	var regions: Array[RID] = []
	for n in _all(m, []):
		if n is NavigationRegion3D:
			var r := NavigationServer3D.region_create()
			NavigationServer3D.region_set_map(r, map)
			NavigationServer3D.region_set_navigation_mesh(r, n.navigation_mesh)
			regions.append(r)
			NavigationServer3D.region_set_transform(r, Transform3D(Basis.IDENTITY, n.position))
		elif n is BulkheadDoor or n is Barricade:
			if n is BulkheadDoor:                      # _ready has not run (the runner never ticks a frame)
				n.link = n.get_node("Link")
				n.blocker = n.get_node("Blocker")
			var l := NavigationServer3D.link_create()
			NavigationServer3D.link_set_map(l, map)
			links.append([l, n.link, n.transform])
	return {"map": map, "links": links, "regions": regions}

func _sync_links(nav: Dictionary) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for e in nav["links"]:
		var lk: NavigationLink3D = e[1]
		var t: Transform3D = e[2]
		NavigationServer3D.link_set_start_position(e[0], t * lk.start_position)
		NavigationServer3D.link_set_end_position(e[0], t * lk.end_position)
		NavigationServer3D.link_set_bidirectional(e[0], lk.bidirectional)
		NavigationServer3D.link_set_enabled(e[0], lk.enabled)
	for i in 20:                                   # the server rebuilds the map over a few physics frames
		await tree.physics_frame

func test_all_zones_reachable_after_doors():
	var m := _load()
	if m == null:
		return
	var zone_pos := {}
	var doors: Array[BulkheadDoor] = []
	var starts: Array = []
	var nm: NavigationMesh = null
	for n in _all(m, []):
		if n.is_in_group(&"player_starts"):
			starts.append(n)
		if n is NavigationRegion3D:
			nm = n.navigation_mesh
		elif n is Zone:
			zone_pos[n.zone_id] = n.position
		elif n is BulkheadDoor:
			doors.append(n)
	assert_true(nm != null and nm.get_polygon_count() > 0, "baked nav mesh")
	if nm == null:
		m.free()
		return
	var nav := _nav_of(m)
	var map: RID = nav["map"]
	await _sync_links(nav)
	var from: Vector3 = (starts[0] as Node3D).position
	assert_true(_reach(m, map, from, zone_pos[&"entrance_lab"]), "start reaches entrance_lab")
	for z in ZONES.slice(1):
		assert_true(not _reach(m, map, from, zone_pos[z]), "closed doors block " + str(z))
	for s in starts:
		assert_true(_reach(m, map, from, (s as Node3D).position), "start reachable from start")
	for d in doors:
		d.set_open(true)
	await _sync_links(nav)
	for z in ZONES:
		assert_true(_reach(m, map, from, zone_pos[z]), "open doors reach " + str(z))
	for d in doors:
		d.set_open(false)
	await _sync_links(nav)
	assert_true(not _reach(m, map, from, zone_pos[&"cafeteria"]), "closing re-blocks")
	for e in nav["links"]:
		NavigationServer3D.free_rid(e[0])
	for r in nav["regions"]:
		NavigationServer3D.free_rid(r)
	NavigationServer3D.free_rid(map)
	m.free()

func test_every_asset_credited() -> void:
	var credits := FileAccess.get_file_as_string("res://content/CREDITS.md")
	assert_true(credits != "", "CREDITS.md exists")
	var files: Array[String] = []
	_walk("res://content/art", files)
	assert_true(files.size() > 0, "art files exist")
	for f in files:
		assert_true(credits.contains(f.get_file()), "credited: " + f)

func _walk(dir: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for f in d.get_files():
		if not f.ends_with(".import") and not f.ends_with(".uid"):
			out.append(dir.path_join(f))
	for sub in d.get_directories():
		_walk(dir.path_join(sub), out)
