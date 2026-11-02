extends TestCase

func test_round_curve_values() -> void:
	var c: RoundCurve = Content.curve
	assert_eq(c.count(1, 1), 8)
	assert_eq(c.count(1, 4), 20)
	assert_eq(c.count(10, 2), 52)
	assert_eq(c.health(1), 120)
	assert_eq(c.health(10), 840)
	assert_eq(c.health(11), 907)
	assert_eq(c.speed_band(3), 0)
	assert_eq(c.speed_band(4), 1)
	assert_eq(c.speed_band(8), 2)
	assert_near(c.spawn_interval(20), 0.4)

func test_all_content_valid() -> void:
	var errs := Content.validate()
	assert_true(errs.is_empty(), "validate: " + ", ".join(errs))
	assert_eq(Content.weapons.size(), 12)
	assert_eq(Content.suds.size(), 4)
	assert_eq(Content.powerups.size(), 6)

func test_validator_catches_bad_data() -> void:
	var w := WeaponData.new()
	w.id = &"bad"
	w.cost = -1
	w.mag = 5
	w.recoil = PackedVector2Array([Vector2.ZERO])
	w.refit = w
	var errs := Content.validate_weapon(w)
	var joined := " ".join(errs)
	assert_true(joined.contains("cost"), "cost error")
	assert_true(joined.contains("refit"), "refit error")

func test_validator_empty_recoil() -> void:
	var w := WeaponData.new()
	w.id = &"norecoil"
	w.mag = 5
	var errs := Content.validate_weapon(w)
	assert_true(" ".join(errs).contains("recoil"), "recoil error")

func test_balance_values() -> void:
	var b: Balance = Content.balance
	assert_eq(b.start_points, 600)
	assert_eq(b.refit_cost, 4500)
	assert_eq(b.crate_cost, 1000)
	assert_eq(b.max_suds, 3)
	assert_near(b.fire_rate_tolerance, 0.10)

func test_thresher_fires_pellets_and_cathode_carbine_is_crate_only() -> void:
	var th := Content.weapon(&"thresher")
	assert_eq(th.pellets, 8)
	assert_eq(Content.weapon(&"thresher_refit").pellets, 8)
	assert_eq(Content.weapon(&"sentinel_45").pellets, 1)
	var cc := Content.weapon(&"cathode_carbine")
	assert_true(cc != null and not cc.is_wall_buy and cc.cost == 0, "crate-only")
	assert_true(Content.weapons.size() >= 12, "six guns plus their refits")
