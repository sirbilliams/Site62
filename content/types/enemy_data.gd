class_name EnemyData
extends Resource

@export var id: StringName
@export var speed_by_band: PackedFloat32Array = PackedFloat32Array([1.0, 3.0, 5.0])
@export var attack_damage: float = 30.0
@export var attack_interval_s: float = 1.0
@export var board_tear_s: float = 1.5
@export var scene: PackedScene
