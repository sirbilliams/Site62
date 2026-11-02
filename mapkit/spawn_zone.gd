class_name SpawnZone
extends Node3D

@export var zone_id: StringName
var active: bool = false

func _init() -> void:
	add_to_group(&"spawn_zones")
