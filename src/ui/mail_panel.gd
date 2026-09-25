class_name MailPanel
extends GamePanel
## Your mailbox: letters on the left (newest first), the open one on the
## right. Refugees write asking to move in, answered here. With a landing
## pad, the Catalogue tab orders things you've found before by drone mail.

var _list: VBoxContainer
var _page: VBoxContainer
var _open_id := ""
var _catalog := false


func _init(p_game: Game) -> void:
	super(p_game, "Mail")
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	body.add_child(tabs)
	tabs.add_child(UiTheme.quiet_button("Letters", func() -> void:
		_catalog = false
		refresh(), Vector2(140, 46)))
	tabs.add_child(UiTheme.quiet_button("Catalogue", func() -> void:
		_catalog = true
		refresh(), Vector2(160, 46)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	body.add_child(row)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(330, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	row.add_child(scroll)
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	_page = VBoxContainer.new()
	_page.custom_minimum_size = Vector2(540, 400)
	_page.add_theme_constant_override("separation", 12)
	row.add_child(_page)


func open() -> void:
	_catalog = false
	_open_id = ""
	for i in range(game.state.mail.size() - 1, -1, -1):
		if not game.state.mail[i]["read"]:
			_open_id = game.state.mail[i]["id"]
			break
	super()
	if _open_id != "":
		game.run({"type": "read_mail", "id": _open_id})


func refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	for child in _page.get_children():
		child.queue_free()
	if _catalog:
		_show_catalog()
		return
	var state := game.state
	if state.mail.is_empty():
		_page.add_child(UiTheme.label("No letters yet.", 20, UiTheme.TEXT_SOFT))
	for i in range(state.mail.size() - 1, -1, -1):
		var letter: Dictionary = state.mail[i]
		var title := "%s%s\n%s · %s" % ["● " if not letter["read"] else "", letter["subject"], letter["from"], GameHud.date_label(letter["day"])]
		var b := UiTheme.quiet_button(title, _open_letter.bind(letter["id"]), Vector2(310, 64))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 16)
		if letter["id"] == _open_id:
			b.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.AMBER_LIGHT, 14, UiTheme.WOOD, 2, 2))
		_list.add_child(b)
	var letter := state.letter(_open_id)
	if letter.is_empty():
		return
	_page.add_child(UiTheme.label(letter["subject"], 24, UiTheme.WOOD_DARK))
	_page.add_child(UiTheme.label("From %s, %s" % [letter["from"], GameHud.date_label(letter["day"])], 16, UiTheme.TEXT_SOFT))
	var text := UiTheme.label(letter["body"], 19)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.custom_minimum_size = Vector2(520, 0)
	_page.add_child(text)
	if letter["kind"] == "move_in":
		var status: String = letter["data"].get("status", "")
		if status == "pending":
			var species := VillageData.species(letter["data"]["species"])
			var about := UiTheme.label("%s: %s" % [species.get("plural", ""), species.get("blurb", "")], 16, UiTheme.TEXT_SOFT)
			about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			about.custom_minimum_size = Vector2(520, 0)
			_page.add_child(about)
			var free := VillageRules.free_homes(state).size()
			_page.add_child(UiTheme.label("Free homes: %d" % free, 16, UiTheme.GOOD if free > 0 else UiTheme.BAD))
			var answer := HBoxContainer.new()
			answer.add_theme_constant_override("separation", 10)
			_page.add_child(answer)
			var yes := UiTheme.button("Welcome them", func() -> void: game.run({"type": "accept_resident", "id": letter["id"]}), Vector2(200, 54))
			yes.disabled = free == 0
			answer.add_child(yes)
			answer.add_child(UiTheme.quiet_button("Not right now", func() -> void: game.run({"type": "decline_resident", "id": letter["id"]}), Vector2(180, 54)))
		else:
			_page.add_child(UiTheme.label("You welcomed them." if status == "accepted" else "You wrote back: not right now.", 17, UiTheme.TEXT_SOFT))


func _open_letter(id: String) -> void:
	_open_id = id
	game.run({"type": "read_mail", "id": id})
	refresh()


func _show_catalog() -> void:
	var state := game.state
	var head := UiTheme.label("Drone Mail catalogue", 24, UiTheme.WOOD_DARK)
	_list.add_child(head)
	var note := UiTheme.label("Anything you've found before can be ordered. It lands on your pad the next morning.", 16, UiTheme.TEXT_SOFT)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size = Vector2(310, 0)
	_list.add_child(note)
	if not state.has_building("landing_pad"):
		_page.add_child(UiTheme.label("Build a landing pad on a village plot so drones can deliver.", 19, UiTheme.TEXT_SOFT))
		return
	if not state.orders.is_empty():
		_list.add_child(UiTheme.label("On the way: %d order(s)" % state.orders.size(), 17, UiTheme.GOOD))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(540, 400)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.add_child(grid)
	_page.add_child(scroll)
	var items := VillageRules.catalog(state)
	if items.is_empty():
		_page.add_child(UiTheme.label("Nothing yet: collect materials, fruit, minerals or shore finds first.", 17, UiTheme.TEXT_SOFT))
	for id in items:
		var item := ItemDatabase.get_item(id)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 8)
		var icon := ItemIcon.new(id)
		icon.custom_minimum_size = Vector2(52, 52)
		h.add_child(icon)
		var name := UiTheme.label("%s\n%d each" % [item.name, VillageRules.catalog_price(id)], 16)
		name.custom_minimum_size = Vector2(130, 0)
		h.add_child(name)
		var count := 5 if ItemDatabase.stack_size(id) > 1 else 1
		var buy := UiTheme.button("Order x%d" % count, func() -> void: game.run({"type": "order", "item": id, "count": count}), Vector2(96, 44))
		buy.add_theme_font_size_override("font_size", 15)
		buy.disabled = state.stardust < VillageRules.catalog_price(id) * count
		h.add_child(buy)
		grid.add_child(h)
