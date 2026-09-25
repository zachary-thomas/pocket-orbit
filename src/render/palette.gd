class_name Palette
extends RefCounted
## The one shared palette texture every model in the game is coloured from.
##
## A 16 x 16 grid of flat colour swatches (256 x 256 px). Models don't carry
## their own textures: each face's UVs point at the centre of a swatch, so one
## material covers everything and changing a colour here recolours the game.
##
## The Blender asset script (tools/blender/build_assets.py) reads the swatch
## list from this file, so models and the game always agree on the layout.
##
## The bottom row (row 15) holds "glow" swatches. The surface shader makes
## those emit light at night, for windows, lamps and shrine crystals.

const GRID := 16
const SWATCH_PX := 16
const GLOW_ROW := 15

const COLORS := {
	# Plain white: terrain and other vertex-coloured meshes point here and
	# carry their colour per vertex instead.
	"white": Color("ffffff"),
	# Terrain tops
	"grass": Color("9dd36a"),
	"tundra": Color("a8c790"),
	"jungle": Color("5aad5c"),
	"sand": Color("efd69c"),
	"snow": Color("f3f6fb"),
	"rock": Color("aba4b6"),
	"shallows": Color("e6d29c"),
	"seabed": Color("8fb3a8"),
	# Terrace sides
	"dirt": Color("b58a66"),
	"dirt_dark": Color("7d6450"),
	"sandstone": Color("d6a878"),
	"stone": Color("a39cab"),
	"stone_dark": Color("857e91"),
	"ice_cliff": Color("a9d3ea"),
	"seabed_cliff": Color("7c9a96"),
	# Plants
	"trunk": Color("8f5c3c"),
	"trunk_dark": Color("6e4630"),
	"leaf": Color("7cc05a"),
	"leaf_light": Color("9ed36b"),
	"leaf_dark": Color("5aa04e"),
	"pine": Color("3f8f64"),
	"pine_light": Color("56a877"),
	"palm": Color("7cc26a"),
	"cactus": Color("6fae5c"),
	"flower": Color("f59ab5"),
	"flower_white": Color("fbf6ee"),
	"flower_yellow": Color("f6cf4a"),
	# Minerals
	"boulder": Color("a9a3b5"),
	"rock_dark": Color("8c8599"),
	"ice": Color("d6f1fb"),
	# Village
	"wood": Color("b98357"),
	"wood_light": Color("d19f6e"),
	"wood_dark": Color("8a5a3a"),
	"awning_red": Color("ec7f86"),
	"awning_white": Color("fff1e2"),
	"cloth_pink": Color("f2a7b0"),
	"wall_cream": Color("f6ead6"),
	"roof_red": Color("e27562"),
	"roof_red_dark": Color("b95547"),
	"roof_blue": Color("6e8fd6"),
	"stone_light": Color("cfc6cc"),
	"terracotta": Color("cf8a62"),
	"apple": Color("e2524a"),
	"orange": Color("f2a33a"),
	"gold": Color("e8b64a"),
	"lamp_post": Color("4c4c6b"),
	"shrine_stone": Color("c9c3d6"),
	# Player
	"jacket": Color("9c6b47"),
	"skin": Color("f6d2b4"),
	"pants": Color("7d8c62"),
	"scarf": Color("d9686a"),
	"hair": Color("8a5a3f"),
	# Sky
	"cloud": Color("ffffff"),
	# Player details (added at the end so existing swatches keep their cells)
	"cuff": Color("efdcbc"),
	"boots": Color("7a4a33"),
	"goggle_rim": Color("e3b56c"),
	"goggle_lens": Color("6f86a8"),
	"eye": Color("3b2a24"),
	"blush": Color("f3a0a0"),
	"bedroll": Color("8aa06a"),
	"bag": Color("a8744c"),
	"roof_green": Color("6fae78"),
	"roof_teal": Color("4f9ea3"),
	"pad_metal": Color("b8bfcc"),
	"pad_stripe": Color("f2c14e"),
	"pool_water": Color("4e9bb3"),
	"moss": Color("86b865"),
	"shell": Color("f4c9b8"),
	"canvas": Color("f0e2c4"),
	"moon": Color("e9e6f2"),
	"moon_dark": Color("b9b4cc"),
}

const GLOW_COLORS := {
	"window_glow": Color("ffcf6e"),
	"lamp_glow": Color("ffe29a"),
	"shrine_glow": Color("9ff0ff"),
}

static var _uv_cache := {}


## UV at the centre of the named swatch.
static func uv(swatch: String) -> Vector2:
	if _uv_cache.is_empty():
		_build_uv_cache()
	if not _uv_cache.has(swatch):
		push_error("Palette: unknown swatch '%s'" % swatch)
		return Vector2.ZERO
	return _uv_cache[swatch]


## The swatch's colour, converted to linear light for use as a vertex colour.
static func linear(swatch: String) -> Color:
	var c: Color = COLORS.get(swatch, GLOW_COLORS.get(swatch, Color.MAGENTA))
	return c.srgb_to_linear()


static func make_texture() -> ImageTexture:
	var size := GRID * SWATCH_PX
	var image := Image.create(size, size, false, Image.FORMAT_RGBA8)
	image.fill(Color.MAGENTA)
	var cells := _cells()
	for cell: Vector2i in cells:
		image.fill_rect(Rect2i(cell * SWATCH_PX, Vector2i(SWATCH_PX, SWATCH_PX)), cells[cell])
	return ImageTexture.create_from_image(image)


## Grid cell -> colour for every swatch. Regular colours fill rows from the
## top; glow colours fill the bottom row.
@warning_ignore("integer_division")
static func _cells() -> Dictionary:
	var cells := {}
	var i := 0
	for name: String in COLORS:
		cells[Vector2i(i % GRID, i / GRID)] = COLORS[name]
		i += 1
	i = 0
	for name: String in GLOW_COLORS:
		cells[Vector2i(i, GLOW_ROW)] = GLOW_COLORS[name]
		i += 1
	return cells


@warning_ignore("integer_division")
static func _build_uv_cache() -> void:
	var i := 0
	for name: String in COLORS:
		_uv_cache[name] = _cell_uv(Vector2i(i % GRID, i / GRID))
		i += 1
	i = 0
	for name: String in GLOW_COLORS:
		_uv_cache[name] = _cell_uv(Vector2i(i, GLOW_ROW))
		i += 1


static func _cell_uv(cell: Vector2i) -> Vector2:
	return (Vector2(cell) + Vector2(0.5, 0.5)) / float(GRID)
