extends Node3D
## Multi-process zombie test (--rtt_ms/--loss on every process). Roles: host | a.
## Host: 40 zombies path through a barricade (6 tears, then the nav link) to the players; the 41st spawn queues.
## Client A fires REAL shots (lag compensated) at moving zombies: the host must see kills incl. a headshot.
## While they move, the client compares what it shows with the host ~100 ms earlier. Then the host repairs one
## board, despawns one zombie, freezes the AI and A checks every position, the board count and the spawn/death
## counts. Host prints ZOMBIE NET PASS.

const Map := preload("res://tests/net/zombie_map.gd")
const SPEED_MAX := 3.2            # shambler band 1 (m/s)
const SYNC_SAMPLE_S := 0.5

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
var frames := 0
# host
var deaths: Array = []            # [zid, killer, head, melee]
var hit_gap := 0.0                # largest |live - rewound| zombie distance at a real hit
var hist: Array = []              # [t, positions] per physics tick (0.4 s)
var next_sample := 0.0
var dead_ids: Array = []
var despawned := 0
var report: Dictionary = {}
var path_checked := false
# client (a)
var stop_fire := false
var last_shot := -1.0
var last_refill := -9.0
var shots := 0
var sync_total := 0
var sync_ok := 0
var sync_worst := 0.0
var sync_samples := 0

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
	net.spawn = Vector3(0, 0.2, -18)
	net.input_source = func():
		var f := InputFrame.new()
		if role == "a":
			f.buttons = InputFrame.ADS
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
		zs.zombie_died.connect(func(zid, killer, head, melee, _p):
			deaths.append([zid, killer, head, melee])
			dead_ids.append(zid))
		svc.hit.connect(_on_hit)
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

# ------------------------------------------------------------------ host
func _on_hit(_shooter: int, target: int, _dmg: float, _head: bool) -> void:
	if target >= 0:
		return
	var z: Zombie = zs.zombies.get(Zombie.zid_of(target))
	var rew = svc.history.pose_at(target, svc.last_rewind.time)
	if z != null and rew != null:
		hit_gap = maxf(hit_gap, z.position.distance_to((rew as Transform3D).origin))

func _nav_path(to: Vector3) -> PackedVector3Array:
	return NavigationServer3D.map_get_path(get_world_3d().navigation_map, Vector3(0, 0, 5), to, true)

func _client_id() -> int:
	for id in Net.players.ids():
		if id != Net.local_id():
			return id
	return 0

func _timeline_tick() -> void:
	hist.append([t, zs.positions()])
	while hist.size() > 2 and hist[1][0] < t - 0.4:
		hist.pop_front()
	if t < next_sample or phase in ["wait", "freeze", "await", "finish"]:
		return
	next_sample = t + SYNC_SAMPLE_S
	Net.send_reliable(self, &"_tl", _client_id(), [_newest_old()])

func _newest_old() -> Dictionary:
	var best: Dictionary = {}
	for h in hist:
		if h[0] <= t - 0.1:
			best = h[1]
	return best

