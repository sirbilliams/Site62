class_name CrateSpot
extends Interactable
## Requisition Crate. One CrateSpot in the map is `active`; using it costs crate_cost (free with a voucher,
## Game.give_voucher) and gives a random base weapon the player does not hold. The HOST rolls (Game.rng) and
## broadcasts the result; clients never roll. After crate_moves_after_uses uses the crate moves to another
## CrateSpot (crate_moved).

signal crate_moved(to: NodePath)
signal rolled(peer: int, weapon_id: StringName)          # host and clients

@export var active := false

var uses := 0
var last_roll_peer := 0
var last_roll_id := &""

func _ready() -> void:
	add_to_group(&"crate_spots")

## Every base (non-refit) weapon the player does not hold, sorted by id (a stable order for the seeded roll).
func pool_for(player: Player) -> Array[StringName]:
	var refits := {}
	for w: WeaponData in Content.weapons.values():
		if w.refit != null:
			refits[w.refit.id] = true
	var out: Array[StringName] = []
	if weapons == null:
		return out
	var kit := weapons.kit_for(player.peer_id)
	for id in Content.weapons.keys():
		var w: WeaponData = Content.weapons[id]
		if refits.has(id) or kit.has_weapon(id):
			continue
		if w.refit != null and kit.has_weapon(w.refit.id):
			continue                                     # holding the refitted twin counts as holding it
		out.append(id)
	out.sort()
	return out

func reject_reason(player: Player) -> StringName:
	if not active:
		return &"inactive"
	return &"" if not pool_for(player).is_empty() else &"no_pool"

func cost_for(player: Player) -> int:
	return 0 if Game.has_voucher(player.peer_id) else Content.balance.crate_cost

func prompt(player: Player) -> String:
	return "Requisition Crate [free]" if Game.has_voucher(player.peer_id) \
		else "Requisition Crate [%d]" % Content.balance.crate_cost

func what(_player: Player) -> StringName:
	return &"crate"

func use(player: Player) -> bool:
	var pool := pool_for(player)
	if pool.is_empty() or weapons == null:
		return false
	var id: StringName = pool[Game.rng.randi_range(0, pool.size() - 1)]
	if not weapons.set_weapon(player.peer_id, id):
		return false
	Game.take_voucher(player.peer_id)
	_set_roll(player.peer_id, id)
	if is_inside_tree():
		Net.send_reliable(self, &"_rx_roll", 0, [player.peer_id, String(id)])
	uses += 1
	if uses >= Content.balance.crate_moves_after_uses:
		_move()
	return true

func _set_roll(peer: int, id: StringName) -> void:
	last_roll_peer = peer
	last_roll_id = id
	rolled.emit(peer, id)

func _move() -> void:
	uses = 0
	if not is_inside_tree():
		return
	var others: Array[CrateSpot] = []
	for s in get_tree().get_nodes_in_group(&"crate_spots"):
		if s != self:
			others.append(s)
	if others.is_empty():
		return
	others.sort_custom(func(a, b): return String(a.get_path()) < String(b.get_path()))
	var to: CrateSpot = others[Game.rng.randi_range(0, others.size() - 1)]
	_apply_move(to)
	Net.send_reliable(self, &"_rx_move", 0, [String(to.get_path())])

func _apply_move(to: CrateSpot) -> void:
	active = false
	uses = 0
	to.active = true
	to.uses = 0
	crate_moved.emit(to.get_path())

@rpc("authority", "reliable")
func _rx_roll(peer, id) -> void:
	if Net.is_host() or typeof(peer) != TYPE_INT or typeof(id) != TYPE_STRING:
		return
	_set_roll(peer, StringName(id))

@rpc("authority", "reliable")
func _rx_move(to) -> void:
	if Net.is_host() or typeof(to) != TYPE_STRING:
		return
	var spot := get_node_or_null(NodePath(to)) as CrateSpot
	if spot != null and spot != self:
		_apply_move(spot)
