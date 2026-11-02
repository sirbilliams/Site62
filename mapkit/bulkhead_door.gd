class_name BulkheadDoor
extends Interactable
## A locked bulkhead. Buying it (host) opens the Zones in `unlocks`, enables its navigation link and removes its
## collision. The open state is sent to clients reliably.

@export var cost: int = 750
@export var unlocks: Array[StringName] = []

var is_open := false
var link: NavigationLink3D
var blocker: StaticBody3D

func _ready() -> void:
	add_to_group(&"doors")
	link = get_node_or_null("Link")
	blocker = get_node_or_null("Blocker")
	_apply()

func reject_reason(_player: Player) -> StringName:
	return &"already_open" if is_open else &""

func cost_for(_player: Player) -> int:
	return 0 if is_open else cost

func prompt(_player: Player) -> String:
	return "" if is_open else "Open bulkhead [%d]" % cost

func what(_player: Player) -> StringName:
	return &"door"

func use(_player: Player) -> bool:
	if is_open:
		return false
	set_open(true)
	if is_inside_tree():
		unlock(get_tree().get_nodes_in_group(&"zones"))
		Net.send_reliable(self, &"_rx_open", 0, [])
	return true

## Door state only (client mirror and host).
func set_open(v: bool) -> void:
	is_open = v
	_apply()

func _apply() -> void:
	if link != null:
		link.enabled = is_open
	if blocker != null:
		blocker.set_deferred(&"collision_layer", 0 if is_open else 1)
		blocker.visible = not is_open

## Open every Zone in `zones` that this door unlocks.
func unlock(zones: Array) -> void:
	for z in zones:
		if (z as Zone).zone_id in unlocks:
			(z as Zone).open = true

@rpc("authority", "reliable")
func _rx_open() -> void:
	if Net.is_host():
		return
	set_open(true)
	unlock(get_tree().get_nodes_in_group(&"zones"))
