extends Node3D
## Multi-process life-cycle test (--rtt_ms/--loss on every process). Roles: host | a | b. Host scripts the steps.
##  1. a goes down (hp 0): DOWN everywhere, Suds gone, sidearm in hand, a downed player cannot pick up a power-up.
##  2. host holds USE: 2 s then release resets the progress; held for the full 4 s a is back at half hp (ALIVE everywhere).
##  3. b bleeds out (Balance.downed_bleedout_s shortened to 5 s here; the 30 s default is a unit test), is DEAD
##     everywhere, and respawns at the next round start with the sidearm, no Suds, full hp, points kept.
##  4. Review Focus 1: a disconnects while down during Overload: match goes on, no per-peer leftovers on the host,
##     Overload still ends on schedule on the remaining peers.
##  5. b then host go down: game_over_reached on every peer with identical stats.
##  6. Last connected player: b leaves, the host alone goes down -> game over.
## Host prints LIFE NET PASS; a client prints LIFE NET CLIENT OK (role) when it leaves on cue.

signal round_started(r: int)

const SPAWN := Vector3(0, 0.2, -18)

var role := ""
var port := 26100
var net: PlayerNet
var svc: WeaponService
var zs: ZombieSync
var eco: EconomyService
var pu: PowerupService
var ms: MatchState
var t := 0.0
var done := false
var frames := 0
var sent_hello := false
var started := false
var ids := {}
var reports := {}
var host_use := false
var leaving := false
var over_signals := 0
var collected_by: Array = []

func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return def

func _ready() -> void:
	role = _arg("role", "host")
	port = int(_arg("port", "26100"))
	Net.beacon_port = 0
	Game.reset()
	_build_map()
	net = PlayerNet.new()
	net.name = "PlayerNet"
	net.spawn = SPAWN
	net.input_source = func():
		var f := InputFrame.new()
		if role == "host" and host_use:
			f.buttons |= InputFrame.USE
		return f
	add_child(net)
	svc = WeaponService.new()
	svc.name = "WeaponService"
	svc.net = net
	add_child(svc)
	zs = ZombieSync.new()
	zs.net = net
	add_child(zs)
	zs.bind_weapons(svc)
	eco = EconomyService.new()
	add_child(eco)
	eco.bind(net, svc, zs)
	pu = PowerupService.new()
	add_child(pu)
	pu.bind(net, zs, eco, svc)
	pu.collected.connect(func(_k, by): collected_by.append(by))
	ms = MatchState.new()
	add_child(ms)
	ms.bind(net, svc, eco, zs, pu, self)
	ms.game_over_reached.connect(func(_s): over_signals += 1)
	Net.player_left.connect(func(id):
		if id == 1 and not done and not leaving:
			done = true
			print("LIFE NET FAIL (%s): host left" % role)
			get_tree().quit(1))
	if role == "host":
		zs.frozen = true
		Content.balance.powerup_duration_s = 8.0
		if Net.host(port) != OK:
			_fail("host failed")
	elif Net.join("127.0.0.1", port) != OK:
		_fail("join failed")

func _build_map() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 2, 200)
	cs.shape = box
	cs.position.y = -1.0
	floor_body.add_child(cs)
	add_child(floor_body)

func _fail(msg: String) -> void:
	if done:
		return
	print("LIFE NET FAIL (%s): %s" % [role, msg])
	done = true
	get_tree().quit(1)

func _ck(cond: bool, msg: String) -> bool:
	if not cond:
		_fail(msg)
	return cond and not done

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _report(who: Array = ["a", "b"]) -> Dictionary:
	reports.clear()
	for r in who:
		Net.send_reliable(self, &"_cmd", ids[r], ["report"])
	var waited := 0.0
	while who.any(func(r): return not reports.has(r)) and waited < 10.0 and not done:
		await _wait(0.1)
		waited += 0.1
	if who.any(func(r): return not reports.has(r)):
		_fail("no reports")
		return {}
	return reports.duplicate()

