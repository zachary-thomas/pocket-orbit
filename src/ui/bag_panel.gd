class_name BagPanel
extends GamePanel
## The backpack: 20 slots, and a card for the selected item with what it's
## worth today. Items can be placed on the ground in front of you, or
## dropped.

var _grid: SlotGrid
var _detail: VBoxContainer
var _selected := -1


func _init(p_game: Game) -> void:
	super(p_game, "Backpack")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	body.add_child(row)
	_grid = SlotGrid.new(5, 76)
	_grid.slot_pressed.connect(_on_slot)
	row.add_child(_grid)
	_detail = VBoxContainer.new()
	_detail.custom_minimum_size = Vector2(270, 0)
	_detail.add_theme_constant_override("separation", 10)
	row.add_child(_detail)


func open() -> void:
	_selected = -1
	super()


func refresh() -> void:
	var bag := game.state.inventory
	if _selected >= 0 and bag.is_empty_slot(_selected):
		_selected = -1
	_grid.selected = _selected
	_grid.show_inventory(bag)
	set_title("Backpack  (%d/%d)" % [bag.size() - bag.free_slots(), bag.size()])
	for child in _detail.get_children():
		child.queue_free()
	if _selected == -1:
		var hint := UiTheme.label("Tap an item to see what it's worth today.\n\nSell things by putting them on your stall's shelves.", 18, UiTheme.TEXT_SOFT)
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.custom_minimum_size = Vector2(260, 0)
		_detail.add_child(hint)
		return
	_detail.add_child(GamePanel.item_card(bag.item_at(_selected), game))
	_detail.add_child(UiTheme.button("Place in front of me", _place))
	_detail.add_child(UiTheme.quiet_button("Drop", func() -> void: game.run({"type": "discard", "slot": _selected})))


func _on_slot(slot: int) -> void:
	_selected = slot if not game.state.inventory.is_empty_slot(slot) and slot != _selected else -1
	refresh()


func _place() -> void:
	var player := game.player
	var planet := game.planet
	var up := player.get_up()
	var spot := (up * planet.ground_radius(player.tile) + player.heading * 1.6).normalized()
	var tile := planet.find_tile_dir(spot, player.tile)
	if planet.data.is_water(tile):
		game.toast.emit("Can't place things in the water.")
		return
	game.run({"type": "place", "slot": _selected, "world_slot": game.graph.nearest_slot(tile, spot)})
