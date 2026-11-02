extends Node3D

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
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
		if a == "--test=shoot":
			add_child(load("res://tests/net/net_shoot.gd").new())
			return
	var label := Label.new()
	label.text = "Site 62"
	add_child(label)
