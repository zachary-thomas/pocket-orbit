class_name GamePanel
extends PanelContainer
## Base for the menus that open over the game (bag, stall, storage, Vessa):
## a cream panel with a title and a close button. Subclasses fill `body`
## and redraw in refresh(), which runs on open and whenever the state
## changes while open.

signal close_requested

var game: Game
var body: VBoxContainer
var _title: Label


func _init(p_game: Game, title: String) -> void:
	game = p_game
	add_to_group("ui_blocker")
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 14)
	add_child(outer)
	var header := HBoxContainer.new()
	outer.add_child(header)
	_title = UiTheme.label(title, 30, UiTheme.WOOD_DARK)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	header.add_child(UiTheme.quiet_button("Close", func() -> void: close_requested.emit(), Vector2(110, 50)))
	body = VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	outer.add_child(body)


func set_title(text: String) -> void:
	_title.text = text


func open() -> void:
	if not game.state.changed.is_connected(_on_state_changed):
		game.state.changed.connect(_on_state_changed)
	refresh()


func closed() -> void:
	if game.state.changed.is_connected(_on_state_changed):
		game.state.changed.disconnect(_on_state_changed)


func refresh() -> void:
	pass


func _on_state_changed(_what: String) -> void:
	refresh()


## Big item picture with name and today's worth, for detail cards.
static func item_card(item_id: String, game_ref: Game) -> VBoxContainer:
	var card := VBoxContainer.new()
	card.add_theme_constant_override("separation", 4)
	var item := ItemDatabase.get_item(item_id)
	var icon := ItemIcon.new(item_id)
	icon.custom_minimum_size = Vector2(110, 110)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.add_child(icon)
	var name := UiTheme.label(item.name if item else "", 24)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	card.add_child(name)
	if item:
		var rarity: String = ["", "Common", "Uncommon", "Rare"][clampi(item.rarity, 0, 3)]
		var kind := UiTheme.label("%s · %s" % [ItemDatabase.category_name(item.category).trim_suffix("s") if item.category != "fish" else "Fish", rarity], 17, UiTheme.TEXT_SOFT)
		kind.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(kind)
		var worth := UiTheme.label("Worth about %d today" % game_ref.worth_today(item_id), 18, UiTheme.TEXT)
		worth.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card.add_child(worth)
	return card
