class_name Settings
extends RefCounted
## Player settings (mouse sensitivity, FOV, master volume, key + gamepad bindings), saved to user://settings.cfg.
## Static state: no node needed. Bindings are codes: "k:<physical keycode>", "m:<mouse button>", "b:<joy button>",
## "a:<joy axis>:+" / "a:<joy axis>:-". Every action has one keyboard/mouse code and one gamepad code.

const PATH := "user://settings.cfg"
const SENS_MIN := 0.2
const SENS_MAX := 3.0
const FOV_MIN := 60.0
const FOV_MAX := 110.0
const AXIS_PRESS := 0.5

# [action, label, default keyboard/mouse code, default gamepad code]
const ACTIONS := [
	[&"move_forward", "Move forward", "k:%d" % KEY_W, "a:1:-"],
	[&"move_back", "Move back", "k:%d" % KEY_S, "a:1:+"],
	[&"move_left", "Move left", "k:%d" % KEY_A, "a:0:-"],
	[&"move_right", "Move right", "k:%d" % KEY_D, "a:0:+"],
	[&"jump", "Jump", "k:%d" % KEY_SPACE, "b:0"],
	[&"sprint", "Sprint", "k:%d" % KEY_SHIFT, "b:7"],
	[&"crouch", "Crouch", "k:%d" % KEY_CTRL, "b:1"],
	[&"fire", "Fire", "m:1", "a:5:+"],
	[&"ads", "Aim down sights", "m:2", "a:4:+"],
	[&"reload", "Reload", "k:%d" % KEY_R, "b:2"],
	[&"use", "Use / revive", "k:%d" % KEY_F, "b:9"],
	[&"melee", "Melee", "k:%d" % KEY_V, "b:8"],
	[&"grenade", "Grenade", "k:%d" % KEY_G, "b:10"],
	[&"swap", "Swap weapon", "k:%d" % KEY_Q, "b:3"],
]
## Fixed gamepad look stick (not rebindable).
const LOOK_AXES := {&"look_left": [2, -1.0], &"look_right": [2, 1.0], &"look_up": [3, -1.0], &"look_down": [3, 1.0]}
const PAD_LOOK_DEG_S := 220.0

static var mouse_sens := 1.0         # multiplier on 0.002 rad/pixel
static var fov := 75.0
static var volume := 0.8             # master, linear 0..1
static var using_pad := false        # last input device (prompts show the matching button)
static var _bind := {}               # action -> {"kb": code, "pad": code}

static func reset_defaults() -> void:
	mouse_sens = 1.0
	fov = 75.0
	volume = 0.8
	_bind = {}
	for a in ACTIONS:
		_bind[a[0]] = {"kb": a[2], "pad": a[3]}

static func _ensure() -> void:
	if _bind.is_empty():
		reset_defaults()

static func _known(action: StringName) -> bool:
	for a in ACTIONS:
		if a[0] == action:
			return true
	return false

static func binding(action: StringName, pad: bool) -> String:
	_ensure()
	return _bind.get(action, {}).get("pad" if pad else "kb", "")

static func set_binding(action: StringName, pad: bool, code: String) -> void:
	_ensure()
	if _known(action) and code_to_event(code) != null:
		_bind[action]["pad" if pad else "kb"] = code

## Rebind and swap with whichever action already used `code` on the same device, so nothing is left unbound.
static func rebind(action: StringName, pad: bool, code: String) -> void:
	_ensure()
	if not _known(action) or code_to_event(code) == null:
		return
	var key := "pad" if pad else "kb"
	var old: String = _bind[action][key]
	for a in ACTIONS:
		if a[0] != action and _bind[a[0]][key] == code:
			_bind[a[0]][key] = old
	_bind[action][key] = code

## Label of the key / button for `action` on the device last used.
static func key_label(action: StringName) -> String:
	return code_label(binding(action, using_pad))

# ---------------------------------------------------------------- codes

static func event_to_code(e: InputEvent) -> String:
	if e is InputEventKey and e.pressed and not e.echo:
		var k: int = e.physical_keycode if e.physical_keycode != 0 else e.keycode
		return "k:%d" % k if k != 0 else ""
	if e is InputEventMouseButton and e.pressed:
		return "m:%d" % e.button_index
	if e is InputEventJoypadButton and e.pressed:
		return "b:%d" % e.button_index
	if e is InputEventJoypadMotion and absf(e.axis_value) >= AXIS_PRESS:
		return "a:%d:%s" % [e.axis, "+" if e.axis_value > 0.0 else "-"]
	return ""

