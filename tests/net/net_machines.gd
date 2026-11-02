extends Node3D
## Multi-process machines test (--rtt_ms/--loss on every process). Roles: host | a | b.
## Host scripts the steps; client a buys, both clients report what THEY see.
##  1. Suds before power: refused. Power on (replicated), buy Suds: effect on host and both clients.
##  2. All four Suds, a duplicate and a 5th are refused.
##  3. Six crate rolls: identical on every peer, never a held gun; the crate then moves; a voucher makes a roll free.
##  4. Isotope Refit swaps the held gun; a second refit is refused.
## Host prints MACHINES NET PASS; each client prints MACHINES NET CLIENT OK (role) when the host leaves.

const SPAWN := Vector3(0, 0.2, -18)
const SETTLE := 1.6

var role := ""
var port := 26100
var net: PlayerNet
var svc: WeaponService
var zs: ZombieSync
var eco: EconomyService
var t := 0.0
var done := false
var frames := 0
var sent_hello := false
var started := false
var ids := {}
var reports := {}
var purchases: Array = []
var rolls: Array = []                    # rolled ids as seen by THIS peer
var moves := 0                           # crate_moved count seen by this peer
var prev_kit: Array = ["sentinel_45"]    # host: kit before the latest roll
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
	for n in ["C1", "C2"]:
		var c: CrateSpot = get_node(n)
		c.rolled.connect(_on_roll)
		c.crate_moved.connect(func(_to): moves += 1)
	Net.player_left.connect(func(id):
		if id == 1 and not done:
			done = true
			if final_sent:
				print("MACHINES NET CLIENT OK (%s)" % role)
				get_tree().quit(0)
			else:
				print("MACHINES NET FAIL (%s): host left before the final report" % role)
				get_tree().quit(1))
	if role == "host":
		eco.purchase.connect(func(p, what, cost): purchases.append([p, what, cost]))
		if Net.host(port) != OK:
			_fail("host failed")
	elif Net.join("127.0.0.1", port) != OK:
		_fail("join failed")

func _on_roll(peer: int, id: StringName) -> void:
	rolls.append(String(id))
	if role == "host":
		var a_peer: int = ids.get("a", -1)
		var now := _kit_ids(a_peer)
		if peer != a_peer or String(id) in prev_kit or not (String(id) in now):
			_fail("roll %s duplicates a held gun %s (kit now %s)" % [id, str(prev_kit), str(now)])
		prev_kit = now

func _kit_ids(peer: int) -> Array:
	var out: Array = []
	for st in svc.kit_for(peer).slots:
		if st != null:
			out.append(String(st.data.id))
	return out

func _machine(n: String, pos: Vector3, node: Node3D) -> void:
	node.name = n
	node.position = SPAWN + pos
	add_child(node)

func _suds_machine(n: String, d: SudsData, pos: Vector3) -> void:
	var m := SudsMachine.new()
	m.suds = d
	_machine(n, pos, m)

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
	_machine("Power", Vector3(1, 1, 0), PowerSwitch.new())
	_suds_machine("S1", Content.suds[&"grape_bulwark"], Vector3(-1, 1, 0))
	_suds_machine("S2", Content.suds[&"snapback_fizz"], Vector3(0, 1, 1))
	_suds_machine("S3", Content.suds[&"second_wind_root_beer"], Vector3(0, 1, -1))
	_suds_machine("S4", Content.suds[&"overclock_orange"], Vector3(1, 1, 1))
	_suds_machine("SDup", Content.suds[&"grape_bulwark"], Vector3(-1, 1, 1))
	var extra := SudsData.new()
	extra.id = &"extra_fizz"
	extra.effect = &"max_hp"
	extra.value = 300.0
	extra.cost = 100
	_suds_machine("SExtra", extra, Vector3(1, 1, -1))
	var c1 := CrateSpot.new()
	c1.active = true
	_machine("C1", Vector3(-1, 1, -1), c1)
	_machine("C2", Vector3(0.5, 1, 0.5), CrateSpot.new())
	_machine("Refit", Vector3(-0.5, 1, -0.5), RefitStation.new())

func _fail(msg: String) -> void:
	if done:
		return
	print("MACHINES NET FAIL (%s): %s" % [role, msg])
	done = true
	get_tree().quit(1)

func _ck(cond: bool, msg: String) -> bool:
	if not cond:
		_fail(msg)
	return cond and not done

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

# ------------------------------------------------------------------ host script
func _cmd_to(r: String, c: String) -> void:
	Net.send_reliable(self, &"_cmd", ids[r], [c])

