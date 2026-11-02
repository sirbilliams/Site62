extends Node3D
## A client that joins a RUNNING match and never sends `ready` (hung or hostile). Roles: host | x.
##  - x is a spectator at once (DEAD, not targetable by zombies), not ready, and no broadcast reaches it
##    (no zombies, no world state: its node never gets spammed).
##  - It does not count for game over: the host goes down and the match ends normally with x still connected.
## Host prints NOREADY NET PASS; x prints NOREADY NET CLIENT OK when the host leaves.

const SPAWN := Vector3(0, 0.2, -18)

var role := ""
var port := 26100
var net: PlayerNet
var svc: WeaponService
var zs: ZombieSync
var eco: EconomyService
var pu: PowerupService
var ms: MatchState
var mt: Match
var ws: WorldSnapshot
var t := 0.0
var done := false
var started := false
var report := {}
var reported := false

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
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200, 2, 200)
	cs.shape = box
	cs.position.y = -1.0
	floor_body.add_child(cs)
	add_child(floor_body)
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
	mt = Match.new()
	mt.name = "Match"
	mt.zombies = zs
	mt.economy = eco
	add_child(mt)
	pu = PowerupService.new()
	add_child(pu)
	pu.bind(net, zs, eco, svc, mt)
	ms = MatchState.new()
	add_child(ms)
	ms.bind(net, svc, eco, zs, pu, mt)
	ws = WorldSnapshot.new()
	add_child(ws)
	ws.bind(net, svc, eco, zs, pu, mt, ms)
	Net.player_left.connect(func(id):
		if id == 1 and not done:
			done = true
			print("NOREADY NET CLIENT OK (%s)" % role)
			get_tree().quit(0))
	if role == "host":
		zs.frozen = true
		if Net.host(port) != OK:
			_fail("host failed")
			return
		Net.require_ready = true
		mt.round = 3
		mt.phase = Match.PLAYING
		mt.running = true
		mt.director = RoundDirector.new()
		zs.spawn(SPAWN + Vector3(3, 0, 0), &"shambler", 100.0, 0)
	elif Net.join("127.0.0.1", port) != OK:
		_fail("join failed")
	# x deliberately never calls ws.announce_ready()

func _fail(msg: String) -> void:
	if done:
		return
	print("NOREADY NET FAIL (%s): %s" % [role, msg])
	done = true
	get_tree().quit(1)

func _ck(cond: bool, msg: String) -> bool:
	if not cond:
		_fail(msg)
	return cond and not done

@rpc("authority", "reliable")
func _cmd(_c: String) -> void:
	if Net.is_host():
		return
	var me := net.local_player()
	_rep.rpc_id(1, {"zombies": zs.zombies.size(), "round": mt.round, "state": me.state if me != null else -1})

@rpc("any_peer", "reliable")
func _rep(d: Dictionary) -> void:
	if Net.is_host():
		report = d

func _physics_process(dt: float) -> void:
	if done or role != "host":
		return
	t += dt
	if t > 60.0:
		_fail("timeout")
		return
	if not started and net.players.size() == 2 and t > 3.0:
		started = true
		_script()

func _script() -> void:
	var x := 0
	for id in net.players:
		if id != 1:
			x = id
	var px: Player = net.players[x]
	var ph: Player = net.players[1]
	if not _ck(px.state == Player.DEAD and not Net.is_ready(x) and Net.ready_peers().is_empty(), "x: spectator at once, not ready (state %d)" % px.state): return
	var z: Zombie = zs.zombies.values()[0]
	px.teleport(z.position + Vector3(0.5, 0, 0))              # x stands right next to the zombie
	if not _ck(z.brain._nearest(net.players) == ph, "the zombie must target the host, not x"): return
	Net.send_reliable(self, &"_cmd", x, ["report"])
	var w := 0.0
	while report.is_empty() and w < 8.0:
		await get_tree().create_timer(0.1).timeout
		w += 0.1
	if not _ck(not report.is_empty(), "no report from x"): return
	if not _ck(report.zombies == 0 and report.round == 0, "broadcasts reached a client that never said ready: %s" % str(report)): return
	ph.hp = 0.0
	await get_tree().create_timer(1.5).timeout
	if not _ck(ms.game_over, "host down, x connected but not ready -> game over"): return
	print("NOREADY NET PASS")
	await get_tree().create_timer(0.5).timeout
	done = true
	get_tree().quit(0)
