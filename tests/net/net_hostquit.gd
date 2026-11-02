extends Node
## Final-review I1: the host quits mid-round and the client must go back to the menu ("The host left the game.").
## The REAL game (scenes/game.tscn). Roles: host | a. The host starts the match, waits for round 1, then leaves and quits.
## Client a connects GameRoot.leave_requested (main.gd goes to the menu from it) and prints
## HOSTQUIT NET CLIENT OK (a) only when it fires with that reason while the game was PLAYING. The runner checks the 3 s limit.

var role := ""
var port := 26100
var game: GameRoot
var t := 0.0
var done := false
var started := false
var round_at := -1.0

func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return def

func _ready() -> void:
	role = _arg("role", "host")
	port = int(_arg("port", "26100"))
	Net.beacon_port = 0
	if role == "host":
		if Net.host(port) != OK:
			_fail("host failed")
			return
		_enter_game()
	else:
		if Net.join("127.0.0.1", port) != OK:
			_fail("join failed")
			return
		Net.session_ready.connect(_enter_game, CONNECT_ONE_SHOT)
		Net.join_failed.connect(func(): _fail("join failed"))

func _enter_game() -> void:
	game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	if role != "host":
		game.leave_requested.connect(_on_leave)

func _on_leave(reason: String) -> void:
	if done:
		return
	done = true
	if reason == "The host left the game." and game.state == GameRoot.PLAYING:
		print("HOSTQUIT NET CLIENT OK (%s)" % role)
		get_tree().quit(0)
	else:
		_fail("left with reason '%s' state %d" % [reason, game.state])

func _fail(why: String) -> void:
	print("HOSTQUIT NET FAIL (%s): %s" % [role, why])
	get_tree().quit(1)

func _process(dt: float) -> void:
	if done or game == null:
		return
	t += dt
	if role != "host":
		if t > 90.0:
			_fail("host never left")
		return
	if not started:
		if Net.ready_peers().size() >= 1:
			started = true
			game.start_match()
		elif t > 40.0:
			_fail("client never became ready")
		return
	if game.mt.round >= 1 and game.zs.live_count() > 0:
		if round_at < 0.0:
			round_at = t
		elif t - round_at > 1.5:
			done = true
			print("HOSTQUIT NET HOST QUITTING (round %d)" % game.mt.round)
			Net.leave()
			get_tree().quit(0)
	elif t > 60.0:
		_fail("round 1 never started")
