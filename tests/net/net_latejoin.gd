extends Node3D
## Multi-process late-join test (--rtt_ms/--loss on every process). Roles: host | a | b | d (d joins last).
## Staged mid-match: round 3 playing, power on, doors D1 + D2 open (zones b, c), D3 closed, barricades 2/0 boards,
## crate moved (spot 2 active, 2 uses), a holds a Suds + a second gun + 700 points, live pickup, active Overload.
## Late join handshake: a client sends `ready` (WorldSnapshot.announce_ready) once its scene is built; the host
## sends the snapshot and live zombies only then (nothing on player_joined).
##  1. d joins: every replicated field of d equals the host's (same _view() on both), d is a spectator (DEAD, start
##     points), the doors are open on d (collision gone, nav link on, zones open), nothing was sent twice.
##  2. A spectator does not count for game over: host, a, b go down -> game over with d connected.
##  3. Round 4 starts: d is ALIVE with the starting kit, no Suds, full hp, at the spawn; points kept.
## Host prints LATEJOIN NET PASS; a client prints LATEJOIN NET CLIENT OK (role) when the host leaves.

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
var mt: Match
var ws: WorldSnapshot
var doors: Array = []
var t := 0.0
var done := false
var frames := 0
var sent_hello := false
var started := false
var final_sent := false
var ids := {}
var reports := {}
var drops_seen := 0

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
	net.input_source = func(): return InputFrame.new()
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
	mt = Match.new()
	mt.name = "Match"
	mt.zombies = zs
	mt.economy = eco
	add_child(mt)
	pu = PowerupService.new()
	add_child(pu)
	pu.bind(net, zs, eco, svc, mt)
	pu.dropped.connect(func(_k, _p): drops_seen += 1)
	ms = MatchState.new()
	add_child(ms)
	ms.bind(net, svc, eco, zs, pu, mt)
	if _arg("nows", "") == "":                      # --nows=1: the RED run, no late join snapshot at all
		ws = WorldSnapshot.new()
		add_child(ws)
		ws.bind(net, svc, eco, zs, pu, mt, ms)
		if role != "host":                          # the handshake: scene built and bound, now ask for the world
			Net.session_ready.connect(ws.announce_ready)
	Net.player_left.connect(func(id):
		if id == 1 and not done:
			done = true
			if final_sent:
				print("LATEJOIN NET CLIENT OK (%s)" % role)
				get_tree().quit(0)
			else:
				print("LATEJOIN NET FAIL (%s): host left before the final report" % role)
				get_tree().quit(1))
	if role == "host":
		zs.frozen = true
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
	var map := Node3D.new()
	map.name = "Map"
	add_child(map)
	for zid in [&"a", &"b", &"c", &"d"]:
		var z := Zone.new()
		z.name = "Zone_" + zid
		z.zone_id = zid
		z.open = zid == &"a"
		map.add_child(z)
	var door_scene: PackedScene = load("res://mapkit/bulkhead_door.tscn")
	for i in 3:
		var door: BulkheadDoor = door_scene.instantiate()
		door.name = "Door%d" % i
		var u: Array[StringName] = []
		u.append([&"b", &"c", &"d"][i])
		door.unlocks = u
		door.position = Vector3(i * 6.0, 0, 30)
		map.add_child(door)
		doors.append(door)
	for i in 2:
		var b := Barricade.new()
		b.name = "Barricade%d" % i
		b.position = Vector3(i * 5.0, 0, 40)
		map.add_child(b)
	for i in 2:
		var c := CrateSpot.new()
		c.name = "Crate%d" % i
		c.active = i == 0
		c.position = Vector3(i * 5.0, 0, 50)
		map.add_child(c)

func _fail(msg: String) -> void:
	if done:
		return
	print("LATEJOIN NET FAIL (%s): %s" % [role, msg])
	done = true
	get_tree().quit(1)

func _ck(cond: bool, msg: String) -> bool:
	if not cond:
		_fail(msg)
	return cond and not done

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _wait_until(cond: Callable, max_s: float) -> bool:
	var w := 0.0
	while not cond.call() and w < max_s and not done:
		await _wait(0.1)
		w += 0.1
	return cond.call()

