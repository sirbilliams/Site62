extends TestCase

func _sync() -> ZombieSync:
	var zs := ZombieSync.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(zs)
	return zs

func _first(zs: ZombieSync) -> Zombie:
	return zs.zombies[1]

func test_kill_plane_replaces_zombie_and_keeps_count() -> void:
	var zs := _sync()
	zs.spawn(Vector3(0, 0.2, 0), &"shambler", 77.0, 2)
	assert_eq(zs.live_count(), 1)
	var died := []
	zs.zombie_died.connect(func(zid, _k, _h, _m, _p): died.append(zid))
	var z := _first(zs)
	z.position.y = -30.0
	zs.guard(0.016, [Vector3(5, 0.2, 5)])
	assert_eq(zs.kill_plane_hits, 1)
	assert_true(not z.alive, "the fallen zombie is gone")
	assert_eq(zs.live_count(), 1, "replaced: the alive count is unchanged")
	assert_eq(died.size(), 0, "not a kill: the director is not told")
	var n: Zombie = zs.zombies[2]
	assert_true(n.alive, "replacement alive")
	assert_eq(n.position, Vector3(5, 0.2, 5), "at the spawn point")
	assert_eq(n.hp, 77.0, "same hp")
	assert_eq(n.band, 2, "same band")
	zs.free()

func test_stalled_zombie_with_target_is_relocated() -> void:
	var zs := _sync()
	zs.spawn(Vector3(1, 0.2, 1), &"shambler", 100.0, 1)
	var z := _first(zs)
	var s: float = Content.balance.stall_s
	for i in int(s) + 2:
		z.brain.walking = true
		zs.guard(1.0, [Vector3(9, 0.2, 9)])
	assert_eq(zs.stall_relocations, 1)
	assert_eq(z.position, Vector3(9, 0.2, 9), "moved to the spawn point")
	assert_true(z.alive, "same zombie")
	zs.free()

func test_zombie_without_target_or_tearing_is_left_alone() -> void:
	var zs := _sync()
	zs.spawn(Vector3(1, 0.2, 1), &"shambler", 100.0, 1)
	var z := _first(zs)
	for i in 20:
		z.brain.walking = false                # no target / meleeing / tearing a barricade
		zs.guard(1.0, [Vector3(9, 0.2, 9)])
	assert_eq(zs.stall_relocations, 0)
	assert_eq(z.position, Vector3(1, 0.2, 1))
	zs.free()

func test_moving_zombie_is_left_alone() -> void:
	var zs := _sync()
	zs.spawn(Vector3(1, 0.2, 1), &"shambler", 100.0, 1)
	var z := _first(zs)
	for i in 20:
		z.brain.walking = true
		z.position.x += 1.0
		zs.guard(1.0, [Vector3(9, 0.2, 9)])
	assert_eq(zs.stall_relocations, 0)
	zs.free()

func test_no_spawn_points_does_nothing() -> void:
	var zs := _sync()
	zs.spawn(Vector3(1, 0.2, 1), &"shambler", 100.0, 1)
	var z := _first(zs)
	z.position.y = -50.0
	zs.guard(1.0, [])
	assert_true(z.alive, "nothing to replace it with: untouched")
	zs.free()
