class_name WeaponService
extends Node3D
## Weapons: client fires locally at once (flash, tracer, predicted marker) and sends a stamped request;
## the host validates it (sender, rate, ammo, origin, line of sight), rewinds targets to what the shooter
## saw (HitHistory + ClockSync) and raycasts. `hit` is a signal only; Task 6 applies the damage.
## Must be a child of the same parent as PlayerNet, named "WeaponService" on every peer.

signal hit(shooter: int, target: int, dmg: float, headshot: bool)
signal melee_hit(attacker: int, target: int, dmg: float)                       # host
signal grenade_hit(thrower: int, target: int, dmg: float)                     # host
signal fire_rejected(shooter: int, reason: StringName)
signal result_received(t: float, kind: int, reason: StringName, target: int, dmg: float, headshot: bool)  # client

enum { MISS, HIT, REJECTED }
const DEFAULT_WEAPON := &"sentinel_45"
const DUMMY_ID := 1000
const SNAP_EVERY := 3
const PING_EVERY := 30                   # physics ticks
const BUCKET_MAX := 12.0                 # request flood limit per peer (burst)
const BUCKET_REFILL := 30.0              # requests per second
const SKIN := 0.05
const AMMO_SYNC_EVERY := 30             # physics ticks (0.5 s)
const BASE_FOV := 75.0
const FOV_RATE := 14.0
const SWAP_TOL := 0.25                   # fraction of swap_s forgiven for network jitter

var net: PlayerNet
var history := HitHistory.new()
var targets := {}                        # id -> HitTarget (host: authoritative; client: visual copies)
var kits := {}                           # peer id -> Inventory (host: all; client: local only)
var grenade_scene: PackedScene = preload("res://weapons/grenade.tscn")
var grenades_live := {}                  # gid -> Grenade (host and client copies)
var last_melee := {}                     # host debug: attacker -> {id, time}
var boom_rx := 0                         # client: explode events received (tests)
var spawn_rx := 0
var view: WeaponView
var dummy: TargetDummy
var lag_comp := true                     # test hook: false = rewind to now
var last_rewind := {}                    # host debug: shooter -> {t, id, pose_origin}
var _bucket := {}                        # peer id -> [tokens, last_msec]
var _tick := 0
var _dummy_buf: Array = []               # client: [recv_msec, pos]
var _semi_held := false
var recoil: Recoil                       # local player's camera kick
var _shot_seq := 0                       # client: shots sent (host counts the same requests itself)
var _inflight := 0                       # client: shots sent whose verdict has not arrived
var _inflight_slots: Array = []          # client: the slot each of those shots was fired from, in order
var _counters := {}                      # host: peer id -> requests received (spread seed)
var _pings := {}                         # host: nonce -> [sent_s, {peer: true} answered]
var _nonce := 0
var _prev_buttons := 0
var _swaps_sent := 0                     # client: swap requests sent
var _swap_count := {}                    # host: peer -> swap requests received (acknowledged in every kit)
var _melees := {}                        # host: peer -> Melee
var _melee_next := 0.0                   # client: local swing cooldown
var _next_throw := {}                    # host: peer -> earliest next throw (host clock)
var _next_gid := 1
var _recoil_id := &""

func _ready() -> void:
	name = "WeaponService"
	view = WeaponView.new()
	add_child(view)
	Net.player_left.connect(_forget_peer)

func _forget_peer(id: int) -> void:
	for d in [_melees, _next_throw, _swap_count, kits, _bucket, _counters]:
		d.erase(id)

static func now_s() -> float:
	return Time.get_ticks_msec() / 1000.0

func balance() -> Balance:
	return Content.balance

# ---------------------------------------------------------------- targets / weapons

func register_target(id: int, t: HitTarget) -> void:
	t.target_id = id
	targets[id] = t

func unregister_target(id: int) -> void:
	targets.erase(id)
	history.forget(id)

func spawn_dummy() -> TargetDummy:
	dummy = TargetDummy.new()
	dummy.position = TargetDummy.pos_at(now_s())
	add_child(dummy)
	register_target(DUMMY_ID, dummy)
	return dummy