func _report(who: Array) -> Dictionary:
	reports.clear()
	for r in who:
		Net.send_reliable(self, &"_cmd", ids[r], ["report"])
	if not await _wait_until(func(): return who.all(func(r): return reports.has(r)), 10.0):
		_fail("no reports")
		return {}
	return reports.duplicate()

## Everything a peer shows of the world, as plain data. `who` = the peer whose kit is reported.
func _view(who: int) -> Dictionary:
	var door_list: Array = []
	for door: BulkheadDoor in doors:
		door_list.append([door.is_open, door.blocker.collision_layer, door.link.enabled])
	var zones_open: Array = []
	for z: Zone in get_tree().get_nodes_in_group(&"zones"):
		if z.open:
			zones_open.append(String(z.zone_id))
	zones_open.sort()
	var crates: Array = []
	for c: CrateSpot in get_tree().get_nodes_in_group(&"crate_spots"):
		crates.append([String(c.name), c.active, c.uses])
	crates.sort()
	var boards: Array = []
	for b: Barricade in get_tree().get_nodes_in_group(&"barricades"):
		boards.append([String(b.name), b.boards, b.link.enabled])
	boards.sort()
	var players := {}
	for id in net.players:
		var p: Player = net.players[id]
		players[id] = [p.state, p.points, Game.suds_of(id).to_list(), Game.has_voucher(id)]
	var act: Array = []
	for k in pu.active:
		if pu.is_active(k):
			act.append(String(k))
	act.sort()
	var picks: Array = []
	for pid in pu.pickups:
		picks.append([pid, String(pu.pickups[pid].kind)])
	picks.sort()
	return {"round": mt.round, "phase": String(mt.phase), "power": Game.power, "doors": door_list, "zones": zones_open,
		"crates": crates, "boards": boards, "players": players, "active": act, "picks": picks,
		"kit": svc.kit_args(who).slice(0, 5), "drops": drops_seen, "zombies": zs.live_count()}

func _stage() -> void:
	var a: int = ids["a"]
	print("LATEJOIN stage")
	mt.round = 3
	mt.phase = Match.PLAYING
	mt.running = true
	mt.director = RoundDirector.new()
	Game.set_power(true)
	doors[0].use(null)
	doors[1].use(null)
	(get_tree().get_nodes_in_group(&"barricades")[0] as Barricade).set_boards(2)
	(get_tree().get_nodes_in_group(&"barricades")[1] as Barricade).set_boards(0)
	var spots := get_tree().get_nodes_in_group(&"crate_spots")
	spots[0].active = false
	spots[1].active = true
	spots[1].uses = 2
	Game.grant_suds(a, Content.suds[&"grape_bulwark"])
	Game.give_voucher(a)
	svc.set_weapon(a, &"hornet")
	eco.wallet(a).points = 700
	pu.force_drop(&"max_ammo", Vector3(30, 0.5, 30))
	pu.collect(&"overload", 1)
	zs.spawn(Vector3(5, 0.2, 5), &"shambler", 100.0, 0)        # a live zombie the joiner must get after `ready`
	zs.spawn(Vector3(8, 0.2, 5), &"shambler", 100.0, 0)
	print("LATEJOIN STAGED")

