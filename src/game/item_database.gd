class_name ItemDatabase
extends RefCounted
## Every item's definition, loaded from data/items.json. Items are data, not
## code: adding a fish means adding a line to that file.

const DATA_PATH := "res://data/items.json"


class ItemDef:
	var id: String
	var name: String
	var category: String
	var value: int
	## 1 common, 2 uncommon, 3 rare.
	var rarity: int
	## Local hours [from, to) the item is around; to < from wraps past midnight.
	var hours := Vector2i(0, 24)
	var waters: PackedStringArray = []
	## Biome ids (Biome.GRASSLAND etc.) the item is found in; empty = anywhere.
	var biomes: PackedInt32Array = []
	var source := ""
	var size := 1
	var color := Color.WHITE
	var tags: PackedStringArray = []

	func available_at(hour: float) -> bool:
		if hours.x < hours.y:
			return hour >= hours.x and hour < hours.y
		return hour >= hours.x or hour < hours.y

	func found_in(biome: int) -> bool:
		return biomes.is_empty() or biome in biomes


static var _items := {}
static var _order: Array[String] = []
static var _categories := {}


static func get_item(id: String) -> ItemDef:
	_ensure_loaded()
	return _items.get(id)


static func has(id: String) -> bool:
	_ensure_loaded()
	return _items.has(id)


static func all() -> Array[ItemDef]:
	_ensure_loaded()
	var result: Array[ItemDef] = []
	for id in _order:
		result.append(_items[id])
	return result


static func in_category(category: String) -> Array[ItemDef]:
	var result: Array[ItemDef] = []
	for item in all():
		if item.category == category:
			result.append(item)
	return result


static func categories() -> PackedStringArray:
	_ensure_loaded()
	return PackedStringArray(_categories.keys())


static func category_name(category: String) -> String:
	_ensure_loaded()
	return _categories.get(category, {}).get("name", category.capitalize())


## How many of an item fit in one inventory slot.
static func stack_size(id: String) -> int:
	var item := get_item(id)
	if item == null:
		return 1
	return int(_categories.get(item.category, {}).get("stack", 1))


static func _ensure_loaded() -> void:
	if not _items.is_empty():
		return
	var text := FileAccess.get_file_as_string(DATA_PATH)
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("ItemDatabase: couldn't read %s" % DATA_PATH)
		return
	_categories = parsed.get("categories", {})
	for entry: Dictionary in parsed.get("items", []):
		var item := ItemDef.new()
		item.id = entry["id"]
		item.name = entry["name"]
		item.category = entry["category"]
		item.value = int(entry["value"])
		item.rarity = int(entry.get("rarity", 1))
		if entry.has("hours"):
			item.hours = Vector2i(int(entry["hours"][0]), int(entry["hours"][1]))
		item.waters = PackedStringArray(entry.get("waters", []))
		for biome_name: String in entry.get("biomes", []):
			var biome := Biome.NAMES_BY_ID.find(biome_name)
			if biome == -1:
				push_error("ItemDatabase: unknown biome %s on %s" % [biome_name, item.id])
			else:
				item.biomes.append(biome)
		item.source = entry.get("source", "")
		item.size = int(entry.get("size", 1))
		item.color = Color(entry.get("color", "ffffff"))
		item.tags = PackedStringArray(entry.get("tags", []))
		_items[item.id] = item
		_order.append(item.id)