## Ask `r` to use `paths` (comma separated), then wait for the effects to settle.
func _use(paths: String) -> void:
	_cmd_to("a", "use:" + paths)
	await _wait(SETTLE + 0.6 * paths.count(","))

func _report() -> Dictionary:
	reports.clear()
	_cmd_to("a", "report")
	_cmd_to("b", "report")
	var waited := 0.0
	while (not reports.has("a") or not reports.has("b")) and waited < 10.0 and not done:
		await _wait(0.1)
		waited += 0.1
	if not reports.has("a") or not reports.has("b"):
		_fail("no reports")
		return {}
	return reports.duplicate()

func _points(r: String) -> int:
	return eco.wallet(ids[r]).points

func _script() -> void:
	var a: int = ids["a"]
	var pa: Player = net.players[a]
	eco.wallet(a).points = 30000
	Game.seed_rng(7)
	# 1: no power
	await _use("S1")
	if not (_ck(_points("a") == 30000 and purchases.is_empty() and not Game.suds_of(a).has(&"grape_bulwark"), "suds bought without power")):
		return
	var r := await _report()
	if done: return
	if not _ck(r.a.denied == "no_power" and not r.a.power and r.a.suds.is_empty(), "client view before power %s" % str(r)):
		return
	await _use("Power")
	if not _ck(Game.power and _points("a") == 30000, "power not on / charged"):
		return
	await _use("S1")
	if not _ck(_points("a") == 27500 and Game.suds_of(a).max_hp(100.0) == 220.0 and is_equal_approx(pa.hp, 220.0) and is_equal_approx(pa.max_health(), 220.0), "host suds effect (points %d hp %f)" % [_points("a"), pa.hp]):
		return
	r = await _report()
	if done: return
	for k in ["a", "b"]:
		if not _ck(r[k].power and r[k].max_hp == 220.0 and r[k].suds == ["grape_bulwark"], "%s suds view %s" % [k, str(r[k])]):
			return
	if not _ck(is_equal_approx(r.a.hp, 220.0) and is_equal_approx(r.b.a_hp, 220.0), "hp replicated %s" % str(r)):
		return
	print("MACHINES power + first suds OK")
	# 2: the other three, a duplicate, a fifth
	await _use("S2,S3,S4")
	var fx := Game.suds_of(a)
	if not _ck(fx.count() == 4 and is_equal_approx(fx.reload_mult(), 0.5) and is_equal_approx(fx.revive_mult(), 0.5) and is_equal_approx(fx.fire_rate_mult(), 1.33), "host stack"):
		return
	if not _ck(is_equal_approx(WeaponService.rate_mult_of(a), 1.33) and is_equal_approx(WeaponService.reload_speed_of(a), 2.0), "weapon service multipliers"):
		return
	var spent := 27500 - 3000 - 1500 - 2000
	if not _ck(_points("a") == spent, "points after four suds %d" % _points("a")):
		return
	await _use("SDup")
	r = await _report()
	if done: return
	if not _ck(r.a.denied == "owned" and _points("a") == spent, "duplicate not refused %s" % str(r.a)):
		return
	await _use("SExtra")
	r = await _report()
	if done: return
	if not _ck(r.a.denied == "max_suds" and r.a.denied_count == 3 and _points("a") == spent and not Game.suds_of(a).has(&"extra_fizz"), "fifth not refused %s" % str(r.a)):
		return
	for k in ["a", "b"]:
		var d: Dictionary = r[k]
		if not _ck(d.suds.size() == 4 and is_equal_approx(d.reload, 0.5) and is_equal_approx(d.revive, 0.5) and is_equal_approx(d.rate, 1.33) and d.max_hp == 220.0, "%s stack view %s" % [k, str(d)]):
			return
	print("MACHINES suds stack + refusals OK")
	# 3: crate
	var before := _points("a")
	await _use("C2")                                          # inactive spot: refused
	if not _ck(_points("a") == before and rolls.is_empty(), "inactive crate sold"):
		return
	await _use("C1,C1,C1,C1,C1,C1")
	await _wait(1.0)
	if not _ck(rolls.size() == 6 and _points("a") == before - 6 * 950, "host rolls %s points %d" % [str(rolls), _points("a")]):
		return
	r = await _report()
	if done: return
	for k in ["a", "b"]:
		if not _ck(r[k].rolls == rolls, "%s rolls differ: %s vs host %s" % [k, str(r[k].rolls), str(rolls)]):
			return
		if not _ck(r[k].moves == 1 and not r[k].c1 and r[k].c2, "%s crate move view %s" % [k, str(r[k])]):
			return
	if not _ck(moves == 1 and not (get_node("C1") as CrateSpot).active and (get_node("C2") as CrateSpot).active, "host crate move"):
		return
	if not _ck(r.a.slots == _kit_ids(a), "a kit view %s vs %s" % [str(r.a.slots), str(_kit_ids(a))]):
		return
	print("MACHINES crate rolls %s OK" % str(rolls))
	before = _points("a")
	Game.give_voucher(a)
	await _use("C2")
	if not _ck(_points("a") == before and rolls.size() == 7 and not Game.has_voucher(a), "voucher crate not free"):
		return
	before = _points("a")
	await _use("C2")
	if not _ck(_points("a") == before - 950, "crate after voucher not charged"):
		return
	# 4: refit
	before = _points("a")
	var held_base: String = String(svc.state_for(a).data.id)
	await _use("Refit")
	var held_now: String = String(svc.state_for(a).data.id)
	if not _ck(held_now == held_base + "_refit" and _points("a") == before - 5000, "refit host %s -> %s, points %d" % [held_base, held_now, _points("a")]):
		return
	r = await _report()
	if done: return
	if not _ck(r.a.held == held_now and r.a.points == before - 5000, "refit client view %s" % str(r.a)):
		return
	await _use("Refit")
	r = await _report()
	if done: return
	if not _ck(_points("a") == before - 5000 and r.a.denied == "no_refit" and String(svc.state_for(a).data.id) == held_now, "second refit not refused %s" % str(r.a)):
		return
	print("MACHINES refit OK")
	Game.clear_suds(a, pa)
	await _wait(SETTLE)
	r = await _report()
	if done: return
	for k in ["a", "b"]:
		if not _ck(r[k].suds.is_empty() and r[k].max_hp == 100.0, "%s still sees suds after clear %s" % [k, str(r[k])]):
			return
	if not _ck(pa.hp <= 100.0 and pa.max_health() == 100.0, "host hp after clear %f" % pa.hp):
		return
	print("MACHINES clear_suds OK")
	await _wait(1.0)
	print("MACHINES NET PASS")
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

