extends Node3D
## Multi-process player-kit test (--rtt_ms/--loss on every process). Roles: host | a.
## Host drives the steps and checks host-owned state; client A acts through the REAL input bits and reports its view.
##  1. A buys a second gun from a wall-buy: it fills slot 1, the start gun stays in slot 0.
##  2. A swaps with NEXT_WEAPON (a shot inside the swap time is blocked), fires each gun: host and client agree
##     on the held gun and on the ammo of BOTH slots.
##  3. A knife-kills two zombies: economy pays pts_melee_kill, kills carry melee = true.
##  4. A throws a grenade: two grouped zombies die (both credited to A), one behind a wall survives, clients
##     saw the spawn and the explosion. Round starts refill grenades up to the cap.
## Host prints KIT NET PASS; the client prints KIT NET CLIENT OK (a) when the host leaves.

const SPAWN := Vector3(0, 0.2, -18)

var role := ""
var port := 26100
var net: PlayerNet
var svc: WeaponService
var zs: ZombieSync
var eco: EconomyService
var t := 0.0
var done := false
var frames := 0
var phase := "wait"
var phase_t := 0.0
# host
var ids := {}
var reports := {}
var deaths: Array = []              # [zid, killer, head, melee]
var z := {}                         # name -> zid
var wall: StaticBody3D
var boom_pos := Vector3.ZERO
# client
var press := 0
var press_frames := 0
var pitch := 0.0
var script_: Array = []             # [at_t, Callable]
var memo := {}
var sent_hello := false
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
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(300, 2, 300)
	cs.shape = box
	cs.position.y = -1.0
	floor_body.add_child(cs)
	add_child(floor_body)
	var near := WallBuy.new()
	near.name = "Near"
	near.weapon_id = &"hornet"
	near.position = SPAWN + Vector3(1, 1, 0)
	add_child(near)
	net = PlayerNet.new()
	net.name = "PlayerNet"
	net.spawn = SPAWN
	net.input_source = func():
		var f := InputFrame.new()
		f.buttons = InputFrame.ADS
		f.look_pitch = pitch
		if press_frames > 0:
			press_frames -= 1
			f.buttons |= press
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
	Net.player_left.connect(func(id):
		if id == 1 and not done:
			done = true
			if final_sent:
				print("KIT NET CLIENT OK (%s)" % role)
				get_tree().quit(0)
			else:
				print("KIT NET FAIL (%s): host left before the final report" % role)
				get_tree().quit(1))
	if role == "host":
		zs.zombie_died.connect(func(zid, killer, head, melee, _p): deaths.append([zid, killer, head, melee]))
		if Net.host(port) != OK:
			_fail("host failed")
	elif Net.join("127.0.0.1", port) != OK:
		_fail("join failed")

func _fail(msg: String) -> void:
	print("KIT NET FAIL (%s): %s" % [role, msg])
	done = true
	get_tree().quit(1)

func _go(p: String) -> void:
	phase = p
	phase_t = t
	print("KIT (%s) phase %s t=%.1f" % [role, p, t])

# ------------------------------------------------------------------ host
func _a() -> int:
	return ids["a"]

func _cmd_to(c: String) -> void:
	Net.send_reliable(self, &"_cmd", _a(), [c])

func _check(cond: bool, msg: String) -> bool:
	if not cond:
		_fail(msg)
	return cond

func _ask(step: String) -> void:
	reports.erase("a")
	_cmd_to("report:" + step)

func _zspawn(key: String, pos: Vector3, hp: float) -> void:
	zs.spawn(pos, &"shambler", hp, 1)
	z[key] = zs._next_zid - 1

func _mags(k: Inventory) -> Array:
	return [k.slots[0].mag if k.slots[0] != null else -1, k.slots[1].mag if k.slots[1] != null else -1]

func _slot_ids(k: Inventory) -> Array:
	return [String(k.slots[0].data.id) if k.slots[0] != null else "", String(k.slots[1].data.id) if k.slots[1] != null else ""]

func _view_ok(r: Dictionary, held: String, mags: Array) -> bool:
	return r.held == held and r.mags == mags