## A bought gun: fills an empty slot, else replaces the held one (see Inventory.give).
func set_weapon(peer: int, weapon_id: StringName) -> bool:
	var d := Content.weapon(weapon_id)
	if d == null:
		return false
	if kit_for(peer).give(d) < 0:
		return false
	_sync_recoil()
	return true

## Host: a downed player keeps only the sidearm (slot 0) in hand.
func force_sidearm(peer: int) -> void:
	var k := kit_for(peer)
	if k.held != 0:
		k.slots[k.held].reloading = false
		k.held = 0
	k.swap_until = -INF
	_sync_recoil()
	send_kit(peer, true)

## Host: a respawned player starts again with the sidearm only (full ammo, starting grenades).
func reset_kit(peer: int) -> void:
	kits[peer] = Inventory.new(Content.weapon(DEFAULT_WEAPON))
	_sync_recoil()
	send_kit(peer, true)

## Firing needs ALIVE, or DOWN with the sidearm in hand (slot 0).
func _may_fire(p: Player) -> bool:
	return p.state == Player.ALIVE or (p.state == Player.DOWN and kit_for(p.peer_id).held == 0)

## Isotope Refit for the held gun of `peer`.
func refit_held(peer: int) -> bool:
	if not kit_for(peer).refit_held():
		return false
	_sync_recoil()
	return true

## Ethereal-Suds multipliers of `peer` (same on every peer: Game mirrors them).
static func rate_mult_of(peer: int) -> float:
	return Game.suds_of(peer).fire_rate_mult()

static func reload_speed_of(peer: int) -> float:
	return 1.0 / maxf(Game.suds_of(peer).reload_mult(), 0.01)

func kit_for(peer: int) -> Inventory:
	if not kits.has(peer):
		kits[peer] = Inventory.new(Content.weapon(DEFAULT_WEAPON))
		_sync_recoil()
	return kits[peer]

func state_for(peer: int) -> WeaponState:
	return kit_for(peer).held_state()

## The local camera kick follows the held gun.
func _sync_recoil() -> void:
	if not kits.has(Net.local_id()):
		return
	var d := (kits[Net.local_id()] as Inventory).held_state().data
	if d.id != _recoil_id:
		_recoil_id = d.id
		recoil = Recoil.new(d.recoil)

## Host: +grenades at the start of a round (up to the cap).
func on_round_start() -> void:
	for peer in kits:
		(kits[peer] as Inventory).refill_grenades()
		send_kit(peer, true)

# ---------------------------------------------------------------- per tick

func _physics_process(_dt: float) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	_tick += 1
	if Net.is_host():
		_host_tick()
	else:
		_client_tick()
	_local_input()

func _host_tick() -> void:
	_recover_recoil()
	var now := now_s()
	if dummy != null:
		dummy.position = TargetDummy.pos_at(now)
	for id in targets:
		var t: HitTarget = targets[id]
		history.record(now, id, t.global_transform, t.alive)
	if _tick % SNAP_EVERY == 0 and dummy != null:
		Net.send_unreliable(self, &"_rx_dummy", 0, [DUMMY_ID, dummy.position])
	if _tick % PING_EVERY == 0:
		_nonce += 1
		_pings[_nonce] = [now, {}]
		_pings.erase(_nonce - 8)
		Net.send_unreliable(self, &"_rx_ping", 0, [_nonce])
	if _tick % AMMO_SYNC_EVERY == 0:
		for id in net.players:
			if id != Net.local_id():
				send_kit(id, false)
	for k: Inventory in kits.values():
		for st in k.slots:
			if st != null:
				st.update(now)

func _client_tick() -> void:
	if kits.has(Net.local_id()):
		state_for(Net.local_id()).update(now_s())
	_recover_recoil()

func _recover_recoil() -> void:
	if recoil == null or net == null:
		return
	var back := recoil.recover(1.0 / 60.0)
	if back != Vector2.ZERO:
		net.add_look(deg_to_rad(back.x), -deg_to_rad(back.y))

