class_name PlayerNet
extends Node3D
## Spawns a Player per roster entry; 60 Hz input up (last 3 frames per packet), 20 Hz snapshots down.
## Host is authoritative: it runs Motor on received frames and acks `seq` in snapshots.

const DT := 1.0 / 60.0
const SNAP_EVERY := 3            # physics ticks per snapshot (20 Hz)
const BATCH := 3
const CREDIT_REFILL := 1.25      # frames per host physics tick (client runs 1.0)
const CREDIT_MAX := 6.0          # slack for jitter bursts
const MAX_SEQ_JUMP := 120
const PLAYER_SCENE := preload("res://player/player.tscn")

var players := {}                # peer id -> Player
var spawn := Vector3(0, 0.2, 0)
var input_source := Callable()   # () -> InputFrame (move/buttons/look); default samples the keyboard
var local_buttons := 0           # buttons of the last local frame (weapon service reads FIRE/RELOAD)
var clock := ClockSync.new()     # host: per-peer client clock model
var last_buttons := {}            # host: peer id -> buttons of the latest applied frame
var _seq := 0
var _recent: Array = []          # last BATCH sent frames as arrays
var _last_seq := {}              # host: peer id -> last applied seq
var _credit := {}                # host: peer id -> frame credit (rate cap)
var _tick := 0
var _yaw := 0.0
var _pitch := 0.0

var input_enabled := true         # false while a menu or the lobby is up: frames carry no buttons or movement

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var k := 0.002 * Settings.mouse_sens
		_yaw -= e.relative.x * k
		_pitch = clampf(_pitch - e.relative.y * k, -1.4, 1.4)

## The default input source: Settings actions (keyboard, mouse and gamepad).
func _sample_keyboard() -> InputFrame:
	var f := InputFrame.new()
	f.look_yaw = _yaw
	f.look_pitch = _pitch
	if not input_enabled:
		return f
	Settings.ensure_actions()
	f.move = Vector2(Input.get_axis(&"move_left", &"move_right"), Input.get_axis(&"move_back", &"move_forward")).limit_length(1.0)
	var look := Vector2(Input.get_axis(&"look_left", &"look_right"), Input.get_axis(&"look_up", &"look_down"))
	if look != Vector2.ZERO:                         # gamepad right stick, response curve for fine aim
		var step := deg_to_rad(Settings.PAD_LOOK_DEG_S) * DT * Settings.mouse_sens
		_yaw -= look.x * absf(look.x) * step
		_pitch = clampf(_pitch - look.y * absf(look.y) * step, -1.4, 1.4)
	var map := {&"jump": InputFrame.JUMP, &"sprint": InputFrame.SPRINT, &"crouch": InputFrame.CROUCH, &"fire": InputFrame.FIRE,
		&"reload": InputFrame.RELOAD, &"ads": InputFrame.ADS, &"use": InputFrame.USE, &"melee": InputFrame.MELEE,
		&"grenade": InputFrame.GRENADE, &"swap": InputFrame.NEXT_WEAPON}
	for a in map:
		if Input.is_action_pressed(a):
			f.buttons |= map[a]
	f.look_yaw = _yaw
	f.look_pitch = _pitch
	return f

func _space() -> PhysicsDirectSpaceState3D:
	if not is_inside_tree():
		return null
	return get_world_3d().direct_space_state

func ensure_player(id: int) -> Player:
	if players.has(id):
		return players[id]
	if not Net.players.has(id):
		return null                  # no ghost players
	var p: Player = PLAYER_SCENE.instantiate()
	p.setup(id, Content.balance, id == Net.local_id())
	p.is_authority = Net.is_host()
	add_child(p)
	p.motor_state = Motor.initial_state(spawn)
	p.position = spawn
	players[id] = p
	return p

