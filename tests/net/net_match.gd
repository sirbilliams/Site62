extends Node3D
## Multi-process match-loop test (--rtt_ms/--loss on every process). Roles: host | a.
## Code-built map: zone "a" (open) with two SpawnZones at z=-10, zone "b" (behind a BulkheadDoor) with two at z=-30.
## Zombies are frozen (no navmesh needed); the host kills them through the real death path (take_damage).
##  1. Round 1: exactly count(1, 2) zombies, all from zone a, with the curve's health. Client sees round 1 playing.
##  2. All dead -> break (client sees it). The door opens during the break; grenades are set to 1.
##  3. Round 2 starts after break_s: client sees round 2, grenades refilled (+2), zone b spawners are used.
## Host prints MATCH NET PASS; the client prints MATCH NET CLIENT OK (a) when the host leaves.

var role := ""
var port := 26100
var net: PlayerNet
var svc: WeaponService
var zs: ZombieSync
var eco: EconomyService
var mt: Match
var door: BulkheadDoor
var t := 0.0
var done := false
var frames := 0
var phase := "wait"
var phase_t := 0.0
var ids := {}
var reports := {}
var spawned: Array = []           # [round, pos, hp, band]
var sent_hello := false
var final_sent := false
var memo := {}

func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return def

func _ready() -> void:
	role = _arg("role", "host")
	port = int(_arg("port", "26100"))
	Net.beacon_port = 0
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 2, 300)
	cs.shape = box
	cs.position.y = -1.0
	floor_body.add_child(cs)
	add_child(floor_body)
	var map := Node3D.new()
	map.name = "Map"
	add_child(map)
	for zid in [&"a", &"b"]:
		var z := Zone.new()
		z.name = "Zone_" + zid
		z.zone_id = zid
		z.open = zid == &"a"
		map.add_child(z)
	var zz := {&"a": -10.0, &"b": -30.0}
	for zid in zz:
		for i in 2:
			var sz := SpawnZone.new()
			sz.name = "SZ_%s%d" % [zid, i]
			sz.zone_id = zid
			sz.position = Vector3(i * 4.0, 0.2, zz[zid])
			map.add_child(sz)
	door = BulkheadDoor.new()
	door.name = "Door"
	door.unlocks = [&"b"]
	map.add_child(door)
	net = PlayerNet.new()
	net.name = "PlayerNet"
	net.spawn = Vector3(0, 0.2, 10)
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
	Net.player_left.connect(func(id):
		if id == 1 and not done:
			done = true
			if final_sent:
				print("MATCH NET CLIENT OK (%s)" % role)
				get_tree().quit(0)
			else:
				print("MATCH NET FAIL (%s): host left before the final report" % role)
				get_tree().quit(1))
	if role == "host":
		Content.curve.spawn_base_s = 0.3          # keep the run short; in-memory only
		Content.curve.spawn_step_s = 0.0
		Content.curve.spawn_min_s = 0.3
		Content.curve.break_s = 3.0
		zs.frozen = true
		zs.zombie_spawned.connect(func(zid):
			var zb: Zombie = zs.zombies[zid]
			spawned.append([mt.round, zb.position, zb.hp, zb.band]))
		if Net.host(port) != OK:
			_fail("host failed")
	elif Net.join("127.0.0.1", port) != OK:
		_fail("join failed")

func _fail(msg: String) -> void:
	print("MATCH NET FAIL (%s): %s" % [role, msg])
	done = true
	get_tree().quit(1)

func _go(p: String) -> void:
	phase = p
	phase_t = t
	print("MATCH (%s) phase %s t=%.1f round=%d %s" % [role, p, t, mt.round, mt.phase])

func _check(cond: bool, msg: String) -> bool:
	if not cond:
		_fail(msg)
	return cond

func _a() -> int:
	return ids["a"]

func _ask(step: String) -> void:
	reports.erase("a")
	Net.send_reliable(self, &"_cmd", _a(), ["report:" + step])

func _kill_all() -> void:
	for z: Zombie in zs.zombies.values():
		if z.alive:
			z.take_damage(1.0e6, _a(), false, false)

func _of_round(r: int) -> Array:
	return spawned.filter(func(s): return s[0] == r)

