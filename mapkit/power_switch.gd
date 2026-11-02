class_name PowerSwitch
extends Interactable
## The generator switch. Free, one-way: throwing it sets Game.power (replicated) and emits power_on.

signal power_on()

func _ready() -> void:
	if not Game.power_changed.is_connected(_on_power):
		Game.power_changed.connect(_on_power)

func _exit_tree() -> void:
	if Game.power_changed.is_connected(_on_power):
		Game.power_changed.disconnect(_on_power)

func _on_power(on: bool) -> void:
	if on:
		power_on.emit()

func reject_reason(_player: Player) -> StringName:
	return &"already_on" if Game.power else &""

func prompt(_player: Player) -> String:
	return "" if Game.power else "Restore power"

func what(_player: Player) -> StringName:
	return &"power"

func use(_player: Player) -> bool:
	if Game.power:
		return false
	Game.set_power(true)
	return true