func _all(r: Dictionary, key: String, fn: Callable, what: String) -> bool:
	for k in r:
		if not _ck(fn.call(r[k][key]), "%s: %s saw %s=%s" % [what, k, key, str(r[k][key])]):
			return false
	return true

func _wait_until(cond: Callable, max_s: float) -> bool:
	var w := 0.0
	while not cond.call() and w < max_s and not done:
		await _wait(0.1)
		w += 0.1
	return cond.call()

func _script() -> void:
	var a: int = ids["a"]
	var b: int = ids["b"]
	var pa: Player = net.players[a]
	var pb: Player = net.players[b]
	var ph: Player = net.players[1]
	eco.wallet(a).points = 700
	eco.wallet(b).points = 900
	print("LIFE step 1")
	# 1: a goes down with a Suds and a second gun
	Game.grant_suds(a, Content.suds[&"grape_bulwark"])
	Game.grant_suds(a, Content.suds[&"second_wind_root_beer"])    # in a team the revive Suds is dropped too
	svc.set_weapon(a, &"hornet")
	svc.set_weapon(b, &"hornet")
	await _wait(1.0)
	var r := await _report()
	if done: return
	if not _all(r, "suds_a", func(v): return v == 2, "a has both Suds before"): return
	pa.hp = 0.0
	await _wait(1.5)
	if not _ck(pa.state == Player.DOWN and ms.stats[a].downs == 1, "host: a DOWN"): return
	if not _ck(Game.suds_of(a).count() == 0, "host: a's Suds dropped"): return
	if not _ck(svc.kit_for(a).held == 0 and svc._may_fire(pa), "host: a on the sidearm, may fire"): return
	svc.kit_for(a).held = 1
	if not _ck(not svc._may_fire(pa), "host: downed a may not fire a held 2nd gun"): return
	svc.kit_for(a).held = 0
	# nobody ALIVE stands there -> a pickup at a's feet has no taker (no ticks run between these lines)
	var old_h := ph.state
	var old_b := pb.state
	ph.state = Player.DEAD
	pb.state = Player.DOWN
	var taker := pu._taker(pa.position)
	ph.state = old_h
	pb.state = old_b
	if not _ck(taker == 0, "downed / dead players cannot take a pickup (taker %d)" % taker): return
	r = await _report()
	if done: return
	if not _all(r, "state_a", func(v): return v == Player.DOWN, "a DOWN on every peer"): return
	if not _all(r, "suds_a", func(v): return v == 0, "a's Suds dropped on every peer"): return
	if not _ck(r["a"]["held_a"] == 0, "client a: sidearm held"): return
	print("LIFE step 2")
	# 2: revive: hold 2 s, release -> reset; hold again for 4 s
	host_use = true
	await _wait(2.0)
	if not _ck(pa.state == Player.DOWN and ms.revive_progress_of(a) > 0.3, "host: mid revive %.2f" % ms.revive_progress_of(a)): return
	host_use = false
	await _wait(1.0)
	if not _ck(pa.state == Player.DOWN and ms.revive_progress_of(a) == 0.0, "release resets the progress"): return
	host_use = true
	var t0 := t
	if not await _wait_until(func(): return pa.state == Player.ALIVE, 8.0):
		_fail("a never revived")
		return
	host_use = false
	if not _ck(t - t0 > 3.0 and t - t0 < 5.5, "revive took %.1f s (want about 4)" % (t - t0)): return
	if not _ck(absf(pa.hp - 50.0) < 0.01 and ms.stats[1].revives == 1, "revived at half hp: %.1f" % pa.hp): return
	await _wait(1.0)
	r = await _report()
	if done: return
	if not _all(r, "state_a", func(v): return v == Player.ALIVE, "a ALIVE on every peer"): return
	print("LIFE step 3")
	Content.balance.downed_bleedout_s = 5.0      # shortened from 30 s for this step only
	# 3: b bleeds out, respawns next round
	pb.hp = 0.0
	if not await _wait_until(func(): return pb.state == Player.DEAD, 9.0):
		_fail("b never bled out")
		return
	await _wait(1.0)
	r = await _report()
	if done: return
	if not _all(r, "state_b", func(v): return v == Player.DEAD, "b DEAD on every peer"): return
	round_started.emit(2)
	await _wait(1.5)
	if not _ck(pb.state == Player.ALIVE and absf(pb.hp - 100.0) < 0.01, "b respawned at full hp"): return
	if not _ck(pb.position.distance_to(SPAWN) < 0.5, "b at the start"): return
	if not _ck(eco.wallet(b).points == 900, "b keeps points"): return
	if not _ck(svc.kit_for(b).slots[1] == null and svc.kit_for(b).held == 0, "b: sidearm only"): return
	r = await _report()
	if done: return
	if not _all(r, "state_b", func(v): return v == Player.ALIVE, "b ALIVE on every peer"): return
	if not _ck(r["b"]["slot1_b"] == "" and r["b"]["suds_b"] == 0, "client b: sidearm only, no Suds"): return
	print("LIFE step 4")
	# 4: a disconnects while down during Overload
	pa.hp = 0.0
	await _wait(1.0)
	if not _ck(pa.state == Player.DOWN, "a down again"): return
	pu.force_drop(&"overload", pa.position + Vector3(0, 0.5, 0))
	await _wait(0.5)
	if not _ck(collected_by.size() == 1 and collected_by[0] != a, "overload taken by an ALIVE player: %s" % str(collected_by)): return
	Net.send_reliable(self, &"_cmd", a, ["leave"])
	if not await _wait_until(func(): return not Net.players.has(a), 6.0):
		_fail("a never left")
		return
	await _wait(0.5)
	if not _ck(not ms.tracked(a) and not ms.game_over and over_signals == 0, "no leftovers for a, match goes on"): return
	if not _ck(pu.is_active(&"overload"), "overload runs on after a left"): return
	r = await _report(["b"])
	if done: return
	if not _all(r, "active", func(v): return "overload" in v, "overload visible to b"): return
	if not await _wait_until(func(): return not pu.is_active(&"overload"), 12.0):
		_fail("overload never ended")
		return
	await _wait(1.0)
	r = await _report(["b"])
	if done: return
	if not _all(r, "active", func(v): return v.is_empty(), "overload over on b"): return
	print("LIFE step 5")
	# 5: b down (match goes on), then the host: game over on every peer
	pb.hp = 0.0
	await _wait(1.0)
	if not _ck(pb.state == Player.DOWN and not ms.game_over, "b down, host alive: no game over"): return
	ph.hp = 0.0
	await _wait(1.0)
	if not _ck(ms.game_over and over_signals == 1, "game over (%d signals)" % over_signals): return
	var want := var_to_str(ms.final_stats)
	if not _ck(ms.final_stats.size() == 2 and ms.final_stats[1].downs == 1 and ms.final_stats[1].revives == 1 \
			and ms.final_stats[b].downs == 2 and ms.final_stats[b].points == 900 and ms.final_stats[1].rounds == 2, "stats: " + want): return
	r = await _report(["b"])
	if done: return
	if not _all(r, "over", func(v): return v == 1, "b got game_over_reached once"): return
	if not _all(r, "stats", func(v): return v == want, "stats match on b"): return
	print("LIFE step 6")
	# 6: last connected player going down
	ms.reset()
	ph.state = Player.ALIVE
	ph.hp = 100.0
	over_signals = 0
	Net.send_reliable(self, &"_cmd", b, ["leave"])
	if not await _wait_until(func(): return Net.players.ids().size() == 1, 6.0):
		_fail("b never left")
		return
	await _wait(0.5)
	if not _ck(not ms.game_over, "alone and alive: no game over"): return
	ph.hp = 0.0
	await _wait(0.5)
	if not _ck(ms.game_over and over_signals == 1 and ms.final_stats.size() == 1, "last player down ends the game"): return
	print("LIFE step 7")
	# 7: solo with Second Wind: the revive Suds survives going down, self revive after revive_hold_s, Suds used up
	ms.reset()
	ph.state = Player.ALIVE
	ph.hp = 100.0
	over_signals = 0
	Game.grant_suds(1, Content.suds[&"grape_bulwark"])
	Game.grant_suds(1, Content.suds[&"second_wind_root_beer"])
	ph.hp = 0.0
	await _wait(1.0)
	if not _ck(ph.state == Player.DOWN and not ms.game_over, "solo with Second Wind: down, no game over"): return
	if not _ck(Game.suds_of(1).has(&"second_wind_root_beer") and not Game.suds_of(1).has(&"grape_bulwark"), "only the revive Suds kept"): return
	var t1 := t
	if not await _wait_until(func(): return ph.state == Player.ALIVE, 6.0):
		_fail("solo self revive never happened")
		return
	if not _ck(t - t1 > 2.0 and t - t1 < 4.5 and Game.suds_of(1).count() == 0 and not ms.game_over and over_signals == 0, "self revive: %.1f s, suds %d" % [t - t1, Game.suds_of(1).count()]): return
	print("LIFE NET PASS")
	done = true
	get_tree().quit(0)