# ------------------------------------------------------------------ client
func _use_paths(paths: String) -> void:
	for p in paths.split(","):
		eco.use_local(get_node(p))
		await _wait(0.6)

@rpc("authority", "reliable")
func _cmd(c: String) -> void:
	if Net.is_host():
		return
	if c.begins_with("use:"):
		_use_paths(c.substr(4))
	elif c == "report":
		var me := net.local_player()
		var fx := Game.suds_of(_a_id())          # the buyer's Suds as THIS peer sees them
		var held := svc.state_for(Net.local_id()).data
		var slots: Array = []
		for st in svc.kit_for(Net.local_id()).slots:
			if st != null:
				slots.append(String(st.data.id))
		var d := {"power": Game.power, "points": me.points, "hp": me.hp, "denied": String(eco.last_denied), "denied_count": eco.denied_count,
			"suds": _sorted(fx.ids()), "max_hp": fx.max_hp(100.0), "reload": fx.reload_mult(), "revive": fx.revive_mult(), "rate": fx.fire_rate_mult(),
			"held": String(held.id), "slots": slots, "rolls": rolls.duplicate(), "moves": moves,
			"c1": (get_node("C1") as CrateSpot).active, "c2": (get_node("C2") as CrateSpot).active, "a_hp": _a_hp()}
		final_sent = true
		_rep.rpc_id(1, role, d)

var ids_a := 0

func _sorted(arr: Array) -> Array:
	var out := arr.map(func(x): return String(x))
	out.sort()
	return out

## Client view of a's peer id: the lowest non-host id that is not b's is unknown, so the host tells everyone.
func _a_id() -> int:
	return ids_a

func _a_hp() -> float:
	var p: Player = net.players.get(ids_a)
	return p.hp if p != null else -1.0

func _physics_process(dt: float) -> void:
	if done:
		return
	t += dt
	frames += 1
	if t > 120.0:
		_fail("timeout")
		return
	if role == "host":
		if not started and ids.size() == 2 and net.players.size() == 3 and t > 3.0:
			started = true
			for r in ["a", "b"]:
				Net.send_reliable(self, &"_set_a", ids[r], [ids["a"]])
			await _wait(1.0)
			_script()
	elif not sent_hello and net.local_player() != null and frames > 30:
		sent_hello = true
		_hello.rpc_id(1, role)

@rpc("authority", "reliable")
func _set_a(id: int) -> void:
	ids_a = id
