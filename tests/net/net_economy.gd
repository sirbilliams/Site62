extends Node3D
## Multi-process economy test (--rtt_ms/--loss on every process). Roles: host | a | b.
## Host drives the steps and checks the host-owned state; clients act on command and report what THEY see.
##  1. A (given 1000) buys the 1000-point wall gun: weapon + points on host and client.
##  2. A buys it again with an empty magazine: ammo at ammo_cost, refilled.
##  3. A tries a wall gun from 5 m away: refused, points kept.
##  4. A and B (1000 each) use the same 750 door at once: one pays, the other is refused and keeps 1000.
## Host prints ECONOMY NET PASS; each client prints ECONOMY NET CLIENT OK (role) when the host leaves.

const SETTLE_S := 2.5
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
var zone: Zone
var door: BulkheadDoor
# host
var ids := {}                     # role -> peer id
var purchases: Array = []
var reports := {}                 # role -> latest report
var sent_report := false
# client
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
	Net.player_left.connect(func(id):
		if id == 1 and not done:
			done = true
			if final_sent:
				print("ECONOMY NET CLIENT OK (%s)" % role)
				get_tree().quit(0)
			else:
				print("ECONOMY NET FAIL (%s): host left before the final report" % role)
				get_tree().quit(1))
	if role == "host":
		eco.purchase.connect(func(p, what, cost): purchases.append([p, what, cost]))
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
	var near := WallBuy.new()
	near.name = "Near"
	near.weapon_id = &"hornet"
	near.position = SPAWN + Vector3(1, 1, 0)
	add_child(near)
	var far := WallBuy.new()
	far.name = "Far"
	far.weapon_id = &"sentinel_45"
	far.position = SPAWN + Vector3(0, 1, 5)
	add_child(far)
	zone = Zone.new()
	zone.name = "Lab"
	zone.zone_id = &"lab"
	add_child(zone)
	door = load("res://mapkit/bulkhead_door.tscn").instantiate()
	door.name = "Door"
	door.cost = 750
	door.unlocks = [&"lab"]
	door.position = SPAWN + Vector3(0, -0.2, 1.8)
	add_child(door)

func _fail(msg: String) -> void:
	print("ECONOMY NET FAIL (%s): %s" % [role, msg])
	done = true
	get_tree().quit(1)

func _go(p: String) -> void:
	phase = p
	phase_t = t
	print("ECONOMY (%s) phase %s t=%.1f" % [role, p, t])

# ------------------------------------------------------------------ host
func _peer(r: String) -> int:
	return ids[r]

func _cmd_to(r: String, c: String) -> void:
	Net.send_reliable(self, &"_cmd", _peer(r), [c])

func _check(cond: bool, msg: String) -> bool:
	if not cond:
		_fail(msg)
	return cond

