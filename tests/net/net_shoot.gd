extends Node3D
## Multi-process shooting test (run with --rtt_ms=150 on every process). Roles: host | a (shooter).
## A fires at the dummy it SEES moving; the host must record the hit (lag compensation: the live dummy
## is far from the rewound pose). Then A is made to violate sender / rate / line of sight / ammo rules.
## Host prints SHOOT NET PASS once it saw every expected hit and rejection.

var role := ""
var port := 26100
var rtt_ms := 0.0
var net: PlayerNet
var svc: WeaponService
var t := 0.0
var done := false
# host
var hits: Array = []              # [shooter, target, dmg, head]
var reasons := {}                 # reason -> count
var body_live_gap := 0.0          # |live dummy x - rewound x| at the body hit
var finish_t := -1.0
# client (a)
var phase := "wait"
var phase_t := 0.0
var result: Dictionary = {}       # last verdict
var results_seen: Array = []
var host_gone := false
var reported := false

func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return def

func _ready() -> void:
	role = _arg("role", "host")
	port = int(_arg("port", "26100"))
	rtt_ms = float(_arg("rtt_ms", "0"))
	Net.beacon_port = 0
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(400, 2, 400)
	cs.shape = box
	cs.position.y = -1.0
	floor_body.add_child(cs)
	add_child(floor_body)
	# wall at z=-6 covering x in [3, 33]: hides the dummy when it is at x > 5
	var wall := StaticBody3D.new()
	wall.collision_layer = 1
	var wcs := CollisionShape3D.new()
	var wb := BoxShape3D.new()
	wb.size = Vector3(30, 4, 0.4)
	wcs.shape = wb
	wall.position = Vector3(18, 2, -6)
	wall.add_child(wcs)
	add_child(wall)
	net = PlayerNet.new()
	net.name = "PlayerNet"
	net.input_source = func(): return InputFrame.new()
	add_child(net)
	svc = WeaponService.new()
	svc.name = "WeaponService"
	svc.net = net
	add_child(svc)
	Net.player_left.connect(func(id):
		if id == 1 and not done:
			done = true
			host_gone = true
			if reported:
				print("SHOOT NET CLIENT OK (%s)" % role)
				get_tree().quit(0)
			else:
				print("SHOOT NET FAIL (%s): host left before phases finished (phase %s)" % [role, phase])
				get_tree().quit(1))
	if role == "host":
		svc.spawn_dummy()
		svc.hit.connect(_on_hit)
		svc.fire_rejected.connect(func(_s, r): reasons[r] = reasons.get(r, 0) + 1)
		if Net.host(port) != OK:
			_fail("host failed")
	else:
		svc.result_received.connect(func(rt, kind, reason, target, dmg, head):
			result = {"t": rt, "kind": kind, "reason": reason, "target": target, "dmg": dmg, "head": head}
			results_seen.append(result))
		if Net.join("127.0.0.1", port) != OK:
			_fail("join failed")

func _fail(msg: String) -> void:
	print("SHOOT NET FAIL (%s): %s" % [role, msg])
	get_tree().quit(1)

# ------------------------------------------------------------------ host
func _on_hit(shooter: int, target: int, dmg: float, head: bool) -> void:
	hits.append([shooter, target, dmg, head])
	if not head and body_live_gap == 0.0 and svc.dummy != null:
		var rew = svc.history.pose_at(target, svc.last_rewind.time)
		if rew != null:
			body_live_gap = absf(svc.dummy.global_position.x - (rew as Transform3D).origin.x)
	print("SHOOT host hit shooter=%d target=%d dmg=%.1f head=%s gap=%.2f" % [shooter, target, dmg, str(head), body_live_gap])

func _host_check() -> void:
	if finish_t >= 0.0:
		if t - finish_t > 1.5:
			print("SHOOT NET PASS")
			get_tree().quit(0)
		return
	var body := hits.filter(func(h): return not h[3])
	var head := hits.filter(func(h): return h[3])
	for r in [&"sender", &"rate", &"los", &"ammo"]:
		if not reasons.has(r):
			return
	if body.is_empty() or head.is_empty():
		return
	if hits.any(func(h): return h[0] == 1):
		_fail("host shot attributed to wrong shooter")
		return
	if absf(body[0][2] - 28.0) > 0.01:
		_fail("body damage %.2f != 28" % body[0][2])
		return
	if absf(head[0][2] - 56.0) > 0.01:
		_fail("head damage %.2f != 56" % head[0][2])
		return
	if rtt_ms >= 100.0 and body_live_gap < 0.3:
		_fail("lag compensation not exercised: live/rewound gap only %.2f m" % body_live_gap)
		return
	print("SHOOT host ok: hits=%d reasons=%s gap=%.2f" % [hits.size(), str(reasons), body_live_gap])
	finish_t = t