func _process(dt: float) -> void:
	var me := net.local_player() if net != null else null
	if me != null and me.camera != null:
		var st := state_for(Net.local_id())
		var target := st.data.ads_fov if (net.local_buttons & InputFrame.ADS) else BASE_FOV
		me.camera.fov = lerpf(me.camera.fov, target, 1.0 - exp(-FOV_RATE * dt))
	if Net.is_host() or dummy == null or _dummy_buf.is_empty():
		return
	var rt := Time.get_ticks_msec() - Player.INTERP_DELAY_MS
	while _dummy_buf.size() > 2 and _dummy_buf[1][0] <= rt:
		_dummy_buf.pop_front()
	if rt <= _dummy_buf[0][0] or _dummy_buf.size() == 1:
		dummy.position = _dummy_buf[0][1]
		return
	var a: Array = _dummy_buf[0]
	var b: Array = _dummy_buf[1]
	dummy.position = (a[1] as Vector3).lerp(b[1], clampf((rt - a[0]) / maxf(b[0] - a[0], 1.0), 0.0, 1.0))

## FIRE / RELOAD buttons of the local frame drive fire_local / reload_local.
func _local_input() -> void:
	var me := net.local_player() if net != null else null
	if me == null or me.state == Player.DEAD or (me.state == Player.DOWN and kit_for(Net.local_id()).held != 0):
		return
	var downed := me.state == Player.DOWN       # downed: sidearm fire / reload only
	var b := net.local_buttons
	var st := state_for(Net.local_id())
	var pressed := b & ~_prev_buttons
	_prev_buttons = b
	if downed:
		pass
	elif pressed & InputFrame.NEXT_WEAPON:
		swap_local()
	if not downed and pressed & InputFrame.MELEE:
		melee_local()
	if not downed and pressed & InputFrame.GRENADE:
		grenade_local()
	st = state_for(Net.local_id())
	if b & InputFrame.RELOAD:
		reload_local()
	if b & InputFrame.FIRE:
		if st.data.mode == 1 or not _semi_held:
			fire_local(_look_dir(me))
		_semi_held = true
	else:
		_semi_held = false

func _look_dir(me: Player) -> Vector3:
	return Basis.from_euler(Vector3(me.pitch, me.yaw, 0.0)) * Vector3(0, 0, -1)

func eye_of(p: Player) -> Vector3:
	return p.motor_state.pos + Vector3(0, Player.EYE_HEIGHT, 0)

# ---------------------------------------------------------------- client side

## Fire the local player's weapon along `dir` (unit; the camera look, which includes recoil kick).
## Returns false if the local state blocks it. Spread is applied here only for the local visuals;
## the host re-derives the same offset from (shooter, request count) and never takes one from the client.
func fire_local(dir: Vector3) -> bool:
	var me := net.local_player()
	if me == null:
		return false
	var t := now_s()
	var st := state_for(Net.local_id())
	if not _predict_fire(t):
		return false
	var origin := eye_of(me)
	var seq := _peek_seq(Net.local_id()) if Net.is_host() else _shot_seq
	var ads := (net.local_buttons & InputFrame.ADS) != 0
	var aim := Spread.offset_dir(dir, Spread.cone_deg(st.data, ads), Net.local_id(), seq)
	var end := origin + aim * balance().max_shot_range
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, end, 1 | HitTarget.LAYER_HITBOX)
	var r := space.intersect_ray(q)
	if not r.is_empty():
		end = r.position
	view.muzzle_flash(origin + aim * 0.6)
	view.tracer(origin + aim * 0.6, end)
	if not r.is_empty() and r.collider is StaticBody3D and (r.collider as Node).has_meta(&"target_id"):
		var tgt = targets.get((r.collider as Node).get_meta(&"target_id"))
		var head: bool = tgt != null and tgt.is_head_shape(r.shape)
		view.predicted_marker(t, r.position, head)
	if recoil != null:
		var k := recoil.kick(t)
		net.add_look(deg_to_rad(k.x), deg_to_rad(k.y))
	if Net.is_host():
		handle_fire(Net.local_id(), Net.local_id(), origin, dir, t, _next_seq(Net.local_id()))
	else:
		_shot_seq += 1
		_inflight += 1
		_inflight_slots.append(kit_for(Net.local_id()).held)
		Net.send_reliable(self, &"request_fire", 1, [Net.local_id(), origin, dir, t, seq])
	return true

