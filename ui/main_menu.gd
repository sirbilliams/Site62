class_name MainMenu
extends Control
## Host, Join (LAN list from LanBeacon + manual IP), Settings, Quit. Gamepad: d-pad / stick + A, B backs out.

signal host_requested
signal join_requested(ip: String, port: int)
signal settings_requested
signal quit_requested

var _menu: VBoxContainer
var _join: VBoxContainer
var _list: ItemList
var _ip: LineEdit
var _status: Label
var _beacon: LanBeacon
var _games: Array = []           # [ip, port] per list row
var _host_b: Button
var _connect_b: Button

func _ready() -> void:
	theme = UiTheme.make()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiTheme.Backdrop.new())
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 140)
	m.add_theme_constant_override("margin_top", 100)
	m.add_theme_constant_override("margin_bottom", 100)
	m.add_theme_constant_override("margin_right", 140)
	add_child(m)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 90)
	m.add_child(row)
	var title := VBoxContainer.new()
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(title)
	title.add_child(UiTheme.body("DEPARTMENT OF APPLIED PHYSICS  /  FORM 62-B", 20, UiTheme.DIM))
	title.add_child(UiTheme.heading("SITE 62", 168, UiTheme.AMBER))
	title.add_child(UiTheme.body("CONTAINMENT BREACH. CO-OPERATIVE SURVIVAL.", 26, UiTheme.GREEN))
	var stripes := HBoxContainer.new()
	stripes.add_theme_constant_override("separation", 0)
	for c in UiTheme.GROOVY:
		var r := ColorRect.new()
		r.color = c
		r.custom_minimum_size = Vector2(110, 14)
		stripes.add_child(r)
	title.add_child(stripes)
	var side := VBoxContainer.new()
	side.custom_minimum_size = Vector2(560, 0)
	side.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_child(side)
	_menu = VBoxContainer.new()
	_menu.add_theme_constant_override("separation", 16)
	side.add_child(_menu)
	_host_b = _button(_menu, "HOST GAME", func(): host_requested.emit())
	_button(_menu, "JOIN GAME", show_join)
	_button(_menu, "SETTINGS", func(): settings_requested.emit())
	_button(_menu, "QUIT", func(): quit_requested.emit())
	_join = VBoxContainer.new()
	_join.add_theme_constant_override("separation", 12)
	_join.visible = false
	side.add_child(_join)
	_join.add_child(UiTheme.body("GAMES ON THIS NETWORK", 20, UiTheme.DIM))
	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(0, 190)
	_list.item_activated.connect(func(i): _connect_row(i))
	_join.add_child(_list)
	_join.add_child(UiTheme.body("OR ENTER AN ADDRESS", 20, UiTheme.DIM))
	_ip = LineEdit.new()
	_ip.placeholder_text = "192.168.1.20  or  host:port"
	_ip.text_submitted.connect(func(_t): _connect_typed())
	_join.add_child(_ip)
	_connect_b = _button(_join, "CONNECT", _connect_typed)
	_button(_join, "BACK", hide_join)
	_status = UiTheme.body("", 20, UiTheme.AMBER)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(_status)
	add_child(UiTheme.crt_overlay())
	visibility_changed.connect(func():
		if visible:
			hide_join()
			_host_b.grab_focus())
	_host_b.grab_focus()

func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 62)
	b.pressed.connect(cb)
	parent.add_child(b)
	return b

func set_status(text: String) -> void:
	if _status != null:
		_status.text = text

func show_join() -> void:
	_menu.visible = false
	_join.visible = true
	set_status("")
	_list.clear()
	_games.clear()
	_stop_beacon()
	_beacon = LanBeacon.new()
	add_child(_beacon)
	if Net.beacon_port > 0 and _beacon.start_listen(Net.beacon_port):
		_beacon.found.connect(_on_found)
	else:
		set_status("LAN discovery unavailable. Type the host's address.")
	_ip.grab_focus.call_deferred()

func hide_join() -> void:
	_stop_beacon()
	if _join != null:
		_join.visible = false
		_menu.visible = true
		if is_inside_tree() and visible:
			_host_b.grab_focus()

func _stop_beacon() -> void:
	if _beacon != null:
		_beacon.queue_free()
		_beacon = null

const MAX_GAMES := 16

func _on_found(ip: String, port: int, host_name: String, players: int) -> void:
	if port < 1 or port > 65535 or _games.size() >= MAX_GAMES:
		return
	for g in _games:
		if g[0] == ip and g[1] == port:
			return
	_games.append([ip, port])
	_list.add_item("%s   %s:%d   %d/4" % [host_name, ip, port, players])
	if _list.item_count == 1:
		_list.select(0)

func _connect_row(i: int) -> void:
	if i >= 0 and i < _games.size():
		join_requested.emit(_games[i][0], _games[i][1])

func _connect_typed() -> void:
	var sel := _list.get_selected_items()
	var t := _ip.text.strip_edges()
	if t == "" and not sel.is_empty():
		_connect_row(sel[0])
		return
	var a := parse_address(t)
	if a.is_empty():
		set_status("Enter an address like 192.168.1.20 or 192.168.1.20:7862")
		return
	join_requested.emit(a[0], a[1])

## "host" or "host:port" -> [host, port]; [] when unusable.
static func parse_address(text: String) -> Array:
	var t := text.strip_edges()
	if t == "":
		return []
	var port := GameRoot.PORT
	var host := t
	if t.count(":") == 1:
		var p := t.split(":")
		host = p[0]
		if not p[1].is_valid_int() or int(p[1]) < 1 or int(p[1]) > 65535:
			return []
		port = int(p[1])
	if host == "" or host.contains(" "):
		return []
	return [host, port]

func _unhandled_input(e: InputEvent) -> void:
	if visible and _join != null and _join.visible and e.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		hide_join()
