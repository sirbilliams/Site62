class_name PowerupService
extends Node
## Power-up drops and effects. The HOST decides everything (drops, pickups by host-side player positions,
## effects); clients mirror pickups (visual) and the timed effects (`active`).
##  - A zombie KILL rolls Game.rng against Balance.powerup_drop_chance, at most powerup_max_per_round per round
##    (reset on round_started). Purge kills and despawns never drop and do not count toward the cap.
##  - Timed kinds (bonus_ration, overload; PowerupData.duration_s > 0) last Balance.powerup_duration_s.
##  - resupply refills every kit; purge kills every live zombie (killer 0 = no per-kill points, so no drops either)
##    and pays every player Balance.pts_purge through the Wallet (bonus ration applies if active);
##    fortify restores every barricade; voucher gives every player a free next crate.
##  - A pickup vanishes after Balance.powerup_despawn_s, or when a player comes within PICKUP_RANGE.

signal dropped(kind: StringName, pos: Vector3)
signal collected(kind: StringName, by: int)

const PICKUP_RANGE := 1.5
const PICKUP_SCENE := preload("res://mapkit/powerup_pickup.tscn")

var net: PlayerNet
var zombies: ZombieSync
var economy: EconomyService
var weapons: WeaponService
var active := {}                   # kind -> end time on `clock`
var pickups := {}                  # id -> PowerupPickup
var drops_this_round := 0
var drop_chance := -1.0            # < 0 = Balance.powerup_drop_chance (test hook)
var clock := 0.0
var _next_id := 1
var _purging := false

func _ready() -> void:
	name = "PowerupService"

## Wire to the other services (host and clients).
func bind(pn: PlayerNet, zs: ZombieSync, eco: EconomyService, svc: WeaponService, round_source: Object = null) -> void:
	net = pn
	zombies = zs
	economy = eco
	weapons = svc
	eco.double_source = func(): return is_active(&"bonus_ration")
	zs.damage_mod = overload_damage
	zs.zombie_died.connect(func(_zid, _k, _h, _m, pos): on_zombie_died(pos))
	if round_source != null:
		round_source.round_started.connect(func(_r): new_round())

## Host: every timed effect ends now (game over), on all peers.
func end_all() -> void:
	if not Net.is_host():
		return
	for kind in active.keys():
		active.erase(kind)
		Net.send_reliable(self, &"_rx_active", 0, [String(kind), 0.0])

func new_round() -> void:
	drops_this_round = 0

func is_active(kind: StringName) -> bool:
	return active.has(kind) and float(active[kind]) > clock

## Overload: any damage that lands kills (the zombie's hp is the floor).
func overload_damage(dmg: float, hp: float) -> float:
	return maxf(dmg, hp) if is_active(&"overload") else dmg

# ---------------------------------------------------------------- drops (host)

func on_zombie_died(pos: Vector3) -> void:
	if _purging or drops_this_round >= Content.balance.powerup_max_per_round or Content.powerups.is_empty():
		return
	var chance: float = drop_chance if drop_chance >= 0.0 else Content.balance.powerup_drop_chance
	if Game.rng.randf() >= chance:
		return
	var kinds: Array = Content.powerups.keys()
	kinds.sort()
	var d: PowerupData = Content.powerups[kinds[Game.rng.randi() % kinds.size()]]
	drops_this_round += 1
	_spawn(d.kind, pos)

## Tests / debug: drop `kind` at `pos` (does not count toward the round cap).
func force_drop(kind: StringName, pos: Vector3) -> void:
	_spawn(kind, pos)

func _spawn(kind: StringName, pos: Vector3) -> int:
	var id := _next_id
	_next_id += 1
	_make(id, kind, pos, Content.balance.powerup_despawn_s)
	Net.send_reliable(self, &"_rx_drop", 0, [id, String(kind), pos])
	dropped.emit(kind, pos)
	return id

func _make(id: int, kind: StringName, pos: Vector3, life: float) -> void:
	var p: PowerupPickup = PICKUP_SCENE.instantiate()
	p.pid = id
	p.kind = kind
	p.life = life
	p.position = pos
	add_child(p)
	pickups[id] = p

func _remove(id: int, tell := true) -> void:
	var p: PowerupPickup = pickups.get(id)
	if p == null:
		return
	pickups.erase(id)
	p.queue_free()
	if tell:
		Net.send_reliable(self, &"_rx_gone", 0, [id])

# ---------------------------------------------------------------- tick

func _physics_process(dt: float) -> void:
	tick(dt)

