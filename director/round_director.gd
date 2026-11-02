class_name RoundDirector
extends Node

signal round_started(r: int)
signal round_ended(r: int)
signal spawn_requested(zone: SpawnZone, health: int, band: int)

var round: int = 0
var remaining: int = 0
var alive: int = 0

var _curve: RoundCurve
var _player_count: int = 0
var _zones: Array[SpawnZone] = []
var _zombies_remaining: int = 0
var _time: float = 0.0
var _break_deadline: float = -1.0

func set_curve(curve: RoundCurve) -> void:
	_curve = curve

func set_zones(zones: Array[SpawnZone]) -> void:
	_zones = zones

func start_match() -> void:
	_player_count = Net.players.ids().size()
	_start_round(1)

func _start_round(r: int) -> void:
	round = r
	remaining = _curve.count(r, _player_count)
	alive = 0
	_zombies_remaining = remaining
	_time = 0.0
	_break_deadline = -1.0
	emit_signal("round_started", r)

func tick(dt: float) -> void:
	if _curve == null:
		return
	_time += dt
	
	if _break_deadline > 0:
		if _time > _break_deadline:
			_break_deadline = -1.0
			_start_round(round + 1)
		return
	
	if _zombies_remaining > 0:
		var interval := _curve.spawn_interval(round)
		var time_since_spawn := _get_time_since_last_spawn()
		if time_since_spawn >= interval:
			_spawn_zombie()

func _get_time_since_last_spawn() -> float:
	return _time

func _spawn_zombie() -> void:
	var open_zones := _get_open_zones()
	if open_zones.size() == 0:
		return
	var zone := open_zones[randi() % open_zones.size()]
	var health := _curve.health(round)
	var band := _curve.speed_band(round)
	alive = min(alive + 1, 40)
	_zombies_remaining -= 1
	remaining = max(0, _zombies_remaining)
	emit_signal("spawn_requested", zone, health, band)

func _get_open_zones() -> Array[SpawnZone]:
	var result: Array[SpawnZone] = []
	for z in _zones:
		if z.active:
			result.append(z)
	return result

func on_zombie_died() -> void:
	alive = max(0, alive - 1)
	if alive == 0 and _zombies_remaining == 0 and _break_deadline < 0:
		_start_break()

func _start_break() -> void:
	_break_deadline = _time + _curve.break_s
	emit_signal("round_ended", round)
