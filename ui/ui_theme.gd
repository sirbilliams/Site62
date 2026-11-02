class_name UiTheme
extends RefCounted
## The look: 1960s Cold War lab console. Stencil + teletype fonts (SIL OFL, see content/CREDITS.md), muted greens
## and ambers on near black, thin phosphor borders, optional CRT scanline overlay. Ethereal-Suds get a groovy 70s accent.

const BG := Color(0.035, 0.055, 0.04)
const PANEL := Color(0.06, 0.1, 0.075, 0.88)
const PANEL_SOLID := Color(0.06, 0.1, 0.075, 1.0)
const LINE := Color(0.33, 0.52, 0.36)
const GREEN := Color(0.64, 0.86, 0.62)
const DIM := Color(0.42, 0.55, 0.42)
const AMBER := Color(0.96, 0.7, 0.24)
const RED := Color(0.86, 0.27, 0.2)
const PAPER := Color(0.86, 0.82, 0.68)
## 70s accent for Suds icons and the odd flourish: orange, mustard, avocado stripes.
const GROOVY := [Color(0.93, 0.45, 0.15), Color(0.95, 0.72, 0.2), Color(0.55, 0.62, 0.2)]

static var _heading: FontFile
static var _body: FontFile
static var _theme: Theme

static func heading_font() -> FontFile:
	if _heading == null:
		_heading = load("res://ui/fonts/StardosStencil-Bold.ttf")
	return _heading

static func body_font() -> FontFile:
	if _body == null:
		_body = load("res://ui/fonts/ShareTechMono-Regular.ttf")
	return _body

static func box(fill: Color, border: Color, bw := 2, pad := 10) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_content_margin_all(pad)
	s.set_corner_radius_all(2)
	return s

static func make() -> Theme:
	if _theme != null:
		return _theme
	var t := Theme.new()
	t.default_font = body_font()
	t.default_font_size = 22
	t.set_color("font_color", "Label", GREEN)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "Label", 1)
	t.set_constant("shadow_offset_y", "Label", 1)
	for cls in ["Button", "CheckButton", "OptionButton"]:
		t.set_stylebox("normal", cls, box(Color(0.07, 0.12, 0.085, 0.95), LINE))
		t.set_stylebox("hover", cls, box(Color(0.1, 0.17, 0.11, 0.95), AMBER))
		t.set_stylebox("pressed", cls, box(Color(0.2, 0.15, 0.05, 0.95), AMBER))
		t.set_stylebox("focus", cls, box(Color(0.14, 0.2, 0.1, 0.98), AMBER, 3))
		t.set_stylebox("disabled", cls, box(Color(0.05, 0.07, 0.06, 0.8), Color(0.2, 0.3, 0.22)))
		t.set_color("font_color", cls, GREEN)
		t.set_color("font_hover_color", cls, AMBER)
		t.set_color("font_focus_color", cls, AMBER)
		t.set_color("font_pressed_color", cls, AMBER)
		t.set_color("font_disabled_color", cls, Color(0.3, 0.4, 0.32))
	t.set_font("font", "Button", heading_font())
	t.set_font_size("font_size", "Button", 26)
	t.set_stylebox("normal", "LineEdit", box(Color(0.03, 0.05, 0.04), LINE))
	t.set_stylebox("focus", "LineEdit", box(Color(0.03, 0.05, 0.04), AMBER, 3))
	t.set_color("font_color", "LineEdit", GREEN)
	t.set_color("caret_color", "LineEdit", AMBER)
	t.set_stylebox("panel", "PanelContainer", box(PANEL, LINE))
	t.set_stylebox("panel", "ItemList", box(Color(0.03, 0.05, 0.04, 0.9), LINE))
	t.set_stylebox("focus", "ItemList", box(Color(0.03, 0.05, 0.04, 0.9), AMBER, 3))
	t.set_stylebox("selected", "ItemList", box(Color(0.2, 0.15, 0.05), AMBER, 1, 4))
	t.set_stylebox("selected_focus", "ItemList", box(Color(0.28, 0.2, 0.06), AMBER, 2, 4))
	t.set_color("font_color", "ItemList", GREEN)
	t.set_color("font_selected_color", "ItemList", AMBER)
	var track := box(Color(0.03, 0.05, 0.04), LINE, 1, 0)
	track.content_margin_top = 5
	track.content_margin_bottom = 5
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", box(Color(0.5, 0.38, 0.12), AMBER, 1, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", box(Color(0.6, 0.45, 0.14), AMBER, 1, 0))
	var grab := GradientTexture2D.new()
	grab.width = 18
	grab.height = 30
	var g := Gradient.new()
	g.set_color(0, AMBER)
	g.set_color(1, AMBER)
	grab.gradient = g
	t.set_icon("grabber", "HSlider", grab)
	t.set_icon("grabber_highlight", "HSlider", grab)
	t.set_icon("grabber_disabled", "HSlider", grab)
	_theme = t
	return t

## A Label with the heading (stencil) font.
static func heading(text: String, size := 40, color := GREEN) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", heading_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func body(text: String, size := 22, color := GREEN) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

## Scanlines + vignette over everything below it. Never takes input.
static func crt_overlay() -> ColorRect:
	var r := ColorRect.new()
	r.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
void fragment() {
	float line = 0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159);
	vec2 uv = UV - 0.5;
	float vig = smoothstep(0.35, 0.95, length(uv * vec2(1.0, 1.15)));
	COLOR = vec4(0.0, 0.03, 0.0, 0.10 * line + 0.45 * vig);
}"""
	var m := ShaderMaterial.new()
	m.shader = sh
	r.material = m
	return r

## Full-screen backdrop: dark phosphor field with a faint blueprint grid.
class Backdrop extends Control:
	func _init() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.BG)
		var c := Color(0.2, 0.35, 0.22, 0.13)
		var x := 0.0
		while x < size.x:
			draw_line(Vector2(x, 0), Vector2(x, size.y), c, 1.0)
			x += 64.0
		var y := 0.0
		while y < size.y:
			draw_line(Vector2(0, y), Vector2(size.x, y), c, 1.0)
			y += 64.0
		for i in 3:                                         # a band of 70s stripes along the bottom edge
			draw_rect(Rect2(0, size.y - 18 + i * 6, size.x, 4), Color(UiTheme.GROOVY[i], 0.5))

## Suds bottle icon: tinted can with a groovy stripe. 56x72 default.
class SudsIcon extends Control:
	var tint := Color.WHITE
	func _init(c := Color.WHITE, s := Vector2(40, 52)) -> void:
		tint = c
		custom_minimum_size = s
		mouse_filter = Control.MOUSE_FILTER_IGNORE
	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_rect(Rect2(w * 0.12, h * 0.14, w * 0.76, h * 0.8), Color(0.04, 0.06, 0.05), true)
		draw_rect(Rect2(w * 0.18, h * 0.2, w * 0.64, h * 0.68), tint, true)
		for i in 3:                                          # 70s stripes across the can
			draw_rect(Rect2(w * 0.18, h * (0.4 + i * 0.1), w * 0.64, h * 0.06), UiTheme.GROOVY[i], true)
		draw_rect(Rect2(w * 0.3, h * 0.04, w * 0.4, h * 0.12), Color(0.75, 0.75, 0.7), true)
		draw_rect(Rect2(w * 0.12, h * 0.14, w * 0.76, h * 0.8), Color(0.9, 0.85, 0.7, 0.9), false, 2.0)
