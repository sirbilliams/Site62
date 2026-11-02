class_name InputFrame
extends RefCounted
## One tick of player input (60 Hz). Sent to the host in batches.

const JUMP := 1
const SPRINT := 2
const CROUCH := 4
const FIRE := 8
const ADS := 16
const RELOAD := 32
const USE := 64
const MELEE := 128
const GRENADE := 256
const NEXT_WEAPON := 512

var seq := 0
var move := Vector2.ZERO      # x = right, y = forward
var look_yaw := 0.0
var look_pitch := 0.0
var buttons := 0
var t := 0.0                  # client clock (s)

func to_array() -> Array:
	return [seq, move.x, move.y, look_yaw, look_pitch, buttons, t]

static func from_array(a: Array) -> InputFrame:
	var f := InputFrame.new()
	if a.size() < 7:
		return f
	f.seq = int(a[0])
	f.move = Vector2(float(a[1]), float(a[2])).limit_length(1.0)  # never trust the wire
	f.look_yaw = float(a[3])
	f.look_pitch = float(a[4])
	f.buttons = int(a[5])
	f.t = float(a[6])
	return f