## Local prediction gate: not mid-swap, and the held gun's state (rate incl. Suds) lets it fire at `t`. Consumes a round.
func _predict_fire(t: float) -> bool:
	var me := Net.local_id()
	return not kit_for(me).swap_blocked(t) and state_for(me).fire(t, rate_mult_of(me))

## Swap to the other gun (predicted at once; the host's kit message confirms).
func swap_local() -> bool:
	if not kit_for(Net.local_id()).swap(now_s()):
		return false
	_sync_recoil()
	if not Net.is_host():
		_swaps_sent += 1
		Net.send_reliable(self, &"request_swap", 1, [])
	return true

func melee_local() -> void:
	var me := net.local_player()
	var t := now_s()
	if me == null or t < _melee_next:
		return
	_melee_next = t + balance().melee_cooldown_s
	var dir := _look_dir(me)
	if Net.is_host():
		handle_melee(Net.local_id(), eye_of(me), dir, t)
	else:
		Net.send_reliable(self, &"request_melee", 1, [Net.local_id(), eye_of(me), dir, t])

func grenade_local() -> void:
	var me := net.local_player()
	if me == null:
		return
	var dir := _look_dir(me)
	if Net.is_host():
		handle_grenade(Net.local_id(), eye_of(me), dir)
	else:
		Net.send_reliable(self, &"request_grenade", 1, [Net.local_id(), eye_of(me), dir])

func reload_local() -> void:
	var st := state_for(Net.local_id())
	if st.start_reload(now_s(), reload_speed_of(Net.local_id())) and not Net.is_host():
		Net.send_reliable(self, &"request_reload", 1, [])

@rpc("authority", "unreliable")
func _rx_dummy(id: int, pos: Vector3) -> void:
	if Net.is_host() or id != DUMMY_ID:
		return
	if dummy == null:
		dummy = TargetDummy.new()
		add_child(dummy)
		register_target(DUMMY_ID, dummy)
	_dummy_buf.append([Time.get_ticks_msec(), pos])
	if _dummy_buf.size() > 40:
		_dummy_buf.pop_front()

@rpc("authority", "unreliable")
func _rx_ping(nonce: int) -> void:
	if Net.is_host():
		return
	Net.send_unreliable(self, &"_rx_pong", 1, [nonce])

## Only a pong that answers a ping the host really sent, once per peer, counts.
@rpc("any_peer", "unreliable")
func _rx_pong(nonce) -> void:
	if not Net.is_host() or typeof(nonce) != TYPE_INT or not _pings.has(nonce):
		return
	var id := multiplayer.get_remote_sender_id()
	var p: Array = _pings[nonce]
	if id == 0 or not net.players.has(id) or p[1].has(id):
		return
	p[1][id] = true
	var rtt := now_s() - float(p[0])
	if rtt <= 0.0 or rtt > 2.0:
		return
	var old := net.clock.rtt(id)
	net.clock.set_rtt(id, rtt if old == 0.0 else lerpf(old, rtt, 0.2))

## Host verdict for one of my shots. kind: MISS | HIT | REJECTED.
@rpc("authority", "reliable")
func _rx_result(t: float, kind: int, reason: String, mag: int, reserve: int, target: int, dmg: float, headshot: bool, held: int = 0) -> void:
	if Net.is_host():
		return
	_inflight = maxi(_inflight - 1, 0)
	if not _inflight_slots.is_empty():
		_inflight_slots.pop_front()
	if held == 0 or held == 1:
		_apply_host_ammo(held, mag, reserve)
	view.resolve(t, kind == HIT)
	result_received.emit(t, kind, StringName(reason), target, dmg, headshot)

