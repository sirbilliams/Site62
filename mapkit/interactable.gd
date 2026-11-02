class_name Interactable
extends Node3D
## Something a player buys with points by pressing use next to it. All state is host-owned.
## EconomyService calls reject_reason -> cost_for -> (try_spend) -> use on the host, one request at a time.

var weapons: WeaponService      # set by EconomyService before each host call

func _init() -> void:
	add_to_group(&"interactables")

## &"" when the player may use it right now, else a short reason (e.g. &"already_open").
func reject_reason(_player: Player) -> StringName:
	return &""

func cost_for(_player: Player) -> int:
	return 0

## HUD text; Task 14 draws it.
func prompt(_player: Player) -> String:
	return ""

## Id reported in EconomyService.purchase.
func what(_player: Player) -> StringName:
	return &"item"

## Host: apply the effect after the points were taken. False = nothing happened (points are refunded).
func use(_player: Player) -> bool:
	return false
