class_name StoragePanel
extends GamePanel
## The cargo pod's storage chest: tap something in your backpack to store
## it, or in the chest to take it back.

var _bag: SlotGrid
var _chest: SlotGrid


func _init(p_game: Game) -> void:
	super(p_game, "Home storage")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 26)
	body.add_child(row)
	var left := VBoxContainer.new()
	row.add_child(left)
	left.add_child(UiTheme.label("Backpack: tap to store", 18, UiTheme.TEXT_SOFT))
	_bag = SlotGrid.new(5, 66)
	_bag.slot_pressed.connect(func(slot: int) -> void: game.run({"type": "store", "slot": slot}))
	left.add_child(_bag)
	var right := VBoxContainer.new()
	row.add_child(right)
	right.add_child(UiTheme.label("Chest: tap to take", 18, UiTheme.TEXT_SOFT))
	_chest = SlotGrid.new(8, 54)
	_chest.slot_pressed.connect(func(slot: int) -> void: game.run({"type": "retrieve", "slot": slot}))
	right.add_child(_chest)


func refresh() -> void:
	_bag.show_inventory(game.state.inventory)
	_chest.show_inventory(game.state.storage)
