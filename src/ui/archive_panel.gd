class_name ArchivePanel
extends GamePanel
## The Archive: how much of each collection has been donated, what's in it,
## and your backpack to donate from (one of each kind; it helps your
## reputation a little).

var _progress: VBoxContainer
var _grid: SlotGrid
var _hint: Label


func _init(p_game: Game) -> void:
	super(p_game, "The Archive")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	body.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(460, 420)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_progress = VBoxContainer.new()
	_progress.add_theme_constant_override("separation", 8)
	_progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_progress)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 10)
	row.add_child(side)
	side.add_child(UiTheme.label("Donate from your backpack", 20, UiTheme.WOOD_DARK))
	_grid = SlotGrid.new(5, 68)
	_grid.slot_pressed.connect(func(slot: int) -> void:
		if not game.state.inventory.is_empty_slot(slot):
			game.run({"type": "donate", "slot": slot}))
	side.add_child(_grid)
	_hint = UiTheme.label("", 16, UiTheme.TEXT_SOFT)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size = Vector2(360, 0)
	side.add_child(_hint)


func refresh() -> void:
	var state := game.state
	_grid.show_inventory(state.inventory)
	for child in _progress.get_children():
		child.queue_free()
	var total := 0
	var have := 0
	for category: String in VillageRules.ARCHIVE_CATEGORIES:
		var items := ItemDatabase.in_category(category)
		var donated := items.filter(func(item: ItemDatabase.ItemDef) -> bool: return state.archive.has(item.id))
		total += items.size()
		have += donated.size()
		_progress.add_child(UiTheme.label("%s  %d / %d" % [ItemDatabase.category_name(category), donated.size(), items.size()], 20, UiTheme.WOOD_DARK))
		var flow := HFlowContainer.new()
		flow.add_theme_constant_override("h_separation", 4)
		flow.add_theme_constant_override("v_separation", 4)
		flow.custom_minimum_size = Vector2(440, 0)
		for item: ItemDatabase.ItemDef in items:
			var icon := ItemIcon.new(item.id if state.archive.has(item.id) else "")
			icon.custom_minimum_size = Vector2(40, 40)
			icon.tooltip_text = item.name if state.archive.has(item.id) else "?"
			var frame := PanelContainer.new()
			frame.add_theme_stylebox_override("panel", UiTheme.slot_style(false))
			frame.add_child(icon)
			flow.add_child(frame)
		_progress.add_child(flow)
	set_title("The Archive  (%d / %d)" % [have, total])
	_hint.text = "Tap something to donate it. The Archive keeps one of every fish, bug, mineral, fossil and shore find."
