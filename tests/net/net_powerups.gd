extends Node3D
## Multi-process power-ups test (--rtt_ms/--loss on every process). Roles: host | a | b.
## Host scripts the steps; both clients report what THEY see.
##  0. A far-away pickup is visible on every peer and despawns after 25 s everywhere.
##  1. double_points: collected by walking onto it; kill-less points are doubled; pickup gone for everyone.
##  2. max_ammo: emptied mags are full again on host and clients.
##  3. purge: every zombie dies on all peers, +400 (doubled) each, no kill points, no drops even at 100 % chance.
##  4. overload: a 1-damage hit kills a zombie. 5. fortify: barricade back to 6 on all peers. 6. voucher: both players.
##  7. Timed effects (double_points, overload) are over 30 s after their pickup, on every peer.
## Host prints POWERUPS NET PASS; each client prints POWERUPS NET CLIENT OK (role) when the host leaves.

const SPAWN := Vector3(0, 0.2, -18)
const FAR := Vector3(25, 0.7, -18)

var role := ""
var port := 26100
var net: PlayerNet
var svc: WeaponService
var zs: ZombieSync
var eco: EconomyService
var pu: PowerupService
var t := 0.0
var done := false
var frames := 0
var sent_hello := false
var started := false
var ids := {}
var reports := {}
var drops_seen := 0
var final_sent := false

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
	pu = PowerupService.new()
	add_child(pu)
	pu.bind(net, zs, eco, svc)
	pu.dropped.connect(func(_k, _p): drops_seen += 1)
	Net.player_left.connect(func(id):
		if id == 1 and not done:
			done = true
			if final_sent:
				print("POWERUPS NET CLIENT OK (%s)" % role)
				get_tree().quit(0)
			else:
				print("POWERUPS NET FAIL (%s): host left before the final report" % role)
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
	var b := Barricade.new()
	b.name = "Bar"
	b.position = SPAWN + Vector3(0, 1, -10)
	add_child(b)

func _fail(msg: String) -> void:
	if done:
		return
	print("POWERUPS NET FAIL (%s): %s" % [role, msg])
	done = true
	get_tree().quit(1)

func _ck(cond: bool, msg: String) -> bool:
	if not cond:
		_fail(msg)
	return cond and not done

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _report() -> Dictionary:
	reports.clear()
	for r in ["a", "b"]:
		Net.send_reliable(self, &"_cmd", ids[r], ["report"])
	var waited := 0.0
	while (not reports.has("a") or not reports.has("b")) and waited < 10.0 and not done:
		await _wait(0.1)
		waited += 0.1
	if not reports.has("a") or not reports.has("b"):
		_fail("no reports")
		return {}
	return reports.duplicate()

func _all(r: Dictionary, key: String, want, what: String) -> bool:
	for k in ["a", "b"]:
		if not _ck(r.has(k) and r[k][key] == want, "%s: %s saw %s=%s, want %s" % [what, k, key, str(r.get(k, {}).get(key)), str(want)]):
			return false
	return true

func _spawn_zombies(n: int) -> void:
	for i in n:
		zs.spawn(SPAWN + Vector3(30 + i, 0, 5), &"shambler", 100.0, 1)

func _script() -> void:
	var a: int = ids["a"]
	var b: int = ids["b"]
	var pa: Player = net.players[a]
	var pb: Player = net.players[b]
	var apos := pa.position
	eco.wallet(a).points = 1000
	eco.wallet(b).points = 1000
	Game.seed_rng(3)
	var t_far := t
	# 0: far pickup visible everywhere
	pu.force_drop(&"fortify", FAR)
	await _wait(2.0)
	var r := await _report()
	if done: return
	if not _ck(pu.pickups.size() == 1, "host far pickup"): return
	if not _all(r, "pickups", 1, "far pickup visible"): return
	# 1: double points
	var t_dbl := t
	pu.force_drop(&"double_points", apos)
	await _wait(2.0)
	if not _ck(pu.is_active(&"double_points") and pu.pickups.size() == 1, "host double_points (pickups %d)" % pu.pickups.size()): return
	eco.award(a, 10)
	if not _ck(eco.wallet(a).points == 1020, "doubled award %d" % eco.wallet(a).points): return
	r = await _report()
	if done: return
	if not _all(r, "pickups", 1, "double_points pickup gone (only far one left)"): return
	for k in ["a", "b"]:
		if not _ck("double_points" in r[k].active, "%s sees double_points %s" % [k, str(r[k].active)]): return
	# 2: max ammo
	for p in [a, b]:
		var st: WeaponState = svc.kit_for(p).held_state()
		st.mag = 0
		st.reserve = 0
		svc.send_kit(p, true)
	await _wait(1.0)
	pu.force_drop(&"max_ammo", apos)
	await _wait(2.0)
	var full: int = svc.kit_for(a).held_state().data.mag
	for p in [a, b]:
		var st2: WeaponState = svc.kit_for(p).held_state()
		if not _ck(st2.mag == full and st2.reserve == st2.data.reserve and full > 0, "host max_ammo peer %d" % p): return
	r = await _report()
	if done: return
	if not _all(r, "mag", full, "max_ammo mag"): return
	# 3: purge (100 % drop chance: purge kills must still not drop)
	_spawn_zombies(3)
	await _wait(2.0)
	if not _ck(zs.live_count() == 3, "3 zombies live"): return
	r = await _report()
	if done: return
	if not _all(r, "live", 3, "zombies visible before purge"): return
	pu.drop_chance = 1.0
	var drops_before := drops_seen
	var pts_a := eco.wallet(a).points
	var pts_b := eco.wallet(b).points
	pu.force_drop(&"purge", apos)
	await _wait(2.5)
	if not _ck(zs.live_count() == 0, "purge left zombies"): return
	if not _ck(eco.wallet(a).points == pts_a + 800 and eco.wallet(b).points == pts_b + 800, "purge points a %d b %d (want +800 each, doubled)" % [eco.wallet(a).points - pts_a, eco.wallet(b).points - pts_b]): return
	if not _ck(drops_seen == drops_before + 1 and pu.drops_this_round == 0, "purge kills dropped something (%d)" % (drops_seen - drops_before)): return
	pu.drop_chance = -1.0
	r = await _report()
	if done: return
	if not _all(r, "live", 0, "zombies gone after purge"): return
	if not _all(r, "pickups", 1, "no purge drops"): return
	# 4: overload
	var t_ov := t
	_spawn_zombies(1)
	await _wait(1.5)
	pu.force_drop(&"overload", apos)
	await _wait(2.0)
	if not _ck(pu.is_active(&"overload"), "host overload"): return
	var zid: int = zs.zombies.keys()[0]
	zs._damage(a, Zombie.hit_id(zid), 1.0, false, false)
	if not _ck(not (zs.zombies[zid] as Zombie).alive, "overload: 1 damage did not kill"): return
	r = await _report()
	if done: return
	for k in ["a", "b"]:
		if not _ck("overload" in r[k].active, "%s sees overload" % k): return
	# 5: fortify
	var bar: Barricade = get_node("Bar")
	bar.set_boards(2)
	await _wait(1.0)
	pu.force_drop(&"fortify", apos)
	await _wait(2.0)
	if not _ck(bar.boards == 6, "host fortify"): return
	r = await _report()
	if done: return
	if not _all(r, "boards", 6, "fortify boards"): return
	# 6: voucher
	pu.force_drop(&"voucher", apos)
	await _wait(2.0)
	if not _ck(Game.has_voucher(a) and Game.has_voucher(b), "voucher for both"): return
	# 0 again: the far pickup despawns 25 s after it dropped
	while t < t_far + 27.0:
		await _wait(0.5)
	if not _ck(pu.pickups.is_empty(), "far pickup still on host"): return
	r = await _report()
	if done: return
	if not _all(r, "pickups", 0, "far pickup despawned"): return
	# 7: timed effects end 30 s after pickup
	while t < t_dbl + 32.5:
		await _wait(0.5)
	if not _ck(not pu.is_active(&"double_points"), "host double_points still on"): return
	while t < t_ov + 32.5:
		await _wait(0.5)
	if not _ck(not pu.is_active(&"overload"), "host overload still on"): return
	r = await _report()
	if done: return
	if not _all(r, "active", [], "timed effects over"): return
	print("POWERUPS NET PASS")
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
	if Net.is_host() or c != "report":
		return
	var live := 0
	for z: Zombie in zs.zombies.values():
		if z.alive:
			live += 1
	var act: Array = []
	for k in pu.active:
		if pu.is_active(k):
			act.append(String(k))
	act.sort()
	var bars := get_tree().get_nodes_in_group(&"barricades")
	var d := {"pickups": pu.pickups.size(), "active": act, "live": live, "mag": svc.state_for(Net.local_id()).mag,
		"boards": (bars[0] as Barricade).boards, "drops": drops_seen}
	final_sent = true
	_rep.rpc_id(1, role, d)

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
			await _wait(1.0)
			_script()
	elif not sent_hello and net.local_player() != null and frames > 30:
		sent_hello = true
		_hello.rpc_id(1, role)
