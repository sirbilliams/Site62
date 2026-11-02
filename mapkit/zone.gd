class_name Zone
extends Node3D

var zone_id: StringName
var open: bool = false

func _init() -> void:
	add_to_group(&"zones")
