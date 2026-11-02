extends Node
## Full-match soak: the REAL game (scenes/game.tscn on Site 62) on a host and 3 bot clients that join and send the
## ready handshake like players; every process also plays with a SoakBot (real InputFrames, the real InteractController).
## Roles: host | b1 | b2 | b3. --rtt_ms / --loss on every process (LinkSim), --maxround (default 8), --timeout (s).
## Every second each client reports round, points, doors and Suds (wall clock). The host checks the reports whose second is a
## multiple of 5: each field must equal a host value from the last LOOKBACK seconds; one failure is retried with the next report.
## Output: host prints SOAK PASS rounds=N (N >= 5), the number of agreement checks, bandwidth and the biggest zombie snapshot.

const LOOKBACK := 1.0
const MIN_ROUNDS := 5

var role := ""
var port := 26100
var max_round := 8
var timeout_s := 600.0
var game: GameRoot
var bot: SoakBot
var t0 := 0.0
var match_t := 0.0
var started := false
var finished := false
var ready_at := -1.0
var last_sec := 0
var hist := {}                 # field -> Array [[unix, key], ...] host values (changes only)
var checks := 0
var retries := 0
var pending_retry := {}        # client id -> true: its last 5 s check failed, next report decides
var last_report := {}          # client id -> last compared fields (for the failure message)
var bw_up := 0
var bw_down := 0
var bw_t := 0.0
var bw_secs := 0
var peak_up := 0
var peak_down := 0
var min_players := 99
var hits := {}
var rejects := {}

func _arg(key: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--%s=" % key):
			return a.substr(key.length() + 3)
	return def

func _ready() -> void:
	name = "Soak"
	role = _arg("role", "host")
	port = int(_arg("port", "26100"))
	max_round = int(_arg("maxround", "8"))
	timeout_s = float(_arg("timeout", "600"))
	Net.beacon_port = 0
	t0 = Time.get_unix_time_from_system()
	Net.player_left.connect(_on_left)
	if role == "host":
		if Net.host(port) != OK:
			_fail("host failed")
		_enter_game()
	else:
		if Net.join("127.0.0.1", port) != OK:
			_fail("join failed")
		Net.session_ready.connect(_enter_game, CONNECT_ONE_SHOT)
		Net.join_failed.connect(func(): _fail("join failed"))

func _enter_game() -> void:
	game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	add_child(game)
	game.zs.measure_snap = true
	game.svc.hit.connect(func(shooter, _t, _d, _h): hits[shooter] = hits.get(shooter, 0) + 1)
	game.svc.fire_rejected.connect(func(peer, why): rejects[str(peer, why)] = rejects.get(str(peer, why), 0) + 1)
	bot = SoakBot.new(game)
	game.net.input_source = bot.frame

func _fail(why: String) -> void:
	if finished:
		return
	finished = true
	print("SOAK FAIL (%s): %s" % [role, why])
	get_tree().quit(1)

func _on_left(id: int) -> void:
	if id == 1 and role != "host" and not finished:
		finished = true
		_print_bw()
		print("SOAK CLIENT OK (%s) bot_frames=%d shots=%d" % [role, bot.frames if bot else 0, bot.shots if bot else 0])
		get_tree().quit(0)

# ---------------------------------------------------------------- sampling

func _door_key() -> String:
	var open: Array = []
	for d: BulkheadDoor in get_tree().get_nodes_in_group(&"doors"):
		if d.is_open:
			open.append(String(d.name))
	open.sort()
	return ",".join(open)

func _fields() -> Dictionary:
	var ids: Array = game.net.players.keys()
	ids.sort()
	var pts: Array = []
	var suds: Array = []
	for id in ids:
		pts.append("%d:%d" % [id, game.net.players[id].points])
		var s: Array = Game.suds_of(id).ids()
		s.sort()
		suds.append("%d:%s" % [id, "+".join(s)])
	return {"round": str(game.mt.round), "points": " ".join(pts), "doors": _door_key(), "suds": " ".join(suds)}

func _record(now: float) -> void:
	var f := _fields()
	for k in f:
		var h: Array = hist.get(k, [])
		if h.is_empty() or h[h.size() - 1][1] != f[k]:
			h.append([now, f[k]])
			while h.size() > 2 and h[1][0] < now - 8.0:
				h.pop_front()
		hist[k] = h

## A host value for `field` that held at some moment in [t - LOOKBACK, t + 0.1] equals `key`.
func _held(field: String, key: String, t: float) -> bool:
	var h: Array = hist.get(field, [])
	for i in h.size():
		var start: float = h[i][0]
		var end: float = h[i + 1][0] if i + 1 < h.size() else INF
		if end >= t - LOOKBACK and start <= t + 0.1 and h[i][1] == key:
			return true
	return false

@rpc("any_peer", "reliable")
func _rx_report(t: float, f: Dictionary) -> void:
	if not Net.is_host() or finished:
		return
	var id := multiplayer.get_remote_sender_id()
	var is_check := int(t) % 5 == 0
	if not is_check and not pending_retry.has(id):
		return
	var bad: Array = []
	for k in ["round", "points", "doors", "suds"]:
		if not _held(k, str(f.get(k, "?")), t):
			bad.append("%s client=[%s] host=%s" % [k, f.get(k, "?"), str((hist.get(k, []) as Array).slice(-3))])
	if bad.is_empty():
		if is_check or pending_retry.has(id):
			checks += 1
		pending_retry.erase(id)
	elif pending_retry.has(id):
		_fail("peer %d disagrees after retry at t=%.1f: %s" % [id, t, " | ".join(bad)])
	elif is_check:
		pending_retry[id] = true
		retries += 1

# ---------------------------------------------------------------- bandwidth

func _bw_tick() -> void:
	var p := multiplayer.multiplayer_peer
	if not (p is ENetMultiplayerPeer) or (p as ENetMultiplayerPeer).host == null:
		return
	var h: ENetConnection = (p as ENetMultiplayerPeer).host
	var up := int(h.pop_statistic(ENetConnection.HOST_TOTAL_SENT_DATA))
	var down := int(h.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_DATA))
	if game == null or game.mt.round < 1:
		return
	bw_up += up
	bw_down += down
	bw_secs += 1
	peak_up = maxi(peak_up, up)
	peak_down = maxi(peak_down, down)