## The host is authoritative for ammo; shots still in flight are subtracted so the display never flickers.
func _apply_host_ammo(slot: int, mag: int, reserve: int) -> void:
	var st := kit_for(Net.local_id()).slots[slot]
	if st == null or st.reloading:
		return                               # the local reload will land on the same numbers
	st.mag = maxi(mag - _inflight_slots.count(slot), 0)
	st.reserve = reserve

## Host -> peer: the whole kit (held slot, both guns' ammo, grenades). `force` (after a buy / swap / throw)
## applies even while shots are in flight; the periodic copy waits for their verdicts.
func send_kit(peer: int, force := true) -> void:
	if not Net.is_host() or peer == Net.local_id() or not kits.has(peer):
		return
	var a := kit_args(peer)
	Net.send_reliable(self, &"_rx_kit", peer, a + [force])

## Host: the arguments of apply_kit for `peer` (without `force`): held, ids, mags, reserves, grenades, swap ack.
func kit_args(peer: int) -> Array:
	var k := kit_for(peer)
	var ids: Array = []
	var mags: Array = []
	var res: Array = []
	for st in k.slots:
		ids.append(String(st.data.id) if st != null else "")
		mags.append(st.mag if st != null else 0)
		res.append(st.reserve if st != null else 0)
	return [k.held, ids, mags, res, k.grenades, _swap_count.get(peer, 0)]

@rpc("authority", "reliable")
func _rx_kit(held: int, ids: Array, mags: Array, res: Array, grenades: int, swap_ack: int, force: bool) -> void:
	apply_kit(held, ids, mags, res, grenades, swap_ack, force)

## Client: take the host's kit (a kit message or the late join WorldSnapshot).
func apply_kit(held: int, ids: Array, mags: Array, res: Array, grenades: int, swap_ack: int, force: bool) -> void:
	if Net.is_host() or (_inflight > 0 and not force) or ids.size() != 2 or mags.size() != 2 or res.size() != 2:
		return
	var k := kit_for(Net.local_id())
	if swap_ack == _swaps_sent and (held == 0 or held == 1) and ids[held] != "":
		k.held = held                         # no swap of mine is still travelling: the host's choice stands
	for i in 2:
		if ids[i] == "":
			k.slots[i] = null
			continue
		var d := Content.weapon(StringName(ids[i]))
		if d == null:
			continue
		var st := k.slots[i]
		if st == null or st.data.id != d.id:
			st = WeaponState.new(d)
			k.slots[i] = st
		elif i == k.held and st.reloading:
			continue                          # the local reload lands on the same numbers
		st.mag = maxi(int(mags[i]) - _inflight_slots.count(i), 0)
		st.reserve = int(res[i])
		if i != k.held:
			st.reloading = false
	if k.slots[k.held] == null:
		k.held = 1 - k.held
	k.grenades = grenades
	_sync_recoil()

# ---------------------------------------------------------------- host side

static func _num(v) -> bool:
	return (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT) and is_finite(float(v))

static func _vec(v) -> bool:
	return typeof(v) == TYPE_VECTOR3 and (v as Vector3).is_finite()

@rpc("any_peer", "reliable")
func request_fire(shooter, origin, dir, t, _client_seq = 0) -> void:
	if not Net.is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return                               # a local call is not a request
	if not _take_token(sender):
		return                               # flood: dropped silently
	var seq := _next_seq(sender)           # the host counts requests itself; the client's seq is ignored
	if not (_vec(origin) and _vec(dir) and _num(t)):
		_reject(sender, &"malformed", t if _num(t) else 0.0)
		return
	if typeof(shooter) != TYPE_INT or not Net.sender_is(shooter):
		_reject(sender, &"sender", float(t))
		return
	handle_fire(sender, shooter, origin, dir, float(t), seq)

@rpc("any_peer", "reliable")
func request_reload() -> void:
	if not Net.is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0 or not _take_token(sender) or not net.players.has(sender):
		return
	_start_reload_for(sender)

## Host: begin the reload of `peer`'s held gun; the Suds make it faster.
func _start_reload_for(peer: int) -> bool:
	return state_for(peer).start_reload(now_s(), reload_speed_of(peer))

