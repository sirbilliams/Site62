extends TestCase

class FakeZombies:
	extends Node
	signal zombie_died(zid: int, killer: int, headshot: bool, melee: bool, pos: Vector3)
	var spawns: Array = []
	func spawn(pos: Vector3, enemy_id: StringName, hp: float, band: int) -> bool:
		spawns.append([pos, enemy_id, hp, band])
		return true

class FakeEconomy:
	extends Node
	var resets := 0
	func reset_round() -> void:
		resets += 1

func _curve() -> RoundCurve:
	var c := RoundCurve.new()
	c.spawn_base_s = 0.1
	c.spawn_step_s = 0.0
	c.spawn_min_s = 0.1
	c.break_s = 5.0
	return c

func _zone(id: StringName, open: bool) -> Array:
	var root := Node3D.new()
	var z := Zone.new()
	z.zone_id = id
	z.open = open
	var sz := SpawnZone.new()
	sz.zone_id = id
	sz.position = Vector3(1, 0, 2)
	root.add_child(z)
	root.add_child(sz)
	return [root, z, sz]

func _make() -> Array:
	var m := Match.new()
	var zs := FakeZombies.new()
	var eco := FakeEconomy.new()
	m.zombies = zs
	m.economy = eco
	m.curve = _curve()
	m.player_count = func(): return 1
	return [m, zs, eco]

func test_spawn_uses_curve_health_and_band() -> void:
	var a := _make()
	var m: Match = a[0]
	var zs: FakeZombies = a[1]
	var map := _zone(&"a", true)
	m.start(map[0])
	m.tick(0.0)
	assert_eq(zs.spawns.size(), 1, "one spawn at once")
	assert_eq(zs.spawns[0][2], float(m.curve.health(1)), "curve health")
	assert_eq(zs.spawns[0][3], m.curve.speed_band(1), "curve band")
	assert_eq(zs.spawns[0][0], Vector3(1, 0, 2), "at the spawn zone")
	assert_eq(m.director.alive, 1)

func test_death_decrements_alive_and_resets_once_per_round() -> void:
	var a := _make()
	var m: Match = a[0]
	var zs: FakeZombies = a[1]
	var eco: FakeEconomy = a[2]
	var map := _zone(&"a", true)
	var started := []
	m.round_started.connect(func(r): started.append(r))
	m.start(map[0])
	assert_eq(eco.resets, 1, "reset at round 1 start")
	assert_eq(m.phase, &"playing")
	m.tick(0.0)
	zs.zombie_died.emit(1, 1, false, false, Vector3.ZERO)
	assert_eq(m.director.alive, 0, "death decrements")
	m.tick(0.1)
	assert_eq(eco.resets, 1, "still once")
	assert_eq(started, [1])

func test_round_flow_and_phase() -> void:
	var a := _make()
	var m: Match = a[0]
	var zs: FakeZombies = a[1]
	var eco: FakeEconomy = a[2]
	var map := _zone(&"a", true)
	var ended := []
	m.round_ended.connect(func(r): ended.append(r))
	m.start(map[0])
	for i in 40:
		m.tick(0.1)
		while m.director.alive > 0:
			zs.zombie_died.emit(1, 1, false, false, Vector3.ZERO)
		if m.phase == &"break":
			break
	assert_eq(m.phase, &"break")
	assert_eq(ended, [1])
	assert_eq(zs.spawns.size(), m.curve.count(1, 1), "round 1 count")
	m.tick(5.1)
	assert_eq(m.round, 2)
	assert_eq(m.phase, &"playing")
	assert_eq(eco.resets, 2, "reset at round 2")
	assert_eq(m.state(), {"round": 2, "phase": "playing"})

func test_door_opening_activates_zone_spawners() -> void:
	var a := _make()
	var m: Match = a[0]
	var map := _zone(&"b", false)
	m.start(map[0])
	var z: Zone = map[1]
	var sz: SpawnZone = map[2]
	assert_true(not sz.active, "closed zone inactive")
	z.open = true
	assert_true(sz.active, "active once the zone opens")
	var d := BulkheadDoor.new()
	d.unlocks = [&"b"]
	var map2 := _zone(&"c", false)
	m.start(map2[0])
	assert_true(not map2[2].active)
	d.unlocks = [&"c"]
	d.unlock([map2[1]])
	assert_true(map2[2].active, "door unlock path")
