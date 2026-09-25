class_name SlotGrid
extends GridContainer
## A grid of inventory slots showing item icons. Tapping a slot emits
## `slot_pressed`; the selected slot is highlighted.

signal slot_pressed(slot: int)

var inventory: Inventory
var selected := -1
var slot_size := 72.0

var _slots: Array[Button] = []
var _icons: Array[ItemIcon] = []


func _init(p_columns: int = 5, p_slot_size: float = 72.0) -> void:
	columns = p_columns
	slot_size = p_slot_size
	add_theme_constant_override("h_separation", 8)
	add_theme_constant_override("v_separation", 8)


func show_inventory(p_inventory: Inventory) -> void:
	inventory = p_inventory
	if _slots.size() != inventory.size():
		for child in get_children():
			child.queue_free()
		_slots.clear()
		_icons.clear()
		for i in inventory.size():
			var button := Button.new()
			button.custom_minimum_size = Vector2(slot_size, slot_size)
			button.focus_mode = Control.FOCUS_NONE
			button.pressed.connect(func() -> void: slot_pressed.emit(i))
			var icon := ItemIcon.new()
			icon.set_anchors_preset(Control.PRESET_FULL_RECT)
			icon.offset_left = 6
			icon.offset_top = 6
			icon.offset_right = -6
			icon.offset_bottom = -6
			button.add_child(icon)
			add_child(button)
			_slots.append(button)
			_icons.append(icon)
	refresh()


func refresh() -> void:
	if inventory == null:
		return
	for i in _slots.size():
		_icons[i].item_id = inventory.item_at(i)
		_icons[i].count = inventory.count_at(i)
		var style := UiTheme.slot_style(i == selected)
		for state in ["normal", "hover", "pressed", "disabled"]:
			_slots[i].add_theme_stylebox_override(state, style)
		var item := ItemDatabase.get_item(inventory.item_at(i)) if not inventory.is_empty_slot(i) else null
		_slots[i].tooltip_text = item.name if item else ""


func select(slot: int) -> void:
	selected = slot
	refresh()
