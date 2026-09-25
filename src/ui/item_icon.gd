class_name ItemIcon
extends Control
## An item's picture, drawn from simple shapes by category in the item's
## colour, with a soft dark outline so it reads on any panel. A stack count
## shows in the corner.

var item_id := "":
	set(value):
		item_id = value
		queue_redraw()
var count := 0:
	set(value):
		count = value
		queue_redraw()

const OUTLINE := Color(0.23, 0.16, 0.12, 0.85)


func _init(p_item: String = "", p_count: int = 0) -> void:
	item_id = p_item
	count = p_count
	custom_minimum_size = Vector2(56, 56)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var item := ItemDatabase.get_item(item_id) if item_id != "" else null
	if item == null:
		return
	var c := size * 0.5
	var s := minf(size.x, size.y) / 64.0
	match item.category:
		"fish":
			_fish(c, s, item.color, item.id)
		"bug":
			_bug(c, s, item.color, item.id)
		"mineral":
			_mineral(c, s, item.color, item.id)
		"material":
			_material(c, s, item.color, item.id)
		"fruit":
			_fruit(c, s, item.color, item.id)
		"fossil":
			_fossil(c, s, item.color, item.id)
		"shore":
			_shore(c, s, item.color, item.id)
	if count > 1:
		var font := get_theme_default_font()
		var text := str(count)
		var font_size := int(15 * s + 3)
		var at := Vector2(size.x - 4 - font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, size.y - 4)
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, 4, Color(0.25, 0.17, 0.12))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.WHITE)


# --- Shapes --------------------------------------------------------------------

## Filled ellipse with an outline and a highlight.
func _oval(center: Vector2, radii: Vector2, color: Color, angle: float = 0.0) -> void:
	var outline := _ellipse(center, radii + Vector2(2.5, 2.5), angle)
	draw_colored_polygon(outline, OUTLINE)
	draw_colored_polygon(_ellipse(center, radii, angle), color)
	var shine := _ellipse(center + Vector2(-radii.x * 0.3, -radii.y * 0.35).rotated(angle), radii * Vector2(0.35, 0.22), angle)
	draw_colored_polygon(shine, color.lightened(0.45))


func _poly(points: PackedVector2Array, color: Color) -> void:
	var closed := points.duplicate()
	closed.append(points[0])
	draw_polyline(closed, OUTLINE, 5.0, true)
	draw_colored_polygon(points, color)


