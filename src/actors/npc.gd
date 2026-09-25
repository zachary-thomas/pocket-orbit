class_name Npc
extends GravityBody
## Someone walking around the planet: passing customers, Vessa, and villagers
## later. Walks routes from the TileGraph, turns to face where it's going,
## and can show a speech bubble ("!", a price reaction) over its head.
##
## Bodies are built from simple shapes until the character models arrive
## (see the polish backlog).

enum Look { TRAVELER, VESSA }

const TRAVELER_COATS := ["e07a5f", "81b29a", "f2cc8f", "6d9dc5", "b392ac", "e5989b", "8ab17d"]
const TRAVELER_SKINS := ["a8d5ba", "c3b1e1", "f6bd9b", "9fd3e6", "f7d488", "d4a5a5"]

@export var walk_speed := 2.4

var look := Look.TRAVELER
var _visual: MeshInstance3D
var _bubble: Label3D
var _bubble_time := 0.0
var _walk_cycle := 0.0


func _ready() -> void:
	min_prop_radius = 1.0
	_visual = MeshInstance3D.new()
	add_child(_visual)
	_bubble = Label3D.new()
	_bubble.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_bubble.position = Vector3(0, 2.25, 0)
	_bubble.font_size = 64
	_bubble.pixel_size = 0.006
	_bubble.outline_size = 18
	_bubble.modulate = UiTheme.TEXT
	_bubble.outline_modulate = UiTheme.CREAM
	_bubble.no_depth_test = true
	_bubble.visible = false
	add_child(_bubble)


func build(p_look: Look, material: Material, rng: RandomNumberGenerator) -> void:
	look = p_look
	var md := MeshData.new()
	if look == Look.VESSA:
		_build_vessa(md)
	else:
		_build_traveler(md, rng)
	_visual.mesh = md.to_mesh(material)


func _process(delta: float) -> void:
	if planet == null:
		return
	var moving := false
	if has_route():
		var wish := follow_route(delta, walk_speed)
		if wish != Vector3.ZERO:
			turn_towards(wish, 8.0 * delta)
			moving = true
	update_vertical(delta)
	if moving:
		_walk_cycle += delta * 11.0
	else:
		_walk_cycle = move_toward(_walk_cycle, ceilf(_walk_cycle / PI) * PI, delta * 11.0)
	_visual.position.y = absf(sin(_walk_cycle)) * 0.07
	_visual.rotation.z = sin(_walk_cycle) * 0.05
	if _bubble_time > 0.0:
		_bubble_time -= delta
		_bubble.visible = _bubble_time > 0.0


## Shows `text` over the head for a few seconds.
func say(text: String, seconds: float = 2.5) -> void:
	_bubble.text = text
	_bubble_time = seconds
	_bubble.visible = true


## Turns to face a world position (instantly).
func face(world_position: Vector3) -> void:
	heading = SphereMath.tangent(world_position - global_position, get_up())
	update_vertical(0.0)


# --- Bodies ------------------------------------------------------------------
# -Z is forward, like the player.

func _build_traveler(md: MeshData, rng: RandomNumberGenerator) -> void:
	var white := Palette.uv("white")
	var coat := Color(TRAVELER_COATS[rng.randi() % TRAVELER_COATS.size()]).srgb_to_linear()
	var skin := Color(TRAVELER_SKINS[rng.randi() % TRAVELER_SKINS.size()]).srgb_to_linear()
	var tall := rng.randf_range(0.9, 1.1)
	var root := Transform3D.IDENTITY.scaled(Vector3(1, tall, 1))
	md.tint = coat.darkened(0.35)
	for side in [-1.0, 1.0]:
		md.add_box(root.translated_local(Vector3(0.13 * side, 0.18, 0)), Vector3(0.16, 0.36, 0.18), white)
	md.tint = coat
	md.add_prism(root.translated_local(Vector3(0, 0.32, 0)), 0.38, 0.26, 0.7, 7, white)
	md.tint = skin
	md.add_blob(root.translated_local(Vector3(0, 1.3, 0)), Vector3(0.38, 0.34, 0.36), white, 1)
	for side in [-1.0, 1.0]:
		md.add_blob(root.translated_local(Vector3(0.4 * side, 0.62, 0)), Vector3(0.11, 0.11, 0.11), white)
	# Eyes, and antennae or round ears depending on the traveller.
	md.tint = Color(0.06, 0.05, 0.08)
	for side in [-1.0, 1.0]:
		md.add_blob(root.translated_local(Vector3(0.13 * side, 1.34, -0.32)), Vector3(0.05, 0.07, 0.03), white)
	md.tint = skin.darkened(0.15)
	var antennae := rng.randf() < 0.5
	for side in [-1.0, 1.0]:
		if antennae:
			md.add_prism(root.translated_local(Vector3(0.14 * side, 1.58, 0)).rotated_local(Vector3.BACK, -0.35 * side), 0.03, 0.02, 0.32, 4, white)
			md.add_blob(root.translated_local(Vector3(0.26 * side, 1.9, 0)), Vector3.ONE * 0.07, white)
		else:
			md.add_blob(root.translated_local(Vector3(0.3 * side, 1.58, 0.02)), Vector3(0.12, 0.12, 0.06), white)
	# A satchel for carrying their shopping home.
	md.tint = Color.WHITE
	md.add_box(root.translated_local(Vector3(0.3, 0.55, 0.12)), Vector3(0.1, 0.26, 0.28), Palette.uv("wood_light"))
	md.tint = Color.WHITE


