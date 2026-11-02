class_name RoundDirector
extends Node

signal round_started(r: int)
signal round_ended(r: int)
signal spawn_requested(zone: SpawnZone, health: int, band: int)

var round: int = 0
var remaining: int = 0  # zombies still queued to spawn
var alive: int = 0

## Injectable: Callable returning the current player count. Invalid = use Net.players.
var _player_count_provider: Callable = Callable()
## Injectable: <= 0 means use Content.balance.max_alive.
var _max_alive_override: int = 0

var _curve: RoundCurve
var _zones: Array[SpawnZone] = []
var _time: float = 0.0
var _last_spawn_time: float = 0.0
var _in_break: bool = false
var _break_end: float = 0.0

func set_curve(curve: RoundCurve) -> void:
	_curve = curve

func set_zones(zones: Array[SpawnZone]) -> void:
	_zones = zones

func set_player_count_provider(p: Callable) -> void:
	_player_count_provider = p

func start_match() -> void:
	_start_round(1)

func max_alive() -> int:
	if _max_alive_override > 0:
		return _max_alive_override
	var content := _autoload("Content")
	if content != null and content.balance != null:
		return content.balance.max_alive
	return 40

func _autoload(n: String) -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null(n)
	return null

func _player_count() -> int:
	if _player_count_provider.is_valid():
		return int(_player_count_provider.call())
	var net := _autoload("Net")
	if net != null:
		return net.players.ids().size()
	return 1

func _start_round(r: int) -> void:
	round = r
	remaining = _curve.count(r, maxi(1, _player_count()))  # read at each round start
	alive = 0
	_time = 0.0
	_last_spawn_time = -_curve.spawn_interval(r)  # first spawn is immediate
	_in_break = false
	round_started.emit(r)

func tick(dt: float) -> void:
	if _curve == null or round == 0:
		return
	_time += dt
	if _in_break:
		if _time >= _break_end:
			_start_round(round + 1)
		return
	if remaining > 0 and alive < max_alive() \
			and _time - _last_spawn_time >= _curve.spawn_interval(round):
		_spawn_zombie()

func _spawn_zombie() -> void:
	var open_zones := _active_zones()
	if open_zones.is_empty():
		return
	var zone: SpawnZone = open_zones[randi() % open_zones.size()]
	alive += 1
	remaining -= 1
	_last_spawn_time = _time
	spawn_requested.emit(zone, _curve.health(round), _curve.speed_band(round))

func _active_zones() -> Array[SpawnZone]:
	var result: Array[SpawnZone] = []
	for z in _zones:
		if z.active:
			result.append(z)
	return result

func on_zombie_died() -> void:
	alive = maxi(0, alive - 1)
	if alive == 0 and remaining == 0 and not _in_break:
		_in_break = true
		_break_end = _time + _curve.break_s
		round_ended.emit(round)