static func _ellipse(center: Vector2, radii: Vector2, angle: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in 24:
		var a := TAU * i / 24.0
		points.append(center + Vector2(cos(a) * radii.x, sin(a) * radii.y).rotated(angle))
	return points


func _fish(c: Vector2, s: float, color: Color, id: String) -> void:
	if id == "nebula_jelly":
		for i in 4:
			var x := c.x + (i - 1.5) * 7 * s
			draw_line(Vector2(x, c.y), Vector2(x + 3 * s, c.y + 22 * s), OUTLINE, 4 * s)
		_oval(c + Vector2(0, -6 * s), Vector2(20, 14) * s, color)
		return
	var tail := PackedVector2Array([c + Vector2(-14, 0) * s, c + Vector2(-27, -12) * s, c + Vector2(-27, 12) * s])
	_poly(tail, color.darkened(0.2))
	var tall := 9.0 if id in ["lagoon_ray", "duskray"] else 13.0
	_oval(c + Vector2(3, 0) * s, Vector2(20, tall) * s, color)
	draw_circle(c + Vector2(13, -3) * s, 3.2 * s, OUTLINE)
	draw_circle(c + Vector2(13.6, -3.6) * s, 1.0 * s, Color.WHITE)


func _bug(c: Vector2, s: float, color: Color, id: String) -> void:
	var winged := id.contains("moth") or id.contains("butterfly") or id.contains("bee") or id.contains("fly") or id.contains("cicada")
	for side in [-1.0, 1.0]:
		for leg in 3:
			var y := c.y + (leg - 1) * 7 * s
			draw_line(Vector2(c.x, y), Vector2(c.x + side * 17 * s, y + 5 * s), OUTLINE, 3 * s)
		draw_line(c + Vector2(side * 3, -14) * s, c + Vector2(side * 10, -24) * s, OUTLINE, 2.5 * s)
	if winged:
		for side in [-1.0, 1.0]:
			_oval(c + Vector2(side * 14, -4) * s, Vector2(13, 9) * s, color.lightened(0.3), side * 0.5)
			_oval(c + Vector2(side * 11, 9) * s, Vector2(9, 6) * s, color.lightened(0.2), side * -0.4)
	_oval(c + Vector2(0, 3) * s, Vector2(8, 15) * s, color)
	_oval(c + Vector2(0, -13) * s, Vector2(6, 6) * s, color.darkened(0.2))


func _mineral(c: Vector2, s: float, color: Color, id: String) -> void:
	if id in ["pebble", "flint", "obsidian"]:
		_oval(c + Vector2(0, 4) * s, Vector2(20, 14) * s, color)
		return
	if id.ends_with("_ore") or id == "geode":
		_oval(c + Vector2(0, 3) * s, Vector2(22, 17) * s, Palette.COLORS["rock"])
		for p: Vector2 in [Vector2(-8, -2), Vector2(7, 5), Vector2(4, -8)]:
			_oval(c + p * s, Vector2(5, 5) * s, color)
		return
	var gem := PackedVector2Array()
	for p: Vector2 in [Vector2(0, -24), Vector2(15, -8), Vector2(11, 20), Vector2(-11, 20), Vector2(-15, -8)]:
		gem.append(c + p * s)
	_poly(gem, color)
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, -24) * s, c + Vector2(15, -8) * s, c + Vector2(0, 0) * s, c + Vector2(-15, -8) * s]), color.lightened(0.3))
	draw_colored_polygon(PackedVector2Array([c + Vector2(0, 0) * s, c + Vector2(11, 20) * s, c + Vector2(-11, 20) * s]), color.darkened(0.15))


func _material(c: Vector2, s: float, color: Color, id: String) -> void:
	match id:
		"wood", "softwood", "hardwood":
			for i in 2:
				var y := c.y + (i * 2 - 1) * 8 * s
				var log := PackedVector2Array([Vector2(c.x - 20 * s, y - 7 * s), Vector2(c.x + 16 * s, y - 7 * s), Vector2(c.x + 16 * s, y + 7 * s), Vector2(c.x - 20 * s, y + 7 * s)])
				_poly(log, color)
				_oval(Vector2(c.x + 16 * s, y), Vector2(5, 7) * s, color.lightened(0.35))
		"stone":
			_oval(c + Vector2(0, 4) * s, Vector2(22, 16) * s, color)
		"clay":
			_oval(c + Vector2(0, 6) * s, Vector2(22, 13) * s, color)
			_oval(c + Vector2(-4, -2) * s, Vector2(12, 8) * s, color.lightened(0.12))
		_:
			_poly(PackedVector2Array([c + Vector2(-13, -10) * s, c + Vector2(13, -10) * s, c + Vector2(15, 20) * s, c + Vector2(-15, 20) * s]), color)
			_poly(PackedVector2Array([c + Vector2(-7, -20) * s, c + Vector2(7, -20) * s, c + Vector2(7, -10) * s, c + Vector2(-7, -10) * s]), Palette.COLORS["wood_light"])


func _fruit(c: Vector2, s: float, color: Color, id: String) -> void:
	draw_line(c + Vector2(0, -12) * s, c + Vector2(2, -22) * s, OUTLINE, 3.5 * s)
	_oval(c + Vector2(8, -21) * s, Vector2(7, 3.5) * s, Palette.COLORS["leaf"], -0.4)
	if id == "starfruit":
		var star := PackedVector2Array()
		for i in 10:
			var r := (20.0 if i % 2 == 0 else 9.0) * s
			var a := -PI / 2 + TAU * i / 10.0
			star.append(c + Vector2(cos(a), sin(a)) * r + Vector2(0, 4) * s)
		_poly(star, color)
	else:
		_oval(c + Vector2(0, 4) * s, Vector2(18, 17) * s, color)



