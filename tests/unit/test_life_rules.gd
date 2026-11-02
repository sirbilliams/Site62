extends TestCase

func _player(hp: float) -> Player:
	var p := Player.new()
	p.hp = hp
	return p

func test_down_at_zero() -> void:
	var p := _player(100.0)
	assert_eq(LifeRules.on_damage(p, 40.0), Player.ALIVE, "40 dmg")
	assert_near(p.hp, 60.0, 1e-4, "hp")
	assert_eq(LifeRules.on_damage(p, 60.0), Player.DOWN, "exactly zero")
	assert_near(p.hp, 0.0, 1e-4, "hp floor")
	p.state = Player.DOWN
	assert_eq(LifeRules.on_damage(p, 10.0), Player.DOWN, "already down stays down")
	p.state = Player.DEAD
	assert_eq(LifeRules.on_damage(p, 10.0), Player.DEAD, "dead stays dead")
	p.free()

func test_revive_4s_or_2s_with_suds() -> void:
	assert_near(LifeRules.revive_progress(2.0, 1.0), 0.5, 1e-4, "half way")
	assert_near(LifeRules.revive_progress(4.0, 1.0), 1.0, 1e-4, "4 s")
	assert_near(LifeRules.revive_progress(2.0, 0.5), 1.0, 1e-4, "2 s with the Suds")
	assert_near(LifeRules.revive_progress(9.0, 1.0), 1.0, 1e-4, "clamped")
	assert_near(LifeRules.revive_progress(-1.0, 1.0), 0.0, 1e-4, "never negative")

func test_bleedout_30s() -> void:
	assert_near(LifeRules.bleedout_left(0.0), 30.0, 1e-4, "start")
	assert_near(LifeRules.bleedout_left(12.5), 17.5, 1e-4, "mid")
	assert_near(LifeRules.bleedout_left(45.0), 0.0, 1e-4, "floor")

func test_solo_self_revive_with_suds() -> void:
	var e := SudsEffects.new()
	assert_near(LifeRules.self_revive_progress(4.0, e, true), 0.0, 1e-4, "no suds, no self revive")
	e.add(Content.suds[&"second_wind_root_beer"])
	assert_near(LifeRules.self_revive_progress(2.0, e, true), 0.5, 1e-4, "half of revive_hold_s")
	assert_near(LifeRules.self_revive_progress(4.0, e, true), 1.0, 1e-4, "after revive_hold_s")
	assert_near(LifeRules.self_revive_progress(4.0, e, false), 0.0, 1e-4, "not alone")
	assert_near(LifeRules.revive_hp(100.0), 50.0, 1e-4, "revive hp fraction")

func test_downed_crawls_dead_stays() -> void:
	var p := Player.new()
	p.balance = Content.balance
	var f := InputFrame.new()
	f.move = Vector2(0, 1)
	f.buttons = InputFrame.JUMP | InputFrame.SPRINT
	assert_true(p._motor_frame(f) == f, "alive: untouched")
	p.state = Player.DOWN
	var g := p._motor_frame(f)
	assert_near(g.move.y, Content.balance.downed_move_mult, 1e-4, "crawl")
	assert_eq(g.buttons, 0, "no jump / sprint")
	p.state = Player.DEAD
	assert_eq(p._motor_frame(f).move, Vector2.ZERO, "dead does not move")
	p.free()
