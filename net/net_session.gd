extends Node
## Autoload "Net": ENet session, roster (host-authoritative) and sender checks.

signal player_joined(id: int)
signal player_left(id: int)
signal session_ready()
signal join_refused(reason: String)

const HOST_ID := 1
var players := PlayerRegistry.new()
var beacon_port := 7800          # 0 disables the LAN beacon
var refused_count := 0           # host: number of refused joiners
var debug_claims := {}           # host, debug only: sender id -> ["rejected:3", ...]
var _beacon: LanBeacon
var _ready_emitted := false

func _ready() -> void:
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(leave)

func host(port: int) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 8)  # headroom so a 5th peer can connect and be told "full"
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players.add(HOST_ID, _default_name(HOST_ID))
	if beacon_port > 0:
		_beacon = LanBeacon.new()
		add_child(_beacon)
		_beacon.start_host(beacon_port, func(): return {"port": port, "name": players.info(HOST_ID).get("name", "Host"), "players": players.ids().size()})
	_ready_emitted = true
	session_ready.emit()
	return OK

func join(ip: String, port: int) -> Error:
	leave()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, port)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	return OK

func leave() -> void:
	if _beacon:
		_beacon.queue_free()
		_beacon = null
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	var old := players.ids()
	players.clear()
	_ready_emitted = false
	for id in old:
		if id != local_id():
			player_left.emit(id)

func is_host() -> bool:
	return multiplayer.is_server()

func local_id() -> int:
	return multiplayer.get_unique_id()

## True when the RPC sender is `id`, or when called locally on the host (no RPC in flight).
func sender_is(id: int) -> bool:
	var s := multiplayer.get_remote_sender_id()
	if s == 0:
		return multiplayer.is_server()
	return s == id

func _default_name(id: int) -> String:
	return "Operative %d" % (players.info(id).get("slot", players.ids().size()) + 1)

# Host: a peer connected.
func _on_peer_connected(id: int) -> void:
	if not is_host():
		return
	if players.is_full():
		refused_count += 1
		_refuse.rpc_id(id, "full")
		get_tree().create_timer(0.5).timeout.connect(func():
			var p: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
			if p:
				p.disconnect_peer(id))
		return
	players.add(id, "")
	var inf := players.info(id)
	players._players[id].name = "Operative %d" % (inf.slot + 1)
	player_joined.emit(id)
	_sync_roster.rpc(players.to_dict())

func _on_peer_disconnected(id: int) -> void:
	if not is_host() or not players.has(id):
		return
	players.remove(id)
	player_left.emit(id)
	_sync_roster.rpc(players.to_dict())

@rpc("authority", "reliable")
func _refuse(reason: String) -> void:
	join_refused.emit(reason)

@rpc("authority", "reliable")
func _sync_roster(d: Dictionary) -> void:
	var old := players.ids()
	players.load_dict(d)
	for id in players.ids():
		if not old.has(id) and id != local_id():
			player_joined.emit(id)
	for id in old:
		if not players.has(id):
			player_left.emit(id)
	if not _ready_emitted and players.has(local_id()):
		_ready_emitted = true
		session_ready.emit()

## DEBUG ONLY: proves sender checks. A peer claims to be `claimed`; host records accept/reject.
@rpc("any_peer", "reliable")
func debug_claim(claimed: int) -> void:
	if not is_host():
		return
	var s := multiplayer.get_remote_sender_id()
	var list: Array = debug_claims.get(s, [])
	list.append(("accepted:%d" if sender_is(claimed) else "rejected:%d") % claimed)
	debug_claims[s] = list
