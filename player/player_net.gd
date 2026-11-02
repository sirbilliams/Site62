class_name PlayerNet
extends Node3D
## Spawns a Player per roster entry; 60 Hz input up (last 3 frames per packet), 20 Hz snapshots down.
## Host is authoritative: it runs Motor on received frames and acks `seq` in snapshots.

const DT := 1.0 / 60.0
const SNAP_EVERY := 3            # physics ticks per snapshot (20 Hz)
const BATCH := 3
const PLAYER_SCENE := preload("res://player/player.tscn")

var players := {}                # peer id -> Player
var spawn := Vector3(0, 0.2, 0)
var input_source := Callable()   # () -> InputFrame (move/buttons/look); default samples the keyboard
var _seq := 0
var _recent: Array = []          # last BATCH sent frames as arrays
var _last_seq := {}              # host: peer id -> last applied seq
var _tick := 0
var _yaw := 0.0
var _pitch := 0.0

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= e.relative.x * 0.002
		_pitch = clampf(_pitch - e.relative.y * 0.002, -1.4, 1.4)

func _sample_keyboard() -> InputFrame:
	var f := InputFrame.new()
	f.move = Vector2(Input.get_axis(&"ui_left", &"ui_right"), Input.get_axis(&"ui_down", &"ui_up"))
	if Input.is_key_pressed(KEY_A): f.move.x -= 1
	if Input.is_key_pressed(KEY_D): f.move.x += 1
	if Input.is_key_pressed(KEY_W): f.move.y += 1
	if Input.is_key_pressed(KEY_S): f.move.y -= 1
	f.move = f.move.limit_length(1.0)
	if Input.is_key_pressed(KEY_SPACE): f.buttons |= InputFrame.JUMP
	if Input.is_key_pressed(KEY_SHIFT): f.buttons |= InputFrame.SPRINT
	if Input.is_key_pressed(KEY_CTRL): f.buttons |= InputFrame.CROUCH
	f.look_yaw = _yaw
	f.look_pitch = _pitch
	return f

func _space() -> PhysicsDirectSpaceState3D:
	return get_world_3d().direct_space_state

func ensure_player(id: int) -> Player:
	if players.has(id):
		return players[id]
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
		_tick += 1
		if _tick % SNAP_EVERY == 0:
			_send_snapshot()

func _local_tick(me: Player) -> void:
	var f: InputFrame = input_source.call() if input_source.is_valid() else _sample_keyboard()
	f.seq = _seq
	_seq += 1
	f.t = Time.get_ticks_msec() / 1000.0
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
	if not Net.is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	if not Net.players.has(id) or batch.size() > 8:
		return
	var p := ensure_player(id)
	var frames: Array = []
	for a in batch:
		if a is Array:
			frames.append(InputFrame.from_array(a))
	frames.sort_custom(func(x: InputFrame, y: InputFrame): return x.seq < y.seq)
	var last: int = _last_seq.get(id, -1)
	for f: InputFrame in frames:
		if f.seq > last:
			p.simulate(f, _space(), DT, false)
			last = f.seq
	_last_seq[id] = last

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
			ensure_player(s.id).apply_snapshot(s, _space(), DT)