## Fossils: the find on a slab of sandy rock.
func _fossil(c: Vector2, s: float, color: Color, id: String) -> void:
	var slab := PackedVector2Array([c + Vector2(-24, -10) * s, c + Vector2(20, -16) * s, c + Vector2(25, 14) * s, c + Vector2(-20, 20) * s])
	_poly(slab, Palette.COLORS["sand"])
	match id:
		"ammonite":
			for i in 5:
				var r := (15.0 - i * 3.0) * s
				draw_arc(c + Vector2(i * 1.2, 0) * s, r, 0.0, TAU * 0.85, 16, color.darkened(0.1 * i), 3.0 * s)
		"amber_bug":
			_oval(c, Vector2(14, 12) * s, color)
			_oval(c, Vector2(5, 3) * s, Palette.COLORS["trunk"])
		"raptor_claw":
			draw_polyline(PackedVector2Array([c + Vector2(-12, 10) * s, c + Vector2(-4, -6) * s, c + Vector2(8, -12) * s, c + Vector2(14, -4) * s]), color, 7.0 * s)
		"shellback_skull", "skywhale_bone":
			_oval(c + Vector2(-5, 0) * s, Vector2(12, 9) * s, color)
			_oval(c + Vector2(10, 3) * s, Vector2(7, 5) * s, color)
		_:
			draw_line(c + Vector2(-16, 0) * s, c + Vector2(16, 0) * s, color, 4.0 * s)
			for i in 5:
				var x := (-12.0 + i * 6.0) * s
				draw_line(c + Vector2(x, -9 * s), c + Vector2(x + 3 * s, 9 * s), color, 3.0 * s)


func _shore(c: Vector2, s: float, color: Color, id: String) -> void:
	match id:
		"starfish":
			var star := PackedVector2Array()
			for i in 10:
				var r := (22.0 if i % 2 == 0 else 9.0) * s
				var a := -PI / 2 + TAU * i / 10.0
				star.append(c + Vector2(cos(a), sin(a)) * r)
			_poly(star, color)
		"sea_urchin":
			for i in 12:
				var a := TAU * i / 12.0
				draw_line(c, c + Vector2(cos(a), sin(a)) * 22 * s, color.darkened(0.2), 2.5 * s)
			_oval(c, Vector2(13, 13) * s, color)
		"conch", "hermit_crab":
			_poly(PackedVector2Array([c + Vector2(-20, 6) * s, c + Vector2(4, -16) * s, c + Vector2(20, 2) * s, c + Vector2(2, 16) * s]), color)
			if id == "hermit_crab":
				_oval(c + Vector2(-16, 12) * s, Vector2(6, 5) * s, Palette.COLORS["scarf"])
		"sea_glass":
			for p: Vector2 in [Vector2(-8, 2), Vector2(8, -4), Vector2(4, 10)]:
				_oval(c + p * s, Vector2(9, 6) * s, Color(color, 0.85))
		"pearl_oyster":
			_oval(c + Vector2(0, 4) * s, Vector2(22, 12) * s, color)
			_oval(c + Vector2(0, -2) * s, Vector2(6, 6) * s, Color.WHITE)
		_:
			var fan := PackedVector2Array([c + Vector2(0, 16) * s])
			for i in 9:
				var a := PI + PI * i / 8.0
				fan.append(c + Vector2(cos(a), sin(a) * 0.9) * 22 * s + Vector2(0, 8) * s)
			_poly(fan, color)
			for i in 5:
				var a := PI + PI * (i + 1) / 6.0
				draw_line(c + Vector2(0, 16) * s, c + Vector2(cos(a), sin(a) * 0.9) * 20 * s + Vector2(0, 8) * s, color.darkened(0.2), 2.0 * s)