func _peek_seq(peer: int) -> int:
	return _counters.get(peer, 0)

func _next_seq(peer: int) -> int:
	var n: int = _counters.get(peer, 0)
	_counters[peer] = n + 1
	return n

func _take_token(peer: int) -> bool:
	var now := Time.get_ticks_msec()
	var b: Array = _bucket.get(peer, [BUCKET_MAX, now])
	b[0] = minf(b[0] + (now - b[1]) * 0.001 * BUCKET_REFILL, BUCKET_MAX)
	b[1] = now
	var ok: bool = b[0] >= 1.0
	if ok:
		b[0] -= 1.0
	_bucket[peer] = b
	return ok

func _reject(peer: int, reason: StringName, t: float) -> void:
	fire_rejected.emit(peer, reason)
	_reply(peer, t, REJECTED, reason, 0, 0.0, false)

func _reply(peer: int, t: float, kind: int, reason: StringName, target: int, dmg: float, head: bool) -> void:
	var st := state_for(peer)
	if peer == Net.local_id():
		view.resolve(t, kind == HIT)
		result_received.emit(t, kind, reason, target, dmg, head)
		return
	Net.send_reliable(self, &"_rx_result", peer, [t, kind, String(reason), st.mag, st.reserve, target, dmg, head, kit_for(peer).held])

## Validate and resolve one shot. `t` is the shooter's client clock stamp (host's own clock for the host).
func handle_fire(sender: int, shooter: int, origin: Vector3, dir: Vector3, t: float, seq: int) -> void:
	if not Net.is_host():
		return
	if shooter != sender:
		_reject(sender, &"sender", t)
		return
	if absf(dir.length() - 1.0) > 0.1:
		_reject(sender, &"malformed", t)
		return
	dir = dir.normalized()
	var p: Player = net.players.get(shooter)
	if p == null or not _may_fire(p):
		_reject(sender, &"state", t)
		return
	if eye_of(p).distance_to(origin) > balance().shot_origin_tolerance:
		_reject(sender, &"origin", t)
		return
	var now := now_s()
	var st_time := _rewind_time(sender, t, now)
	if kit_for(shooter).swap_blocked(now, balance().swap_s * SWAP_TOL):
		_reject(sender, &"swap", t)
		return
	var mult := (1.0 + balance().fire_rate_tolerance) * rate_mult_of(shooter)
	var ws := state_for(shooter)
	var reason := ws.block_reason(_fire_clock(sender, t, now), mult)
	if reason != &"":
		_reject(sender, reason, t)
		return
	ws.fire(_fire_clock(sender, t, now), mult)
	var ads: bool = ((net.local_buttons if sender == Net.local_id() else net.last_buttons.get(sender, 0)) & InputFrame.ADS) != 0
	dir = Spread.offset_dir(dir, Spread.cone_deg(ws.data, ads), sender, seq)
	_trace(sender, shooter, origin, dir, t, st_time, ws)

## Clock used for the rate limiter: the shooter's own stamp mapped to host time, so network
## jitter on arrival cannot make an honest shooter look fast or slow.
func _fire_clock(sender: int, t: float, now: float) -> float:
	if sender == Net.local_id() or not net.clock.has(sender):
		return now
	return clampf(t - net.clock.offset(sender), now - ClockSync.MAX_REWIND, now)

func _wall_dist(origin: Vector3, dir: Vector3) -> float:
	var max_d := balance().max_shot_range
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * max_d, 1)
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	return INF if r.is_empty() else origin.distance_to(r.position)

## Nearest live target the ray hits at rewound time `st_time`: {found, t, id, head}. Corpses never absorb a bullet.
func pick_target(origin: Vector3, dir: Vector3, st_time: float) -> Dictionary:
	var max_d := balance().max_shot_range
	var out := {"found": false, "t": INF, "id": 0, "head": false}     # id 0 is never used (peers > 0, zombies < 0, dummy 1000)
	for id in targets:
		var tg: HitTarget = targets[id]
		if not tg.alive:
			continue
		var pose = history.pose_at(id, st_time)
		if pose == null:
			continue
		var h: Dictionary = tg.ray_at(pose, origin, dir)
		if not h.is_empty() and h.t < out.t and h.t <= max_d:
			out = {"found": true, "t": h.t, "id": id, "head": h.head}
	return out

