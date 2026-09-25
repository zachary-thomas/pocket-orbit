class_name Inventory
extends RefCounted
## A fixed number of slots, each empty or holding a stack of one item. Stack
## sizes come from the item's category (a fish takes a whole slot; stones
## stack to 30).

var slots: Array[Dictionary] = []


func _init(size: int = 20) -> void:
	slots.resize(size)
	for i in size:
		slots[i] = {}


func size() -> int:
	return slots.size()


func is_empty_slot(slot: int) -> bool:
	return slots[slot].is_empty()


func item_at(slot: int) -> String:
	return slots[slot].get("item", "")


func count_at(slot: int) -> int:
	return slots[slot].get("count", 0)


func count_of(item: String) -> int:
	var total := 0
	for s in slots:
		if s.get("item", "") == item:
			total += int(s["count"])
	return total


func free_slots() -> int:
	var n := 0
	for s in slots:
		if s.is_empty():
			n += 1
	return n


## How many of `item` would fit.
func room_for(item: String) -> int:
	var stack := ItemDatabase.stack_size(item)
	var room := 0
	for s in slots:
		if s.is_empty():
			room += stack
		elif s["item"] == item:
			room += stack - int(s["count"])
	return room


## Adds as many as fit (topping up existing stacks first). Returns how many
## didn't fit.
func add(item: String, count: int = 1) -> int:
	var stack := ItemDatabase.stack_size(item)
	for s in slots:
		if count <= 0:
			break
		if not s.is_empty() and s["item"] == item and s["count"] < stack:
			var moved := mini(count, stack - int(s["count"]))
			s["count"] += moved
			count -= moved
	for i in slots.size():
		if count <= 0:
			break
		if slots[i].is_empty():
			var moved := mini(count, stack)
			slots[i] = {"item": item, "count": moved}
			count -= moved
	return count


## Takes up to `count` from one slot. Returns {"item", "count"} taken.
func take(slot: int, count: int = 1) -> Dictionary:
	if slots[slot].is_empty():
		return {}
	var taken := mini(count, int(slots[slot]["count"]))
	var item: String = slots[slot]["item"]
	slots[slot]["count"] -= taken
	if slots[slot]["count"] <= 0:
		slots[slot] = {}
	return {"item": item, "count": taken}


## Removes `count` of an item from anywhere. False (and no change) if there
## aren't that many.
func remove_item(item: String, count: int) -> bool:
	if count_of(item) < count:
		return false
	for i in range(slots.size() - 1, -1, -1):
		if count <= 0:
			break
		if slots[i].get("item", "") == item:
			count -= int(take(i, count)["count"])
	return true


func to_array() -> Array:
	return slots.duplicate(true)


func load_array(data: Array) -> void:
	for i in mini(data.size(), slots.size()):
		var s: Dictionary = data[i] if data[i] is Dictionary else {}
		if s.has("item") and ItemDatabase.has(s["item"]):
			slots[i] = {"item": s["item"], "count": int(s["count"])}
		else:
			slots[i] = {}