## Vessa: a relaxed fox-like smuggler in a long coat with a cargo satchel.
func _build_vessa(md: MeshData) -> void:
	var white := Palette.uv("white")
	var fur := Color("d9793f").srgb_to_linear()
	var cream := Color("fbe8cf").srgb_to_linear()
	var coat := Color("3f5d6e").srgb_to_linear()
	var root := Transform3D.IDENTITY.scaled(Vector3.ONE * 1.08)
	md.tint = Color("3a2c28").srgb_to_linear()
	for side in [-1.0, 1.0]:
		md.add_box(root.translated_local(Vector3(0.12 * side, 0.15, 0)), Vector3(0.14, 0.3, 0.18), white)
	md.tint = coat
	md.add_prism(root.translated_local(Vector3(0, 0.12, 0)), 0.4, 0.27, 0.95, 8, white)
	md.add_prism(root.translated_local(Vector3(0, 1.0, 0)), 0.3, 0.2, 0.12, 8, white)
	md.tint = Color("e9b44c").srgb_to_linear()
	md.add_box(root.translated_local(Vector3(0, 0.62, -0.33)).rotated_local(Vector3.BACK, 0.7), Vector3(0.06, 0.9, 0.04), white)
	md.tint = Color.WHITE
	md.add_box(root.translated_local(Vector3(-0.36, 0.5, 0.05)), Vector3(0.14, 0.3, 0.34), Palette.uv("wood"))
	# Head: fox face with a cream muzzle and tall ears.
	md.tint = fur
	md.add_blob(root.translated_local(Vector3(0, 1.36, 0)), Vector3(0.34, 0.3, 0.32), white, 1)
	for side in [-1.0, 1.0]:
		md.add_prism(root.translated_local(Vector3(0.18 * side, 1.56, 0.04)).rotated_local(Vector3.BACK, -0.25 * side), 0.11, 0.0, 0.34, 4, white)
		md.add_blob(root.translated_local(Vector3(0.42 * side, 0.62, 0)), Vector3(0.1, 0.1, 0.1), white)
	md.tint = cream
	md.add_blob(root.translated_local(Vector3(0, 1.28, -0.26)), Vector3(0.16, 0.12, 0.16), white)
	md.tint = Color(0.06, 0.05, 0.08)
	md.add_blob(root.translated_local(Vector3(0, 1.32, -0.42)), Vector3.ONE * 0.045, white)
	for side in [-1.0, 1.0]:
		md.add_blob(root.translated_local(Vector3(0.13 * side, 1.43, -0.27)), Vector3(0.045, 0.03, 0.02), white)
	# Bushy tail with a white tip.
	md.tint = fur
	md.add_blob(root.translated_local(Vector3(0.05, 0.35, 0.45)).rotated_local(Vector3.RIGHT, -0.6), Vector3(0.16, 0.34, 0.16), white, 1)
	md.tint = cream
	md.add_blob(root.translated_local(Vector3(0.06, 0.12, 0.66)), Vector3(0.1, 0.12, 0.1), white)
	md.tint = Color.WHITE
