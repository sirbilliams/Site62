class_name EconomyService
extends Node
## Host-owned points. Awards points for hits / kills / board repairs and sells Interactables.
## Use requests are processed strictly one at a time in arrival order, so the second buyer of a door that
## the first just opened is refused ("already_open") and keeps their points.

signal points_changed(player: int, points: int)
signal purchase(player: int, what: StringName, cost: int)
signal denied(path: String, reason: StringName)       # the local player's last use request was refused

var net: PlayerNet
var zombies_sync: ZombieSync
var weapons: WeaponService
var players := {}                         # peer id -> Player (the PlayerNet dictionary once bound)
var wallets := {}                         # host: peer id -> Wallet
var double_source := Callable()           # () -> bool; Task 10 power-ups drive it, default off
var last_denied := &""                    # client: reason of the latest refusal
var denied_count := 0
var _hooked := {}                         # Barricade -> true
var _last_use := {}                       # peer -> msec of the last accepted use request

func _ready() -> void:
	name = "EconomyService"

## Wire to the other services (host and clients).
func bind(pn: PlayerNet, svc: WeaponService, zs: ZombieSync) -> void:
	net = pn
	players = pn.players
	weapons = svc
	zombies_sync = zs
	Net.player_left.connect(func(id): wallets.erase(id); _last_use.erase(id))
	svc.hit.connect(on_hit)
	zs.zombie_died.connect(func(_zid, killer, head, melee, _p): on_kill(killer, head, melee))

func _double() -> bool:
	return double_source.is_valid() and bool(double_source.call())

## Host: the wallet of a player (created with start_points).
func wallet(peer: int) -> Wallet:
	if not wallets.has(peer):
		wallets[peer] = Wallet.new(Content.balance.start_points, Content.balance.board_cap_per_round)
	return wallets[peer]

func _known(peer: int) -> bool:
	return players.has(peer)

func _changed(peer: int) -> void:
	var p: Player = players.get(peer)
	if p != null:
		p.points = wallet(peer).points
	points_changed.emit(peer, wallet(peer).points)

## Host: zombie hits pay pts_hit (zombie hit ids are negative).
func on_hit(shooter: int, target: int, _dmg: float, _head: bool) -> void:
	if target >= 0 or not _known(shooter):
		return
	if zombies_sync != null:
		var z: Zombie = zombies_sync.zombies.get(Zombie.zid_of(target))
		if z == null or not z.alive:
			return                          # corpse / despawned: no points
	wallet(shooter).add(Content.balance.pts_hit, _double())
	_changed(shooter)

func on_kill(killer: int, headshot: bool, melee: bool) -> void:
	if not _known(killer):
		return
	var b := Content.balance
	var n := b.pts_melee_kill if melee else b.pts_kill + (b.pts_headshot_bonus if headshot else 0)
	wallet(killer).add(n, _double())
	_changed(killer)

func on_board(by: int) -> void:
	if not _known(by):
		return
	wallet(by).add_board(Content.balance.pts_board, _double())
	_changed(by)

## The director calls this at the start of every round.
func reset_round() -> void:
	for w: Wallet in wallets.values():
		w.reset_round()
	if weapons != null:
		weapons.on_round_start()

func _hook_barricades() -> void:
	for b in _hooked.keys():
		if not is_instance_valid(b):
			_hooked.erase(b)
	for b: Barricade in get_tree().get_nodes_in_group(&"barricades"):
		hook_barricade(b)

func hook_barricade(b: Barricade) -> void:
	if not _hooked.has(b):
		_hooked[b] = true
		b.board_repaired.connect(on_board)

## Per-peer flood limit: one accepted request per Balance.use_min_interval_s.
func use_allowed(peer: int, now_ms: int) -> bool:
	var last: int = _last_use.get(peer, -1000000)
	if now_ms - last < int(Content.balance.use_min_interval_s * 1000.0):
		return false
	_last_use[peer] = now_ms
	return true

func _physics_process(_dt: float) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer or not Net.is_host():
		return
	_hook_barricades()
	for id in players:                      # keep Player.points (replicated in snapshots) current, new joiners included
		_changed_if_stale(id)

func _changed_if_stale(id: int) -> void:
	var p: Player = players[id]
	var w := wallet(id)
	if p.points != w.points:
		_changed(id)

# ---------------------------------------------------------------- use

## Any peer: ask to use an Interactable. `player` must be the sender.
@rpc("any_peer", "reliable")
func request_use(player, path) -> void:
	if not Net.is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or typeof(player) != TYPE_INT or typeof(path) != TYPE_NODE_PATH:
		return
	if not Net.sender_is(player) or not use_allowed(sender, Time.get_ticks_msec()):
		return
	var it := get_node_or_null(path) as Interactable
	var p: Player = players.get(sender)
	if it == null or p == null:
		_deny(sender, String(path), &"invalid")
		return
	var r := handle_use(sender, it, p.position)
	if r != &"":
		_deny(sender, String(path), r)

## Local convenience (client or host): ask for `it`.
func use_local(it: Interactable) -> void:
	if Net.is_host():
		var me: Player = players.get(Net.local_id())
		var r := handle_use(Net.local_id(), it, me.position if me != null else Vector3.INF)
		if r != &"":
			_deny(Net.local_id(), String(it.get_path()), r)
	else:
		Net.send_reliable(self, &"request_use", 1, [Net.local_id(), it.get_path()])

## Host: one use request, in arrival order. Returns &"" on success, else the refusal reason.
func handle_use(peer: int, it: Interactable, pos: Vector3) -> StringName:
	var p: Player = players.get(peer)
	if p == null:
		return &"player"
	var at := it.global_position if it.is_inside_tree() else it.position
	var d := Vector2(at.x - pos.x, at.z - pos.z).length()
	if not pos.is_finite() or d > Content.balance.use_range or absf(at.y - pos.y) > 3.0:
		return &"far"
	it.weapons = weapons
	var why := it.reject_reason(p)
	if why != &"":
		return why
	var cost := it.cost_for(p)
	var w := wallet(peer)
	if not w.try_spend(cost):
		return &"points"
	var what := it.what(p)
	if not it.use(p):
		w.points += cost                    # nothing happened: refund
		return &"failed"
	_changed(peer)
	purchase.emit(peer, what, cost)
	_send_loadout(peer)
	return &""

func _deny(peer: int, path: String, reason: StringName) -> void:
	if peer == Net.local_id():
		_rx_denied(path, String(reason))
	else:
		Net.send_reliable(self, &"_rx_denied", peer, [path, String(reason)])

@rpc("authority", "reliable")
func _rx_denied(path: String, reason: String) -> void:
	last_denied = StringName(reason)
	denied_count += 1
	denied.emit(path, StringName(reason))

# ---------------------------------------------------------------- loadout (clients learn a bought weapon / refill)

func _send_loadout(peer: int) -> void:
	if weapons != null:
		weapons.send_kit(peer, true)
