class_name Hud
extends Control
## In-play overlay: round, points (own + teammates), ammo / slots / grenades, Suds icons, hp, interact prompt,
## hit marker, down + revive bars, spectate hint, power-up timers, crosshair. Everything is read from the bound
## services each frame; nothing here changes game state.

static func format_points(n: int) -> String:
	return HudText.format_points(n)

static func format_time(sec: float) -> String:
	return HudText.format_time(sec)

static func prompt_text(i: Interactable, p: Player) -> String:
	return HudText.prompt_text(i, p)

## A flat horizontal bar.
class Bar extends Control:
	var frac := 0.0
	var fill := UiTheme.GREEN
	func _init(c := UiTheme.GREEN, s := Vector2(300, 14)) -> void:
		fill = c
		custom_minimum_size = s
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func set_frac(f: float) -> void:
		f = clampf(f, 0.0, 1.0)
		if not is_equal_approx(f, frac):
			frac = f
			queue_redraw()
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.04, 0.03, 0.85))
		draw_rect(Rect2(Vector2(2, 2), Vector2((size.x - 4) * frac, size.y - 4)), fill)
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.LINE, false, 1.5)

## Crosshair + hit marker, drawn at the centre.
class Cross extends Control:
	var hit := 0.0                 # 1 -> 0
	var hit_head := false
	var gap := 7.0
	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var c := size * 0.5
		var col := Color(0.8, 1.0, 0.75, 0.9)
		var sh := Color(0, 0, 0, 0.6)
		for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(c + d * gap + Vector2(1, 1), c + d * (gap + 11) + Vector2(1, 1), sh, 3.0)
			draw_line(c + d * gap, c + d * (gap + 11), col, 2.0)
		draw_circle(c, 1.8, col)
		if hit > 0.0:
			var hc := UiTheme.RED if hit_head else Color(1, 1, 1)
			hc.a = clampf(hit * 1.4, 0.0, 1.0)
			for d in [Vector2(1, 1), Vector2(-1, 1), Vector2(1, -1), Vector2(-1, -1)]:
				draw_line(c + d * 9.0, c + d * 20.0, hc, 3.0)

const HIT_FADE := 0.28

var net: PlayerNet
var weapons: WeaponService
var economy: EconomyService
var powerups: PowerupService
var match_node: Match
var life: MatchState
var interact: InteractController
var spectating := false          # GameRoot: the local player is DEAD and watching
var spectate_name := ""

var _round_l: Label
var _phase_l: Label
var _pts_l: Label
var _mates: VBoxContainer
var _suds_row: HBoxContainer
var _suds_sig := ""
var _hp_bar: Bar
var _hp_l: Label
var _weapon_l: Label
var _ammo_l: Label
var _slots_l: Label
var _nades_l: Label
var _cross: Cross
var _prompt_l: Label
var _hold_bar: Bar
var _pu_row: HBoxContainer
var _pu_nodes := {}
var _down_box: VBoxContainer
var _down_l: Label
var _bleed_bar: Bar
var _revive_bar: Bar
var _revive_l: Label
var _rev_box: VBoxContainer
var _rev_l: Label
var _rev_bar: Bar
var _spec_l: Label
var _toast_l: Label
var _toast_t := 0.0
var _banner_l: Label
var _banner_t := 0.0
var _flash: ColorRect
var _flash_a := 0.0
var _last_hp := -1.0
var _last_round := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = UiTheme.make()
	_flash = ColorRect.new()
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(0.7, 0.05, 0.03, 0)
	add_child(_flash)
	_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cross = Cross.new()
	add_child(_cross)
	_build_top_left()
	_build_bottom_left()
	_build_bottom_right()
	_build_center()
	_build_top_center()

