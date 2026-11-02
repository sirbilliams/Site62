class_name ZombieSync
extends Node
## Owns every zombie. Host: spawns (queueing past Balance.max_alive), ticks AI, applies WeaponService hits,
## sends reliable spawn/death and 20 Hz snapshots [zid, pos, yaw, anim] (<= max_alive entries).
## Client: builds visual copies and interpolates INTERP_DELAY_MS behind the newest snapshot.

signal zombie_died(zid: int, killer: int, headshot: bool, melee: bool, pos: Vector3)   # host
signal zombie_spawned(zid: int)

const SNAP_EVERY := 3
const INTERP_DELAY_MS := 100.0
const REMOVE_DELAY_S := 0.3
const ZOMBIE_SCENE := preload("res://enemies/zombie.tscn")

var net: PlayerNet
var svc: WeaponService
var zombies := {}                 # zid -> Zombie
var queue: Array = []             # host: pending [pos, enemy_id, hp, band]
var frozen := false               # test hook: host AI paused (snapshots keep flowing)
var spawn_rx := 0                 # client counters (tests)
var die_rx := 0
var _next_zid := 1
var _tick := 0
var _hooked := {}                 # host: Barricade -> true once its boards_changed is forwarded
var _bufs := {}                   # client: zid -> Array of [recv_msec, pos, yaw, anim]

func _ready() -> void:
	name = "ZombieSync"
	Net.player_joined.connect(_on_player_joined)

func bind_weapons(w: WeaponService) -> void:
	svc = w
	svc.hit.connect(_on_hit)

func live_count() -> int:
	var n := 0
	for z: Zombie in zombies.values():
		if z.alive:
			n += 1
	return n

func positions() -> Dictionary:
	var out := {}
	for z: Zombie in zombies.values():
		if z.alive:
			out[z.zid] = z.position
	return out

func _barricades() -> Array:
	return get_tree().get_nodes_in_group(&"barricades")

# ------------------------------------------------------------------ host
## Host: spawn now, or queue when Balance.max_alive zombies are alive. True if spawned immediately.
func spawn(pos: Vector3, enemy_id: StringName, hp: float, band: int) -> bool:
	if not Net.is_host():
		return false
	if live_count() >= Content.balance.max_alive:
		queue.append([pos, enemy_id, hp, band])
		return false
	_spawn_now(pos, enemy_id, hp, band)
	return true

func _make(zid: int, pos: Vector3, enemy_id: StringName, hp: float, band: int, host: bool) -> Zombie:
	var data: EnemyData = Content.enemies.get(enemy_id)
	if data == null:
		return null
	var z: Zombie = (data.scene if data.scene != null else ZOMBIE_SCENE).instantiate()
	z.setup(zid, data, hp, band, host)
	z.position = pos
	if svc != null:
		svc.register_target(Zombie.hit_id(zid), z)
	add_child(z)
	zombies[zid] = z
	return z

func _spawn_now(pos: Vector3, enemy_id: StringName, hp: float, band: int) -> void:
	var zid := _next_zid
	_next_zid += 1
	var z := _make(zid, pos, enemy_id, hp, band, true)
	if z == null:
		return
	z.brain._repath_in = (zid % 5) * 0.1        # spread path queries over the repath window
	z.died.connect(_on_died)
	Net.send_reliable(self, &"_rx_spawn", 0, [zid, pos, String(enemy_id), band])
	zombie_spawned.emit(zid)

func _on_died(zid: int, killer: int, headshot: bool, melee: bool, pos: Vector3) -> void:
	_finish(zid, pos)
	zombie_died.emit(zid, killer, headshot, melee, pos)

## Host: remove a zombie without a kill (round end, cleanup). Same cleanup as a death, no `zombie_died`.
func despawn(zid: int) -> void:
	var z: Zombie = zombies.get(zid)
	if not Net.is_host() or z == null or not z.alive:
		return
	z.alive = false
	_finish(zid, z.position)

func _finish(zid: int, pos: Vector3) -> void:
	var z: Zombie = zombies.get(zid)
	if z != null and z.brain != null:
		z.brain.release_all()     # drops any barricade tear claim
	Net.send_reliable(self, &"_rx_die", 0, [zid, pos])
	_schedule_remove(zid)

func _on_hit(shooter: int, target: int, dmg: float, head: bool) -> void:
	if not Net.is_host() or target >= 0:
		return
	var z: Zombie = zombies.get(Zombie.zid_of(target))
	if z != null:
		z.take_damage(dmg, shooter, head)

func _schedule_remove(zid: int) -> void:
	get_tree().create_timer(REMOVE_DELAY_S).timeout.connect(_remove.bind(zid))

func _remove(zid: int) -> void:
	var z: Zombie = zombies.get(zid)
	if z == null:
		return
	if svc != null:
		svc.unregister_target(Zombie.hit_id(zid))     # also HitHistory.forget
	zombies.erase(zid)
	_bufs.erase(zid)
	z.queue_free()

