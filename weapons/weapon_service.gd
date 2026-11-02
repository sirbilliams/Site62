class_name WeaponService
extends Node3D
## Weapons: client fires locally at once (flash, tracer, predicted marker) and sends a stamped request;
## the host validates it (sender, rate, ammo, origin, line of sight), rewinds targets to what the shooter
## saw (HitHistory + ClockSync) and raycasts. `hit` is a signal only; Task 6 applies the damage.
## Must be a child of the same parent as PlayerNet, named "WeaponService" on every peer.

signal hit(shooter: int, target: int, dmg: float, headshot: bool)
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

var net: PlayerNet
var history := HitHistory.new()
var targets := {}                        # id -> HitTarget (host: authoritative; client: visual copies)
var states := {}                         # peer id -> WeaponState (host: all; client: local only)
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
var _counters := {}                      # host: peer id -> requests received (spread seed)
var _pings := {}                         # host: nonce -> [sent_s, {peer: true} answered]
var _nonce := 0

func _ready() -> void:
	name = "WeaponService"
	view = WeaponView.new()
	add_child(view)

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

func set_weapon(peer: int, weapon_id: StringName) -> bool:
	var d := Content.weapon(weapon_id)
	if d == null:
		return false
	states[peer] = WeaponState.new(d)
	if peer == Net.local_id():
		recoil = Recoil.new(d.recoil)
	return true

func state_for(peer: int) -> WeaponState:
	if not states.has(peer):
		set_weapon(peer, DEFAULT_WEAPON)
	return states[peer]

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
				var ws := state_for(id)
				Net.send_reliable(self, &"_rx_ammo", id, [ws.mag, ws.reserve])
	for st in states.values():
		(st as WeaponState).update(now)

func _client_tick() -> void:
	var st: WeaponState = states.get(Net.local_id())
	if st != null:
		st.update(now_s())
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
	if me == null or me.state != Player.ALIVE:
		return
	var b := net.local_buttons
	var st := state_for(Net.local_id())
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
	if not st.fire(t):
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
		Net.send_reliable(self, &"request_fire", 1, [Net.local_id(), origin, dir, t, seq])
	return true

func reload_local() -> void:
	var st := state_for(Net.local_id())
	if st.start_reload(now_s()) and not Net.is_host():
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
func _rx_result(t: float, kind: int, reason: String, mag: int, reserve: int, target: int, dmg: float, headshot: bool) -> void:
	if Net.is_host():
		return
	_inflight = maxi(_inflight - 1, 0)
	_apply_host_ammo(mag, reserve)
	view.resolve(t, kind == HIT)
	result_received.emit(t, kind, StringName(reason), target, dmg, headshot)

## The host is authoritative for ammo; shots still in flight are subtracted so the display never flickers.
func _apply_host_ammo(mag: int, reserve: int) -> void:
	var st := state_for(Net.local_id())
	if st.reloading:
		return                               # the local reload will land on the same numbers
	st.mag = maxi(mag - _inflight, 0)
	st.reserve = reserve

@rpc("authority", "reliable")
func _rx_ammo(mag: int, reserve: int) -> void:
	if Net.is_host() or _inflight > 0:
		return
	_apply_host_ammo(mag, reserve)

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
	state_for(sender).start_reload(now_s())

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
	Net.send_reliable(self, &"_rx_result", peer, [t, kind, String(reason), st.mag, st.reserve, target, dmg, head])

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
	if p == null or p.state != Player.ALIVE:
		_reject(sender, &"state", t)
		return
	if eye_of(p).distance_to(origin) > balance().shot_origin_tolerance:
		_reject(sender, &"origin", t)
		return
	var now := now_s()
	var st_time := now
	if sender != Net.local_id():
		st_time = clampf(net.clock.rewind_time(sender, t, now, Player.INTERP_DELAY_MS / 1000.0), now - ClockSync.MAX_REWIND, now) \
			if lag_comp else now
	var mult := 1.0 + balance().fire_rate_tolerance
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