func _trace(sender: int, shooter: int, origin: Vector3, dir: Vector3, t: float, st_time: float, ws: WeaponState) -> void:
	var pick := pick_target(origin, dir, st_time)
	var best_t: float = pick.t
	var best_id: int = pick.id
	var found: bool = pick.found
	var best_head: bool = pick.head
	if not found:
		_reply(sender, t, MISS, &"", 0, 0.0, false)
		return
	if _wall_dist(origin, dir) < best_t - SKIN:
		_reject(sender, &"los", t)
		return
	var dmg := ws.damage_at(best_t) * (balance().headshot_mult if best_head else 1.0)
	last_rewind = {"id": best_id, "time": st_time, "now": now_s()}
	hit.emit(shooter, best_id, dmg, best_head)
	_reply(sender, t, HIT, &"", best_id, dmg, best_head)

# ---------------------------------------------------------------- swap / melee / grenade (host)

func _rewind_time(sender: int, t: float, now: float) -> float:
	if sender == Net.local_id() or not lag_comp:
		return now
	return clampf(net.clock.rewind_time(sender, t, now, Player.INTERP_DELAY_MS / 1000.0), now - ClockSync.MAX_REWIND, now)

@rpc("any_peer", "reliable")
func request_swap() -> void:
	if not Net.is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender == 0:
		return
	_swap_count[sender] = _swap_count.get(sender, 0) + 1    # counted even when refused: the client matches it
	var p: Player = net.players.get(sender)
	if p == null or p.state != Player.ALIVE or not _take_token(sender):
		return                               # flood / dead: no reply (the next periodic kit carries the ack)
	kit_for(sender).swap(now_s(), balance().swap_s * SWAP_TOL)
	send_kit(sender, true)

## Shared checks of a melee / grenade request: finite values, sender, alive, origin near the host's eye.
func _vet(sender: int, shooter, origin, dir) -> Player:
	if sender == 0 or not _take_token(sender):
		return null
	if not (_vec(origin) and _vec(dir)) or typeof(shooter) != TYPE_INT or not Net.sender_is(shooter):
		return null
	return _vet_pose(sender, origin, dir)

func _vet_pose(sender: int, origin: Vector3, dir: Vector3) -> Player:
	if absf(dir.length() - 1.0) > 0.1:
		return null
	var p: Player = net.players.get(sender)
	if p == null or p.state != Player.ALIVE or eye_of(p).distance_to(origin) > balance().shot_origin_tolerance:
		return null
	return p

@rpc("any_peer", "reliable")
func request_melee(shooter, origin, dir, t) -> void:
	if not Net.is_host() or not _num(t):
		return
	var sender := multiplayer.get_remote_sender_id()
	if _vet(sender, shooter, origin, dir) == null:
		return
	_melee(sender, origin, (dir as Vector3).normalized(), float(t))

@rpc("any_peer", "reliable")
func request_grenade(shooter, origin, dir) -> void:
	if not Net.is_host():
		return
	var sender := multiplayer.get_remote_sender_id()
	if _vet(sender, shooter, origin, dir) == null:
		return
	_throw(sender, origin, (dir as Vector3).normalized())

func _blocked_by_wall(from: Vector3, to: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to, 1)
	return not get_world_3d().direct_space_state.intersect_ray(q).is_empty()

## Host: one knife swing. Returns the target id hit (0 = none, or refused by the cooldown / state checks).
func handle_melee(sender: int, origin: Vector3, dir: Vector3, t: float) -> int:
	if not Net.is_host() or _vet_pose(sender, origin, dir) == null:
		return 0
	return _melee(sender, origin, dir, t)

