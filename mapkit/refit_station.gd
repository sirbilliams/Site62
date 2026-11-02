class_name RefitStation
extends Interactable
## Isotope Refit: needs power, replaces the HELD gun with its upgraded twin (WeaponData.refit). A gun that has no
## refit (already refitted) is refused.

func reject_reason(player: Player) -> StringName:
	if not Game.power:
		return &"no_power"
	if weapons == null:
		return &"invalid"
	var st := weapons.kit_for(player.peer_id).held_state()
	if st == null or st.data.refit == null:
		return &"no_refit"
	if weapons.kit_for(player.peer_id).has_weapon(st.data.refit.id):
		return &"no_refit"
	return &""

func cost_for(_player: Player) -> int:
	return Content.balance.refit_cost

func prompt(_player: Player) -> String:
	return "Isotope Refit [%d]" % Content.balance.refit_cost if Game.power else "Isotope Refit (no power)"

func what(_player: Player) -> StringName:
	return &"refit"

func use(player: Player) -> bool:
	return weapons != null and weapons.refit_held(player.peer_id)
