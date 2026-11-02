class_name Zone
extends Node3D

signal opened

@export var zone_id: StringName
@export var open: bool = false:
	set(v):
		var was := open
		open = v
		if v and not was:
			opened.emit()

func _init() -> void:
	add_to_group(&"zones")
