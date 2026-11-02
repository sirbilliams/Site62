class_name GameRoot
extends Node3D
## The playable game: Site 62 plus every service, wired in the same order on host and clients (RPC paths must match).
## Lobby -> playing (host presses Start, Match.start) -> game over. A joining client builds this scene first, then sends
## `ready` (WorldSnapshot.announce_ready); the host answers with the world state and the live zombies.

signal leave_requested(reason: String)

const PORT := 7862
const MAP := "res://maps/site62/site62.tscn"
enum { LOBBY, PLAYING, OVER }

var state := LOBBY
var map: Node3D
var net: PlayerNet
var svc: WeaponService
var zs: ZombieSync
var eco: EconomyService
var mt: Match
var pu: PowerupService
var ms: MatchState
var ws: WorldSnapshot
var interact: InteractController
var hud: Hud
var lobby: Lobby
var game_over: GameOver
var paused := false
var spectate_cam: Camera3D
var _spec_target := 0
var _spec_prev_fire := false
var _ui: CanvasLayer
var _pause: Control
var _resume: Button
var _settings: SettingsScreen
var _built := false

func _ready() -> void:
	name = "GameRoot"
	Settings.ensure_actions()
	Game.reset()
	map = (load(MAP) as PackedScene).instantiate()
	map.name = "Map"
	add_child(map)
	var spawn := Vector3(0, 0.2, 0)
	var starts := get_tree().get_nodes_in_group(&"player_starts")
	if not starts.is_empty():
		starts.sort_custom(func(a, b): return String(a.get_path()) < String(b.get_path()))
		spawn = (starts[0] as Node3D).global_position + Vector3(0, 0.1, 0)
	# the same order as the net tests: PlayerNet, WeaponService, ZombieSync, EconomyService, Match, PowerupService, MatchState, WorldSnapshot
	net = PlayerNet.new()
	net.name = "PlayerNet"
	net.spawn = spawn
	net.input_enabled = false
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
	interact = InteractController.new()
	interact.name = "Interact"
	add_child(interact)
	interact.bind(net, eco, svc, ms)
	spectate_cam = Camera3D.new()
	spectate_cam.name = "SpectateCam"
	add_child(spectate_cam)
	_build_ui()
	ms.game_over_reached.connect(_on_game_over)
	Net.player_left.connect(_on_left)
	_built = true
	if Net.is_host():
		lobby.set_host(true)
	else:
		ws.announce_ready()                         # the handshake: scene built, now send me the world
	_refresh_lobby()

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.name = "UI"
	add_child(_ui)
	hud = Hud.new()
	hud.visible = false
	_ui.add_child(hud)
	hud.bind(net, svc, eco, pu, mt, ms, interact)
	lobby = Lobby.new()
	lobby.start_pressed.connect(start_match)
	lobby.leave_pressed.connect(func(): leave_requested.emit(""))
	_ui.add_child(lobby)
	game_over = GameOver.new()
	game_over.visible = false
	game_over.back_pressed.connect(func(): leave_requested.emit(""))
	_ui.add_child(game_over)
	_pause = _build_pause()
	_pause.visible = false
	_ui.add_child(_pause)
	_settings = SettingsScreen.new()
	_settings.visible = false
	_settings.closed.connect(func():
		_settings.visible = false
		_pause.visible = true
		_resume.grab_focus())
	_ui.add_child(_settings)

func _build_pause() -> Control:
	var c := Control.new()
	c.theme = UiTheme.make()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0, 0.02, 0, 0.7)
	c.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.add_child(cc)
	var p := PanelContainer.new()
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.name = "Box"
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size = Vector2(420, 0)
	p.add_child(v)
	v.add_child(UiTheme.heading("PAUSED", 56, UiTheme.AMBER))
	v.add_child(UiTheme.body("The operation continues without you.", 18, UiTheme.DIM))
	for e in [["Resume", "RESUME", set_paused.bind(false)], ["Settings", "SETTINGS", func():
			_pause.visible = false
			_settings.visible = true], ["Leave", "LEAVE OPERATION", func(): leave_requested.emit("")]]:
		var b := Button.new()
		b.name = e[0]
		b.text = e[1]
		b.custom_minimum_size = Vector2(0, 54)
		b.pressed.connect(e[2])
		v.add_child(b)
		if e[0] == "Resume":
			_resume = b
	return c

