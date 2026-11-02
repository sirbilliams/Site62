class_name HudText
extends RefCounted
## Pure HUD text: points formatting and interact prompts. Hud (ui/hud.gd) exposes the same functions.

static func format_points(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out

## Whole seconds left, rounded up.
static func format_time(sec: float) -> String:
	return str(maxi(int(ceil(sec)), 0))

static func use_label() -> String:
	return Settings.key_label(&"use")

static func _hold(rest: String) -> String:
	return "Hold %s: %s" % [use_label(), rest]

## What to show for `i` next to player `p` ("" = nothing). Wraps Interactable.prompt/reject_reason/cost_for:
## "Hold F: Hornet [1000]", "Hold F: Ammo [500]", "Need power", "Hold F: Requisition Crate [Free]".
## The caller sets i.weapons (EconomyService does it on the host) so wall buys know the player's kit.
static func prompt_text(i: Interactable, p: Player) -> String:
	if i == null or p == null:
		return ""
	var raw := i.prompt(p)
	if raw == "":
		return ""
	var why := i.reject_reason(p)
	var cost := i.cost_for(p)
	if i is WallBuy:
		var d: WeaponData = Content.weapon((i as WallBuy).weapon_id)
		if why == &"ammo_full":
			return "Ammo full"
		if why != &"":
			return ""
		var holds: bool = i.weapons != null and i.weapons.kit_for(p.peer_id).has_weapon(d.id)
		return _hold("%s [%d]" % ["Ammo" if holds else d.display_name, cost])
	if i is BulkheadDoor:
		return "" if why == &"already_open" else _hold("Open bulkhead [%d]" % cost)
	if i is SudsMachine:
		var s: SudsData = (i as SudsMachine).suds
		match why:
			&"no_power":
				return "Need power"
			&"owned":
				return "%s owned" % s.display_name
			&"max_suds":
				return "Suds full"
			&"":
				return _hold("%s [%d]" % [s.display_name, cost])
		return ""
	if i is CrateSpot:
		match why:
			&"inactive":
				return ""
			&"no_pool":
				return "Nothing left in the crate"
		return _hold("Requisition Crate [%s]" % ("Free" if cost == 0 else str(cost)))
	if i is RefitStation:
		match why:
			&"no_power":
				return "Need power"
			&"no_refit":
				return "Already refitted"
		return _hold("Isotope Refit [%d]" % cost)
	if i is PowerSwitch:
		return _hold("Restore power")
	return _hold(raw) if cost == 0 else _hold("%s [%d]" % [raw, cost])