## A full-rect margin box; its child sits where the size flags say (SHRINK_BEGIN / CENTER / END).
func _place(h: int, v: int, margin: Vector4) -> MarginContainer:
	var m := MarginContainer.new()
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", int(margin.x))
	m.add_theme_constant_override("margin_top", int(margin.y))
	m.add_theme_constant_override("margin_right", int(margin.z))
	m.add_theme_constant_override("margin_bottom", int(margin.w))
	add_child(m)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.set_meta("h", h)
	m.set_meta("v", v)
	return m

func _panel(h: int, v: int, margin: Vector4) -> PanelContainer:
	var m := _place(h, v, margin)
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.size_flags_horizontal = h
	p.size_flags_vertical = v
	m.add_child(p)
	return p

func _build_top_left() -> void:
	var p := _panel(Control.SIZE_SHRINK_BEGIN, Control.SIZE_SHRINK_BEGIN, Vector4(28, 24, 0, 0))
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(UiTheme.body("ROUND", 18, UiTheme.DIM))
	_round_l = UiTheme.heading("0", 76, UiTheme.AMBER)
	v.add_child(_round_l)
	_phase_l = UiTheme.body("", 18, UiTheme.AMBER)
	v.add_child(_phase_l)

func _build_bottom_left() -> void:
	var p := _panel(Control.SIZE_SHRINK_BEGIN, Control.SIZE_SHRINK_END, Vector4(28, 0, 0, 24))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	p.add_child(v)
	_mates = VBoxContainer.new()
	v.add_child(_mates)
	_suds_row = HBoxContainer.new()
	_suds_row.add_theme_constant_override("separation", 6)
	_suds_row.custom_minimum_size = Vector2(0, 54)
	v.add_child(_suds_row)
	var hp_row := HBoxContainer.new()
	v.add_child(hp_row)
	_hp_bar = Bar.new(UiTheme.GREEN, Vector2(260, 18))
	hp_row.add_child(_hp_bar)
	_hp_l = UiTheme.body("100", 20)
	hp_row.add_child(_hp_l)
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 10)
	v.add_child(pr)
	_pts_l = UiTheme.heading("500", 56, UiTheme.AMBER)
	pr.add_child(_pts_l)
	var pl := UiTheme.body("PTS", 20, UiTheme.DIM)
	pl.size_flags_vertical = Control.SIZE_SHRINK_END
	pr.add_child(pl)

func _build_bottom_right() -> void:
	var p := _panel(Control.SIZE_SHRINK_END, Control.SIZE_SHRINK_END, Vector4(0, 0, 28, 24))
	var v := VBoxContainer.new()
	v.alignment = BoxContainer.ALIGNMENT_END
	p.add_child(v)
	_slots_l = UiTheme.body("", 20, UiTheme.DIM)
	_slots_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_slots_l)
	_weapon_l = UiTheme.heading("", 30, UiTheme.GREEN)
	_weapon_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_weapon_l)
	_ammo_l = UiTheme.heading("0 / 0", 64, UiTheme.AMBER)
	_ammo_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_ammo_l)
	_nades_l = UiTheme.body("", 22, UiTheme.GREEN)
	_nades_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(_nades_l)