func _host_step() -> void:
	var age := t - phase_t
	var k: Inventory = svc.kit_for(_a()) if ids.has("a") else null
	match phase:
		"wait":
			if ids.size() == 1 and net.players.size() == 2 and age > 7.0:
				zs.frozen = true
				eco.wallet(_a()).add(500, false)
				_cmd_to("use_near")
				_go("buy")
		"buy":
			if age > 2.5:
				if not (_check(k.held == 1 and k.slots[0].data.id == &"sentinel_45" and k.slots[1].data.id == &"hornet", "buy: host kit %s" % str(_mags(k)))
						and _check(eco.wallet(_a()).points == 0, "buy: points %d" % eco.wallet(_a()).points)
						and _check(k.grenades == 2, "start grenades")):
					return
				_ask("buy")
				_go("buy_r")
		"buy_r":
			if reports.has("a") and reports["a"].step == "buy":
				var r: Dictionary = reports["a"]
				if not _check(r.ids == ["sentinel_45", "hornet"] and r.held == "hornet" and r.mags == [8, 32] and r.grenades == 2, "buy: client view %s" % str(r)):
					return
				_zspawn("far", SPAWN + Vector3(0, 0, -6), 100000.0)
				_cmd_to("swap_try")
				_go("swap1")
			elif age > 10.0:
				_fail("no buy report")
		"swap1":
			if age > 3.0:
				if not _check(k.held == 0 and _mags(k) == [7, 32], "swap1: host held %d mags %s" % [k.held, str(_mags(k))]):
					return
				_ask("swap1")
				_go("swap1_r")
		"swap1_r":
			if reports.has("a") and reports["a"].step == "swap1":
				var r: Dictionary = reports["a"]
				if not _check(_view_ok(r, "sentinel_45", [7, 32]) and r.try_fire == false and r.late_fire == true, "swap1: client view %s" % str(r)):
					return
				_cmd_to("swap_fire")
				_go("swap2")
			elif age > 10.0:
				_fail("no swap1 report")
		"swap2":
			if age > 3.0:
				if not _check(k.held == 1 and _mags(k) == [7, 31], "swap2: host held %d mags %s" % [k.held, str(_mags(k))]):
					return
				_ask("swap2")
				_go("swap2_r")
		"swap2_r":
			if reports.has("a") and reports["a"].step == "swap2":
				if not _check(_view_ok(reports["a"], "hornet", [7, 31]), "swap2: client view %s" % str(reports["a"])):
					return
				print("KIT NET SWAP OK host and client agree on held gun and both slots' ammo")
				zs.despawn(z.far)
				_zspawn("m1", SPAWN + Vector3(0, 0, -1.1), 100.0)
				_zspawn("m2", SPAWN + Vector3(0, 0, -1.25), 100.0)
				reports.erase("a")
				memo.pts = eco.wallet(_a()).points
				_go("melee_wait")
			elif age > 10.0:
				_fail("no swap2 report")
		"melee_wait":
			if age > 1.0:                       # the zombies need a history older than the rewind
				_cmd_to("melee2")
				_go("melee")
		"melee":
			if age > 4.0:
				var ms := deaths.filter(func(d): return d[3])
				if not (_check(ms.size() == 2 and ms.all(func(d): return d[1] == _a()), "melee: deaths %s" % str(deaths))
						and _check(eco.wallet(_a()).points == memo.pts + 2 * Content.balance.pts_melee_kill, "melee: points %d from %d" % [eco.wallet(_a()).points, memo.pts])):
					return
				print("KIT NET MELEE OK 2 knife kills paid %d each" % Content.balance.pts_melee_kill)
				_zspawn("g1", SPAWN + Vector3(0, 0, -10), 100.0)
				_zspawn("g2", SPAWN + Vector3(0, 0, -11), 100.0)
				_zspawn("g3", SPAWN + Vector3(0, 0, -12), 100.0)
				wall = StaticBody3D.new()
				wall.collision_layer = 1
				var wcs := CollisionShape3D.new()
				var wb := BoxShape3D.new()
				wb.size = Vector3(8, 2.6, 0.2)
				wcs.shape = wb
				wall.add_child(wcs)
				add_child(wall)
				memo.pts = eco.wallet(_a()).points
				memo.deaths = deaths.size()
				_cmd_to("grenade")
				_go("grenade")
		"grenade":
			_track_grenade()
			if age > 6.0:
				var gk := deaths.slice(memo.deaths)
				var ids_dead := gk.map(func(d): return d[0])
				var g3: Zombie = zs.zombies.get(z.g3)
				if not (_check(gk.size() == 2 and ids_dead.has(z.g1) and ids_dead.has(z.g2) and gk.all(func(d): return d[1] == _a() and not d[3]), "grenade: deaths %s" % str(gk))
						and _check(g3 != null and g3.alive and g3.hp == 100.0, "grenade: the zombie behind the wall was hurt")
						and _check(eco.wallet(_a()).points == memo.pts + 2 * Content.balance.pts_kill, "grenade: points %d from %d" % [eco.wallet(_a()).points, memo.pts])
						and _check(k.grenades == 1, "grenade: host count %d" % k.grenades)):
					return
				print("KIT NET GRENADE OK both grouped zombies credited, wall blocked the third")
				_ask("grenade")
				_go("grenade_r")
		"grenade_r":
			if reports.has("a") and reports["a"].step == "grenade":
				var r: Dictionary = reports["a"]
				if not _check(r.spawn_rx == 1 and r.boom_rx == 1 and r.grenades == 1 and r.live == 0, "grenade: client view %s" % str(r)):
					return
				eco.reset_round()
				_go("refill1")
			elif age > 10.0:
				_fail("no grenade report")
		"refill1":
			if age > 1.0:
				if not _check(k.grenades == 3, "refill1: host %d" % k.grenades):
					return
				_ask("refill1")
				_go("refill1_r")
		"refill1_r":
			if reports.has("a") and reports["a"].step == "refill1":
				if not _check(reports["a"].grenades == 3, "refill1: client %s" % str(reports["a"])):
					return
				eco.reset_round()
				eco.reset_round()
				_go("refill2")
			elif age > 10.0:
				_fail("no refill1 report")
		"refill2":
			if age > 1.0:
				if not _check(k.grenades == Content.balance.grenades_max, "refill2: host %d" % k.grenades):
					return
				_ask("refill2")
				_go("refill2_r")
		"refill2_r":
			if reports.has("a") and reports["a"].step == "refill2":
				if not _check(reports["a"].grenades == Content.balance.grenades_max, "refill2: client %s" % str(reports["a"])):
					return
				print("KIT NET REFILL OK +2 per round, capped at %d" % Content.balance.grenades_max)
				_go("finish")
			elif age > 10.0:
				_fail("no refill2 report")
		"finish":
			if age > 1.5:
				print("KIT NET PASS")
				done = true
				get_tree().quit(0)

