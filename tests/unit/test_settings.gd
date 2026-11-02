extends TestCase

const PATH := "user://test_settings.cfg"

func _reset() -> void:
	Settings.reset_defaults()
	if FileAccess.file_exists(PATH):
		DirAccess.remove_absolute(PATH)

func test_defaults() -> void:
	_reset()
	assert_near(Settings.mouse_sens, 1.0)
	assert_near(Settings.fov, 75.0)
	assert_near(Settings.volume, 0.8)
	assert_eq(Settings.binding(&"use", false), "k:%d" % KEY_F, "use key")
	assert_eq(Settings.key_label(&"use"), "F", "label")

func test_save_load_roundtrip() -> void:
	_reset()
	Settings.mouse_sens = 1.7
	Settings.fov = 90.0
	Settings.volume = 0.35
	Settings.set_binding(&"reload", false, "k:%d" % KEY_T)
	Settings.set_binding(&"jump", true, "b:3")
	assert_eq(Settings.save_file(PATH), OK, "saved")
	Settings.reset_defaults()
	assert_near(Settings.fov, 75.0)
	assert_true(Settings.load_file(PATH), "loaded")
	assert_near(Settings.mouse_sens, 1.7)
	assert_near(Settings.fov, 90.0)
	assert_near(Settings.volume, 0.35)
	assert_eq(Settings.binding(&"reload", false), "k:%d" % KEY_T)
	assert_eq(Settings.binding(&"jump", true), "b:3")
	assert_eq(Settings.binding(&"fire", false), "m:1", "untouched stays default")
	_reset()

func test_load_clamps_and_ignores_garbage() -> void:
	_reset()
	var c := ConfigFile.new()
	c.set_value("input", "mouse_sens", 99.0)
	c.set_value("video", "fov", 5.0)
	c.set_value("audio", "volume", -3.0)
	c.set_value("keys", "use", "banana")
	c.set_value("keys", "nonsense_action", "k:65")
	c.save(PATH)
	assert_true(Settings.load_file(PATH))
	assert_near(Settings.mouse_sens, Settings.SENS_MAX)
	assert_near(Settings.fov, Settings.FOV_MIN)
	assert_near(Settings.volume, 0.0)
	assert_eq(Settings.binding(&"use", false), "k:%d" % KEY_F, "bad code ignored")
	_reset()

func test_missing_file_is_false() -> void:
	_reset()
	assert_true(not Settings.load_file("user://does_not_exist.cfg"))

func test_event_codes() -> void:
	var k := InputEventKey.new()
	k.physical_keycode = KEY_G
	k.pressed = true
	assert_eq(Settings.event_to_code(k), "k:%d" % KEY_G)
	var m := InputEventMouseButton.new()
	m.button_index = MOUSE_BUTTON_RIGHT
	m.pressed = true
	assert_eq(Settings.event_to_code(m), "m:2")
	var b := InputEventJoypadButton.new()
	b.button_index = JOY_BUTTON_Y
	b.pressed = true
	assert_eq(Settings.event_to_code(b), "b:3")
	var a := InputEventJoypadMotion.new()
	a.axis = JOY_AXIS_TRIGGER_RIGHT
	a.axis_value = 0.9
	assert_eq(Settings.event_to_code(a), "a:5:+")
	a.axis_value = 0.1
	assert_eq(Settings.event_to_code(a), "", "below threshold is not a press")
	var ev := Settings.code_to_event("a:5:+")
	assert_true(ev is InputEventJoypadMotion and ev.axis == 5 and ev.axis_value > 0.0)
	assert_true(Settings.code_to_event("junk") == null)
	assert_eq(Settings.code_label("m:1"), "Mouse 1")
	assert_eq(Settings.code_label("b:0"), "A")
	assert_eq(Settings.code_label("a:5:+"), "RT")

func test_rebind_swaps_conflict() -> void:
	_reset()
	Settings.rebind(&"reload", false, "k:%d" % KEY_F)     # F is use's key: use gets reload's old key
	assert_eq(Settings.binding(&"reload", false), "k:%d" % KEY_F)
	assert_eq(Settings.binding(&"use", false), "k:%d" % KEY_R)
	_reset()

func test_actions_registered() -> void:
	_reset()
	Settings.apply_bindings()
	for a in Settings.ACTIONS:
		assert_true(InputMap.has_action(a[0]), "action " + String(a[0]))
	Settings.set_binding(&"use", false, "k:%d" % KEY_H)
	Settings.apply_bindings()
	var keys := InputMap.action_get_events(&"use").filter(func(e): return e is InputEventKey)
	assert_eq(keys.size(), 1)
	assert_eq(keys[0].physical_keycode, KEY_H)
	_reset()
	Settings.apply_bindings()