# ---------------------------------------------------------------- flow

## Host: lobby -> playing.
func start_match() -> void:
	if not Net.is_host() or state != LOBBY:
		return
	mt.start(map)

func _on_game_over(stats: Dictionary) -> void:
	state = OVER
	game_over.show_stats(stats)
	game_over.visible = true
	hud.visible = false
	_pause.visible = false
	paused = false

func _on_left(id: int) -> void:
	if id == 1 and not Net.is_host():
		leave_requested.emit("The host left the game.")
	elif _built:
		_refresh_lobby()

func _refresh_lobby() -> void:
	var ids: Array = []
	for id in Net.players.ids():
		ids.append(id)
	lobby.refresh(ids)

func set_paused(p: bool) -> void:
	if state != PLAYING:
		return
	paused = p
	_pause.visible = p
	_settings.visible = false
	if p:
		_resume.grab_focus()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventJoypadButton or e is InputEventJoypadMotion:
		Settings.using_pad = true
	elif e is InputEventKey or e is InputEventMouseButton:
		Settings.using_pad = false
	var esc: bool = e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_ESCAPE
	var start: bool = e is InputEventJoypadButton and e.pressed and e.button_index == JOY_BUTTON_START
	# gamepad B is crouch in play, so only Esc / Start open the pause menu; B (ui_cancel) closes it
	if state == PLAYING and not _settings.visible and (esc or start or (paused and e.is_action_pressed(&"ui_cancel"))):
		set_paused(not paused)
		get_viewport().set_input_as_handled()

func _process(_dt: float) -> void:
	if not _built:
		return
	if state == LOBBY:
		_refresh_lobby()
		if mt.round >= 1 or ms.game_over:
			state = PLAYING if not ms.game_over else OVER
			lobby.visible = false
			hud.visible = state == PLAYING
	var playing := state == PLAYING and not paused
	var me := net.local_player()
	net.input_enabled = playing and me != null
	interact.enabled = playing
	hud.visible = state == PLAYING
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if playing else Input.MOUSE_MODE_VISIBLE
	_update_spectate(me, playing)

# ---------------------------------------------------------------- spectate

func _update_spectate(me: Player, playing: bool) -> void:
	var watching := me != null and me.state == Player.DEAD and state == PLAYING
	hud.spectating = watching
	if not watching:
		if spectate_cam.current and me != null and me.camera != null:
			me.camera.make_current()
		hud.spectate_name = ""
		return
	var cands: Array = []
	for id in net.players:
		var p: Player = net.players[id]
		if id != Net.local_id() and p.state != Player.DEAD:
			cands.append(id)
	cands.sort()
	var fire := playing and Input.is_action_pressed(&"fire")
	if fire and not _spec_prev_fire and not cands.is_empty():
		var i := cands.find(_spec_target)
		_spec_target = cands[(i + 1) % cands.size()]
	_spec_prev_fire = fire
	if not cands.has(_spec_target):
		_spec_target = cands[0] if not cands.is_empty() else 0
	if _spec_target == 0:
		hud.spectate_name = ""
		return
	var t: Player = net.players[_spec_target]
	spectate_cam.global_position = t.global_position + Vector3(0, Player.EYE_HEIGHT, 0)
	spectate_cam.global_rotation = Vector3(t.pitch, t.yaw, 0)
	spectate_cam.fov = Settings.fov
	if not spectate_cam.current:
		spectate_cam.make_current()
	hud.spectate_name = Hud.player_name(_spec_target)
