class_name ShopPanel
extends GamePanel
## The market stall: four shelves, each with a price slider from bargain to
## premium, and the demand board with today's hints. "Stock" swaps the
## demand board for your backpack so you can pick what goes on the shelf.

var _rows: Array[Dictionary] = []
var _side: VBoxContainer
var _stocking := -1
var _reputation: Label


func _init(p_game: Game) -> void:
	super(p_game, "Your Stall")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	body.add_child(row)
	var shelves := VBoxContainer.new()
	shelves.add_theme_constant_override("separation", 10)
	row.add_child(shelves)
	for i in GameState.SHELF_COUNT:
		_rows.append(_make_row(shelves, i))
	_reputation = UiTheme.label("", 17, UiTheme.TEXT_SOFT)
	shelves.add_child(_reputation)
	_side = VBoxContainer.new()
	_side.custom_minimum_size = Vector2(390, 0)
	_side.add_theme_constant_override("separation", 10)
	row.add_child(_side)


func open() -> void:
	_stocking = -1
	super()


func _make_row(parent: Control, shelf: int) -> Dictionary:
	var card := PanelContainer.new()
	var style := UiTheme.box(UiTheme.CREAM_DARK, 18, Color(UiTheme.WOOD, 0.4), 2, 0)
	style.set_content_margin_all(8)
	card.add_theme_stylebox_override("panel", style)
	parent.add_child(card)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	card.add_child(h)
	var icon := ItemIcon.new()
	icon.custom_minimum_size = Vector2(64, 64)
	h.add_child(icon)
	var text := VBoxContainer.new()
	text.custom_minimum_size = Vector2(190, 0)
	text.add_theme_constant_override("separation", 0)
	h.add_child(text)
	var name := UiTheme.label("", 20)
	text.add_child(name)
	var info := UiTheme.label("", 15, UiTheme.TEXT_SOFT)
	text.add_child(info)
	var price_box := VBoxContainer.new()
	price_box.custom_minimum_size = Vector2(210, 0)
	price_box.add_theme_constant_override("separation", 0)
	h.add_child(price_box)
	var price := UiTheme.label("", 18)
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	price_box.add_child(price)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.custom_minimum_size = Vector2(200, 34)
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(value: float) -> void: game.run({"type": "set_price", "shelf": shelf, "level": value}))
	price_box.add_child(slider)
	var ends := HBoxContainer.new()
	price_box.add_child(ends)
	var cheap := UiTheme.label("bargain", 13, UiTheme.TEXT_SOFT)
	cheap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ends.add_child(cheap)
	ends.add_child(UiTheme.label("premium", 13, UiTheme.TEXT_SOFT))
	var button := UiTheme.button("Stock", func() -> void: _on_shelf_button(shelf), Vector2(96, 50))
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(button)
	return {"icon": icon, "name": name, "info": info, "price": price, "slider": slider, "button": button, "price_box": price_box}


func refresh() -> void:
	var state := game.state
	for i in _rows.size():
		var row := _rows[i]
		var shelf: Dictionary = state.shelves[i]
		var empty := shelf.is_empty()
		row["icon"].item_id = "" if empty else shelf["item"]
		row["price_box"].modulate.a = 0.0 if empty else 1.0
		row["slider"].editable = not empty
		if empty:
			row["name"].text = "Empty shelf"
			row["info"].text = "Stock it from your backpack" if _stocking != i else "Pick something →"
			row["button"].text = "Stock" if _stocking != i else "Cancel"
			continue
		var item := ItemDatabase.get_item(shelf["item"])
		var worth := game.worth_today(shelf["item"])
		var asking := Economy.price(shelf["item"], float(shelf["price"]))
		row["name"].text = item.name
		row["info"].text = "%d of %d left · worth %d today" % [int(shelf["count"]), GameState.SHELF_STACK, worth]
		row["slider"].set_value_no_signal(float(shelf["price"]))
		var feel := Economy.price_feel(asking, worth)
		row["price"].text = "%d Stardust · %s" % [asking, feel]
		row["price"].add_theme_color_override("font_color", {"bargain": UiTheme.GOOD, "fair": UiTheme.TEXT, "pricey": UiTheme.AMBER_DARK, "too much": UiTheme.BAD}[feel])
		var room := int(shelf["count"]) < GameState.SHELF_STACK
		row["button"].text = "Cancel" if _stocking == i else ("Add" if room else "Clear")
	_reputation.text = "Reputation: %s (%d)  ·  fair prices build it, and it brings more customers" % [reputation_name(state.reputation), state.reputation]
	for child in _side.get_children():
		child.queue_free()
	if _stocking >= 0:
		_side.add_child(UiTheme.label("Put on shelf %d:" % (_stocking + 1), 22, UiTheme.WOOD_DARK))
		var grid := SlotGrid.new(5, 68)
		grid.show_inventory(state.inventory)
		grid.slot_pressed.connect(_stock_from)
		_side.add_child(grid)
		var clear_row := HBoxContainer.new()
		_side.add_child(clear_row)
		if not state.shelves[_stocking].is_empty():
			clear_row.add_child(UiTheme.quiet_button("Take back what's there", func() -> void:
				game.run({"type": "unstock_shelf", "shelf": _stocking})
				_stocking = -1
				refresh()))
	else:
		_side.add_child(_demand_board())


func _on_shelf_button(shelf: int) -> void:
	var current: Dictionary = game.state.shelves[shelf]
	if _stocking != shelf and not current.is_empty() and int(current["count"]) >= GameState.SHELF_STACK:
		game.run({"type": "unstock_shelf", "shelf": shelf})
		return
	_stocking = -1 if _stocking == shelf else shelf
	refresh()


static func reputation_name(reputation: int) -> String:
	return ["New in town", "Known", "Liked", "Trusted", "Beloved"][clampi(reputation / 20, 0, 4)]


func _stock_from(slot: int) -> void:
	if _stocking < 0 or game.state.inventory.is_empty_slot(slot):
		return
	var result := game.run({"type": "stock_shelf", "slot": slot, "shelf": _stocking})
	if result["ok"]:
		_stocking = -1
		refresh()


func _demand_board() -> Control:
	var board := PanelContainer.new()
	var style := UiTheme.box(UiTheme.NAVY, 20, UiTheme.WOOD, 6, 0)
	style.set_content_margin_all(18)
	board.add_theme_stylebox_override("panel", style)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	board.add_child(v)
	v.add_child(UiTheme.label("Today's demand", 24, UiTheme.AMBER_LIGHT))
	for hint in Economy.hints(game.state.world_seed, game.state.day):
		var line := UiTheme.label("·  " + hint, 18, UiTheme.CREAM)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.custom_minimum_size = Vector2(340, 0)
		v.add_child(line)
	var total := 0
	for sale in game.state.sales_today:
		total += int(sale["price"])
	v.add_child(UiTheme.label("Sold today: %d  (%d Stardust)" % [game.state.sales_today.size(), total], 17, Color(UiTheme.CREAM, 0.75)))
	return board
