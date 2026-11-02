extends Node3D

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a == "--test=basic":
			add_child(load("res://tests/net/net_basic.gd").new())
			return
	var label := Label.new()
	label.text = "Site 62"
	add_child(label)
