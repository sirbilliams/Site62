extends TestCase

func _player(peer := 1) -> Player:
	var p := Player.new()
	p.peer_id = peer
	return p

func _svc_with(p: Player, weapon: StringName = &"") -> WeaponService:
	var w := WeaponService.new()
	if weapon != &"":
		w.kits[p.peer_id] = Inventory.new(Content.weapon(weapon))
	return w

func test_format_points() -> void:
	assert_eq(Hud.format_points(0), "0")
	assert_eq(Hud.format_points(999), "999")
	assert_eq(Hud.format_points(1000), "1,000")
	assert_eq(Hud.format_points(1234567), "1,234,567")
	assert_eq(Hud.format_points(-4500), "-4,500")

func test_format_time() -> void:
	assert_eq(Hud.format_time(0.0), "0")
	assert_eq(Hud.format_time(12.2), "13")
	assert_eq(Hud.format_time(30.0), "30")

func test_wall_buy_prompt() -> void:
	var p := _player()
	var w := _svc_with(p)                       # holds only the default sidearm
	var wb := WallBuy.new()
	wb.weapons = w
	wb.weapon_id = &"hornet"
	var d := Content.weapon(&"hornet")
	assert_eq(Hud.prompt_text(wb, p), "Hold F: %s [%d]" % [d.display_name, d.cost], "buy")
	p.free(); w.free(); wb.free()

func test_ammo_prompt() -> void:
	var p := _player()
	var w := _svc_with(p, &"hornet")
	var wb := WallBuy.new()
	wb.weapons = w
	wb.weapon_id = &"hornet"
	var d := Content.weapon(&"hornet")
	var st := w.kit_for(1).state_of(&"hornet")
	st.mag = 0
	assert_eq(Hud.prompt_text(wb, p), "Hold F: Ammo [%d]" % d.ammo_cost, "ammo")
	st.mag = d.mag
	st.reserve = d.reserve
	assert_eq(Hud.prompt_text(wb, p), "Ammo full", "full")
	p.free(); w.free(); wb.free()

func test_door_prompt() -> void:
	var p := _player()
	var d := BulkheadDoor.new()
	d.cost = 750
	assert_eq(Hud.prompt_text(d, p), "Hold F: Open bulkhead [750]")
	d.is_open = true
	assert_eq(Hud.prompt_text(d, p), "", "open door shows nothing")
	p.free(); d.free()

func test_suds_prompts() -> void:
	var p := _player()
	var m := SudsMachine.new()
	m.suds = Content.suds[&"grape_bulwark"]
	Game.reset()
	assert_eq(Hud.prompt_text(m, p), "Need power", "no power")
	Game.power = true
	assert_eq(Hud.prompt_text(m, p), "Hold F: %s [%d]" % [m.suds.display_name, m.suds.cost], "powered")
	Game.suds_of(1).add(m.suds)
	assert_eq(Hud.prompt_text(m, p), "%s owned" % m.suds.display_name, "owned")
	Game.reset()
	p.free(); m.free()

func test_crate_prompts() -> void:
	var p := _player()
	var w := _svc_with(p)
	var c := CrateSpot.new()
	c.weapons = w
	Game.reset()
	assert_eq(Hud.prompt_text(c, p), "", "inactive crate shows nothing")
	c.active = true
	assert_eq(Hud.prompt_text(c, p), "Hold F: Requisition Crate [%d]" % Content.balance.crate_cost)
	Game.give_voucher(1)
	assert_eq(Hud.prompt_text(c, p), "Hold F: Requisition Crate [Free]", "voucher")
	Game.reset()
	p.free(); w.free(); c.free()

func test_refit_prompts() -> void:
	var p := _player()
	var w := _svc_with(p, &"hornet")
	var r := RefitStation.new()
	r.weapons = w
	Game.reset()
	assert_eq(Hud.prompt_text(r, p), "Need power")
	Game.power = true
	assert_eq(Hud.prompt_text(r, p), "Hold F: Isotope Refit [%d]" % Content.balance.refit_cost)
	w.kit_for(1).slots[0] = WeaponState.new(Content.weapon(&"hornet_refit"))
	w.kit_for(1).held = 0
	assert_eq(Hud.prompt_text(r, p), "Already refitted", "no second refit")
	Game.reset()
	p.free(); w.free(); r.free()

func test_power_switch_prompt() -> void:
	var p := _player()
	var s := PowerSwitch.new()
	Game.reset()
	assert_eq(Hud.prompt_text(s, p), "Hold F: Restore power")
	Game.power = true
	assert_eq(Hud.prompt_text(s, p), "")
	Game.reset()
	p.free(); s.free()

func test_null_is_empty() -> void:
	assert_eq(Hud.prompt_text(null, null), "")
