class_name PlayerRegistry
extends RefCounted
## Player roster: peer id -> {name, slot}. At most MAX_PLAYERS. Slots 0-3.

const MAX_PLAYERS := 4
var _players: Dictionary = {}

func ids() -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in _players.keys():
		out.append(int(k))
	out.sort()
	return out

func has(id: int) -> bool:
	return _players.has(id)

func info(id: int) -> Dictionary:
	return _players.get(id, {}).duplicate()

func is_full() -> bool:
	return _players.size() >= MAX_PLAYERS

## Adds a player in the lowest free slot. Returns false when full or already present.
func add(id: int, pname: String) -> bool:
	if _players.has(id) or is_full():
		return false
	var used := {}
	for v in _players.values():
		used[v.slot] = true
	var slot := 0
	while used.has(slot):
		slot += 1
	_players[id] = {"name": pname, "slot": slot}
	return true

func remove(id: int) -> void:
	_players.erase(id)

func clear() -> void:
	_players.clear()

func to_dict() -> Dictionary:
	return _players.duplicate(true)

func load_dict(d: Dictionary) -> void:
	_players = d.duplicate(true)
