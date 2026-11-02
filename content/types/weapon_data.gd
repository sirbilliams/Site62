class_name WeaponData
extends Resource

@export var id: StringName
@export var display_name: String = ""
@export var damage: float = 20.0
@export var falloff_start: float = 15.0
@export var falloff_end: float = 40.0
@export var falloff_min_mult: float = 0.5
@export var fire_rate_rpm: float = 300.0
@export_enum("semi", "auto", "burst") var mode: int = 0
@export var mag: int = 10
@export var reserve: int = 60
@export var reload_s: float = 2.0
@export var spread_hip_deg: float = 3.0
@export var spread_ads_deg: float = 0.5
@export var recoil: PackedVector2Array = PackedVector2Array()
@export var ads_fov: float = 60.0
@export var cost: int = 0
@export var ammo_cost: int = 0
@export var scene: PackedScene
@export var refit: WeaponData
@export var is_wall_buy: bool = false