## Advance the clock; the host also ages and collects pickups and ends timed effects.
func tick(dt: float) -> void:
	clock += dt
	if not Net.is_host() or multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	for kind in active.keys():
		if float(active[kind]) <= clock:
			active.erase(kind)
			Net.send_reliable(self, &"_rx_active", 0, [String(kind), 0.0])
	for id in pickups.keys():
		var p: PowerupPickup = pickups[id]
		p.life -= dt
		if p.life <= 0.0:
			_remove(id)
			continue
		var by := _taker(p.position)
		if by != 0:
			_remove(id)
			collect(p.kind, by)

func _taker(pos: Vector3) -> int:
	if net == null:
		return 0
	for id in net.players:
		var pl: Player = net.players[id]
		if pl.state != Player.ALIVE:
			continue                 # downed / dead players cannot pick anything up
		if absf(pl.position.y - pos.y) < 3.0 and Vector2(pl.position.x - pos.x, pl.position.z - pos.z).length() <= PICKUP_RANGE:
			return id
	return 0

# ---------------------------------------------------------------- effects (host)

func collect(kind: StringName, by: int) -> void:
	var d: PowerupData = Content.powerups.get(kind)
	if d != null and d.duration_s > 0.0:
		var secs: float = Content.balance.powerup_duration_s
		active[kind] = clock + secs
		Net.send_reliable(self, &"_rx_active", 0, [String(kind), secs])
	match kind:
		&"resupply": _resupply()
		&"purge": _purge()
		&"fortify": _fortify()
		&"voucher":
			for id in _peers():
				Game.give_voucher(id)
	collected.emit(kind, by)

func _peers() -> Array:
	return net.players.keys() if net != null else []

func _resupply() -> void:
	if weapons == null:
		return
	for id in _peers():
		var k: Inventory = weapons.kits.get(id)
		if k == null:
			continue
		for st in k.slots:
			if st != null:
				st.refill()
		k.refill_grenades()
		weapons.send_kit(id, true)

func _purge() -> void:
	_purging = true
	if zombies != null:
		for z: Zombie in zombies.zombies.values():
			if z.alive:
				z.take_damage(z.hp + 1.0, 0, false)        # killer 0: the normal death path, no points
	_purging = false
	if economy != null:
		for id in _peers():
			economy.award(id, Content.balance.pts_purge)

func _fortify() -> void:
	for b: Barricade in get_tree().get_nodes_in_group(&"barricades"):
		b.set_boards(b.max_boards)

# ---------------------------------------------------------------- replication

## Host: live pickups and the remaining seconds of every timed effect (a late joiner gets them in the WorldSnapshot).
func snapshot() -> Dictionary:
	var drops: Array = []
	for pid in pickups:
		var p: PowerupPickup = pickups[pid]
		drops.append([pid, String(p.kind), p.position])
	var act := {}
	for kind in active:
		if is_active(kind):
			act[String(kind)] = float(active[kind]) - clock
	return {"pickups": drops, "active": act}

## Client: mirror a snapshot() of the host.
func apply_snapshot(d: Dictionary) -> void:
	if Net.is_host():
		return
	var drops = d.get("pickups")
	if drops is Array:
		for e in drops:
			if e is Array and e.size() == 3:
				_apply_drop(e[0], e[1], e[2])
	var act = d.get("active")
	if act is Dictionary:
		for k in act:
			_rx_active(k, act[k])

@rpc("authority", "reliable")
func _rx_drop(id, kind, pos) -> void:
	_apply_drop(id, kind, pos)

func _apply_drop(id, kind, pos) -> void:
	if Net.is_host() or not (id is int and kind is String and pos is Vector3) or not pos.is_finite():
		return
	if pickups.has(id) or pickups.size() > 64 or not Content.POWERUP_KINDS.has(StringName(kind)):
		return
	_make(id, StringName(kind), pos, Content.balance.powerup_despawn_s)
	dropped.emit(StringName(kind), pos)

@rpc("authority", "reliable")
func _rx_gone(id) -> void:
	if Net.is_host() or not id is int:
		return
	_remove(id, false)

@rpc("authority", "reliable")
func _rx_active(kind, remaining) -> void:
	if Net.is_host() or not (kind is String and remaining is float) or not Content.POWERUP_KINDS.has(StringName(kind)):
		return
	if remaining <= 0.0:
		active.erase(StringName(kind))
	else:
		active[StringName(kind)] = clock + minf(remaining, 600.0)
