extends Node3D

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--test=basic":
			add_child(load("res://tests/net/net_basic.gd").new())
			return
		if a == "--test=move":
			add_child(load("res://tests/net/net_move.gd").new())
			return
		if a == "--test=zombie":
			add_child(load("res://tests/net/net_zombie.gd").new())
			return
		if a == "--test=shoot":
			add_child(load("res://tests/net/net_shoot.gd").new())
			return
	var label := Label.new()
	label.text = "Site 62"
	add_child(label)
