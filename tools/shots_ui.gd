extends Node3D
## Visual check of every UI screen and HUD state -> ~/Projects/arena-assets/shots/site62/ui/ (never the repo).
## Run: VRUN_TIMEOUT=240 VRUN_W=1920 VRUN_H=1080 tools/vrun.sh res://tools/shots_ui.tscn [-- --tag=_800]
## Drives a real hosted game (Net.host + GameRoot) and sets states directly on the host.

var out := ""
var tag := ""
var layer: CanvasLayer
var game: GameRoot

func _shot(name: String, frames := 6) -> void:
	for _i in frames:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(out + name + tag + ".png")
	print("SHOT ", name, tag, " ", img.get_size())

func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout

func _ready() -> void:
	out = OS.get_environment("HOME") + "/Projects/arena-assets/shots/site62/ui/"
	DirAccess.make_dir_recursive_absolute(out)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--tag="):
			tag = a.substr(6)
	Settings.reset_defaults()
	Settings.apply_all()
	Net.beacon_port = 0
	layer = CanvasLayer.new()
	add_child(layer)
	await _menus()
	await _game()
	Net.leave()
	get_tree().quit()

func _menus() -> void:
	var menu: MainMenu = load("res://ui/main_menu.tscn").instantiate()
	layer.add_child(menu)
	await _shot("01_main_menu")
	menu.show_join()
	menu._on_found("192.168.1.20", 7862, "Operative 1", 2)
	menu._on_found("192.168.1.31", 7862, "Operative 1", 1)
	menu._ip.text = ""
	await _shot("02_join")
	menu.queue_free()
	var st: SettingsScreen = load("res://ui/settings_screen.tscn").instantiate()
	layer.add_child(st)
	await _shot("08_settings")
	st._begin_capture(&"reload", false)
	await _shot("09_settings_rebind")
	st.queue_free()

func _game() -> void:
	if Net.host(GameRoot.PORT + 1) != OK:
		print("SHOTS host failed")
		return
	Net.players.add(2, "")
	Net.players.add(3, "")
	game = load("res://scenes/game.tscn").instantiate()
	add_child(game)
	await _wait(0.5)
	await _shot("03_lobby")
	game.start_match()
	await _wait(2.0)
	game.zs.frozen = true                              # nothing hurts the staged players
	var me: Player = game.net.local_player()
	me.points = 1850
	game.eco.wallet(1).points = 1850
	game.eco.wallet(2).points = 3200
	game.eco.wallet(3).points = 640
	Game.grant_suds(1, Content.suds[&"grape_bulwark"])
	Game.grant_suds(1, Content.suds[&"overclock_orange"])
	Game.grant_suds(1, Content.suds[&"snapback_fizz"])
	game.pu.collect(&"double_points", 1)
	game.pu.collect(&"overload", 1)
	game.pu.clock += 11.0                              # the timers are partly run down
	# stand in front of a wall buy (prompt)
	var wb: WallBuy = null
	for it in get_tree().get_nodes_in_group(&"interactables"):
		if it is WallBuy and (wb == null or it.name < wb.name):
			wb = it
	game.svc.kit_for(1).slots[0] = WeaponState.new(Content.weapon(&"hornet"))   # not the wall buy's gun, so the prompt offers a purchase
	var fwd := wb.global_transform.basis.z
	var pos := wb.global_position + fwd * 1.3
	pos.y = me.position.y
	me.teleport(pos)
	game.net._yaw = atan2(fwd.x, fwd.z)                # look back at the wall buy: forward = -z rotated by yaw
	game.net._pitch = 0.0
	# teammates standing at the spawn (visible capsules)
	for id in [2, 3]:
		var p: Player = game.net.players[id]
		p.teleport(pos + Vector3(-1.5 * (id - 1), 0, 2.5))
		p.yaw = game.net._yaw
	await _wait(1.0)
	game.hud.show_hit(true)
	await _shot("04_hud", 2)
	# downed with a teammate reviving
	me.hp = 0.0
	await _wait(0.4)
	game.ms.apply_revive(1, 2, 0.45, 0.62)
	game.net.players[2].points = 3200
	await _shot("05_down_revive", 2)
	# I am the reviver
	game.ms._revive(1, me, 1)
	var mate: Player = game.net.players[2]
	mate.state = Player.DOWN
	mate.hp = 0.0
	me.hp = 100.0
	game.ms._view = {}
	game.ms.apply_revive(2, 1, 0.6, 0.8)
	await _shot("06_reviving", 2)
	# spectating: I am out, watching a teammate standing in the open
	var open_spot := game.net.spawn + Vector3(0, 0, 0)
	mate.teleport(open_spot)
	mate.yaw = 0.0
	mate.pitch = -0.05
	game.ms._view = {}
	mate.state = Player.ALIVE
	mate.hp = 100.0
	me.state = Player.DEAD
	me.hp = 0.0
	game.net.players[3].state = Player.DEAD
	await _wait(0.6)
	await _shot("07_spectate")
	# pause
	me.state = Player.ALIVE
	me.hp = 100.0
	game.set_paused(true)
	await _shot("10_pause")
	game.set_paused(false)
	# game over
	game._on_game_over({1: {"rounds": 7, "kills": 64, "downs": 2, "revives": 1, "points": 18450},
		2: {"rounds": 7, "kills": 51, "downs": 1, "revives": 3, "points": 12200}, 3: {"rounds": 7, "kills": 12, "downs": 4, "revives": 0, "points": 4300}})
	await _shot("11_game_over")
