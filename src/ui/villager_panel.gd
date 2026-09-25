class_name VillagerPanel
extends GamePanel
## Chatting with a villager (game.ui_subject is their id): what they say
## today, how well you know each other, and what their kind likes.

var _text: Label
var _about: Label
var _hearts: Label


func _init(p_game: Game) -> void:
	super(p_game, "")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.custom_minimum_size = Vector2(640, 0)
	body.add_child(v)
	_hearts = UiTheme.label("", 20, UiTheme.BAD)
	v.add_child(_hearts)
	_text = UiTheme.label("", 22)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(620, 90)
	v.add_child(_text)
	_about = UiTheme.label("", 16, UiTheme.TEXT_SOFT)
	_about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_about.custom_minimum_size = Vector2(620, 0)
	v.add_child(_about)
	v.add_child(UiTheme.button("See you!", func() -> void: close_requested.emit(), Vector2(160, 54)))


func open() -> void:
	super()
	var result := game.run({"type": "talk_villager", "id": game.ui_subject})
	_text.text = "\"%s\"" % result.get("line", "...")
	refresh()


func refresh() -> void:
	var v := game.state.villager(game.ui_subject)
	if v.is_empty():
		return
	var species := VillageData.species(v["species"])
	set_title("%s the %s" % [v["name"], species.get("name", "")])
	var friendship := int(v["friendship"])
	_hearts.text = "♥".repeat(mini(friendship / 2 + 1, 10)) + "  friends for %d chats" % friendship
	var likes := PackedStringArray()
	for like: String in species.get("likes", []):
		likes.append(ItemDatabase.category_name(like).to_lower() if like in ItemDatabase.categories() else "%s things" % like)
	_about.text = "%s  They love %s, and pay more for them in your shop." % [species.get("blurb", ""), ", ".join(likes)]
