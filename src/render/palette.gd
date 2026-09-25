class_name Palette
extends RefCounted
## The one shared palette texture every model in the game is coloured from.
##
## A 16 x 16 grid of flat colour swatches (256 x 256 px). Models don't carry
## their own textures: each face's UVs point at the centre of a swatch, so one
## material covers everything and changing a colour here recolours the game.
##
## The bottom row (row 15) holds "glow" swatches. The surface shader makes
## those emit light at night, for windows, lamps and shrine crystals.

const GRID := 16
const SWATCH_PX := 16
const GLOW_ROW := 15

const COLORS := {
	# Terrain tops
	"grass": Color("8ccf6b"),
	"tundra": Color("a3c28c"),
	"jungle": Color("4fa35a"),
	"sand": Color("ecd49a"),
	"snow": Color("f2f6fb"),
	"rock": Color("aaa3ab"),
	"shallows": Color("e3cf98"),
	"seabed": Color("8fb3a8"),
	# Terrace sides
	"dirt": Color("b98a5e"),
	"dirt_dark": Color("7a6048"),
	"sandstone": Color("d4a46c"),
	"stone": Color("8f8b91"),
	"stone_dark": Color("77717e"),
	"ice_cliff": Color("a9d3ea"),
	"seabed_cliff": Color("7c9a96"),
	# Plants
	"trunk": Color("8a5a3c"),
	"leaf": Color("6fbf5a"),
	"leaf_dark": Color("4f9a4c"),
	"pine": Color("3f7d5a"),
	"palm": Color("7cc26a"),
	"cactus": Color("6fae5c"),
	"flower": Color("f59ab5"),
	# Minerals
	"boulder": Color("9c97a3"),
	"ice": Color("d6f1fb"),
	# Village
	"wood": Color("c08a5a"),
	"wood_dark": Color("8f623f"),
	"awning_red": Color("e46a6a"),
	"awning_white": Color("fff4e6"),
	"wall_cream": Color("f3e3c3"),
	"roof_red": Color("d9695b"),
	"roof_blue": Color("6e8fd6"),
	"lamp_post": Color("5b5566"),
	"shrine_stone": Color("c9c3d6"),
	# Player placeholder
	"jacket": Color("e9a04b"),
	"skin": Color("f2c7a0"),
	"pants": Color("4d6aa3"),
	"scarf": Color("d9534f"),
	"hair": Color("6b4a35"),
	# Sky
	"cloud": Color("ffffff"),
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