func _sync_roster() -> void:
	for id in Net.players.ids():
		ensure_player(id)
	for id in players.keys():
		if not Net.players.has(id):
			players[id].queue_free()
			players.erase(id)
			_last_seq.erase(id)
			_credit.erase(id)
			clock.forget(id)
			last_buttons.erase(id)

## Nudge the local look direction (recoil kick and its recovery), radians.
func add_look(dyaw: float, dpitch: float) -> void:
	_yaw += dyaw
	_pitch = clampf(_pitch + dpitch, -1.4, 1.4)

func local_player() -> Player:
	return players.get(Net.local_id())

func _physics_process(_dt: float) -> void:
	if multiplayer.multiplayer_peer == null or multiplayer.multiplayer_peer is OfflineMultiplayerPeer:
		return
	_sync_roster()
	var me := local_player()
	if me != null:
		_local_tick(me)
	if Net.is_host():
		_refill_credit()
		_tick += 1
		if _tick % SNAP_EVERY == 0:
			_send_snapshot()

func _local_tick(me: Player) -> void:
	var f: InputFrame = input_source.call() if input_source.is_valid() else _sample_keyboard()
	f.seq = _seq
	_seq += 1
	f.t = Time.get_ticks_msec() / 1000.0
	local_buttons = f.buttons
	if Net.is_host():
		me.simulate(f, _space(), DT, false)
		return
	me.simulate(f, _space(), DT, true)
	_recent.append(f.to_array())
	if _recent.size() > BATCH:
		_recent.pop_front()
	Net.send_unreliable(self, &"_rx_inputs", 1, [_recent.duplicate()])

@rpc("any_peer", "unreliable")
func _rx_inputs(batch: Array) -> void:
	if not Net.is_host() or batch.size() > 8:
		return
	_apply_batch(multiplayer.get_remote_sender_id(), batch)

## Host: apply new frames from `id`. Returns how many were applied.
## Dropped: malformed, duplicate/old seq, seq jumps > MAX_SEQ_JUMP, and anything beyond the rate credit.
func _apply_batch(id: int, batch: Array) -> int:
	var p := ensure_player(id)
	if p == null:
		return 0
	var frames: Array = []
	for a in batch:
		var f := InputFrame.from_array(a)
		if f != null:
			frames.append(f)
	frames.sort_custom(func(x: InputFrame, y: InputFrame): return x.seq < y.seq)
	var last: int = _last_seq.get(id, -1)
	var credit: float = _credit.get(id, CREDIT_MAX)
	var applied := 0
	for f: InputFrame in frames:
		if f.seq <= last or f.seq > last + MAX_SEQ_JUMP:
			continue
		if credit < 1.0:
			break                    # excess is dropped, never queued
		credit -= 1.0
		p.simulate(f, _space(), DT, false)
		clock.observe(id, f.t, Time.get_ticks_msec() / 1000.0)
		last_buttons[id] = f.buttons
		last = f.seq
		applied += 1
	_last_seq[id] = last
	_credit[id] = credit
	return applied

func _refill_credit() -> void:
	for id in _credit.keys():
		_credit[id] = minf(_credit[id] + CREDIT_REFILL, CREDIT_MAX)

func _send_snapshot() -> void:
	var out: Array = []
	for id in players:
		var p: Player = players[id]
		out.append({"id": id, "pos": p.motor_state.pos, "vy": p.motor_state.vy, "grounded": p.motor_state.grounded,
			"yaw": p.yaw, "pitch": p.pitch, "ack": _last_seq.get(id, -1), "hp": p.hp, "state": p.state, "points": p.points})
	Net.send_unreliable(self, &"_rx_snapshot", 0, [out])

@rpc("authority", "unreliable")
func _rx_snapshot(entries: Array) -> void:
	if Net.is_host():
		return
	for s in entries:
		if s is Dictionary and s.has("id") and s.has("pos"):
			var p := ensure_player(s.id)
			if p != null:
				p.apply_snapshot(s, _space(), DT)
