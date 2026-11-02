extends Node
## Final-review I2: game over ends the match on the host. The REAL game (scenes/game.tscn). Roles: host | e | f.
##  - e joins in the lobby but builds its game scene late (after the game ended): its snapshot must carry game_over + stats,
##    so it lands on the summary (GameRoot.OVER) instead of watching frozen players.
##  - host: after game over the match is stopped (no director, no live zombies, no new round), joins are closed, and f,
##    who connects afterwards, is refused with "over".
## Host prints GAMEOVER NET OVER once the game ended and GAMEOVER NET PASS at the end; e and f print GAMEOVER NET CLIENT OK (role).

const E_DELAY := 12.0

var role := ""
var port := 26100
var game: GameRoot
var t := 0.0
var done := false
var started := false
var over_at := -1.0
var round_at_over := -1
var entered := false
var join_at := -1.0
var refused := false

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
		Net.join_failed.connect(func(): _fail("join failed"))
		if role == "f":
			Net.session_ready.connect(func(): _fail("f was let in after game over"))
			Net.join_refused.connect(func(why):
				if why == "over":
					print("GAMEOVER NET CLIENT OK (f)")
					get_tree().quit(0)
				else:
					_fail("refused with '%s'" % why))
		else:
			Net.session_ready.connect(func(): join_at = t, CONNECT_ONE_SHOT)

func _enter_game() -> void:
	entered = true
	game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)

func _fail(why: String) -> void:
	if done:
		return
	done = true
	print("GAMEOVER NET FAIL (%s): %s" % [role, why])
	get_tree().quit(1)

func _process(dt: float) -> void:
	if done:
		return
	t += dt
	if role == "f":
		if t > 60.0:
			_fail("not refused")
	elif role == "e":
		_client_loop()
	else:
		_host_loop()

func _client_loop() -> void:
	if not entered:
		if join_at >= 0.0 and t - join_at > E_DELAY:
			_enter_game()
		elif t > 60.0:
			_fail("never joined")
		return
	if game.ms.game_over:
		if game.state != GameRoot.OVER or not game.ms.final_stats.has(1) or not game.game_over.visible:
			_fail("game_over set but state %d stats %s visible %s" % [game.state, str(game.ms.final_stats), str(game.game_over.visible)])
			return
		done = true
		print("GAMEOVER NET CLIENT OK (e)")
		get_tree().quit(0)
	elif t - join_at > E_DELAY + 15.0:
		_fail("snapshot never carried game over (state %d round %d)" % [game.state, game.mt.round])

func _host_loop() -> void:
	if not started:
		if Net.players.ids().size() >= 2 and t > 2.0:
			started = true
			game.start_match()
		elif t > 40.0:
			_fail("e never joined")
		return
	if over_at < 0.0:
		if game.mt.round >= 1 and game.zs.live_count() > 0:
			round_at_over = game.mt.round
			for p: Player in game.net.players.values():
				p.state = Player.DEAD
			game.ms._check_game_over()
			if not game.ms.game_over:
				_fail("game over did not trigger")
				return
			over_at = t
			var bad := ""
			if game.mt.running or game.mt.director != null:
				bad += " match still running;"
			if game.zs.live_count() != 0:
				bad += " %d zombies alive;" % game.zs.live_count()
			if Net.accepting:
				bad += " still accepting joins;"
			if bad != "":
				_fail("after game over:" + bad)
				return
			print("GAMEOVER NET OVER")
		elif t > 60.0:
			_fail("round 1 never ran")
		return
	var since := t - over_at
	if since > 6.0 and since < 6.1 and Net.refused_count < 1:
		_fail("f was not refused")
		return
	if since > E_DELAY + 8.0:
		if game.mt.round != round_at_over or game.zs.live_count() != 0:
			_fail("match kept going: round %d (was %d), %d zombies" % [game.mt.round, round_at_over, game.zs.live_count()])
			return
		done = true
		print("GAMEOVER NET PASS (refused=%d)" % Net.refused_count)
		Net.leave()
		get_tree().quit(0)