func _host_step() -> void:
	var age := t - phase_t
	match phase:
		"wait":
			if Net.players.ids().size() == 2 and net.players.size() == 2 and frames > 10 and age > 1.0:
				var closed := _nav_path(Vector3(0, 0, -10))
				if not closed.is_empty() and closed[closed.size() - 1].z < 0.5:
					_fail("closed barricade: a nav path reaches the inside: %s" % str(closed))
					return
				var spawned := 0
				for i in 40:
					if zs.spawn(Vector3(-7.0 + (i % 8) * 2.0, 0, 6.0 + (i / 8) * 2.0), &"shambler", 40.0, 1):
						spawned += 1
				var q := zs.spawn(Vector3(0, 0, 18), &"shambler", 40.0, 1)
				if spawned != 40 or q or zs.queue.size() != 1 or zs.live_count() != 40:
					_fail("41st spawn not queued: spawned=%d q=%s queue=%d live=%d" % [spawned, str(q), zs.queue.size(), zs.live_count()])
					return
				print("ZOMBIE host spawned 40, 41st queued; no nav path through 6 boards")
				_go("cross")
		"cross":
			if barricade.boards == 0:
				var tear_min: float = 6.0 * Content.enemies[&"shambler"].board_tear_s
				if age < tear_min * 0.9:
					_fail("barricade opened in %.1f s, faster than 6 tears take" % age)
					return
				_go("link")
			elif age > 50.0:
				_fail("cross timeout boards=%d" % barricade.boards)
		"link":
			if age > 0.5 and not path_checked:
				path_checked = true
				var p := _nav_path(Vector3(0, 0, -10))
				var crosses := false
				for i in range(1, p.size()):
					if p[i - 1].z > 0.5 and p[i].z < -0.5:
						crosses = true
				if p.is_empty() or p[p.size() - 1].distance_to(Vector3(0, 0, -10)) > 0.5 or not crosses:
					_fail("open barricade: no nav path through the link: %s" % str(p))
					return
				print("ZOMBIE NET PATH OK link carries a path (%d points)" % p.size())
				_go("shoot")
		"shoot":
			var by_a := deaths.filter(func(d): return d[1] == _client_id())
			var heads := by_a.filter(func(d): return d[2])
			if by_a.size() >= 3 and not heads.is_empty():
				_stop.rpc_id(_client_id())
				_go("settle")
			elif age > 40.0:
				_fail("shoot timeout: deaths=%s hit_gap=%.2f" % [str(deaths), hit_gap])
		"settle":
			if age > 1.5:
				var k := deaths.size()
				if deaths.any(func(d): return d[1] != _client_id() or d[3]):
					_fail("deaths not all shot by A: %s" % str(deaths))
					return
				if hit_gap < 0.15:
					_fail("lag comp not exercised on moving zombies: gap %.2f" % hit_gap)
					return
				if zs.live_count() != 41 - k or not zs.queue.is_empty():
					_fail("queue/refill: live=%d queue=%d kills=%d" % [zs.live_count(), zs.queue.size(), k])
					return
				for z: Zombie in zs.zombies.values():
					if z.brain.min_repath_gap < Content.balance.repath_s - 0.01:
						_fail("zombie %d re-pathed after %.3f s" % [z.zid, z.brain.min_repath_gap])
						return
				print("ZOMBIE NET SHOT KILLS OK kills=%d heads=%d gap=%.2f" % [k, deaths.filter(func(d): return d[2]).size(), hit_gap])
				_go("melee")
		"melee":
			if net.players.values().any(func(p): return p.hp < Content.balance.player_hp):
				print("ZOMBIE host melee hurt a player")
				var k := deaths.size()
				var alive: Array = zs.positions().keys()
				alive.sort()
				dead_ids.append(alive[0])
				zs.despawn(alive[0])
				despawned = 1
				if zs.live_count() != 41 - k - 1:
					_fail("despawn did not remove the zombie")
					return
				barricade.repair_one(Net.local_id())
				_go("freeze")
			elif age > 25.0:
				_fail("no zombie ever hurt a player")
		"freeze":
			if age > 0.5 and not zs.frozen:
				zs.frozen = true
			if age > 3.5:
				_cmp.rpc_id(_client_id(), zs.positions(), dead_ids, barricade.boards)
				_go("await")
		"await":
			if not report.is_empty():
				var k := deaths.size()
				if not report.ok:
					_fail("client report %s" % str(report))
					return
				if report.spawns != 41 or report.deaths != k + 1:
					_fail("client saw spawns=%d deaths=%d (want 41 / %d)" % [report.spawns, report.deaths, k + 1])
					return
				if report.sync_samples < 8 or report.sync_total < 100 or float(report.sync_ok) / report.sync_total < 0.95:
					_fail("moving sync: %s" % str(report))
					return
				print("ZOMBIE NET MOVING SYNC OK samples=%d compared=%d within=%.3f worst=%.2f bound=%.2f" % [
					report.sync_samples, report.sync_total, float(report.sync_ok) / report.sync_total, report.sync_worst, report.bound])
				print("ZOMBIE host ok: client report %s" % str(report))
				_go("finish")
			elif age > 15.0:
				_fail("no client report")
		"finish":
			if age > 1.5:
				print("ZOMBIE NET PASS")
				done = true
				get_tree().quit(0)

# ------------------------------------------------------------------ client
func _bound() -> float:
	return 0.5 + SPEED_MAX * (0.25 if Net.link_sim.loss > 0.0 else 0.1)

@rpc("authority", "reliable")
func _tl(host_positions: Dictionary) -> void:
	if Net.is_host():
		return
	sync_samples += 1
	for zid in host_positions:
		var z: Zombie = zs.zombies.get(zid)
		if z == null or not z.alive:
			continue
		var e := z.position.distance_to(host_positions[zid])
		sync_total += 1
		sync_worst = maxf(sync_worst, e)
		if e <= _bound():
			sync_ok += 1

@rpc("authority", "reliable")
func _stop() -> void:
	stop_fire = true

func _client_step() -> void:
	var me := net.local_player()
	if stop_fire or me == null or me.last_ack < 0 or t < 6.0:
		return
	var st := svc.state_for(Net.local_id())
	if st.mag <= 1 and t - last_refill > 1.0:
		last_refill = t
		_refill_host.rpc_id(1)
	if t - last_shot < 0.3 or st.mag < 1:
		return
	var eye := svc.eye_of(me)
	var best: Zombie = null
	var bd := INF
	for z: Zombie in zs.zombies.values():
		var d := z.position.distance_to(me.position)
		if z.alive and z.position.z < -2.0 and d > 2.5 and d < bd:
			bd = d
			best = z
	if best == null:
		return
	var off := Vector3(0, 0.7, 0) if shots % 3 == 2 else Vector3(0, 1.65, 0)
	if svc.fire_local(((best.position + off) - eye).normalized()):
		shots += 1
		last_shot = t

@rpc("authority", "reliable")
func _cmp(host_pos: Dictionary, dead: Array, boards: int) -> void:
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
	for k in dead:
		if zs.zombies.has(k) and zs.zombies[k].alive:
			extra += 1
	var r := {"ok": missing == 0 and extra == 0 and worst <= 0.5 and barricade.boards == boards and barricade.link.enabled == (boards == 0),
		"worst": worst, "missing": missing, "extra": extra, "boards": barricade.boards, "want_boards": boards,
		"count": host_pos.size(), "spawns": zs.spawn_rx, "deaths": zs.die_rx, "shots": shots,
		"sync_samples": sync_samples, "sync_total": sync_total, "sync_ok": sync_ok, "sync_worst": sync_worst, "bound": _bound()}
	print("ZOMBIE (a) compare %s" % str(r))
	report = r
	_report.rpc_id(1, r)

@rpc("any_peer", "reliable")
func _report(r: Dictionary) -> void:
	if Net.is_host():
		report = r

@rpc("any_peer", "reliable")
func _refill_host() -> void:
	if Net.is_host():
		svc.state_for(multiplayer.get_remote_sender_id()).refill()

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
		_timeline_tick()
	else:
		_client_step()