## Keep two zombies 1 m either side of the flying grenade and one behind a floating wall slab (so it
## cannot touch the grenade), whatever the bounces do.
func _track_grenade() -> void:
	if svc.grenades_live.is_empty():
		return
	var g: Grenade = svc.grenades_live.values()[0]
	var p := g.global_position
	boom_pos = p
	var a: Zombie = zs.zombies.get(z.g1)
	var b: Zombie = zs.zombies.get(z.g2)
	var c: Zombie = zs.zombies.get(z.g3)
	a.position = Vector3(p.x - 1.0, 0, p.z)
	b.position = Vector3(p.x + 1.0, 0, p.z)
	c.position = Vector3(p.x, 0, p.z + 2.5)
	wall.position = Vector3(p.x, 0.4 + 1.3, p.z + 1.2)

@rpc("any_peer", "reliable")
func _hello() -> void:
	if Net.is_host():
		ids["a"] = multiplayer.get_remote_sender_id()

@rpc("any_peer", "reliable")
func _rep(d: Dictionary) -> void:
	if Net.is_host():
		reports["a"] = d

# ------------------------------------------------------------------ client
func _at(delay: float, f: Callable) -> void:
	script_.append([t + delay, f])

func _press(bits: int) -> void:
	press = bits
	press_frames = 4

func _try_fire(key: String) -> void:
	var me := net.local_player()
	var eye := svc.eye_of(me)
	var tgt := SPAWN + Vector3(0, 0.9, -6)
	memo[key] = svc.fire_local((tgt - eye).normalized())

@rpc("authority", "reliable")
func _cmd(c: String) -> void:
	if Net.is_host():
		return
	if c == "use_near":
		eco.use_local(get_node("Near"))
	elif c == "swap_try":
		_press(InputFrame.NEXT_WEAPON)
		_at(0.2, _try_fire.bind("try_fire"))             # inside the swap time: blocked
		_at(0.9, _try_fire.bind("late_fire"))
	elif c == "swap_fire":
		_press(InputFrame.NEXT_WEAPON)
		_at(0.9, _try_fire.bind("hornet_fire"))
	elif c == "melee2":
		_press(InputFrame.MELEE)
		_at(1.2, _press.bind(InputFrame.MELEE))
	elif c == "grenade":
		pitch = -0.6
		_at(0.3, _press.bind(InputFrame.GRENADE))
	elif c.begins_with("report:"):
		var k := svc.kit_for(Net.local_id())
		var d := {"step": c.substr(7), "held": String(k.held_state().data.id),
			"ids": _slot_ids(k), "mags": _mags(k),
			"grenades": k.grenades, "spawn_rx": svc.spawn_rx, "boom_rx": svc.boom_rx, "live": svc.grenades_live.size(),
			"try_fire": memo.get("try_fire"), "late_fire": memo.get("late_fire")}
		print("KIT (%s) report %s" % [role, str(d)])
		final_sent = c == "report:refill2"
		_rep.rpc_id(1, d)

func _physics_process(dt: float) -> void:
	if done:
		return
	t += dt
	frames += 1
	if t > 100.0:
		_fail("timeout phase=%s" % phase)
		return
	if role == "host":
		_host_step()
		return
	for s in script_.duplicate():
		if t >= s[0]:
			script_.erase(s)
			s[1].call()
	if not sent_hello and net.local_player() != null and frames > 30:
		sent_hello = true
		_hello.rpc_id(1)