func _script() -> void:
	var d: int = ids["d"]
	var ph: Player = net.players[1]
	var pa: Player = net.players[ids["a"]]
	var pb: Player = net.players[ids["b"]]
	var pd: Player = net.players[d]
	# 1: the joiner's state equals the host's
	var r := await _report(["d", "a"])
	if done: return
	var want := _view(d)
	var want_a := _view(ids["a"])
	var got: Dictionary = r["d"]
	for k in want:
		if k == "drops":
			continue
		if not _ck(var_to_str(got[k]) == var_to_str(want[k]), "d differs on %s: host %s vs d %s" % [k, var_to_str(want[k]), var_to_str(got[k])]): return
	if not _ck(var_to_str(r["a"]["kit"]) == var_to_str(want_a["kit"]), "a's kit: %s vs %s" % [var_to_str(r["a"]["kit"]), var_to_str(want_a["kit"])]): return
	var no_voucher := func(pl: Dictionary) -> String:        # vouchers are host knowledge; only the joiner is told
		var c := {}
		for id in pl:
			c[id] = pl[id].slice(0, 3)
		return var_to_str(c)
	if not _ck(no_voucher.call(r["a"]["players"]) == no_voucher.call(want["players"]), "a's players: %s vs %s" % [no_voucher.call(r["a"]["players"]).replace("\n", " "), no_voucher.call(want["players"]).replace("\n", " ")]): return
	if not _ck(got["doors"][0] == [true, 0, true] and got["doors"][1] == [true, 0, true] and got["doors"][2] == [false, 1, false], "doors on d: " + str(got["doors"])): return
	if not _ck(got["zones"] == ["a", "b", "c"], "zones on d: " + str(got["zones"])): return
	if not _ck(got["round"] == 3 and got["phase"] == "playing" and got["power"], "round/power on d"): return
	if not _ck(got["players"][d][0] == Player.DEAD and got["players"][d][1] == Content.balance.start_points, "d: spectator with start points: " + str(got["players"][d])): return
	if not _ck(got["players"][ids["a"]][1] == 700 and got["players"][ids["a"]][2].size() == 1 and got["players"][ids["a"]][3], "a's points, Suds and voucher on d"): return
	if not _ck(got["picks"].size() == 1 and got["active"] == ["overload"] and got["crates"][1][1] and got["crates"][1][2] == 2, "pickup / overload / crate on d"): return
	if not _ck(got["boards"][0][1] == 2 and got["boards"][1][1] == 0 and got["boards"][1][2], "boards on d: " + str(got["boards"])): return
	if not _ck(got["drops"] == 1, "d saw the pickup once (%d)" % got["drops"]): return
	if not _ck(got["zombies"] == 2, "d got the 2 live zombies after ready (%s)" % str(got["zombies"])): return
	print("LATEJOIN step 1 ok")
	# 2: the spectator is not counted for game over
	if not _ck(pd.state == Player.DEAD and not ms.game_over, "d spectates, no game over"): return
	ph.hp = 0.0
	pa.hp = 0.0
	pb.hp = 0.0
	await _wait(1.5)
	if not _ck(ms.game_over, "host, a, b down -> game over even though d is connected"): return
	ms.reset()
	for p in [ph, pa, pb]:
		p.state = Player.ALIVE
		p.hp = 100.0
	await _wait(0.5)
	print("LATEJOIN step 2 ok")
	# 3: round 4 -> d joins in
	mt.round = 4
	mt._on_round_started(4)
	await _wait(2.0)
	if not _ck(pd.state == Player.ALIVE and absf(pd.hp - 100.0) < 0.01, "d ALIVE at full hp in round 4"): return
	if not _ck(pd.position.distance_to(SPAWN) < 0.5, "d at the start"): return
	if not _ck(eco.wallet(d).points == Content.balance.start_points and svc.kit_for(d).slots[1] == null, "d: start points, sidearm only"): return
	r = await _report(["d"])
	if done: return
	got = r["d"]
	if not _ck(got["players"][d][0] == Player.ALIVE and got["round"] == 4, "d ALIVE on d, round 4"): return
	if not _ck(var_to_str(got["kit"]) == var_to_str(_view(d)["kit"]) and got["kit"][1][1] == "", "d's kit: starting sidearm"): return
	for who in ["a", "b", "d"]:
		Net.send_reliable(self, &"_cmd", ids[who], ["final"])
	await _wait(1.0)
	print("LATEJOIN NET PASS")
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
	if c == "final":
		final_sent = true
		return
	if c != "report":
		return
	_rep.rpc_id(1, role, _view(Net.local_id()))

func _physics_process(dt: float) -> void:
	if done:
		return
	t += dt
	frames += 1
	if t > 150.0:
		_fail("timeout")
		return
	if role == "host":
		if not started and ids.size() == 2 and net.players.size() == 3 and t > 3.0:
			started = true
			_stage()
			await _wait_until(func(): return ids.has("d") and net.players.size() == 4, 40.0)
			await _wait(3.0)
			if not done:
				_script()
	elif not sent_hello and net.local_player() != null and frames > 30:
		sent_hello = true
		_hello.rpc_id(1, role)
