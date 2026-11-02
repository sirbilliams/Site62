class_name WorldSnapshot
extends Node
## Late join: the host sends a player who joins mid-match the full current state in ONE reliable message.
## It is the only late join path (the services no longer resync on player_joined themselves). The joiner first loads
## the game scene and builds its services, THEN sends a `ready` RPC (announce_ready); only that triggers the
## snapshot and ZombieSync's live zombies, so nothing is sent to a node that does not exist yet:
##  - round and phase (Match), power, every Suds and voucher (Game), open zones and bulkhead doors,
##    barricade boards, the Requisition Crate (active spot, uses), live power-ups and active timed effects,
##    and per player: points, life state, hp, kit (Inventory as in WeaponService.send_kit).
##  - Live zombies are the one other thing a joiner needs; ZombieSync sends them (they stream, they are not state).
## The joiner of a running match spawns as a spectator (MatchState.spectate): not ALIVE, not counted for game
## over, and ALIVE again with the starting kit at the next round start. Their wallet starts at Balance.start_points.
## Per-player life state and points also arrive through PlayerNet's 20 Hz snapshots; here they are applied as soon
## as the joiner's Player exists, so the joiner is consistent without waiting for it.

var net: PlayerNet
var weapons: WeaponService
var economy: EconomyService
var zombies: ZombieSync
var powerups: PowerupService
var match_node: Match
var life: MatchState
var _ready_peers := {}                  # host: peers that completed the handshake
var _pending := {}                      # client: peer -> {points, state, hp} not yet applied (Player not spawned yet)

func _ready() -> void:
	name = "WorldSnapshot"
	Net.player_left.connect(func(id): _ready_peers.erase(id))

func bind(pn: PlayerNet, svc: WeaponService, eco: EconomyService, zs: ZombieSync, pu: PowerupService, mt: Match, ms: MatchState) -> void:
	net = pn
	weapons = svc
	economy = eco
	zombies = zs
	powerups = pu
	match_node = mt
	life = ms

# ---------------------------------------------------------------- host

## Client: my game scene is built and bound; ask the host for the world.
func announce_ready() -> void:
	if Net.is_host():
		return
	Net.send_reliable(self, &"_rx_ready", 1, [])

@rpc("any_peer", "reliable")
func _rx_ready() -> void:
	if Net.is_host():
		on_ready(multiplayer.get_remote_sender_id())

## Host: peer `id` finished loading. Its spectator status, the world snapshot and the live zombies, once.
func on_ready(id: int) -> void:
	if not Net.is_host() or id == Net.local_id() or not Net.players.has(id) or _ready_peers.has(id):
		return
	_ready_peers[id] = true
	if match_node != null and match_node.running and life != null and net != null and net.ensure_player(id) != null:
		life.spectate(id)
	Net.send_reliable(self, &"_rx_snapshot", id, [capture()])
	if zombies != null:
		zombies.send_live_to(id)

## The whole world state as plain data.
func capture() -> Dictionary:
	var ids: Array = []
	for id in Net.players.ids():
		ids.append(id)
	var d := {"game": Game.snapshot(ids), "zones": [], "doors": [], "crates": [], "boards": [], "players": {}}
	if match_node != null:
		d["round"] = match_node.round
		d["phase"] = String(match_node.phase)
	for z: Zone in _zones():
		if z.open:
			d.zones.append(String(z.zone_id))
	for door: BulkheadDoor in _sorted(&"doors"):
		d.doors.append(door.is_open)
	for c: CrateSpot in _sorted(&"crate_spots"):
		d.crates.append({"active": c.active, "uses": c.uses})
	if zombies != null:
		d["boards"] = zombies.boards_list()
	if powerups != null:
		d["powerups"] = powerups.snapshot()
	for id in ids:
		var p: Player = net.players.get(id) if net != null else null
		var e := {"points": economy.wallet(id).points if economy != null else (p.points if p != null else 0)}
		if p != null:
			e["state"] = p.state
			e["hp"] = p.hp
		if weapons != null:
			e["kit"] = weapons.kit_args(id)
		d.players[id] = e
	return d

func _zones() -> Array:
	return get_tree().get_nodes_in_group(&"zones")

func _sorted(group: StringName) -> Array:
	var out := get_tree().get_nodes_in_group(group)
	out.sort_custom(func(a, b): return String(a.get_path()) < String(b.get_path()))
	return out

# ---------------------------------------------------------------- client

@rpc("authority", "reliable")
func _rx_snapshot(d) -> void:
	if Net.is_host() or typeof(d) != TYPE_DICTIONARY:
		return
	apply(d)

## Client: take a capture() of the host.
func apply(d: Dictionary) -> void:
	if Net.is_host():
		return
	if match_node != null and d.get("round") is int:
		match_node.apply_state(d.round, d.get("phase"))
	if d.get("game") is Dictionary:
		Game.apply_snapshot(d.game)
	var open_zones: Array = d.get("zones", []) if d.get("zones") is Array else []
	for z: Zone in _zones():
		if String(z.zone_id) in open_zones:
			z.open = true
	var doors := _sorted(&"doors")
	var dl = d.get("doors")
	if dl is Array:
		for i in mini(dl.size(), doors.size()):
			if dl[i] is bool and dl[i]:
				var door: BulkheadDoor = doors[i]
				door.set_open(true)
				door.unlock(_zones())
	var crates := _sorted(&"crate_spots")
	var cl = d.get("crates")
	if cl is Array:
		for i in mini(cl.size(), crates.size()):
			if cl[i] is Dictionary and cl[i].get("active") is bool and cl[i].get("uses") is int:
				(crates[i] as CrateSpot).active = cl[i].active
				(crates[i] as CrateSpot).uses = cl[i].uses
	if zombies != null:
		zombies.apply_boards(d.get("boards"))
	if powerups != null and d.get("powerups") is Dictionary:
		powerups.apply_snapshot(d.powerups)
	var pl = d.get("players")
	if pl is Dictionary:
		for id in pl:
			if typeof(id) == TYPE_INT and pl[id] is Dictionary:
				_apply_player(id, pl[id])

func _apply_player(id: int, e: Dictionary) -> void:
	if id == Net.local_id() and weapons != null and e.get("kit") is Array and e.kit.size() == 6:
		var k: Array = e.kit
		if k[1] is Array and k[2] is Array and k[3] is Array and k[0] is int and k[4] is int:
			weapons.apply_kit(k[0], k[1], k[2], k[3], k[4], 0, true)
	_pending[id] = {"points": e.get("points"), "state": e.get("state"), "hp": e.get("hp")}
	_flush_pending()

func _flush_pending() -> void:
	for id in _pending.keys():
		var p: Player = net.players.get(id) if net != null else null
		if p == null:
			continue
		var e: Dictionary = _pending[id]
		if e.points is int:
			p.points = e.points
		if e.state is int and e.state >= Player.ALIVE and e.state <= Player.DEAD:
			p.state = e.state
		if e.hp is float:
			p.hp = e.hp
		_pending.erase(id)

func _physics_process(_dt: float) -> void:
	if not _pending.is_empty():
		_flush_pending()
	for id in _pending.keys():
		if not Net.players.has(id):
			_pending.erase(id)