func _build_center() -> void:
	var m := _place(Control.SIZE_SHRINK_CENTER, Control.SIZE_SHRINK_BEGIN, Vector4(0, 660, 0, 0))
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	col.add_theme_constant_override("separation", 8)
	m.add_child(col)
	_prompt_l = UiTheme.body("", 28, UiTheme.PAPER)
	_prompt_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_prompt_l)
	_hold_bar = Bar.new(UiTheme.AMBER, Vector2(260, 10))
	_hold_bar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_hold_bar)
	_rev_box = VBoxContainer.new()
	_rev_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(_rev_box)
	_rev_l = UiTheme.body("", 24, UiTheme.GREEN)
	_rev_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rev_box.add_child(_rev_l)
	_rev_bar = Bar.new(UiTheme.GREEN, Vector2(360, 18))
	_rev_box.add_child(_rev_bar)
	_toast_l = UiTheme.body("", 26, UiTheme.RED)
	_toast_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_toast_l)
	# downed block, lower centre
	var m2 := _place(Control.SIZE_SHRINK_CENTER, Control.SIZE_SHRINK_BEGIN, Vector4(0, 770, 0, 0))
	_down_box = VBoxContainer.new()
	_down_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_down_box.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_down_box.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_down_box.add_theme_constant_override("separation", 8)
	m2.add_child(_down_box)
	_down_l = UiTheme.heading("YOU ARE DOWN", 54, UiTheme.RED)
	_down_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_down_box.add_child(_down_l)
	var bl := UiTheme.body("BLEEDING OUT", 18, UiTheme.DIM)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_down_box.add_child(bl)
	_bleed_bar = Bar.new(UiTheme.RED, Vector2(520, 20))
	_down_box.add_child(_bleed_bar)
	_revive_l = UiTheme.body("", 22, UiTheme.GREEN)
	_revive_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_down_box.add_child(_revive_l)
	_revive_bar = Bar.new(UiTheme.GREEN, Vector2(520, 20))
	_down_box.add_child(_revive_bar)
	# spectating hint, bottom centre
	var m3 := _place(Control.SIZE_SHRINK_CENTER, Control.SIZE_SHRINK_END, Vector4(0, 0, 0, 90))
	_spec_l = UiTheme.heading("", 30, UiTheme.PAPER)
	_spec_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spec_l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_spec_l.size_flags_vertical = Control.SIZE_SHRINK_END
	m3.add_child(_spec_l)
	var m4 := _place(Control.SIZE_SHRINK_CENTER, Control.SIZE_SHRINK_BEGIN, Vector4(0, 150, 0, 0))
	_banner_l = UiTheme.heading("", 120, UiTheme.AMBER)
	_banner_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_l.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_banner_l.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	m4.add_child(_banner_l)

func _build_top_center() -> void:
	var m := _place(Control.SIZE_SHRINK_CENTER, Control.SIZE_SHRINK_BEGIN, Vector4(0, 24, 0, 0))
	_pu_row = HBoxContainer.new()
	_pu_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pu_row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_pu_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_pu_row.add_theme_constant_override("separation", 14)
	m.add_child(_pu_row)

# ---------------------------------------------------------------- wiring

func bind(pn: PlayerNet, svc: WeaponService, eco: EconomyService, pu: PowerupService, mt: Match, ms: MatchState, ic: InteractController) -> void:
	net = pn
	weapons = svc
	economy = eco
	powerups = pu
	match_node = mt
	life = ms
	interact = ic
	svc.hit.connect(func(shooter, _t, _d, head):
		if shooter == Net.local_id():
			show_hit(head))
	svc.result_received.connect(func(_t, kind, _r, _tg, _d, head):
		if kind == WeaponService.HIT:
			show_hit(head))
	eco.denied.connect(func(_p, reason): toast(denied_text(reason)))

static func denied_text(reason: StringName) -> String:
	match reason:
		&"points":
			return "Not enough points"
		&"far":
			return "Too far"
		&"no_power":
			return "Need power"
		&"owned":
			return "Already owned"
		&"max_suds":
			return "Carrying all the Suds you can"
		&"ammo_full":
			return "Ammo full"
		&"already_open":
			return "Already open"
		&"no_refit":
			return "Nothing to refit"
		&"down":
			return "You are down"
	return "Can't do that"

func show_hit(head: bool) -> void:
	_cross.hit = 1.0
	_cross.hit_head = head

func toast(text: String) -> void:
	_toast_l.text = text
	_toast_t = 1.6

# ---------------------------------------------------------------- per frame

