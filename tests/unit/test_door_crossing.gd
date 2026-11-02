extends TestCase

func _frame() -> void:
	await (Engine.get_main_loop() as SceneTree).physics_frame       # _ready of nodes added during _initialize runs on the first frame

func _door() -> BulkheadDoor:
	var d: BulkheadDoor = load("res://mapkit/bulkhead_door.tscn").instantiate()
	d.position = Vector3(28, 0, 20)             # identity rotation like Door_offices: link ends at z = 21 and 19
	(Engine.get_main_loop() as SceneTree).root.add_child(d)
	return d

func _zombie(pos: Vector3, band: int) -> Zombie:
	var z := Zombie.new()
	z.setup(1, Content.enemies[&"shambler"], 100.0, band, true)
	z.position = pos
	(Engine.get_main_loop() as SceneTree).root.add_child(z)
	return z

func _player(pos: Vector3) -> Player:
	var p := Player.new()
	p.set_physics_process(false)
	p.position = pos
	(Engine.get_main_loop() as SceneTree).root.add_child(p)
	return p

func test_link_ends_are_world_positions() -> void:
	var d := _door()
	await _frame()
	var e := d.link_ends()
	assert_near(e[0].z, 21.0, 1e-4, "start")
	assert_near(e[1].z, 19.0, 1e-4, "end")
	assert_near(e[0].x, 28.0, 1e-4)
	d.free()

func test_slow_zombie_crosses_straight_to_the_target_side() -> void:
	var d := _door()
	var p := _player(Vector3(28, 0.2, 30))
	var z := _zombie(Vector3(28, 0.45, 19.8), 0)          # shamble band, just past the link start, target beyond the far end
	await _frame()
	d.set_open(true)
	var last := z.position.z
	var back := false
	for i in 200:
		z.brain.tick(1.0 / 60.0, {1: p}, [], [d])
		p.hp = 100.0
		if z.position.z < last - 1e-6:
			back = true
		last = z.position.z
	assert_true(not back, "never steps back (no ping-pong at the link middle)")
	assert_true(z.position.z > 20.9, "reached the far end, z=%f" % z.position.z)
	z.free(); p.free(); d.free()

func test_zombie_heading_back_when_target_is_on_its_side() -> void:
	var d := _door()
	var p := _player(Vector3(28, 0.2, 10))
	var z := _zombie(Vector3(28, 0.45, 20.2), 0)
	await _frame()
	d.set_open(true)
	for i in 120:
		z.brain.tick(1.0 / 60.0, {1: p}, [], [d])
		p.hp = 100.0
	assert_true(z.position.z < 19.2, "left through the south end, z=%f" % z.position.z)
	z.free(); p.free(); d.free()

func test_closed_door_is_not_a_crossing() -> void:
	var d := _door()
	var p := _player(Vector3(28, 0.2, 30))
	var z := _zombie(Vector3(28, 0.45, 20.0), 0)
	await _frame()
	d.set_open(false)
	assert_true(z.brain._door_zone([d]) == null, "closed")
	d.set_open(true)
	assert_true(z.brain._door_zone([d]) == d, "open: the middle of the link counts")
	z.position = Vector3(28, 0.45, 18.0)
	assert_true(z.brain._door_zone([d]) == null, "outside the link ends")
	z.free(); p.free(); d.free()
