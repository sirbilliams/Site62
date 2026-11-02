extends Node3D
## Multi-process zombie test (--rtt_ms/--loss on every process). Roles: host | a.
## Host: 40 zombies path through a barricade to the players (tear 6 boards, climb through, melee), the 41st
## spawn request queues, kills (via WeaponService.hit) refill from the queue. Then AI freezes and client A
## compares every zombie position with the host's (<= 0.5 m), plus spawn/death counts. Host prints ZOMBIE NET PASS.

const Map := preload("res://tests/net/zombie_map.gd")

var role := ""
var port := 26100
var net: PlayerNet
var svc: WeaponService
var zs: ZombieSync
var barricade: Barricade
var t := 0.0
var done := false
var phase := "wait"
var phase_t := 0.0
var started := false
var deaths: Array = []
var repath_ok := true
var report: Dictionary = {}
var killed_ids: Array = []
var frames := 0

func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return def

func _ready() -> void:
	role = _arg("role", "host")
	port = int(_arg("port", "26100"))
	Net.beacon_port = 0
	barricade = Map.build(self)
	net = PlayerNet.new()
	net.name = "PlayerNet"
	net.spawn = Vector3(0, 0.2, -10)
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
	Net.player_left.connect(func(id):
		if id == 1 and not done:
			done = true
			if not report.is_empty() and report.ok:
				print("ZOMBIE NET CLIENT OK (%s)" % role)
				get_tree().quit(0)
			else:
				print("ZOMBIE NET FAIL (%s): host left before the comparison finished" % role)
				get_tree().quit(1))
	if role == "host":
		zs.zombie_died.connect(func(zid, killer, head, melee, _p): deaths.append([zid, killer, head, melee]))
		if Net.host(port) != OK:
			_fail("host failed")
	elif Net.join("127.0.0.1", port) != OK:
		_fail("join failed")

func _fail(msg: String) -> void:
	print("ZOMBIE NET FAIL (%s): %s" % [role, msg])
	done = true
	get_tree().quit(1)

func _go(p: String) -> void:
	phase = p
	phase_t = t
	print("ZOMBIE (%s) phase %s t=%.1f" % [role, p, t])

func _host_step() -> void:
	var age := t - phase_t
	match phase:
		"wait":
			if Net.players.ids().size() == 2 and net.players.size() == 2 and frames > 10 and age > 1.0:
				var spawned := 0
				for i in 40:
					if zs.spawn(Vector3(-7.0 + (i % 8) * 2.0, 0, 6.0 + (i / 8) * 2.0), &"shambler", 120.0, 1):
						spawned += 1
				var q := zs.spawn(Vector3(0, 0, 18), &"shambler", 120.0, 1)
				if spawned != 40 or q or zs.queue.size() != 1 or zs.live_count() != 40:
					_fail("41st spawn not queued: spawned=%d q=%s queue=%d live=%d" % [spawned, str(q), zs.queue.size(), zs.live_count()])
					return
				print("ZOMBIE host spawned 40, 41st queued")
				_go("cross")
		"cross":
			var inside := 0
			for p in zs.positions().values():
				if p.z < -1.0:
					inside += 1
			var hurt := net.players.values().any(func(p): return p.hp < Content.balance.player_hp)
			if barricade.boards == 0 and inside > 0 and hurt:
				var tear_min: float = 6.0 * Content.enemies[&"shambler"].board_tear_s
				if age < tear_min * 0.9:
					_fail("barricade opened in %.1f s, faster than %d tears take" % [age, 6])
					return
				print("ZOMBIE host barricade open, %d zombies through, players hurt" % inside)
				_go("kill")
			elif age > 50.0:
				_fail("cross timeout boards=%d inside=%d hurt=%s" % [barricade.boards, inside, str(hurt)])
		"kill":
			if killed_ids.is_empty():
				var ids: Array = zs.positions().keys()
				ids.sort()
				for i in 3:
					killed_ids.append(ids[i])
					svc.hit.emit(Net.local_id(), Zombie.hit_id(ids[i]), 9999.0, true)
			elif age > 1.0:
				if deaths.size() != 3 or deaths.any(func(d): return not d[2] or d[3] or d[1] != Net.local_id()):
					_fail("deaths %s" % str(deaths))
					return
				if zs.live_count() != 38 or not zs.queue.is_empty():
					_fail("queue did not refill: live=%d queue=%d" % [zs.live_count(), zs.queue.size()])
					return
				for z: Zombie in zs.zombies.values():
					if z.brain != null and z.alive:
						if z.brain.repaths > (t - 0.0) / Content.balance.repath_s + 2:
							repath_ok = false
				if not repath_ok:
					_fail("a zombie re-pathed faster than repath_s")
					return
				zs.frozen = true
				_go("freeze")
		"freeze":
			if age > 3.0:
				_cmp.rpc_id(_other_peer(), zs.positions(), killed_ids)
				_go("await")
		"await":
			if not report.is_empty():
				if not report.ok:
					_fail("client report %s" % str(report))
					return
				if report.spawns != 41 or report.deaths != 3:
					_fail("client saw spawns=%d deaths=%d (want 41 / 3)" % [report.spawns, report.deaths])
					return
				print("ZOMBIE host ok: client report %s" % str(report))
				_go("finish")
			elif age > 15.0:
				_fail("no client report")
		"finish":
			if age > 1.5:
				print("ZOMBIE NET PASS")
				done = true
				get_tree().quit(0)

func _other_peer() -> int:
	for id in Net.players.ids():
		if id != Net.local_id():
			return id
	return 0

@rpc("authority", "reliable")
func _cmp(host_pos: Dictionary, killed: Array) -> void:
	if Net.is_host():
		return
	var worst := 0.0
	var missing := 0
	for zid in host_pos:
		var z: Zombie = zs.zombies.get(zid)
		if z == null:
			missing += 1
		else:
			worst = maxf(worst, z.position.distance_to(host_pos[zid]))
	var extra := 0
	for z: Zombie in zs.zombies.values():
		if z.alive and not host_pos.has(z.zid):
			extra += 1
	for k in killed:
		if zs.zombies.has(k):
			extra += 1
	var r := {"ok": missing == 0 and extra == 0 and worst <= 0.5, "worst": worst, "missing": missing, "extra": extra,
		"count": host_pos.size(), "spawns": zs.spawn_rx, "deaths": zs.die_rx}
	print("ZOMBIE (a) compare %s" % str(r))
	report = r
	_report.rpc_id(1, r)

@rpc("any_peer", "reliable")
func _report(r: Dictionary) -> void:
	if Net.is_host():
		report = r

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
