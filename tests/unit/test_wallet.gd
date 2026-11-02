extends TestCase

func _eco(n := 1) -> EconomyService:
	var e := EconomyService.new()
	for i in n:
		var p := Player.new()
		p.peer_id = i + 1
		e.players[i + 1] = p
	return e

func _free(e: EconomyService) -> void:
	for p in e.players.values():
		p.free()
	e.free()

func test_wallet_basics() -> void:
	var w := Wallet.new(500, 400)
	assert_eq(w.points, 500)
	assert_true(not w.try_spend(501), "cannot overspend")
	assert_eq(w.points, 500, "failed spend keeps points")
	assert_true(w.try_spend(500), "exact spend")
	assert_eq(w.points, 0)
	w.add(10, false)
	w.add(10, true)
	assert_eq(w.points, 30)

func test_points_hit_kill_headshot_melee() -> void:
	var e := _eco()
	var b := Content.balance
	e.on_hit(1, -5, 20.0, false)
	assert_eq(e.wallet(1).points, b.start_points + 5, "hit")
	e.wallet(1).points = 0
	e.on_kill(1, false, false)
	assert_eq(e.wallet(1).points, 50, "kill")
	e.wallet(1).points = 0
	e.on_kill(1, true, false)
	assert_eq(e.wallet(1).points, 80, "headshot kill")
	e.wallet(1).points = 0
	e.on_kill(1, false, true)
	assert_eq(e.wallet(1).points, 120, "melee kill")
	e.wallet(1).points = 0
	e.on_hit(1, 1000, 20.0, false)
	assert_eq(e.wallet(1).points, 0, "hitting a dummy pays nothing")
	e.on_kill(99, false, false)
	assert_true(not e.wallets.has(99), "unknown killer gets no wallet")
	_free(e)

func test_board_cap() -> void:
	var e := _eco()
	e.wallet(1).points = 0
	for i in 60:
		e.on_board(1)
	assert_eq(e.wallet(1).points, 400, "board points stop at 400 per round")
	e.reset_round()
	e.on_board(1)
	assert_eq(e.wallet(1).points, 415, "new round pays again")
	_free(e)

func test_board_cap_is_per_player() -> void:
	var e := _eco(2)
	e.wallet(1).points = 0
	e.wallet(2).points = 0
	for i in 60:
		e.on_board(1)
	e.on_board(2)
	assert_eq(e.wallet(2).points, 15)
	_free(e)

func test_bonus_ration() -> void:
	var e := _eco()
	e.wallet(1).points = 0
	var on := [true]
	e.double_source = func(): return on[0]
	e.on_hit(1, -5, 20.0, false)
	assert_eq(e.wallet(1).points, 10, "hit x2")
	on[0] = false
	e.on_hit(1, -5, 20.0, false)
	assert_eq(e.wallet(1).points, 15, "back to normal")
	_free(e)
