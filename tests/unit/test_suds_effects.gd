extends TestCase

func _all() -> SudsEffects:
	var e := SudsEffects.new()
	for id in [&"grape_bulwark", &"snapback_fizz", &"second_wind_root_beer", &"overclock_orange"]:
		e.add(Content.suds[id])
	return e

func test_suds_stack_effects() -> void:
	var e := _all()
	assert_near(e.max_hp(100.0), 220.0, 1e-4, "max_hp")
	assert_near(e.reload_mult(), 0.5, 1e-4, "reload")
	assert_near(e.revive_mult(), 0.5, 1e-4, "revive")
	assert_near(e.fire_rate_mult(), 1.33, 1e-4, "fire rate")
	assert_eq(e.count(), 4, "count")

func test_no_suds_is_neutral() -> void:
	var e := SudsEffects.new()
	assert_near(e.max_hp(100.0), 100.0, 1e-4, "max_hp")
	assert_near(e.reload_mult(), 1.0, 1e-4, "reload")
	assert_near(e.revive_mult(), 1.0, 1e-4, "revive")
	assert_near(e.fire_rate_mult(), 1.0, 1e-4, "rate")
	assert_true(not e.can_self_revive(true), "no revive without suds")

func test_self_revive_only_solo() -> void:
	var e := _all()
	assert_true(e.can_self_revive(true), "solo")
	assert_true(not e.can_self_revive(false), "not in a team")

func test_has_and_duplicate() -> void:
	var e := SudsEffects.new()
	assert_true(e.add(Content.suds[&"grape_bulwark"]), "first")
	assert_true(not e.add(Content.suds[&"grape_bulwark"]), "duplicate refused")
	assert_true(e.has(&"grape_bulwark"), "has")
	assert_eq(e.count(), 1, "count")

func test_refit_swaps_held_weapon() -> void:
	var inv := Inventory.new(Content.weapon(&"sentinel_45"))
	assert_true(inv.refit_held(), "refit")
	assert_eq(inv.held_state().data.id, &"sentinel_45_refit", "id")
	assert_true(not inv.refit_held(), "already refitted")
