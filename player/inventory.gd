class_name Inventory
extends RefCounted
## Pure per-player kit: two weapon slots (either may be empty), which one is held, and the grenade count.
## `now` is whatever clock the caller uses consistently.

var slots: Array[WeaponState] = [null, null]
var held := 0
var grenades := 0
var swap_until := -INF

func _init(start: WeaponData = null) -> void:
	if start == null:
		start = Content.weapon(&"sentinel_45")
	slots[0] = WeaponState.new(start)
	grenades = Content.balance.grenades_start

func held_state() -> WeaponState:
	return slots[held]

func has_weapon(id: StringName) -> bool:
	return state_of(id) != null

## The state of the slot holding weapon `id`, or null.
func state_of(id: StringName) -> WeaponState:
	for s in slots:
		if s != null and s.data.id == id:
			return s
	return null

## A bought gun goes into an empty slot, else replaces the held one; it becomes the held gun. Returns the slot used,
## or -1 (nothing changes) if the gun is already in the kit.
func give(data: WeaponData) -> int:
	if has_weapon(data.id):
		return -1
	var i := held
	if slots[0] == null:
		i = 0
	elif slots[1] == null:
		i = 1
	slots[i] = WeaponState.new(data)
	held = i
	return i

func swap_blocked(now: float, tolerance := 0.0) -> bool:
	return now < swap_until - tolerance

## Switch to the other gun (cancelling a reload on the one put away). False if there is none or a swap is under way.
func swap(now := 0.0, tolerance := 0.0) -> bool:
	var other := 1 - held
	if slots[other] == null or swap_blocked(now, tolerance):
		return false
	slots[held].reloading = false
	held = other
	swap_until = now + Content.balance.swap_s
	return true

func refill_grenades() -> void:
	grenades = mini(grenades + Content.balance.grenades_round_refill, Content.balance.grenades_max)

func take_grenade() -> bool:
	if grenades <= 0:
		return false
	grenades -= 1
	return true
