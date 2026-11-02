extends Node3D
## Visual check: renders the Site 62 map from fixed viewpoints to ~/Projects/arena-assets/shots/site62/map/ (never the repo).
## Run: VRUN_TIMEOUT=240 tools/vrun.sh res://tools/shots_map.tscn

# [name, camera position, look-at, hide ceilings, fov]
const SHOTS := [
	["01_overview", Vector3(14, 72, 31), Vector3(14, 0, 30), true, 55.0],
	["02_entrance_lab", Vector3(7, 2.4, 14.5), Vector3(-3, 1.2, 4), false, 75.0],
	["03_yard_windows", Vector3(0, 2.4, -8), Vector3(0, 1.4, 0), false, 75.0],
	["04_cafeteria", Vector3(36, 2.6, 14.5), Vector3(24, 1.2, 4), false, 75.0],
	["05_offices", Vector3(36.5, 2.6, 38.5), Vector3(24, 1.0, 28), false, 75.0],
	["06_reactor_wing", Vector3(8.5, 2.4, 38.5), Vector3(-2, 1.5, 30), false, 75.0],
	["07_suds_closeup", Vector3(-5.2, 1.6, 28.5), Vector3(-6, 1.3, 24.6), false, 60.0],
	["08_refit_chamber", Vector3(0, 2.4, 49.5), Vector3(0, 1.0, 59), false, 75.0],
	["09_loop_route", Vector3(3.5, 2.2, 11.5), Vector3(0, 1.4, 24), false, 75.0],
]

func _ready() -> void:
	var out := OS.get_environment("HOME") + "/Projects/arena-assets/shots/site62/map/"
	DirAccess.make_dir_recursive_absolute(out)
	var map: Node3D = load("res://maps/site62/site62.tscn").instantiate()
	add_child(map)
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	for _i in 10:
		await get_tree().process_frame
	for s in SHOTS:
		map.get_node("Ceilings").visible = not s[3]
		cam.fov = s[4]
		cam.position = s[1]
		cam.look_at(s[2], Vector3.UP if absf(s[1].y - s[2].y) < 50 else Vector3(0, 0, -1))
		for _i in 6:
			await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png(out + s[0] + ".png")
		print("SHOT ", s[0], " ", img.get_size())
	get_tree().quit()
