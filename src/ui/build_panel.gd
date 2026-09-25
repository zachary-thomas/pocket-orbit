class_name BuildPanel
extends GamePanel
## Building on an empty village plot (game.ui_subject is the plot id): what
## can go there, what each costs, and what's still missing.

var _cards: VBoxContainer


func _init(p_game: Game) -> void:
	super(p_game, "Build")
	var note := UiTheme.label("Materials come from your backpack first, then your storage chest.", 16, UiTheme.TEXT_SOFT)
	body.add_child(note)
	_cards = VBoxContainer.new()
	_cards.add_theme_constant_override("separation", 10)
	body.add_child(_cards)


func refresh() -> void:
	for child in _cards.get_children():
		child.queue_free()
	var state := game.state
	for def: Dictionary in VillageData.plot_buildings():
		var card := PanelContainer.new()
		var style := UiTheme.box(UiTheme.CREAM_DARK, 18, Color(UiTheme.WOOD, 0.4), 2, 0)
		style.set_content_margin_all(12)
		card.add_theme_stylebox_override("panel", style)
		_cards.add_child(card)
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		card.add_child(h)
		var text := VBoxContainer.new()
		text.custom_minimum_size = Vector2(560, 0)
		h.add_child(text)
		text.add_child(UiTheme.label(def["name"], 22, UiTheme.WOOD_DARK))
		var blurb := UiTheme.label(def["blurb"], 16, UiTheme.TEXT_SOFT)
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb.custom_minimum_size = Vector2(540, 0)
		text.add_child(blurb)
		var costs: Dictionary = def["costs"]
		var affordable := Commands.can_afford(state, costs)
		text.add_child(UiTheme.label("Costs " + Commands.costs_text(costs), 16, UiTheme.TEXT if affordable else UiTheme.BAD))
		var built := def["id"] != "burrow_house" and state.has_building(def["id"])
		var b := UiTheme.button("Built" if built else "Build", func() -> void:
			var result := game.run({"type": "build", "kind": def["id"], "plot": game.ui_subject})
			if result["ok"]:
				close_requested.emit(), Vector2(130, 56))
		b.disabled = built or not affordable
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(b)
