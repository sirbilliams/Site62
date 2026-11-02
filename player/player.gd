class_name Player
extends CharacterBody3D
## One player avatar. Position is driven by Motor (not by CharacterBody3D physics).
## Local client: predicts, keeps unacknowledged InputFrames, replays them after each host correction.
## Remote view: interpolates snapshots INTERP_DELAY behind the newest.

enum { ALIVE, DOWN, DEAD }
const INTERP_DELAY_MS := 100.0
const MAX_PENDING := 180
const EYE_HEIGHT := 1.6
const SMOOTH_S := 0.1

var peer_id := 0
var hp := 100.0
var state := ALIVE
var points := 0                  # host-owned, replicated
var is_local := false
var is_authority := false        # host simulating this player (local on host, or remote driven by inputs)
var balance: Balance
var motor_state := Motor.initial_state(Vector3.ZERO)
var pending: Array[InputFrame] = []
var last_ack := -1
var yaw := 0.0
var pitch := 0.0
var max_correction := 0.0         # largest reconcile jump seen (m)
var _offset_rate := 0.0
var _offset := Vector3.ZERO      # visual smoothing, decays over SMOOTH_S
var _buf: Array = []             # [recv_msec, pos, yaw]
var camera: Camera3D

## hp ceiling: the base, raised by Grape Bulwark.
func max_health() -> float:
	return Game.max_hp_of(peer_id, balance.player_hp if balance != null else 100.0)

func setup(id: int, bal: Balance, local: bool) -> void:
	peer_id = id
	balance = bal
	is_local = local
	hp = bal.player_hp
	name = str(id)
	collision_layer = 2          # players never block Motor's world rays (mask 1)
	collision_mask = 0
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = Motor.BODY_RADIUS
	cap.height = 1.8
	col.shape = cap
	col.position.y = 0.9
	add_child(col)
	if local:
		camera = Camera3D.new()
		camera.position.y = EYE_HEIGHT
		add_child(camera)
		camera.current = true

## Run one input frame through the motor. Local prediction also queues it for replay.
func simulate(f: InputFrame, space: PhysicsDirectSpaceState3D, dt: float, predicted: bool) -> void:
	motor_state = Motor.step(motor_state, _motor_frame(f), dt, space, balance)
	yaw = f.look_yaw
	pitch = f.look_pitch
	if predicted:
		pending.append(f)
		if pending.size() > MAX_PENDING:
			pending.pop_front()
	_show(motor_state.pos)

## What the motor sees: DOWN crawls (Balance.downed_move_mult, no jump / sprint), DEAD does not move.
func _motor_frame(f: InputFrame) -> InputFrame:
	if state == ALIVE:
		return f
	var g := InputFrame.new()
	g.seq = f.seq
	g.t = f.t
	g.look_yaw = f.look_yaw
	g.look_pitch = f.look_pitch
	g.move = Vector2.ZERO if state == DEAD else f.move * balance.downed_move_mult
	return g

## Host: put the avatar at `pos` right now (respawn).
func teleport(pos: Vector3) -> void:
	motor_state = Motor.initial_state(pos)
	_offset = Vector3.ZERO
	_show(pos)

func _show(p: Vector3) -> void:
	position = p + _offset
	rotation.y = yaw
	if camera:
		camera.rotation.x = pitch

## Host snapshot entry: {pos, vy, grounded, yaw, pitch, ack, hp, state, points}.
func apply_snapshot(s: Dictionary, space: PhysicsDirectSpaceState3D = null, dt := 1.0 / 60.0) -> void:
	hp = s.get("hp", hp)
	state = s.get("state", state)
	points = s.get("points", points)
	if is_authority:
		return
	if is_local:
		var ack: int = s.get("ack", -1)
		if ack < last_ack:
			return                       # stale (reordered) snapshot
		last_ack = ack
		var before: Vector3 = motor_state.pos
		motor_state = {"pos": s.pos, "vy": s.vy, "grounded": s.grounded}
		while not pending.is_empty() and pending[0].seq <= ack:
			pending.pop_front()
		for f in pending:                # replay unacknowledged inputs
			motor_state = Motor.step(motor_state, _motor_frame(f), dt, space, balance)
		var jump: float = before.distance_to(motor_state.pos)
		max_correction = maxf(max_correction, jump)
		# blend the visual toward the corrected position; motor_state itself snaps
		_offset = (_offset + before - motor_state.pos) if jump < 3.0 else Vector3.ZERO
		_offset_rate = _offset.length() / SMOOTH_S
		_show(motor_state.pos)
	else:
		_buf.append([Time.get_ticks_msec(), s.pos, float(s.get("yaw", 0.0)), float(s.get("pitch", 0.0))])
		if _buf.size() > 40:
			_buf.pop_front()

func _process(_dt: float) -> void:
	if _offset != Vector3.ZERO:
		_offset = _offset.move_toward(Vector3.ZERO, _offset_rate * _dt)
		if is_local or is_authority:
			_show(motor_state.pos)
	if is_local or is_authority or _buf.is_empty():
		return
	var rt := Time.get_ticks_msec() - INTERP_DELAY_MS
	while _buf.size() > 2 and _buf[1][0] <= rt:
		_buf.pop_front()
	if rt <= _buf[0][0] or _buf.size() == 1:
		_show_remote(_buf[0])
		return
	var a: Array = _buf[0]
	var b: Array = _buf[1]
	var k := clampf((rt - a[0]) / maxf(b[0] - a[0], 1.0), 0.0, 1.0)
	yaw = lerp_angle(a[2], b[2], k)
	pitch = lerpf(a[3], b[3], k)
	_show((a[1] as Vector3).lerp(b[1], k))

func _show_remote(e: Array) -> void:
	yaw = e[2]
	pitch = e[3]
	_show(e[1])
