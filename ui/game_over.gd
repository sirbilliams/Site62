class_name GameOver
extends Control
## End of the run: per-player table from MatchState.game_over_reached(stats).

signal back_pressed

var _table: GridContainer
var _title: Label
var _sub: Label
var _back: Button

func _ready() -> void:
	theme = UiTheme.make()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.02, 0.0, 0.0, 0.82)
	add_child(dim)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	var panel := PanelContainer.new()
	c.add_child(panel)
	var v := VBoxContainer.new()
	v.custom_minimum_size = Vector2(980, 0)
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	v.add_child(UiTheme.body("SITE 62  //  INCIDENT REPORT", 20, UiTheme.DIM))
	_title = UiTheme.heading("CONTAINMENT LOST", 78, UiTheme.RED)
	v.add_child(_title)
	_sub = UiTheme.body("", 26, UiTheme.AMBER)
	v.add_child(_sub)
	_table = GridContainer.new()
	_table.columns = 6
	_table.add_theme_constant_override("h_separation", 36)
	_table.add_theme_constant_override("v_separation", 8)
	v.add_child(_table)
	_back = Button.new()
	_back.text = "BACK TO MENU"
	_back.custom_minimum_size = Vector2(0, 56)
	_back.pressed.connect(func(): back_pressed.emit())
	v.add_child(_back)
	visibility_changed.connect(func():
		if visible:
			_back.grab_focus())

## stats: peer -> {rounds, kills, downs, revives, points}
func show_stats(stats: Dictionary) -> void:
	var best := 0
	for id in stats:
		best = maxi(best, int(stats[id].rounds))
	_sub.text = "Survived %d round%s" % [best, "" if best == 1 else "s"]
	for c in _table.get_children():
		_table.remove_child(c)
		c.queue_free()
	for h in ["OPERATIVE", "ROUNDS", "KILLS", "DOWNS", "REVIVES", "POINTS"]:
		var l := UiTheme.body(h, 20, UiTheme.DIM)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if h == "OPERATIVE" else HORIZONTAL_ALIGNMENT_RIGHT
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_table.add_child(l)
	var ids := stats.keys()
	ids.sort()
	for id in ids:
		var s: Dictionary = stats[id]
		var cells := [Hud.player_name(id) + ("  (YOU)" if id == Net.local_id() else ""), str(s.rounds), str(s.kills), str(s.downs), str(s.revives), Hud.format_points(s.points)]
		for i in cells.size():
			var l := UiTheme.body(cells[i], 30, UiTheme.AMBER if i == 5 else UiTheme.GREEN)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if i == 0 else HORIZONTAL_ALIGNMENT_RIGHT
			l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_table.add_child(l)
