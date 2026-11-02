extends Node
## Autoload "Net": ENet session, roster (host-authoritative) and sender checks.

signal player_joined(id: int)
signal player_left(id: int)
signal session_ready()
signal join_refused(reason: String)
signal join_failed()
signal host_lost()                # client: the host quit or the link dropped (emitted before leave())

const HOST_ID := 1
var players := PlayerRegistry.new()
var beacon_port := 7800          # 0 disables the LAN beacon
var refused_count := 0           # host: number of refused joiners
var debug_claims := {}           # host, debug only: sender id -> ["rejected:3", ...]
var _beacon: LanBeacon
var _ready_emitted := false
var accepting := true            # host: false after game over (new connections are refused with "over")
var link_sim := LinkSim.new()
var require_ready := false       # host: peer-0 (broadcast) game messages go only to peers that finished loading (mark_ready)
var _ready_peers := {}

func _ready() -> void:
	link_sim.configure_from_args()
	add_child(link_sim)
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(func():
		host_lost.emit()
		leave())
	multiplayer.connection_failed.connect(func():
		leave()
		join_failed.emit())

func host(port: int) -> Error:
	leave()
	accepting = true
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(port, 8)  # headroom so a 5th peer can connect and be told "full"
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	players.add(HOST_ID, "")
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

## Host: peer `id` built its game scene (the `ready` handshake). Broadcasts reach it from now on.
func mark_ready(id: int) -> void:
	if players.has(id):
		_ready_peers[id] = true

func is_ready(id: int) -> bool:
	return id == local_id() or _ready_peers.has(id)

## Host: the connected peers (not the host) that are ready.
func ready_peers() -> Array:
	var out: Array = []
	for id in players.ids():
		if id != local_id() and _ready_peers.has(id):
			out.append(id)
	return out

## Host: the match is over. Stop the LAN advertisement and refuse every new connection.
func close_joins() -> void:
	accepting = false
	if _beacon:
		_beacon.queue_free()
		_beacon = null

func leave() -> void:
	require_ready = false
	accepting = true
	_ready_peers.clear()
	var me := local_id()
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
		if id != me:
			player_left.emit(id)

func is_host() -> bool:
	return multiplayer == null or multiplayer.is_server()   # null: not in tree yet (unit tests)

func local_id() -> int:
	return 1 if multiplayer == null else multiplayer.get_unique_id()

## True when the RPC sender is `id`, or when called locally on the host (no RPC in flight).
func sender_is(id: int) -> bool:
	var s := multiplayer.get_remote_sender_id()
	if s == 0:
		return multiplayer.is_server()
	return s == id

## Unreliable game message to `peer` (0 = everyone). Goes through LinkSim (no-op when off).
func send_unreliable(node: Node, method: StringName, peer: int, args: Array) -> void:
	if link_sim.enabled():
		link_sim.submit(_do_send.bind(node, method, peer, args))
	else:
		_do_send(node, method, peer, args)

## Reliable game message (target method must be declared @rpc reliable). LinkSim delays it but never drops it.
func send_reliable(node: Node, method: StringName, peer: int, args: Array) -> void:
	if link_sim.enabled():
		link_sim.submit(_do_send.bind(node, method, peer, args), false)
	else:
		_do_send(node, method, peer, args)

func _do_send(node: Node, method: StringName, peer: int, args: Array) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	if peer != 0 and not multiplayer.get_peers().has(peer):
		return                   # peer left while the message was in the sim queue
	if peer == 0 and require_ready and is_host():
		for id in multiplayer.get_peers():           # a joiner still loading has no node to receive it
			if _ready_peers.has(id):
				node.callv("rpc_id", [id, method] + args)
		return
	var a: Array = [method] + args
	if peer != 0:
		a = [peer, method] + args
		node.callv("rpc_id", a)
	else:
		node.callv("rpc", a)

# Host: a peer connected.
func _on_peer_connected(id: int) -> void:
	if not is_host():
		return
	if players.is_full() or not accepting:
		refused_count += 1
		_refuse.rpc_id(id, "full" if players.is_full() else "over")
		get_tree().create_timer(0.5).timeout.connect(func():
			var p: ENetMultiplayerPeer = multiplayer.multiplayer_peer as ENetMultiplayerPeer
			if p:
				p.disconnect_peer(id))
		return
	players.add(id, "")
	player_joined.emit(id)
	_sync_roster.rpc(players.to_dict())

func _on_peer_disconnected(id: int) -> void:
	if not is_host() or not players.has(id):
		return
	players.remove(id)
	_ready_peers.erase(id)
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
	if not OS.is_debug_build() or not is_host():
		return
	var s := multiplayer.get_remote_sender_id()
	var list: Array = debug_claims.get(s, [])
	list.append(("accepted:%d" if sender_is(claimed) else "rejected:%d") % claimed)
	debug_claims[s] = list