func _melee(sender: int, origin: Vector3, dir: Vector3, t: float) -> int:
	var now := now_s()
	var m: Melee = _melees.get(sender)
	if m == null:
		m = Melee.new()
		_melees[sender] = m
	var clk := _fire_clock(sender, t, now)
	if not m.ready(clk, balance().melee_cooldown_s, balance().fire_rate_tolerance):
		return 0
	m.swing(clk)
	var st_time := _rewind_time(sender, t, now)
	var cands: Array = []
	for id in targets:
		var tg: HitTarget = targets[id]
		if not tg.alive:
			continue
		var pose = history.pose_at(id, st_time)
		if pose == null:
			continue
		var pts: Array = []
		for b in tg.boxes:
			pts.append((pose as Transform3D) * (b.aabb as AABB).get_center())
		cands.append({"id": id, "points": pts})
	var hit_id := Melee.pick(origin, dir, cands, balance().melee_range, balance().melee_cone_deg, _blocked_by_wall)
	if hit_id != 0:
		last_melee[sender] = {"id": hit_id, "time": st_time}
		melee_hit.emit(sender, hit_id, balance().melee_damage)
	return hit_id

## Host: throw one grenade from the eye along `dir`. False if refused.
func handle_grenade(sender: int, origin: Vector3, dir: Vector3) -> bool:
	if not Net.is_host() or _vet_pose(sender, origin, dir) == null:
		return false
	return _throw(sender, origin, dir)

func _throw(sender: int, origin: Vector3, dir: Vector3) -> bool:
	var now := now_s()
	var cd := balance().grenade_cooldown_s
	if now < _next_throw.get(sender, -INF) - cd * SWAP_TOL:
		return false
	var kit := kit_for(sender)
	if not kit.take_grenade():
		return false
	_next_throw[sender] = now + cd
	var d := Content.throwable(&"frag")
	var gid := _next_gid
	_next_gid += 1
	var at := origin + dir * 0.5
	var vel := dir * d.throw_speed
	var g := _make_grenade(gid, sender, d, at, vel, true)
	g.exploded.connect(_on_boom)
	Net.send_reliable(self, &"_rx_grenade_spawn", 0, [gid, sender, at, vel])
	send_kit(sender, true)
	return true

func _make_grenade(gid: int, by: int, d: ThrowableData, at: Vector3, vel: Vector3, host: bool) -> Grenade:
	var g: Grenade = grenade_scene.instantiate()
	g.launch(gid, by, d, at, vel, host)
	add_child(g)
	grenades_live[gid] = g
	return g

func _on_boom(gid: int, thrower: int, pos: Vector3) -> void:
	var g: Grenade = grenades_live.get(gid)
	grenades_live.erase(gid)
	var d: ThrowableData = g.data if g != null else Content.throwable(&"frag")
	if g != null:
		g.queue_free()
	var center := pos + Vector3(0, 0.25, 0)
	var cands: Array = []
	for id in targets:
		var tg: HitTarget = targets[id]
		if tg.alive and not tg.boxes.is_empty():
			cands.append({"id": id, "pos": tg.global_transform * (tg.boxes[0].aabb as AABB).get_center()})
	for r in Grenade.blast(center, cands, d, _blocked_by_wall):
		grenade_hit.emit(thrower, r.id, r.dmg)
	Net.send_reliable(self, &"_rx_grenade_boom", 0, [gid, pos])
	view.explosion(pos, d.radius)

@rpc("authority", "reliable")
func _rx_grenade_spawn(gid: int, thrower: int, at: Vector3, vel: Vector3) -> void:
	if Net.is_host() or not _vec(at) or not _vec(vel):
		return
	spawn_rx += 1
	_make_grenade(gid, thrower, Content.throwable(&"frag"), at, vel, false)

@rpc("authority", "reliable")
func _rx_grenade_boom(gid: int, pos: Vector3) -> void:
	if Net.is_host():
		return
	boom_rx += 1
	var g: Grenade = grenades_live.get(gid)
	grenades_live.erase(gid)
	if g != null:
		g.queue_free()
	view.explosion(pos, Content.throwable(&"frag").radius)
