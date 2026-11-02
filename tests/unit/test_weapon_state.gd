extends TestCase

func _data(rpm := 600.0, mag := 30, reserve := 40) -> WeaponData:
	var d := WeaponData.new()
	d.fire_rate_rpm = rpm
	d.mag = mag
	d.reserve = reserve
	d.reload_s = 1.0
	d.damage = 20.0
	d.falloff_start = 10.0
	d.falloff_end = 30.0
	d.falloff_min_mult = 0.5
	return d

func test_fire_rate_limit() -> void:
	var s := WeaponState.new(_data(600.0))
	assert_true(s.fire(0.0), "first")
	assert_true(not s.can_fire(0.05), "too soon")
	assert_true(not s.fire(0.05), "fire too soon")
	assert_true(s.fire(0.1), "at interval")

func test_rate_mult_and_reason() -> void:
	var s := WeaponState.new(_data(600.0))
	s.fire(0.0)
	assert_eq(s.block_reason(0.095, 1.0), &"rate", "no tolerance")
	assert_eq(s.block_reason(0.095, 1.1), &"", "10% tolerance")
	assert_eq(s.block_reason(-1.0, 1.0), &"rate", "time going backwards")

func test_ammo_reason() -> void:
	var s := WeaponState.new(_data(600.0, 2, 0))
	s.fire(0.0)
	s.fire(1.0)
	assert_eq(s.mag, 0, "empty")
	assert_eq(s.block_reason(2.0, 1.0), &"ammo", "ammo")

func test_reload_moves_ammo() -> void:
	var s := WeaponState.new(_data(600.0, 30, 40))
	s.mag = 0
	s.reserve = 40
	assert_true(s.start_reload(0.0), "start")
	assert_eq(s.block_reason(0.5, 1.0), &"reload", "reloading")
	s.update(0.5)
	assert_eq(s.mag, 0, "not done")
	s.update(1.0)
	assert_eq(s.mag, 30, "mag")
	assert_eq(s.reserve, 10, "reserve")
	assert_true(not s.start_reload(2.0), "full mag no reload")

func test_reload_partial_reserve() -> void:
	var s := WeaponState.new(_data(600.0, 30, 40))
	s.mag = 0
	s.reserve = 7
	s.start_reload(0.0, 2.0)
	s.update(0.5)
	assert_eq(s.mag, 7, "faster reload")
	assert_eq(s.reserve, 0, "reserve")

func test_falloff() -> void:
	var s := WeaponState.new(_data())
	assert_near(s.damage_at(5.0), 20.0, 1e-4, "near")
	assert_near(s.damage_at(10.0), 20.0, 1e-4, "start")
	assert_near(s.damage_at(20.0), 15.0, 1e-4, "mid")
	assert_near(s.damage_at(30.0), 10.0, 1e-4, "end")
	assert_near(s.damage_at(80.0), 10.0, 1e-4, "far")

func test_refill() -> void:
	var s := WeaponState.new(_data(600.0, 30, 40))
	s.mag = 3
	s.reserve = 0
	s.refill()
	assert_eq(s.mag, 30, "mag")
	assert_eq(s.reserve, 40, "reserve")
