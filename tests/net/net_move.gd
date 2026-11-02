extends Node3D
## Multi-process movement test (run with --rtt_ms=120 on every process).
## Roles: host | a (mover, holds forward 2 s) | b (observer, samples A's remote view).
## Host prints MOVE NET PASS when A's predicted pos is within 0.15 m of the host's after the last ack,
## and B's view of A is within 0.3 m of the host's A position delayed by 100 ms (+ one-way link delay).

const HOLD_S := 2.0
const SETTLE_S := 1.5

var role := ""
var port := 26100
var bp := 0
var rtt_ms := 0.0
var net: PlayerNet
var t := 0.0
var start_t := -1.0
var ready_t := -1.0
var first_joiner := -1
var done := false
var sent_final := false
var last_fwd_seq := -1
# host
var hist: Array = []              # [unix, Vector3] of A's host position
var a_final := Vector3.INF
var b_samples: Array = []
var b_received := false
var a_checked := false
var a_err := 0.0
# b
var samples: Array = []
var b_sent := false

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
	net = PlayerNet.new()
	net.name = "PlayerNet"
	add_child(net)
	if role == "a":
		net.input_source = _a_input
	else:
		net.input_source = func(): return InputFrame.new()
	Net.player_left.connect(func(id):
		if id == 1 and not done:
			done = true
			print("MOVE NET CLIENT OK (%s): host gone start_t=%.1f samples=%d pa=%s" % [role, start_t, samples.size(), str(net.players.get(_a_id()))])
			get_tree().quit(0))
	Net.player_joined.connect(func(id): if first_joiner < 0: first_joiner = id)
	if role == "host":
		if Net.host(port) != OK:
			_fail("host failed")
	elif Net.join("127.0.0.1", port) != OK:
		_fail("join failed")

func _a_input() -> InputFrame:
	var f := InputFrame.new()
	if start_t >= 0.0 and t - start_t < HOLD_S:
		f.move = Vector2(0, 1)
		last_fwd_seq = net._seq
	return f

func _fail(msg: String) -> void:
	print("MOVE NET FAIL (%s): %s" % [role, msg])
	get_tree().quit(1)

func _physics_process(_dt: float) -> void:
	if done:
		return
	t += _dt
	var ready3 := Net.players.ids().size() == 3
	if role == "host":
		var pa: Player = net.players.get(_a_id())
		if pa != null:
			hist.append([Time.get_unix_time_from_system(), pa.motor_state.pos])
		_host_check()
		if t > 50.0:
			_fail("timeout a_final=%s b_received=%s" % [str(a_final), str(b_received)])
		return
	if t > 50.0:
		_fail("timeout")
		return
	var me := net.local_player()
	if role == "a":
		if ready3 and ready_t < 0.0:
			ready_t = t
		if start_t < 0.0 and ready_t >= 0.0 and me != null and me.last_ack >= 0 and t - ready_t > 3.0:
			start_t = t
		if start_t >= 0.0 and not sent_final and t - start_t > HOLD_S + SETTLE_S:
			sent_final = true
			if me.last_ack < last_fwd_seq:
				_fail("last forward seq %d never acked (ack %d)" % [last_fwd_seq, me.last_ack])
				return
			_report_final.rpc_id(1, me.motor_state.pos)
			get_tree().create_timer(2.0).timeout.connect(func():
				done = true
				print("MOVE NET CLIENT OK (a)")
				get_tree().quit(0))
	elif role == "b":
		var pa: Player = net.players.get(_a_id())
		if pa != null and ready3:
			if samples.is_empty() and pa.position.distance_to(net.spawn) > 0.5:
				start_t = t
			if start_t >= 0.0 and t - start_t < HOLD_S + 0.8:
				samples.append([Time.get_unix_time_from_system(), pa.position])
			elif start_t >= 0.0 and not b_sent:
				b_sent = true
				_report_samples.rpc_id(1, samples)
				get_tree().create_timer(2.0).timeout.connect(func():
					done = true
					print("MOVE NET CLIENT OK (b, %d samples)" % samples.size())
					get_tree().quit(0))

## Peer ids are random. Host: A is the first joiner. B: the one non-host peer that isn't itself.
func _a_id() -> int:
	if role == "host":
		return first_joiner
	for id in Net.players.ids():
		if id != 1 and id != Net.local_id():
			return id
	return -1

@rpc("any_peer", "reliable")
func _report_final(pos: Vector3) -> void:
	if Net.is_host():
		a_final = pos

@rpc("any_peer", "reliable")
func _report_samples(s: Array) -> void:
	if Net.is_host():
		b_samples = s
		b_received = true

func _hist_at(ts: float) -> Vector3:
	for i in range(1, hist.size()):
		if hist[i][0] >= ts:
			var a: Array = hist[i - 1]
			var b: Array = hist[i]
			return (a[1] as Vector3).lerp(b[1], clampf((ts - a[0]) / maxf(b[0] - a[0], 1e-6), 0.0, 1.0))
	return Vector3.INF

func _host_check() -> void:
	if a_final == Vector3.INF or not b_received:
		return
	done = true
	var pa: Player = net.players[_a_id()]
	var moved: float = pa.motor_state.pos.distance_to(net.spawn)
	a_err = pa.motor_state.pos.distance_to(a_final)
	# B's view lags host by: interpolation delay (100 ms) + one-way link delay (rtt/2)
	var lag := 0.1 + rtt_ms / 2000.0
	var t0 := 0.0
	var t1 := 0.0
	for h in hist:
		if (h[1] as Vector3).distance_to(net.spawn) > 0.01:
			if t0 == 0.0:
				t0 = h[0]
			t1 = h[0]
	var worst := 0.0
	var n := 0
	for s in b_samples:
		var ref: float = s[0] - lag
		if ref < t0 + 0.2 or ref > t1:
			continue
		var hp: Vector3 = _hist_at(ref)
		if hp == Vector3.INF:
			continue
		worst = maxf(worst, (s[1] as Vector3).distance_to(hp))
		n += 1
	print("MOVE moved=%.2f a_err=%.3f b_worst=%.3f b_samples=%d" % [moved, a_err, worst, n])
	if moved < 6.0:
		_fail("A barely moved: %.2f" % moved)
	elif a_err > 0.15:
		_fail("A prediction error %.3f" % a_err)
	elif n < 20:
		_fail("too few comparable samples: %d" % n)
	elif worst > 0.3:
		_fail("B remote error %.3f" % worst)
	else:
		print("MOVE NET PASS")
		get_tree().quit(0)