func _on_player_joined(id: int) -> void:
	if not Net.is_host():
		return
	_hook_barricades()
	Net.send_reliable(self, &"_rx_boards_all", id, [_boards_list()])
	for z: Zombie in zombies.values():
		if z.alive:
			Net.send_reliable(self, &"_rx_spawn", id, [z.zid, z.position, String(z.data.id), z.band])

func _on_boards_changed(n: int, b: Barricade) -> void:
	Net.send_reliable(self, &"_rx_boards", 0, [_barricades().find(b), n])

func _boards_list() -> Array:
	var out: Array = []
	for b: Barricade in _barricades():
		out.append(b.boards)
	return out

## Host: forward every barricade's board count to clients (index = tree order of the "barricades" group).
func _hook_barricades() -> void:
	var bars := _barricades()
	for i in bars.size():
		var b: Barricade = bars[i]
		if not _hooked.has(b):
			_hooked[b] = true
			b.boards_changed.connect(_on_boards_changed.bind(b))

func _physics_process(dt: float) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	if not Net.is_host():
		return
	_hook_barricades()
	while not queue.is_empty() and live_count() < Content.balance.max_alive:
		var q: Array = queue.pop_front()
		_spawn_now(q[0], q[1], q[2], q[3])
	if not frozen:
		var bars := _barricades()
		for z: Zombie in zombies.values():
			if z.alive:
				z.brain.tick(dt, net.players, bars)
	_tick += 1
	if _tick % SNAP_EVERY == 0:
		_send_snapshot()

func _send_snapshot() -> void:
	var out: Array = []
	for z: Zombie in zombies.values():
		if z.alive and out.size() < Content.balance.max_alive:
			out.append([z.zid, z.position, z.yaw, int(z.anim)])
	Net.send_unreliable(self, &"_rx_snap", 0, [out])

# ------------------------------------------------------------------ client
@rpc("authority", "reliable")
func _rx_spawn(zid, pos, enemy_id, band) -> void:
	if Net.is_host() or not (zid is int and pos is Vector3 and enemy_id is String and band is int):
		return
	if zid <= 0 or zombies.has(zid) or zombies.size() > Content.balance.max_alive * 2 or not pos.is_finite():
		return
	var z := _make(zid, pos, StringName(enemy_id), 1.0, band, false)
	if z == null:
		return
	_bufs[zid] = [[Time.get_ticks_msec(), pos, 0.0, 0]]
	spawn_rx += 1
	zombie_spawned.emit(zid)

@rpc("authority", "reliable")
func _rx_boards(index, n) -> void:
	if Net.is_host() or not (index is int and n is int):
		return
	var bars := _barricades()
	if index >= 0 and index < bars.size():
		(bars[index] as Barricade).set_boards(n)

@rpc("authority", "reliable")
func _rx_boards_all(list) -> void:
	if Net.is_host() or not list is Array:
		return
	var bars := _barricades()
	for i in mini(list.size(), bars.size()):
		if list[i] is int:
			(bars[i] as Barricade).set_boards(list[i])

@rpc("authority", "reliable")
func _rx_die(zid, pos) -> void:
	if Net.is_host() or not (zid is int and pos is Vector3):
		return
	var z: Zombie = zombies.get(zid)
	if z == null or not z.alive:
		return
	z.alive = false
	die_rx += 1
	_schedule_remove(zid)

@rpc("authority", "unreliable")
func _rx_snap(entries) -> void:
	if Net.is_host() or not entries is Array:
		return
	var now := Time.get_ticks_msec()
	for e in entries:
		if not (e is Array and e.size() == 4 and e[0] is int and e[1] is Vector3 and e[2] is float and e[3] is int):
			continue
		var z: Zombie = zombies.get(e[0])
		if z == null or not z.alive or not (e[1] as Vector3).is_finite():
			continue
		var buf: Array = _bufs[e[0]]
		buf.append([now, e[1], e[2], e[3]])
		if buf.size() > 40:
			buf.pop_front()

func _process(_dt: float) -> void:
	if Net.is_host():
		return
	var rt := Time.get_ticks_msec() - INTERP_DELAY_MS
	for zid in _bufs:
		var z: Zombie = zombies.get(zid)
		var buf: Array = _bufs[zid]
		if z == null or not z.alive or buf.is_empty():
			continue
		while buf.size() > 2 and buf[1][0] <= rt:
			buf.pop_front()
		var a: Array = buf[0]
		if rt <= a[0] or buf.size() == 1:
			_show(z, a[1], a[2], a[3])
			continue
		var b: Array = buf[1]
		var k := clampf((rt - a[0]) / maxf(b[0] - a[0], 1.0), 0.0, 1.0)
		_show(z, (a[1] as Vector3).lerp(b[1], k), lerp_angle(a[2], b[2], k), b[3])

func _show(z: Zombie, pos: Vector3, yaw: float, anim: int) -> void:
	z.position = pos
	z.yaw = yaw
	z.rotation.y = yaw
	z.anim = anim
