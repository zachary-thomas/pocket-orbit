class_name WorldItems
extends Node3D
## Items shown in the world from the game state: what's on the stall's four
## shelves (with price tags) and things the player has placed on the ground.
## Rebuilt whenever the state changes; there are only ever a handful.

## Where each shelf's item sits on the stall counter, in the stall's space
## (+Z is the customer side).
const SHELF_SPOTS := [Vector3(-0.92, 1.03, 0.3), Vector3(-0.32, 1.03, 0.36), Vector3(0.3, 1.03, 0.36), Vector3(0.9, 1.03, 0.32)]
## The general shop's twelve: six along the counter, six on the shelf
## across the window above it.
const SHOP_SPOTS := [
	Vector3(-1.3, 1.04, 1.62), Vector3(-0.78, 1.04, 1.62), Vector3(-0.26, 1.04, 1.62), Vector3(0.26, 1.04, 1.62), Vector3(0.78, 1.04, 1.62), Vector3(1.3, 1.04, 1.62),
	Vector3(-1.3, 1.53, 1.4), Vector3(-0.78, 1.53, 1.4), Vector3(-0.26, 1.53, 1.4), Vector3(0.26, 1.53, 1.4), Vector3(0.78, 1.53, 1.4), Vector3(1.3, 1.53, 1.4),
]
## Items on the counter are shown a little bigger than life, so they read.
const SHELF_SCALE := 1.35
## Placed items are shown bigger than on a shelf so they read on the ground.
const PLACED_SCALE := 1.8

var game: Game
var _material: Material
var _shelves: Node3D
var _placed: Node3D


func setup(p_game: Game, material: Material) -> void:
	game = p_game
	_material = material
	for child in get_children():
		child.queue_free()
	_shelves = Node3D.new()
	_shelves.name = "Shelves"
	add_child(_shelves)
	_shelves.transform = game.planet.data.village["stall"]
	_placed = Node3D.new()
	_placed.name = "Placed"
	add_child(_placed)
	game.state.changed.connect(_on_changed)
	refresh()


func _on_changed(what: String) -> void:
	if what in ["stock_shelf", "unstock_shelf", "set_price", "sell", "place", "pick_up", "upgrade_shop"]:
		refresh()


func refresh() -> void:
	for child in _shelves.get_children():
		child.queue_free()
	for child in _placed.get_children():
		child.queue_free()
	var state := game.state
	var spots: Array = SHOP_SPOTS if state.shop_tier >= 2 else SHELF_SPOTS
	for i in mini(state.shelves.size(), spots.size()):
		var shelf: Dictionary = state.shelves[i]
		if shelf.is_empty():
			continue
		var item := MeshInstance3D.new()
		item.mesh = ItemMeshes.mesh(shelf["item"], _material)
		item.position = spots[i]
		item.rotation.y = PI * 0.5 + (i % 6 - 2.5) * 0.2
		item.scale = Vector3.ONE * SHELF_SCALE
		_shelves.add_child(item)
		var tag := Label3D.new()
		tag.text = "%d" % Economy.price(shelf["item"], float(shelf["price"]))
		if int(shelf["count"]) > 1:
			tag.text += "  x%d" % int(shelf["count"])
		tag.position = spots[i] + Vector3(0, 0.02, 0.24 if spots[i].y < 1.3 else 0.14)
		tag.rotation.x = -PI * 0.3
		tag.font_size = 40
		tag.pixel_size = 0.004
		tag.outline_size = 12
		tag.modulate = UiTheme.TEXT
		tag.outline_modulate = UiTheme.CREAM
		_shelves.add_child(tag)
	for id: String in state.placed:
		var placed: Dictionary = state.placed[id]
		var at := game.graph.slot_position(placed["slot"])
		var item := MeshInstance3D.new()
		item.mesh = ItemMeshes.mesh(placed["item"], _material)
		item.transform = Transform3D(SphereMath.basis_from_up(at.normalized(), hash(id) % 628 / 100.0).scaled(Vector3.ONE * PLACED_SCALE), at)
		item.set_meta("placed_id", id)
		_placed.add_child(item)


## Placed item ids with their world positions, for interaction.
func placed_positions() -> Dictionary:
	var result := {}
	for id: String in game.state.placed:
		result[id] = game.graph.slot_position(game.state.placed[id]["slot"])
	return result


## A caught or gathered item pops up above `at` and fades, as feedback.
static func pop(parent: Node, item_id: String, at: Vector3, up: Vector3, material: Material) -> void:
	var node := MeshInstance3D.new()
	node.mesh = ItemMeshes.mesh(item_id, material)
	parent.add_child(node)
	node.global_transform = Transform3D(SphereMath.basis_from_up(up).scaled(Vector3.ONE * 2.2), at + up * 1.6)
	var tween := node.create_tween()
	tween.tween_property(node, "global_position", at + up * 2.6, 1.1).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(node, "scale", Vector3.ONE * 0.01, 0.25)
	tween.tween_callback(node.queue_free)
