extends Node
## Multi-process net test. Roles: host | client (--idx=1..3 joiners, 5 = extra that must be refused).
## Host prints BASIC NET PASS when: claim of host id rejected + own id accepted, one refusal, a leave seen.

var role := ""
var idx := 0
var port := 26100
var bp := 7800
var left_seen := 0
var joined_seen := 0
var refused_reason := ""
var claim_sent := false
var beacon: LanBeacon
var beacon_found := false
var t := 0.0
var done := false

func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return def

func _ready() -> void:
	role = _arg("role", "host")
	idx = int(_arg("idx", "0"))
	port = int(_arg("port", "26100"))
	bp = int(_arg("bp", "7800"))
	Net.beacon_port = bp
	Net.player_joined.connect(func(_id): joined_seen += 1)
	Net.player_left.connect(func(_id): left_seen += 1)
	Net.join_refused.connect(func(r): refused_reason = r)
	if role == "host":
		var e := Net.host(port)
		if e != OK:
			_fail("host failed %d" % e)
	else:
		if idx == 1:
			beacon = LanBeacon.new()
			add_child(beacon)
			beacon.start_listen(bp)
			beacon.found.connect(func(_ip, p, _n, _pl): beacon_found = (p == port))
		var e := Net.join("127.0.0.1", port)
		if e != OK:
			_fail("join failed %d" % e)

func _claims_ok() -> bool:
	for s in Net.debug_claims:
		var l: Array = Net.debug_claims[s]
		if l.has("rejected:1") and l.has("accepted:%d" % s):
			return true
	return false

func _fail(msg: String) -> void:
	print("BASIC NET FAIL (%s %d): %s" % [role, idx, msg])
	get_tree().quit(1)

func _ok(msg: String) -> void:
	print("BASIC NET CLIENT OK (%d): %s" % [idx, msg])
	get_tree().quit(0)

func _process(dt: float) -> void:
	if done:
		return
	t += dt
	if role == "host":
		if t > 60.0:
			_fail("timeout ids=%d claims=%s refused=%d left=%d" % [Net.players.ids().size(), str(Net.debug_claims), Net.refused_count, left_seen])
		elif Net.refused_count >= 1 and left_seen >= 1 and _claims_ok():
			done = true
			print("BASIC NET PASS")
			get_tree().quit(0)
		return
	# clients
	if idx == 5:
		if refused_reason == "full":
			done = true
			_ok("refused full")
		elif t > 30.0:
			_fail("not refused, reason='%s'" % refused_reason)
		return
	if t > 60.0:
		_fail("timeout ids=%d left=%d" % [Net.players.ids().size(), left_seen])
		return
	if Net.players.ids().size() == 4 and not claim_sent:
		claim_sent = true
		if idx == 2:
			Net.rpc_id(1, "debug_claim", 1)
			Net.rpc_id(1, "debug_claim", Net.local_id())
		if idx == 3:
			get_tree().create_timer(14.0).timeout.connect(func():
				done = true
				Net.leave()
				_ok("left"))
	if idx == 1 and left_seen >= 1 and not beacon_found and t > 20.0:
		_fail("no beacon heard")
	elif left_seen >= 1 and idx != 3 and (idx != 1 or beacon_found):
		done = true
		_ok("saw player_left, ids=%d" % Net.players.ids().size())