@rpc("any_peer", "reliable")
func _hello(r: String) -> void:
	if Net.is_host():
		ids[r] = multiplayer.get_remote_sender_id()

@rpc("any_peer", "reliable")
func _rep(r: String, d: Dictionary) -> void:
	if Net.is_host():
		reports[r] = d

@rpc("authority", "reliable")
func _cmd(c: String) -> void:
	if Net.is_host():
		return
	if c == "leave":
		leaving = true
		print("LIFE NET CLIENT OK (%s)" % role)
		Net.leave()
		get_tree().quit(0)
		return
	if c != "report":
		return
	var act: Array = []
	for k in pu.active:
		if pu.is_active(k):
			act.append(String(k))
	act.sort()
	var me := Net.local_id()
	var st := {}
	for id in net.players:
		st[id] = (net.players[id] as Player).state
	var kit := svc.kit_for(me)
	var d := {"active": act, "over": over_signals, "stats": var_to_str(ms.final_stats),
		"state_a": _state_of("a"), "state_b": _state_of("b"),
		"suds_a": Game.suds_of(a_id()).count(), "suds_b": Game.suds_of(b_id()).count(),
		"held_a": kit.held, "slot1_b": "" if kit.slots[1] == null else String(kit.slots[1].data.id)}
	_rep.rpc_id(1, role, d)

var _ab := {}

func a_id() -> int:
	return _ab.get("a", 0)

func b_id() -> int:
	return _ab.get("b", 0)

func _state_of(who: String) -> int:
	var p: Player = net.players.get(_ab.get(who, 0))
	return p.state if p != null else -1

func _physics_process(dt: float) -> void:
	if done:
		return
	t += dt
	frames += 1
	if t > 160.0:
		_fail("timeout")
		return
	if role == "host":
		if not started and ids.size() == 2 and net.players.size() == 3 and t > 3.0:
			started = true
			_tell_ids()
			await _wait(1.0)
			_script()
	elif not sent_hello and net.local_player() != null and frames > 30:
		sent_hello = true
		_hello.rpc_id(1, role)

func _tell_ids() -> void:
	for r in ["a", "b"]:
		Net.send_reliable(self, &"_ids", ids[r], [ids["a"], ids["b"]])

@rpc("authority", "reliable")
func _ids(a: int, b: int) -> void:
	_ab = {"a": a, "b": b}