func _process(dt: float) -> void:
	if net == null:
		return
	var me := net.local_player()
	_cross.hit = maxf(_cross.hit - dt / HIT_FADE, 0.0)
	_cross.queue_redraw()
	_cross.visible = me != null and me.state != Player.DEAD and not spectating
	_toast_t = maxf(_toast_t - dt, 0.0)
	_toast_l.modulate.a = clampf(_toast_t / 0.4, 0.0, 1.0)
	_update_round(dt)
	_update_points(me)
	_update_kit(me)
	_update_suds()
	_update_powerups()
	_update_prompt(me)
	_update_life(me, dt)

func _update_round(dt: float) -> void:
	var r: int = match_node.round if match_node != null else 0
	_round_l.text = str(r)
	_phase_l.text = "WAVE CLEARED" if match_node != null and match_node.phase == Match.BREAK else ""
	if r != _last_round:
		if r > 0:
			_banner_l.text = "ROUND %d" % r
			_banner_t = 2.6
		_last_round = r
	_banner_t = maxf(_banner_t - dt, 0.0)
	_banner_l.modulate.a = clampf(_banner_t / 0.8, 0.0, 1.0)

func _update_points(me: Player) -> void:
	_pts_l.text = format_points(me.points if me != null else 0)
	var ids: Array = []
	for id in net.players:
		if id != Net.local_id():
			ids.append(id)
	ids.sort()
	while _mates.get_child_count() > ids.size():
		var old := _mates.get_child(_mates.get_child_count() - 1)
		_mates.remove_child(old)
		old.queue_free()
	while _mates.get_child_count() < ids.size():
		_mates.add_child(UiTheme.body("", 22))
	for i in ids.size():
		var p: Player = net.players[ids[i]]
		var l: Label = _mates.get_child(i)
		var tag := ""
		var col := UiTheme.GREEN
		if p.state == Player.DOWN:
			tag = "  DOWN"
			col = UiTheme.RED
		elif p.state == Player.DEAD:
			tag = "  OUT"
			col = UiTheme.DIM
		l.text = "%-13s %7s%s" % [player_name(ids[i]), format_points(p.points), tag]
		l.add_theme_color_override("font_color", col)

static func player_name(id: int) -> String:
	var n: String = Net.players.info(id).get("name", "")
	return (n if n != "" else "Operative").to_upper().substr(0, 13)

func _update_kit(me: Player) -> void:
	if weapons == null or me == null:
		return
	var kit := weapons.kit_for(Net.local_id())
	var st := kit.held_state()
	if st == null:
		return
	_weapon_l.text = st.data.display_name.to_upper()
	_ammo_l.text = "RELOADING" if st.reloading else "%d / %d" % [st.mag, st.reserve]
	_ammo_l.add_theme_font_size_override("font_size", 40 if st.reloading else 64)
	var low := st.mag <= maxi(st.data.mag / 4, 1) and not st.reloading
	_ammo_l.add_theme_color_override("font_color", UiTheme.RED if low else UiTheme.AMBER)
	var parts: Array = []
	for i in 2:
		var s := kit.slots[i]
		if s != null:
			parts.append(("[%d] %s" if i == kit.held else " %d  %s") % [i + 1, s.data.display_name.to_upper()])
	_slots_l.text = "   ".join(parts)
	_nades_l.text = "GRENADES  " + "o ".repeat(kit.grenades).strip_edges() if kit.grenades > 0 else "GRENADES  -"

func _update_suds() -> void:
	var list: Array = Game.suds_of(Net.local_id()).to_list()
	var sig := var_to_str(list)
	if sig == _suds_sig:
		return
	_suds_sig = sig
	for c in _suds_row.get_children():
		_suds_row.remove_child(c)
		c.queue_free()
	for e in list:
		var data: SudsData = Content.suds.get(StringName(e[0]))
		_suds_row.add_child(UiTheme.SudsIcon.new(data.color if data != null else Color.WHITE))

