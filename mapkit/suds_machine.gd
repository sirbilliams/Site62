class_name SudsMachine
extends Interactable
## Ethereal-Suds dispenser. Needs power; refuses a Suds the player already has and a player at max_suds.
## The effect (max hp, reload, revive, fire rate) lives in Game.suds_of(peer), mirrored on every peer.

@export var suds: SudsData

func reject_reason(player: Player) -> StringName:
	if suds == null:
		return &"invalid"
	if not Game.power:
		return &"no_power"
	var have := Game.suds_of(player.peer_id)
	if have.has(suds.id):
		return &"owned"
	if have.count() >= Content.balance.max_suds:
		return &"max_suds"
	return &""

func cost_for(_player: Player) -> int:
	return suds.cost if suds != null else 0

func prompt(player: Player) -> String:
	if suds == null:
		return ""
	if not Game.power:
		return "%s (no power)" % suds.display_name
	return "Buy %s [%d]" % [suds.display_name, suds.cost]

func what(_player: Player) -> StringName:
	return suds.id if suds != null else &"suds"

func use(player: Player) -> bool:
	var before := player.max_health()
	if not Game.grant_suds(player.peer_id, suds):
		return false
	player.hp += maxf(player.max_health() - before, 0.0)     # the new ceiling is filled in
	return true
