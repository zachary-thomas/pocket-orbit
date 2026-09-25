class_name UiTheme
extends RefCounted
## The game's interface look, built in code from the UI direction mockups: warm
## cream panels with wood trim, amber buttons, navy accents, big rounded
## shapes and thumb-sized targets.

const CREAM := Color("fff5df")
const CREAM_DARK := Color("f1dfbd")
const WOOD := Color("b98252")
const WOOD_DARK := Color("7a5236")
const AMBER := Color("f6ae3f")
const AMBER_LIGHT := Color("ffc766")
const AMBER_DARK := Color("d98b22")
const NAVY := Color("27365e")
const NAVY_LIGHT := Color("3b4f84")
const TEXT := Color("4a3527")
const TEXT_SOFT := Color("8a6b52")
const GOOD := Color("5aa05a")
const BAD := Color("c8574a")

static var _theme: Theme


static func get_theme() -> Theme:
	if _theme:
		return _theme
	var t := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Nunito", "Varela Round", "Quicksand", "Segoe UI", "Roboto", "Helvetica Neue", "Arial"])
	font.font_weight = 700
	t.default_font = font
	t.default_font_size = 20

	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	t.set_color("font_color", "Label", TEXT)

	var normal := box(AMBER, 16, AMBER_DARK, 0, 3)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", box(AMBER_LIGHT, 16, AMBER_DARK, 0, 3))
	t.set_stylebox("pressed", "Button", box(AMBER_DARK, 16, AMBER_DARK, 0, 0))
	t.set_stylebox("disabled", "Button", box(CREAM_DARK, 16, Color(0, 0, 0, 0.08), 0, 2))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
		t.set_color(state, "Button", TEXT)
	t.set_color("font_disabled_color", "Button", TEXT_SOFT.lerp(CREAM_DARK, 0.4))

	var track := box(CREAM_DARK, 10, WOOD, 2, 0)
	track.content_margin_top = 8
	track.content_margin_bottom = 8
	t.set_stylebox("slider", "HSlider", track)
	var filled := box(AMBER, 10, AMBER_DARK, 2, 0)
	filled.content_margin_top = 8
	filled.content_margin_bottom = 8
	t.set_stylebox("grabber_area", "HSlider", filled)
	t.set_stylebox("grabber_area_highlight", "HSlider", filled)
	var grabber := _circle_texture(34, CREAM, WOOD_DARK)
	t.set_icon("grabber", "HSlider", grabber)
	t.set_icon("grabber_highlight", "HSlider", grabber)
	t.set_stylebox("panel", "TooltipPanel", box(NAVY, 12, NAVY_LIGHT, 2, 0))
	t.set_color("font_color", "TooltipLabel", CREAM)
	_theme = t
	return t


## Rounded box with an optional border and a darker "lip" under it, which
## makes buttons look chunky and pressable.
static func box(color: Color, radius: int, border: Color, border_width: int, lip: int) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.set_corner_radius_all(radius)
	s.border_color = border
	s.set_border_width_all(border_width)
	s.border_width_bottom = border_width + lip
	s.content_margin_left = 16
	s.content_margin_right = 16
	s.content_margin_top = 8
	s.content_margin_bottom = 8 + lip
	s.anti_aliasing = true
	return s


static func panel_style() -> StyleBoxFlat:
	var s := box(CREAM, 26, WOOD, 5, 3)
	s.shadow_color = Color(0.1, 0.06, 0.15, 0.35)
	s.shadow_size = 10
	s.shadow_offset = Vector2(0, 4)
	s.content_margin_left = 22
	s.content_margin_right = 22
	s.content_margin_top = 18
	s.content_margin_bottom = 20
	return s


## Small pill for the HUD (time, Stardust).
static func pill_style(color: Color = NAVY) -> StyleBoxFlat:
	var s := box(Color(color, 0.88), 22, Color(CREAM, 0.6), 2, 0)
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 6
	s.content_margin_bottom = 6
	return s


## An inventory slot: a sunken cream square.
static func slot_style(selected: bool = false) -> StyleBoxFlat:
	var s := box(CREAM_DARK if not selected else AMBER_LIGHT, 14, WOOD if selected else Color(WOOD, 0.35), 3 if selected else 2, 0)
	s.set_content_margin_all(4)
	return s


static func label(text: String, size: int = 20, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, action: Callable, min_size: Vector2 = Vector2(0, 54)) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	return b


## A navy "secondary" button.
static func quiet_button(text: String, action: Callable, min_size: Vector2 = Vector2(0, 54)) -> Button:
	var b := button(text, action, min_size)
	b.add_theme_stylebox_override("normal", box(NAVY, 16, Color("1a2544"), 0, 3))
	b.add_theme_stylebox_override("hover", box(NAVY_LIGHT, 16, Color("1a2544"), 0, 3))
	b.add_theme_stylebox_override("pressed", box(Color("1a2544"), 16, Color("1a2544"), 0, 0))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
		b.add_theme_color_override(state, CREAM)
	return b


static func _circle_texture(diameter: int, fill: Color, edge: Color) -> ImageTexture:
	var image := Image.create(diameter, diameter, false, Image.FORMAT_RGBA8)
	var r := diameter * 0.5
	for y in diameter:
		for x in diameter:
			var d := Vector2(x + 0.5 - r, y + 0.5 - r).length()
			var c := fill if d < r - 4.0 else edge
			c.a = clampf(r - d, 0.0, 1.0)
			image.set_pixel(x, y, c)
	return ImageTexture.create_from_image(image)
