extends TestCase

func _svc() -> PowerupService:
	var s := PowerupService.new()
	s.drop_chance = 1.0
	return s

func test_drop_cap_per_round() -> void:
	var s := _svc()
	var n := [0]
	s.dropped.connect(func(_k, _p): n[0] += 1)
	for i in 10:
		s.on_zombie_died(Vector3(i, 0, 0))
	assert_eq(n[0], 4, "cap 4 at 100% chance")
	s.new_round()
	s.on_zombie_died(Vector3.ZERO)
	assert_eq(n[0], 5, "cap resets next round")
	s.free()

func test_no_drop_at_zero_chance_or_during_purge() -> void:
	var s := _svc()
	var n := [0]
	s.dropped.connect(func(_k, _p): n[0] += 1)
	s.drop_chance = 0.0
	s.on_zombie_died(Vector3.ZERO)
	s.drop_chance = 1.0
	s._purging = true
	s.on_zombie_died(Vector3.ZERO)
	assert_eq(n[0], 0, "none")
	assert_eq(s.drops_this_round, 0, "purge kills do not count")
	s.free()

func test_overload_one_hit() -> void:
	var s := _svc()
	assert_eq(s.overload_damage(1.0, 100.0), 1.0, "normal")
	s.active[&"overload"] = s.clock + 30.0
	assert_true(s.is_active(&"overload"), "active")
	var z := Zombie.new()
	z.setup(5, Content.enemies[&"shambler"], 100.0, 1, false)
	z.take_damage(s.overload_damage(1.0, z.hp), 2, false)
	assert_true(not z.alive, "one hit kills")
	s.clock = 31.0
	assert_true(not s.is_active(&"overload"), "expired")
	z.free()
	s.free()
