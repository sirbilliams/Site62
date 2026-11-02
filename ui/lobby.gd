class_name Lobby
extends Control
## Briefing room: who is connected, host presses Start. Clients wait.

signal start_pressed
signal leave_pressed

var _list: VBoxContainer
var _start: Button
var _leave: Button
var _wait: Label
var _addr: Label
var is_host := false

func _ready() -> void:
	theme = UiTheme.make()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(UiTheme.Backdrop.new())
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + s, 120)
	margin.add_theme_constant_override("margin_top", 70)
	margin.add_theme_constant_override("margin_bottom", 70)
	add_child(margin)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 60)
	margin.add_child(row)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 16)
	row.add_child(left)
	left.add_child(UiTheme.body("SITE 62  //  PERSONNEL ROSTER", 20, UiTheme.DIM))
	left.add_child(UiTheme.heading("BRIEFING ROOM", 68, UiTheme.AMBER))
	var panel := PanelContainer.new()
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	left.add_child(panel)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 10)
	panel.add_child(_list)
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(520, 0)
	right.add_theme_constant_override("separation", 18)
	row.add_child(right)
	var memo := PanelContainer.new()
	right.add_child(memo)
	var mv := VBoxContainer.new()
	memo.add_child(mv)
	mv.add_child(UiTheme.body("MEMO 62-B  /  EYES ONLY", 18, UiTheme.AMBER))
	var txt := UiTheme.body("Reactor containment has failed. Restore generator power, open the bulkheads, hold the line. Revive your colleagues - nobody gets out alone.", 21, UiTheme.PAPER)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	txt.custom_minimum_size = Vector2(480, 0)
	mv.add_child(txt)
	_addr = UiTheme.body("", 20, UiTheme.DIM)
	_addr.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_addr)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(sp)
	_wait = UiTheme.body("Waiting for the host to start the operation...", 22, UiTheme.AMBER)
	_wait.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(_wait)
	_start = Button.new()
	_start.text = "START OPERATION"
	_start.pressed.connect(func(): start_pressed.emit())
	right.add_child(_start)
	_leave = Button.new()
	_leave.text = "LEAVE"
	_leave.pressed.connect(func(): leave_pressed.emit())
	right.add_child(_leave)
	add_child(UiTheme.crt_overlay())
	visibility_changed.connect(_focus)
	set_host(is_host)

func _focus() -> void:
	if visible and is_inside_tree():
		(_start if is_host else _leave).grab_focus()

func set_host(h: bool) -> void:
	is_host = h
	if _start == null:
		return
	_start.visible = h
	_wait.visible = not h
	var ips := PackedStringArray()
	if h:
		for a in IP.get_local_addresses():
			if a.count(".") == 3 and not a.begins_with("127.") and not a.begins_with("169.254."):
				ips.append(a)
	_addr.text = ("Friends on the LAN find this game in the Join list, or enter: " + ", ".join(ips) + ":" + str(GameRoot.PORT)) if h else ""
	_focus()

## Redraw the roster. ids: peer ids.
func refresh(ids: Array) -> void:
	if _list == null:
		return
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	for i in ids.size():
		var id: int = ids[i]
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 16)
		var tag := UiTheme.heading("%02d" % (i + 1), 34, UiTheme.AMBER)
		r.add_child(tag)
		var n := UiTheme.body(Hud.player_name(id) if id != Net.local_id() else Hud.player_name(id) + "  (YOU)", 28)
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		r.add_child(n)
		r.add_child(UiTheme.body("HOST" if id == 1 else "READY", 22, UiTheme.DIM if id != 1 else UiTheme.AMBER))
		_list.add_child(r)
	for i in range(ids.size(), 4):
		var e := UiTheme.body("%02d   -  open  -" % (i + 1), 26, Color(0.25, 0.36, 0.27))
		_list.add_child(e)