func _host_step() -> void:
	var age := t - phase_t
	match phase:
		"wait":
			if ids.size() == 2 and net.players.size() == 3 and age > 1.5:
				if not _check(eco.wallet(_peer("a")).points == 500 and eco.wallet(_peer("b")).points == 500, "start points"):
					return
				eco.wallet(_peer("a")).add(500, false)
				_cmd_to("a", "use_near")
				_go("s1")
		"s1":
			if age > SETTLE_S:
				var a := _peer("a")
				if not (_check(eco.wallet(a).points == 0, "s1 host points %d" % eco.wallet(a).points)
						and _check(svc.state_for(a).data.id == &"hornet", "s1 host weapon")
						and _check(purchases == [[a, &"hornet", 1000]], "s1 purchase %s" % str(purchases))):
					return
				_ask("a", "s1")
				_go("s1r")
		"s1r":
			if reports.has("a") and reports["a"].step == "s1":
				var r: Dictionary = reports["a"]
				if not _check(r.points == 0 and r.weapon == "hornet" and r.mag == 32 and r.reserve == 192, "s1 client view %s" % str(r)):
					return
				var a := _peer("a")
				svc.state_for(a).mag = 1
				svc.state_for(a).reserve = 0
				eco.wallet(a).add(500, false)
				_cmd_to("a", "use_near")
				_go("s2")
			elif age > 10.0:
				_fail("no s1 report")
		"s2":
			if age > SETTLE_S:
				var a := _peer("a")
				var st := svc.state_for(a)
				if not (_check(eco.wallet(a).points == 0, "s2 ammo cost not taken: %d" % eco.wallet(a).points)
						and _check(st.mag == st.data.mag and st.reserve == st.data.reserve, "s2 ammo not refilled")
						and _check(purchases.size() == 2 and purchases[1] == [a, &"ammo_hornet", 500], "s2 purchase %s" % str(purchases))):
					return
				_ask("a", "s2")
				_go("s2r")
		"s2r":
			if reports.has("a") and reports["a"].step == "s2":
				var r: Dictionary = reports["a"]
				if not _check(r.points == 0 and r.weapon == "hornet" and r.mag == 32 and r.reserve == 192, "s2 client view %s" % str(r)):
					return
				eco.wallet(_peer("a")).add(1000, false)
				_cmd_to("a", "use_far")
				_go("s3")
		"s3":
			if age > SETTLE_S:
				var a := _peer("a")
				if not (_check(eco.wallet(a).points == 1000, "s3 points changed by a far buy: %d" % eco.wallet(a).points)
						and _check(svc.state_for(a).data.id == &"hornet", "s3 weapon changed")
						and _check(purchases.size() == 2, "s3 purchase happened")):
					return
				_ask("a", "s3")
				_go("s3r")
		"s3r":
			if reports.has("a") and reports["a"].step == "s3":
				var r: Dictionary = reports["a"]
				if not _check(r.denied == "far" and r.denied_count == 1 and r.points == 1000 and r.weapon == "hornet", "s3 client view %s" % str(r)):
					return
				eco.wallet(_peer("b")).add(500, false)
				_cmd_to("a", "use_door")
				_cmd_to("b", "use_door")
				_go("s4")
		"s4":
			if age > SETTLE_S + 1.0:
				var a := _peer("a")
				var b := _peer("b")
				var pa: int = eco.wallet(a).points
				var pb: int = eco.wallet(b).points
				var doors := purchases.filter(func(p): return p[1] == &"door")
				if not (_check(door.is_open and zone.open and door.link.enabled, "s4 door not open on host")
						and _check(doors.size() == 1 and doors[0][2] == 750, "s4 purchases %s" % str(purchases))
						and _check((pa == 250 and pb == 1000) or (pa == 1000 and pb == 250), "s4 points a=%d b=%d" % [pa, pb])):
					return
				print("ECONOMY door race: %s paid; a=%d b=%d" % ["a" if pa == 250 else "b", pa, pb])
				_ask("a", "s4")
				_ask("b", "s4")
				_go("s4r")
		"s4r":
			if reports.has("a") and reports.has("b") and reports["a"].step == "s4" and reports["b"].step == "s4":
				var ra: Dictionary = reports["a"]
				var rb: Dictionary = reports["b"]
				var a_paid: bool = eco.wallet(_peer("a")).points == 250
				var loser: Dictionary = rb if a_paid else ra
				var winner: Dictionary = ra if a_paid else rb
				if not (_check(ra.door and ra.zone and rb.door and rb.zone, "s4 clients do not see the door open: %s %s" % [str(ra), str(rb)])
						and _check(winner.points == 250 and winner.denied != "already_open", "s4 winner view %s" % str(winner))
						and _check(loser.points == 1000 and loser.denied == "already_open", "s4 loser view %s" % str(loser))):
					return
				print("ECONOMY NET DOOR OK")
				_go("finish")
			elif age > 10.0:
				_fail("no s4 reports")
		"finish":
			if age > 1.5:
				print("ECONOMY NET PASS")
				done = true
				get_tree().quit(0)

func _ask(r: String, step: String) -> void:
	reports.erase(r)
	_cmd_to(r, "report:" + step)

@rpc("any_peer", "reliable")
func _hello(r: String) -> void:
	if Net.is_host():
		ids[r] = multiplayer.get_remote_sender_id()

@rpc("any_peer", "reliable")
func _rep(r: String, d: Dictionary) -> void:
	if Net.is_host():
		reports[r] = d

# ------------------------------------------------------------------ client
@rpc("authority", "reliable")
func _cmd(c: String) -> void:
	if Net.is_host():
		return
	if c == "use_near":
		eco.use_local(get_node("Near"))
	elif c == "use_far":
		eco.use_local(get_node("Far"))
	elif c == "use_door":
		eco.use_local(get_node("Door"))
	elif c.begins_with("report:"):
		var me := net.local_player()
		var st := svc.state_for(Net.local_id())
		var d := {"step": c.substr(7), "points": me.points, "weapon": String(st.data.id), "mag": st.mag, "reserve": st.reserve,
			"denied": String(eco.last_denied), "denied_count": eco.denied_count, "door": door.is_open, "zone": zone.open}
		print("ECONOMY (%s) report %s" % [role, str(d)])
		final_sent = c == "report:s4"
		_rep.rpc_id(1, role, d)

func _physics_process(dt: float) -> void:
	if done:
		return
	t += dt
	frames += 1
	if t > 90.0:
		_fail("timeout phase=%s" % phase)
		return
	if role == "host":
		_host_step()
	elif not sent_report and net.local_player() != null and frames > 30:
		sent_report = true
		_hello.rpc_id(1, role)
