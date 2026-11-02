extends TestCase

func test_parse_address() -> void:
	assert_eq(MainMenu.parse_address("192.168.1.20"), ["192.168.1.20", GameRoot.PORT])
	assert_eq(MainMenu.parse_address(" 10.0.0.5:9000 "), ["10.0.0.5", 9000])
	assert_eq(MainMenu.parse_address("lab.local"), ["lab.local", GameRoot.PORT])
	assert_eq(MainMenu.parse_address(""), [])
	assert_eq(MainMenu.parse_address("10.0.0.5:abc"), [])
	assert_eq(MainMenu.parse_address("10.0.0.5:70000"), [])
	assert_eq(MainMenu.parse_address("a b"), [])

func test_denied_text() -> void:
	assert_eq(Hud.denied_text(&"points"), "Not enough points")
	assert_eq(Hud.denied_text(&"no_power"), "Need power")
	assert_eq(Hud.denied_text(&"weird"), "Can't do that")

func test_prompt_follows_rebound_key() -> void:
	Settings.reset_defaults()
	Settings.set_binding(&"use", false, "k:%d" % KEY_E)
	var d := BulkheadDoor.new()
	d.cost = 750
	var p := Player.new()
	assert_eq(Hud.prompt_text(d, p), "Hold E: Open bulkhead [750]")
	Settings.using_pad = true
	assert_eq(Hud.prompt_text(d, p), "Hold LB: Open bulkhead [750]", "gamepad shows its button")
	Settings.using_pad = false
	Settings.reset_defaults()
	d.free()
	p.free()

func test_handle_repair_rules() -> void:
	var e := EconomyService.new()
	var p := Player.new()
	p.peer_id = 1
	e.players[1] = p
	var b := Barricade.new()                      # at the origin; local +Z is the outside
	b.tear_one()
	p.position = Vector3(0, 0, -1.0)              # inside
	assert_true(e.handle_repair(1, b, p.position), "inside, in reach: a board goes back")
	assert_eq(b.boards, 6)
	b.tear_one()
	assert_true(not e.handle_repair(1, b, Vector3(0, 0, 1.0)), "outside the lab: refused")
	assert_true(not e.handle_repair(1, b, Vector3(0, 0, -6.0)), "too far: refused")
	p.state = Player.DOWN
	assert_true(not e.handle_repair(1, b, Vector3(0, 0, -1.0)), "downed: refused")
	p.state = Player.ALIVE
	assert_true(not e.handle_repair(9, b, Vector3(0, 0, -1.0)), "unknown player: refused")
	b.free()
	p.free()
	e.free()
