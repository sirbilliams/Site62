class_name WallBuy
extends Interactable
## A weapon on the wall: full price for the gun, ammo_cost for a refill when the player already holds it.
## One weapon slot per player for now (a 2-slot inventory is a later task), so buying replaces the held gun.

@export var weapon_id: StringName = &""

func _data() -> WeaponData:
	return Content.weapon(weapon_id)

func _holds(player: Player) -> bool:
	return weapons != null and weapons.state_for(player.peer_id).data.id == weapon_id

func reject_reason(player: Player) -> StringName:
	var d := _data()
	if d == null or not d.is_wall_buy:
		return &"invalid"
	if _holds(player):
		var st := weapons.state_for(player.peer_id)
		if st.mag >= d.mag and st.reserve >= d.reserve:
			return &"ammo_full"
	return &""

func cost_for(player: Player) -> int:
	var d := _data()
	if d == null:
		return 0
	return d.ammo_cost if _holds(player) else d.cost

func prompt(player: Player) -> String:
	var d := _data()
	if d == null:
		return ""
	return "Buy ammo for %s [%d]" % [d.display_name, cost_for(player)] if _holds(player) \
		else "Buy %s [%d]" % [d.display_name, cost_for(player)]

func what(player: Player) -> StringName:
	return StringName("ammo_" + String(weapon_id)) if _holds(player) else weapon_id

func use(player: Player) -> bool:
	if weapons == null:
		return false
	if _holds(player):
		weapons.state_for(player.peer_id).refill()
		return true
	return weapons.set_weapon(player.peer_id, weapon_id)
