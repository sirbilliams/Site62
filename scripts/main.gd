extends Node3D

func _ready() -> void:
	# --test=* and --smoke=* are developer hooks: only in debug builds (editor / debug export) or the "smoke" feature export
	for a in (OS.get_cmdline_user_args() if OS.is_debug_build() else PackedStringArray()):
		if a == "--test=basic":
			add_child(load("res://tests/net/net_basic.gd").new())
			return
		if a == "--test=move":
			add_child(load("res://tests/net/net_move.gd").new())
			return
		if a == "--test=economy":
			add_child(load("res://tests/net/net_economy.gd").new())
			return
		if a == "--test=zombie":
			add_child(load("res://tests/net/net_zombie.gd").new())
			return
		if a == "--test=kit":
			add_child(load("res://tests/net/net_kit.gd").new())
			return
		if a == "--test=match":
			add_child(load("res://tests/net/net_match.gd").new())
			return
		if a == "--test=machines":
			add_child(load("res://tests/net/net_machines.gd").new())
			return
		if a == "--test=powerups":
			add_child(load("res://tests/net/net_powerups.gd").new())
			return
		if a == "--test=life":
			add_child(load("res://tests/net/net_life.gd").new())
			return
		if a == "--test=latejoin":
			add_child(load("res://tests/net/net_latejoin.gd").new())
			return
		if a == "--test=noready":
			add_child(load("res://tests/net/net_noready.gd").new())
			return
		if a == "--test=soak":
			add_child(load("res://tests/net/net_soak.gd").new())
			return
		if a == "--test=hostquit":
			add_child(load("res://tests/net/net_hostquit.gd").new())
			return
		if a == "--test=gameover":
			add_child(load("res://tests/net/net_gameover.gd").new())
			return
		if a == "--test=shoot":
			add_child(load("res://tests/net/net_shoot.gd").new())
			return
	_start_ui()

# ---------------------------------------------------------------- the game: menu -> lobby -> play

var _menu_layer: CanvasLayer
var _menu: MainMenu
var _settings: SettingsScreen
var _game: GameRoot
var _smoke_path := ""
var _smoke_bot: RefCounted

func _start_ui() -> void:
	Settings.load_file()
	Settings.apply_all()
	_menu_layer = CanvasLayer.new()
	_menu_layer.name = "Menus"
	add_child(_menu_layer)
	_menu = (load("res://ui/main_menu.tscn") as PackedScene).instantiate()
	_menu.host_requested.connect(_host)
	_menu.join_requested.connect(_join)
	_menu.settings_requested.connect(func():
		_menu.visible = false
		_settings.visible = true)
	_menu.quit_requested.connect(func(): get_tree().quit())
	_menu_layer.add_child(_menu)
	_settings = (load("res://ui/settings_screen.tscn") as PackedScene).instantiate()
	_settings.visible = false
	_settings.closed.connect(func():
		_settings.visible = false
		_menu.visible = true)
	_menu_layer.add_child(_settings)
	Net.join_refused.connect(func(why): _back_to_menu("The host refused the connection (%s)." % why))
	Net.join_failed.connect(func(): _back_to_menu("Could not reach the host."))
	Net.host_lost.connect(func(): _back_to_menu("The host left the game."))
	for a in (OS.get_cmdline_user_args() if (OS.is_debug_build() or OS.has_feature("smoke")) else PackedStringArray()):
		if a.begins_with("--smoke="):
			_smoke_path = a.substr(8)
			_smoke.call_deferred()

func _host() -> void:
	var err := Net.host(GameRoot.PORT)
	if err != OK:
		_menu.set_status("Could not host on port %d (error %d). Is another game running?" % [GameRoot.PORT, err])
		return
	_enter_game()

func _join(ip: String, port: int) -> void:
	_menu.set_status("Connecting to %s:%d ..." % [ip, port])
	if Net.join(ip, port) != OK:
		_menu.set_status("Could not start the connection.")
		return
	if not Net.session_ready.is_connected(_enter_game):
		Net.session_ready.connect(_enter_game, CONNECT_ONE_SHOT)

func _enter_game() -> void:
	if _game != null:
		return
	_menu.visible = false
	_game = (load("res://scenes/game.tscn") as PackedScene).instantiate()
	_game.leave_requested.connect(_back_to_menu)
	add_child(_game)

var _leaving := false

func _back_to_menu(reason := "") -> void:
	if _leaving:                                      # Net.leave() emits player_left, which can ask to leave again
		return
	_leaving = true
	if Net.session_ready.is_connected(_enter_game):
		Net.session_ready.disconnect(_enter_game)
	Net.leave()
	if _game != null:
		_game.queue_free()
		_game = null
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_settings.visible = false
	_menu.visible = true
	_menu.set_status(reason)
	_leaving = false

## Manual smoke check (tools/vrun.sh, tools/smoke_build.sh): host, press Start, wait for round `--smoke_round=N` (default 1)
## with zombies, save a screenshot, quit. `--smoke_bot` lets the scripted SoakBot play the host (real input frames) so a
## solo run can clear round 1.
func _smoke() -> void:
	Net.beacon_port = 0
	var want_round := 1
	var bot := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--smoke_round="):
			want_round = int(a.substr(14))
		elif a == "--smoke_bot":
			bot = true
	_host()
	await get_tree().create_timer(1.5).timeout
	if bot:
		_smoke_bot = load("res://tests/net/soak_bot.gd").new(_game)       # kept in a member: a Callable does not keep its RefCounted alive
		_game.net.input_source = _smoke_bot.frame
	_game.start_match()
	var waited := 0.0
	var next_log := 10.0
	while waited < 240.0 and not (_game.mt.round >= want_round and _game.zs.live_count() > 0):
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
		if waited >= next_log:
			next_log += 10.0
			var me := _game.net.local_player()
			print("SMOKE t=%ds round=%d zombies=%d hp=%s state=%s pos=%s" % [int(waited), _game.mt.round, _game.zs.live_count(), str(me.hp) if me else "-", str(me.state) if me else "-", str(me.position.snapped(Vector3.ONE * 0.1)) if me else "-"])
	await get_tree().create_timer(4.0).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(_smoke_path)
	print("SMOKE round=%d zombies=%d phase=%s saved=%s" % [_game.mt.round, _game.zs.live_count(), _game.mt.phase, _smoke_path])
	get_tree().quit(0 if _game.mt.round >= want_round and _game.zs.live_count() > 0 else 1)