# ------------------------------------------------------------------ client
func _dummy_x() -> float:
	return svc.dummy.position.x if svc.dummy != null else INF

func _aim_at(local_off: Vector3) -> Vector3:
	var me := net.local_player()
	return ((svc.dummy.position + local_off) - svc.eye_of(me)).normalized()

func _go(p: String) -> void:
	phase = p
	phase_t = t
	result = {}
	sent = false
	print("SHOOT (a) phase %s" % p)

func _client_step() -> void:
	var me := net.local_player()
	var ready := me != null and me.last_ack >= 0 and svc.dummy != null and Net.players.ids().size() == 2
	var age := t - phase_t
	var got := not result.is_empty()
	match phase:
		"wait":
			if ready and t > 4.0:       # clock model + rtt need a few seconds
				_go("body")
		"body", "head":
			var off := Vector3(0, 0.8, 0) if phase == "body" else Vector3(0, 1.8, 0)
			var tol := 0.3 if phase == "body" else 0.12
			if not sent:
				if age > 0.0 and absf(_dummy_x()) < tol and svc.fire_local(_aim_at(off)):
					_sent()
			elif got:
				if result.kind == WeaponService.HIT and result.head == (phase == "head"):
					_go("head" if phase == "body" else "sender")
				else:
					_retry(0.4)                # miss or wrong part: wait a bit, retry
			elif age > 1.6:
				_retry(0.0)                    # verdict lost
		"sender":
			if not sent:
				svc.request_fire.rpc_id(1, 1, svc.eye_of(me), Vector3.UP, WeaponService.now_s())
				_sent()
			elif got and result.reason == &"sender":
				_go("rate")
			elif got or age > 1.0:
				_retry(0.0)
		"rate":
			if not sent:
				if age > 0.5:
					for i in 3:      # raw requests: a cheating client skips its own rate limit
						svc.request_fire.rpc_id(1, Net.local_id(), svc.eye_of(me), Vector3.UP, WeaponService.now_s())
					_sent()
					results_seen.clear()
			elif results_seen.any(func(r): return r.reason == &"rate"):
				_go("wall")
			elif age > 1.5:
				_retry(0.0)
		"wall":
			if not refilled:
				refilled = true
				_refill_host.rpc_id(1)
				phase_t = t
			elif not sent:
				svc.state_for(Net.local_id()).refill()       # mirror of the host refill
				if age > 0.5 and _dummy_x() > 7.0 and _dummy_x() < 9.5 and svc.fire_local(_aim_at(Vector3(0, 0.8, 0))):
					_sent()
			elif got and result.reason == &"los":
				_go("empty")
			elif got or age > 1.6:
				_retry(0.0)
		"empty":
			if age > 0.4:
				phase_t = t
				svc.state_for(Net.local_id()).refill()       # keep sending so the host can say "ammo"
				svc.fire_local(Vector3.UP)
			if results_seen.any(func(r): return r.reason == &"ammo"):
				reported = true
				print("SHOOT NET CLIENT DONE (a)")
				phase = "finished"

var sent := false
var refilled := false

func _sent() -> void:
	sent = true
	result = {}
	phase_t = t

func _retry(delay: float) -> void:
	sent = false
	result = {}
	phase_t = t + delay

@rpc("any_peer", "reliable")
func _refill_host() -> void:
	if Net.is_host():
		svc.state_for(multiplayer.get_remote_sender_id()).refill()

func _physics_process(dt: float) -> void:
	if done:
		return
	t += dt
	if t > 70.0:
		_fail("timeout phase=%s hits=%s reasons=%s" % [phase, str(hits), str(reasons)])
		return
	if role == "host":
		_host_check()
	else:
		_client_step()