static func code_to_event(code: String) -> InputEvent:
	var p := code.split(":")
	if p.size() < 2 or not p[1].is_valid_int():
		return null
	var n := int(p[1])
	match p[0]:
		"k":
			if n <= 0:
				return null
			var k := InputEventKey.new()
			k.physical_keycode = n as Key
			return k
		"m":
			if n < 1 or n > 9:
				return null
			var m := InputEventMouseButton.new()
			m.button_index = n as MouseButton
			return m
		"b":
			if n < 0 or n > 20:
				return null
			var b := InputEventJoypadButton.new()
			b.button_index = n as JoyButton
			return b
		"a":
			if p.size() != 3 or n < 0 or n > 9 or not (p[2] == "+" or p[2] == "-"):
				return null
			var a := InputEventJoypadMotion.new()
			a.axis = n as JoyAxis
			a.axis_value = 1.0 if p[2] == "+" else -1.0
			return a
	return null

const _BTN := ["A", "B", "X", "Y", "Back", "Guide", "Start", "L3", "R3", "LB", "RB", "Up", "Down", "Left", "Right"]
const _AXES := ["Left stick X", "Left stick Y", "Right stick X", "Right stick Y", "LT", "RT"]

static func code_label(code: String) -> String:
	var p := code.split(":")
	if p.size() < 2 or not p[1].is_valid_int():
		return "?"
	var n := int(p[1])
	match p[0]:
		"k":
			return OS.get_keycode_string(n as Key)
		"m":
			return "Mouse %d" % n
		"b":
			return _BTN[n] if n < _BTN.size() else "Btn %d" % n
		"a":
			var sign: String = p[2] if p.size() > 2 else "+"
			if n >= 4:
				return _AXES[n] if n < _AXES.size() else "Axis %d" % n
			var base: String = _AXES[n] if n < _AXES.size() else "Axis %d" % n
			if n == 0:
				return "Left stick " + ("right" if sign == "+" else "left")
			if n == 1:
				return "Left stick " + ("down" if sign == "+" else "up")
			return base + sign
	return "?"

# ---------------------------------------------------------------- file

static func save_file(path := PATH) -> int:
	_ensure()
	var c := ConfigFile.new()
	c.set_value("input", "mouse_sens", mouse_sens)
	c.set_value("video", "fov", fov)
	c.set_value("audio", "volume", volume)
	for a in ACTIONS:
		c.set_value("keys", String(a[0]), _bind[a[0]]["kb"])
		c.set_value("pad", String(a[0]), _bind[a[0]]["pad"])
	return c.save(path)

## True if a file was read. Missing or bad entries keep their defaults; numbers are clamped.
static func load_file(path := PATH) -> bool:
	_ensure()
	var c := ConfigFile.new()
	if c.load(path) != OK:
		return false
	mouse_sens = clampf(_num(c.get_value("input", "mouse_sens", mouse_sens), mouse_sens), SENS_MIN, SENS_MAX)
	fov = clampf(_num(c.get_value("video", "fov", fov), fov), FOV_MIN, FOV_MAX)
	volume = clampf(_num(c.get_value("audio", "volume", volume), volume), 0.0, 1.0)
	for a in ACTIONS:
		for sec in ["keys", "pad"]:
			var v = c.get_value(sec, String(a[0]), "")
			if typeof(v) == TYPE_STRING and code_to_event(v) != null:
				_bind[a[0]]["pad" if sec == "pad" else "kb"] = v
	return true

static func _num(v, fallback: float) -> float:
	return float(v) if (typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_INT) and is_finite(float(v)) else fallback

# ---------------------------------------------------------------- apply

static func apply_bindings() -> void:
	_ensure()
	for a in ACTIONS:
		var id: StringName = a[0]
		if InputMap.has_action(id):
			InputMap.erase_action(id)
		InputMap.add_action(id, 0.2 if String(id).begins_with("move_") else 0.3)
		for pad in [false, true]:
			var ev := code_to_event(_bind[id]["pad" if pad else "kb"])
			if ev != null:
				InputMap.action_add_event(id, ev)
	for id in LOOK_AXES:
		if InputMap.has_action(id):
			InputMap.erase_action(id)
		InputMap.add_action(id, 0.15)
		var e := InputEventJoypadMotion.new()
		e.axis = LOOK_AXES[id][0] as JoyAxis
		e.axis_value = LOOK_AXES[id][1]
		InputMap.action_add_event(id, e)

static func ensure_actions() -> void:
	if not InputMap.has_action(&"fire"):
		apply_bindings()

## Volume to the Master bus.
static func apply_audio() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))

static func apply_all() -> void:
	apply_bindings()
	apply_audio()
