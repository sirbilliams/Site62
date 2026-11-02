extends TestCase

func test_safe_spot_follows_grounded_player() -> void:
	var g := FallGuard.new(Vector3(0, 0.2, 0))
	assert_true(not g.step(0.1, Vector3(1, 0, 0), true, -20.0, 0.5), "no fall")
	assert_eq(g.safe, Vector3(0, 0.2, 0), "interval not yet over: still the start")
	assert_true(not g.step(0.5, Vector3(2, 0, 0), true, -20.0, 0.5), "no fall")
	assert_eq(g.safe, Vector3(2, 0, 0), "grounded after the interval: remembered")
	assert_true(not g.step(0.6, Vector3(3, 2, 0), false, -20.0, 0.5), "airborne")
	assert_eq(g.safe, Vector3(2, 0, 0), "airborne positions are never safe")

func test_fall_below_kill_plane() -> void:
	var g := FallGuard.new(Vector3(4, 0.2, 4))
	assert_true(not g.step(0.016, Vector3(0, -19.9, 0), false, -20.0, 0.5), "just above the plane")
	assert_true(g.step(0.016, Vector3(0, -20.1, 0), false, -20.0, 0.5), "below the plane")
	assert_eq(g.safe, Vector3(4, 0.2, 4), "the fall never overwrites the safe spot")

func test_player_net_returns_fallen_player_alive() -> void:
	var pn := PlayerNet.new()
	var p: Player = Player.new()
	p.peer_id = 3
	p.setup(3, Content.balance, false)
	p.motor_state = Motor.initial_state(Vector3(7, 0.2, 7))
	pn.players[3] = p
	pn._guard_falls()                                    # first call remembers the start as the safe spot
	p.motor_state = {"pos": Vector3(7, -25, 7), "vy": -30.0, "grounded": false}
	pn._guard_falls()
	assert_eq(pn.falls, 1, "one return")
	assert_eq(p.motor_state.pos, Vector3(7, 0.2, 7), "back at the safe spot")
	assert_eq(p.motor_state.vy, 0.0, "fall speed cleared")
	assert_eq(p.state, Player.ALIVE, "no death")
	assert_true(p.hp > 0.0, "hp untouched")
	p.free()
	pn.free()
