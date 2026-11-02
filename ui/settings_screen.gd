class_name SettingsScreen
extends Control
## Settings: mouse sensitivity, FOV, master volume, and key + gamepad rebinds. Saves to user://settings.cfg.
## Menus work on gamepad (focus + d-pad / A / B); rebinding waits for the next key / button press.

signal closed

var _sens: HSlider
var _fov: HSlider
var _vol: HSlider
var _sens_l: Label
var _fov_l: Label
var _vol_l: Label
var _binds := {}                 # "action:pad" -> Button
var _capture := ""               # "action:pad" while waiting for a press
var _capture_age := 0.0
var _hint: Label
var _first: Control

func _ready() -> void:
	theme = UiTheme.make()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiTheme.Backdrop.new())
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right"]:
		m.add_theme_constant_override("margin_" + s, 110)
	m.add_theme_constant_override("margin_top", 50)
	m.add_theme_constant_override("margin_bottom", 50)
	add_child(m)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	m.add_child(root)
	root.add_child(UiTheme.body("SITE 62  //  OPERATOR PREFERENCES", 20, UiTheme.DIM))
	root.add_child(UiTheme.heading("SETTINGS", 64, UiTheme.AMBER))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 50)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	var left := PanelContainer.new()
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	cols.add_child(left)
	var lv := VBoxContainer.new()
	lv.custom_minimum_size = Vector2(560, 0)
	lv.add_theme_constant_override("separation", 12)
	left.add_child(lv)
	_sens = _slider(lv, "MOUSE / STICK SENSITIVITY", Settings.SENS_MIN, Settings.SENS_MAX, 0.05, Settings.mouse_sens)
	_sens_l = _sens.get_meta("label")
	_fov = _slider(lv, "FIELD OF VIEW", Settings.FOV_MIN, Settings.FOV_MAX, 1.0, Settings.fov)
	_fov_l = _fov.get_meta("label")
	_vol = _slider(lv, "MASTER VOLUME", 0.0, 1.0, 0.01, Settings.volume)
	_vol_l = _vol.get_meta("label")
	_first = _sens
	_sens.value_changed.connect(func(v): Settings.mouse_sens = v; _labels())
	_fov.value_changed.connect(func(v): Settings.fov = v; _labels())
	_vol.value_changed.connect(func(v): Settings.volume = v; Settings.apply_audio(); _labels())
	var reset := Button.new()
	reset.text = "RESET TO DEFAULTS"
	reset.pressed.connect(func():
		Settings.reset_defaults()
		Settings.apply_all()
		_sens.value = Settings.mouse_sens
		_fov.value = Settings.fov
		_vol.value = Settings.volume
		_refresh_binds())
	lv.add_child(reset)
	var back := Button.new()
	back.text = "SAVE AND BACK"
	back.pressed.connect(close)
	lv.add_child(back)
	_hint = UiTheme.body("", 20, UiTheme.AMBER)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lv.add_child(_hint)
	var right := PanelContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cols.add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)
	var head := HBoxContainer.new()
	rv.add_child(head)
	for t in [["CONTROL", 1.4], ["KEYBOARD / MOUSE", 1.0], ["GAMEPAD", 1.0]]:
		var l := UiTheme.body(t[0], 18, UiTheme.DIM)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_stretch_ratio = t[1]
		head.add_child(l)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rv.add_child(scroll)
	var grid := VBoxContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("separation", 4)
	scroll.add_child(grid)
	for a in Settings.ACTIONS:
		var r := HBoxContainer.new()
		grid.add_child(r)
		var l := UiTheme.body(a[1], 22)
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.size_flags_stretch_ratio = 1.4
		r.add_child(l)
		for pad in [false, true]:
			var b := Button.new()
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			b.add_theme_font_size_override("font_size", 20)
			b.add_theme_font_override("font", UiTheme.body_font())
			b.pressed.connect(_begin_capture.bind(a[0], pad))
			r.add_child(b)
			_binds["%s:%s" % [a[0], pad]] = b
	_refresh_binds()
	_labels()
	add_child(UiTheme.crt_overlay())
	visibility_changed.connect(func():
		if visible:
			_first.grab_focus())

func _slider(parent: Control, title: String, lo: float, hi: float, step: float, v: float) -> HSlider:
	var box := VBoxContainer.new()
	parent.add_child(box)
	var row := HBoxContainer.new()
	box.add_child(row)
	var t := UiTheme.body(title, 20, UiTheme.DIM)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(t)
	var val := UiTheme.body("", 24, UiTheme.AMBER)
	row.add_child(val)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = v
	s.focus_mode = Control.FOCUS_ALL
	s.custom_minimum_size = Vector2(0, 34)
	s.set_meta("label", val)
	box.add_child(s)
	return s

func _labels() -> void:
	_sens_l.text = "%.2fx" % Settings.mouse_sens
	_fov_l.text = "%d deg" % int(Settings.fov)
	_vol_l.text = "%d%%" % int(round(Settings.volume * 100.0))

func _refresh_binds() -> void:
	for a in Settings.ACTIONS:
		for pad in [false, true]:
			_binds["%s:%s" % [a[0], pad]].text = Settings.code_label(Settings.binding(a[0], pad))

func _begin_capture(action: StringName, pad: bool) -> void:
	_capture = "%s:%s" % [action, pad]
	_capture_age = 0.0
	_binds[_capture].text = "press a %s..." % ("button" if pad else "key")
	_hint.text = "Press the new %s. Esc cancels." % ("gamepad button" if pad else "key or mouse button")

func _process(dt: float) -> void:
	if _capture != "":
		_capture_age += dt
		if _capture_age > 8.0:
			_end_capture()

func _end_capture() -> void:
	_capture = ""
	_hint.text = ""
	_refresh_binds()

func _input(e: InputEvent) -> void:
	if not visible:
		return
	if _capture != "":
		if _capture_age < 0.15:
			return
		var pad := _capture.ends_with(":true")
		var action := StringName(_capture.substr(0, _capture.rfind(":")))
		if e is InputEventKey and e.pressed and e.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_end_capture()
			return
		var is_pad_ev := e is InputEventJoypadButton or e is InputEventJoypadMotion
		if is_pad_ev != pad:
			return
		var code := Settings.event_to_code(e)
		if code == "":
			return
		get_viewport().set_input_as_handled()
		Settings.rebind(action, pad, code)
		Settings.apply_bindings()
		_end_capture()
		return
	if e.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()

func close() -> void:
	Settings.save_file()
	closed.emit()
