class_name VillageData
extends RefCounted
## The sanctuary's data from data/village.json: refugee species, buildings
## you can put up, and the auditor's questions. Read-only; loaded once.

const DATA_PATH := "res://data/village.json"

static var _data := {}


static func _ensure_loaded() -> void:
	if not _data.is_empty():
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_PATH))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("VillageData: couldn't read %s" % DATA_PATH)
		_data = {"species": [], "buildings": [], "audit": {"questions": []}}
		return
	_data = parsed


## Species in the order they arrive.
static func all_species() -> Array:
	_ensure_loaded()
	return _data["species"]


static func species(id: String) -> Dictionary:
	for s: Dictionary in all_species():
		if s["id"] == id:
			return s
	return {}


static func all_buildings() -> Array:
	_ensure_loaded()
	return _data["buildings"]


static func building(id: String) -> Dictionary:
	for b: Dictionary in all_buildings():
		if b["id"] == id:
			return b
	return {}


## Buildings that go on an empty village plot.
static func plot_buildings() -> Array:
	return all_buildings().filter(func(b: Dictionary) -> bool: return b.get("on", "") == "plot")


static func audit_questions() -> Array:
	_ensure_loaded()
	return _data["audit"]["questions"]


## How much a member of `species_id` likes an item: x1.3 for each liked
## category or tag (at most once), x0.75 for a disliked one.
static func liking(species_id: String, item_id: String) -> float:
	var s := species(species_id)
	var item := ItemDatabase.get_item(item_id)
	if s.is_empty() or item == null:
		return 1.0
	var traits := PackedStringArray([item.category]) + item.tags
	var m := 1.0
	for t in traits:
		if t in s["likes"]:
			m = 1.3
			break
	for t in traits:
		if t in s["dislikes"]:
			m *= 0.75
			break
	return m