func _update_powerups() -> void:
	if powerups == null:
		return
	var live := {}
	for kind in powerups.active:
		var left: float = float(powerups.active[kind]) - powerups.clock
		if left > 0.0:
			live[kind] = left
	for kind in _pu_nodes.keys():
		if not live.has(kind):
			_pu_nodes[kind].queue_free()
			_pu_nodes.erase(kind)
	for kind in live:
		if not _pu_nodes.has(kind):
			var box := PanelContainer.new()
			box.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var v := VBoxContainer.new()
			v.name = "V"
			box.add_child(v)
			var data: PowerupData = Content.powerups.get(kind)
			var l := UiTheme.body(data.display_name.to_upper() if data != null else String(kind).to_upper(), 20, UiTheme.AMBER)
			l.name = "L"
			v.add_child(l)
			var b := Bar.new(UiTheme.AMBER, Vector2(170, 10))
			b.name = "B"
			v.add_child(b)
			_pu_row.add_child(box)
			_pu_nodes[kind] = box
		var node: PanelContainer = _pu_nodes[kind]
		var data2: PowerupData = Content.powerups.get(kind)
		var total := data2.duration_s if data2 != null and data2.duration_s > 0.0 else Content.balance.powerup_duration_s
		node.get_node("V/B").set_frac(live[kind] / total)
		var lab: Label = node.get_node("V/L")
		lab.text = "%s  %s" % [(data2.display_name if data2 != null else String(kind)).to_upper(), format_time(live[kind])]

func _update_prompt(me: Player) -> void:
	var txt := interact.prompt if interact != null and me != null and not spectating else ""
	_prompt_l.text = txt
	_hold_bar.visible = txt != "" and interact.hold > 0.0
	if _hold_bar.visible:
		_hold_bar.set_frac(interact.hold)

func _update_life(me: Player, dt: float) -> void:
	var down := me != null and me.state == Player.DOWN
	_down_box.visible = down
	_rev_box.visible = false
	var v := life.view_for(Net.local_id()) if life != null else {"role": ""}
	if down:
		_bleed_bar.set_frac(v.bleed if v.role == "downed" else life.bleed_left_of(Net.local_id()))
		var by: int = v.other if v.role == "downed" else 0
		_revive_bar.set_frac(v.progress if v.role == "downed" else 0.0)
		_revive_l.text = "%s is reviving you" % player_name(by).capitalize() if by != 0 else "Waiting for a teammate to revive you"
	elif v.role == "reviver" and me != null and me.state == Player.ALIVE:
		var other: Player = net.players.get(v.other)
		if other != null and other.state == Player.DOWN:
			_rev_box.visible = true
			_rev_l.text = "REVIVING %s" % player_name(v.other)
			_rev_bar.set_frac(v.progress)
	spectate_label()
	# damage flash and low hp pulse
	if me != null:
		if _last_hp >= 0.0 and me.hp < _last_hp - 0.5:
			_flash_a = minf(_flash_a + 0.5, 0.7)
		_last_hp = me.hp
		var maxhp := me.max_health()
		_hp_bar.set_frac(me.hp / maxf(maxhp, 1.0))
		_hp_bar.fill = UiTheme.RED if me.hp / maxf(maxhp, 1.0) < 0.35 else UiTheme.GREEN
		_hp_l.text = " %d" % int(ceil(me.hp))
		var low := me.state == Player.ALIVE and me.hp / maxf(maxhp, 1.0) < 0.35
		var pulse := 0.12 + 0.08 * sin(Time.get_ticks_msec() / 220.0) if low else 0.0
		if down:
			pulse = 0.2
		_flash_a = maxf(_flash_a - dt * 1.2, 0.0)
		_flash.color.a = maxf(_flash_a, pulse)
	_hp_bar.queue_redraw()

func spectate_label() -> void:
	_spec_l.text = ("SPECTATING  %s\n[%s] next player" % [spectate_name, Settings.key_label(&"fire")]) if spectating and spectate_name != "" \
		else ("SPECTATING\nWaiting for the next round" if spectating else "")