func _host_step() -> void:
	var age := t - phase_t
	var curve := Content.curve
	match phase:
		"wait":
			if ids.size() == 1 and net.players.size() == 2 and age > 7.0:
				svc.kit_for(_a())
				mt.start(get_node("Map"))
				_go("r1")
		"r1":
			if age > 1.5:
				_ask("r1")
				_go("r1_r")
		"r1_r":
			if reports.has("a") and reports["a"].step == "r1":
				var r: Dictionary = reports["a"]
				if not _check(r.round == 1 and r.phase == "playing", "r1: client view %s" % str(r)):
					return
				_go("r1_kill")
			elif age > 10.0:
				_fail("no r1 report")
		"r1_kill":
			_kill_all()
			if mt.phase == Match.BREAK:
				var s1 := _of_round(1)
				var want := curve.count(1, 2)
				if not (_check(s1.size() == want, "r1: spawned %d want %d" % [s1.size(), want])
						and _check(s1.all(func(s): return s[1].z < -5.0 and s[1].z > -15.0), "r1: a spawn outside zone a")
						and _check(s1.all(func(s): return s[2] == float(curve.health(1)) and s[3] == curve.speed_band(1)), "r1: health/band %s" % str(s1[0]))):
					return
				print("MATCH NET ROUND1 OK %d zombies, zone a only, health %d" % [want, curve.health(1)])
				door.use(null)
				svc.kit_for(_a()).grenades = 1
				_ask("break")
				_go("break_r")
			elif age > 40.0:
				_fail("round 1 never ended")
		"break_r":
			if reports.has("a") and reports["a"].step == "break":
				var r: Dictionary = reports["a"]
				if not _check(r.round == 1 and r.phase == "break", "break: client view %s" % str(r)):
					return
				_go("r2_wait")
			elif age > 10.0:
				_fail("no break report")
		"r2_wait":
			if mt.round == 2 and mt.phase == Match.PLAYING:
				var k := svc.kit_for(_a())
				if not _check(k.grenades == 3, "r2: host grenades %d" % k.grenades):
					return
				_go("r2")
			elif age > 15.0:
				_fail("round 2 never started")
		"r2":
			if age > 1.5 and not memo.has("asked"):
				memo.asked = true
				_ask("r2")
			if memo.has("asked") and reports.has("a") and reports["a"].step == "r2" and not memo.has("ok"):
				var r: Dictionary = reports["a"]
				if not _check(r.round == 2 and r.phase == "playing" and r.grenades == 3, "r2: client view %s" % str(r)):
					return
				memo.ok = true
				_go("r2_kill")
			elif age > 10.0 and not memo.has("ok"):
				_fail("no r2 report")
		"r2_kill":
			_kill_all()
			if mt.phase == Match.BREAK and mt.round == 2:
				var s2 := _of_round(2)
				var want := curve.count(2, 2)
				if not (_check(s2.size() == want, "r2: spawned %d want %d" % [s2.size(), want])
						and _check(s2.any(func(s): return s[1].z < -25.0), "r2: zone b never used")
						and _check(s2.all(func(s): return s[2] == float(curve.health(2))), "r2: health")):
					return
				print("MATCH NET ROUND2 OK %d zombies, zone b used after the door, grenades refilled" % want)
				final_sent = true
				_go("finish")
			elif age > 40.0:
				_fail("round 2 never ended")
		"finish":
			if age > 1.5:
				print("MATCH NET PASS")
				done = true
				get_tree().quit(0)

@rpc("any_peer", "reliable")
func _hello() -> void:
	if Net.is_host():
		ids["a"] = multiplayer.get_remote_sender_id()

@rpc("any_peer", "reliable")
func _rep(d: Dictionary) -> void:
	if Net.is_host():
		reports["a"] = d

@rpc("authority", "reliable")
func _cmd(c: String) -> void:
	if Net.is_host():
		return
	if c.begins_with("report:"):
		var d := {"step": c.substr(7), "round": mt.round, "phase": String(mt.phase),
			"grenades": svc.kit_for(Net.local_id()).grenades,
			"door": door.is_open, "zone_b": (get_node("Map/Zone_b") as Zone).open}
		print("MATCH (%s) report %s" % [role, str(d)])
		if c == "report:r2":
			final_sent = true
		_rep.rpc_id(1, d)

func _physics_process(dt: float) -> void:
	if done:
		return
	t += dt
	frames += 1
	if t > 110.0:
		_fail("timeout phase=%s" % phase)
		return
	if role == "host":
		_host_step()
		return
	if not sent_hello and net.local_player() != null and frames > 30:
		sent_hello = true
		mt.start(get_node("Map"))                 # must be ignored on a client
		if mt.director != null or mt.running:
			_fail("client Match.start built a director")
			return
		print("MATCH NET CLIENT GUARD OK")
		_hello.rpc_id(1)