func _print_bw() -> void:
	var s := maxi(bw_secs, 1)
	print("SOAK BW (%s): up=%.0f B/s down=%.0f B/s peak_up=%d peak_down=%d over %d s" % [role, float(bw_up) / s, float(bw_down) / s, peak_up, peak_down, bw_secs])

# ---------------------------------------------------------------- loop

func _process(dt: float) -> void:
	if finished or game == null:
		return
	var now := Time.get_unix_time_from_system()
	var sec := int(now)
	if sec != last_sec:
		last_sec = sec
		_bw_tick()
		if sec % 5 == 0 and _arg("debug", "") != "" and bot != null and game.mt.round >= 1:
			var me := game.net.local_player()
			if role == "host":
				var zl: Array = []
				for z: Zombie in game.zs.zombies.values():
					zl.append("%s@%s a%d" % [z.name, str(z.position.snapped(Vector3.ONE * 0.1)), int(z.anim)])
				print("SOAK zdbg ", " ".join(zl.slice(0, 8)))
			print("SOAK dbg %s r=%d z=%d branch=%s pos=%s goal=%s mag=%d/%d st=%d shots=%d pts=%d path=%d wp=%s stuck=%.1f" % [role, game.mt.round, game.zs.live_count(), bot.branch, str(me.position.snapped(Vector3.ONE * 0.1)), str(bot.goal_dbg), bot.g.svc.state_for(Net.local_id()).mag, bot.g.svc.state_for(Net.local_id()).reserve, me.state, bot.shots, me.points, bot._path.size(), str(bot._path[1] if bot._path.size() > 1 else Vector3.ZERO), bot._stuck_t])
		if game.mt.round >= 1:
			if role != "host":
				Net.send_reliable(self, &"_rx_report", 1, [now, _fields()])
	if role == "host":
		_host_loop(now, dt)

func _host_loop(now: float, dt: float) -> void:
	if game.mt.round >= 1:
		_record(now)
	min_players = mini(min_players, game.net.players.size()) if started else min_players
	if not started:
		if Net.ready_peers().size() >= 3 and game.state == GameRoot.LOBBY:
			if ready_at < 0.0:
				ready_at = now
			elif now - ready_at > 1.0:
				started = true
				match_t = now
				game.start_match()
		elif now - t0 > 60.0:
			_fail("clients did not join (%d ready)" % Net.ready_peers().size())
		return
	var elapsed := now - match_t
	var over := game.ms.game_over or game.state == GameRoot.OVER
	var done := game.mt.round >= max_round or over or elapsed > timeout_s
	if elapsed > 1.0 and int(elapsed) % 20 == 0 and int(elapsed) != int(elapsed - dt):
		print("SOAK t=%ds round=%d zombies=%d checks=%d players=%s" % [int(elapsed), game.mt.round, game.zs.live_count(), checks, _fields()["points"]])
	if not done:
		return
	_finish(over, elapsed)

func _finish(over: bool, elapsed: float) -> void:
	finished = true
	var rounds: int = game.mt.round
	_print_bw()
	print("SOAK hits=%s rejects=%s" % [str(hits), str(rejects)])
	print("SOAK stats (host): %s" % str(game.ms.final_stats if not game.ms.final_stats.is_empty() else game.ms.stats))
	print("SOAK zombie snapshot: max=%d bytes (%d zombies), per-client downlink includes it" % [game.zs.max_snap_bytes, game.zs.max_snap_zombies])
	print("SOAK agreement checks=%d retries=%d elapsed=%ds game_over=%s link=rtt %s ms loss %s" % [checks, retries, int(elapsed), str(over), _arg("rtt_ms", "0"), _arg("loss", "0")])
	var ok := rounds >= MIN_ROUNDS and checks >= 3
	if ok:
		print("SOAK PASS rounds=%d" % rounds)
	else:
		print("SOAK FAIL (host): rounds=%d checks=%d" % [rounds, checks])
	await get_tree().create_timer(1.0).timeout
	get_tree().quit(0 if ok else 1)
