extends TestCase
## WeaponService must honour the Ethereal-Suds multipliers on every call site (no timed waits).

const PEER := 2

func _svc() -> WeaponService:
	Game.reset()
	var svc := WeaponService.new()
	svc.net = PlayerNet.new()
	svc.lag_comp = false
	return svc

func _done(svc: WeaponService) -> void:
	Game.forget_peer(PEER)
	Game.forget_peer(Net.local_id())
	svc.net.free()
	svc.free()

func _give(peer: int, id: StringName) -> void:
	Game.suds_of(peer).add(Content.suds[id])

func _reload_time(svc: WeaponService, peer: int, local: bool) -> float:
	var st := svc.state_for(peer)
	st.mag = 0
	st.reloading = false
	var before := WeaponService.now_s()
	if local:
		svc.reload_local()
	else:
		svc._start_reload_for(peer)
	return st.reload_end - before

func test_reload_halved_by_suds_host_and_local() -> void:
	var svc := _svc()
	var rs := Content.weapon(&"sentinel_45").reload_s
	assert_near(_reload_time(svc, PEER, false), rs, 0.05, "host plain")
	assert_near(_reload_time(svc, Net.local_id(), true), rs, 0.05, "local plain")
	_give(PEER, &"snapback_fizz")
	_give(Net.local_id(), &"snapback_fizz")
	svc.state_for(PEER).reloading = false
	assert_near(_reload_time(svc, PEER, false), rs * 0.5, 0.05, "host suds")
	assert_near(_reload_time(svc, Net.local_id(), true), rs * 0.5, 0.05, "local suds")
	_done(svc)

func test_local_prediction_rate_uses_suds() -> void:
	var svc := _svc()
	var me := Net.local_id()
	var gap := 60.0 / Content.weapon(&"sentinel_45").fire_rate_rpm / 1.15     # between boosted (/1.33) and plain intervals
	assert_true(svc._predict_fire(10.0), "first shot")
	assert_true(not svc._predict_fire(10.0 + gap), "plain: too soon")
	svc.state_for(me).refill()
	_give(me, &"overclock_orange")
	assert_true(svc._predict_fire(20.0), "first shot (suds)")
	assert_true(svc._predict_fire(20.0 + gap), "suds: allowed")
	_done(svc)

func _host_second_shot(svc: WeaponService, overclock: bool) -> StringName:
	var p := Player.new()
	p.peer_id = PEER
	svc.net.players[PEER] = p
	svc.net.clock.observe(PEER, 0.0, 0.0)                    # offset 0: the stamp is the host time
	if overclock:
		_give(PEER, &"overclock_orange")
	var reasons: Array = []
	svc.fire_rejected.connect(func(_peer, r): reasons.append(r))
	var plain := 60.0 / Content.weapon(&"sentinel_45").fire_rate_rpm
	var tol := 1.0 + Content.balance.fire_rate_tolerance
	var gap := (plain / tol + plain / (tol * 1.33)) * 0.5     # between the two minimum intervals
	var base := WeaponService.now_s() - 0.19                  # both stamps inside the +-0.25 s window
	var o := svc.eye_of(p)
	svc.handle_fire(PEER, PEER, o, Vector3.FORWARD, base, 1)
	svc.handle_fire(PEER, PEER, o, Vector3.FORWARD, base + gap, 2)
	p.free()
	return reasons[0] if not reasons.is_empty() else &""

func test_host_fire_rate_validation_uses_suds() -> void:
	var svc := _svc()
	assert_eq(_host_second_shot(svc, false), &"rate", "plain: second shot rejected")
	_done(svc)
	svc = _svc()
	assert_eq(_host_second_shot(svc, true), &"", "overclock: second shot accepted")
	assert_eq(svc.state_for(PEER).mag, Content.weapon(&"sentinel_45").mag - 2, "both rounds spent")
	_done(svc)

func test_clear_suds() -> void:
	Game.reset()
	var p := Player.new()
	p.setup(PEER, Content.balance, false)
	_give(PEER, &"grape_bulwark")
	p.hp = 220.0
	assert_near(p.max_health(), 220.0, 1e-4, "raised")
	Game.clear_suds(PEER, p)
	assert_eq(Game.suds_of(PEER).count(), 0, "cleared")
	assert_near(p.max_health(), 100.0, 1e-4, "ceiling back")
	assert_near(p.hp, 100.0, 1e-4, "hp clamped")
	Game.forget_peer(PEER)
	p.free()

func test_reset_emits_power_and_reseeds() -> void:
	Game.reset()
	Game.power = true
	var seen: Array = []
	var cb := func(on): seen.append(on)
	Game.power_changed.connect(cb)
	Game.reset()
	Game.power_changed.disconnect(cb)
	assert_eq(seen, [false], "power_changed(false)")
	Game.seed_rng(5)
	var a := Game.rng.randi()
	Game.reset()
	Game.seed_rng(5)
	assert_eq(Game.rng.randi(), a, "seed_rng still deterministic after reset")
