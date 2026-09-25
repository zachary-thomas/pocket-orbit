class_name Commands
extends RefCounted
## The one way game state changes. Every player action is a small dictionary
## such as {"type": "stock_shelf", "slot": 3, "shelf": 0}; execute() checks
## it, applies it and emits GameState.changed. Keeping actions as plain
## messages means the same ones can later be sent over the network for
## multiplayer visits, logged, or replayed in tests.
##
## Returns {"ok": bool, "message": String, ...extra}.


static func execute(state: GameState, cmd: Dictionary) -> Dictionary:
	var result: Dictionary
	match cmd.get("type", ""):
		"collect":
			result = _collect(state, cmd["item"], int(cmd.get("count", 1)))
		"discard":
			result = _discard(state, int(cmd["slot"]))
		"stock_shelf":
			result = _stock_shelf(state, int(cmd["slot"]), int(cmd["shelf"]))
		"unstock_shelf":
			result = _unstock_shelf(state, int(cmd["shelf"]))
		"set_price":
			result = _set_price(state, int(cmd["shelf"]), float(cmd["level"]))
		"sell":
			result = _sell(state, int(cmd["shelf"]), int(cmd["worth"]))
		"customer_left":
			result = _customer_left(state, int(cmd["asking"]), int(cmd["worth"]))
		"pay_debt":
			result = _pay_debt(state, int(cmd["amount"]))
		"place":
			result = _place(state, int(cmd["slot"]), int(cmd["world_slot"]))
		"pick_up":
			result = _pick_up(state, cmd["id"])
		"store":
			result = _move(state.inventory, state.storage, int(cmd["slot"]), "Stored")
		"retrieve":
			result = _move(state.storage, state.inventory, int(cmd["slot"]), "Took")
		"harvest":
			result = _harvest(state, cmd["prop"], int(cmd["max"]))
		"new_day":
			result = _new_day(state, int(cmd["day"]))
		"set_flag":
			state.flags[cmd["flag"]] = cmd.get("value", true)
			result = {"ok": true, "message": ""}
		"set_player_tile":
			state.player_tile = int(cmd["tile"])
			return {"ok": true, "message": ""}
		_:
			return {"ok": false, "message": "Unknown command %s" % cmd.get("type", "")}
	if result.get("ok", false):
		state.changed.emit(cmd["type"])
	return result


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "message": message}


static func _collect(state: GameState, item: String, count: int) -> Dictionary:
	if not ItemDatabase.has(item):
		return _fail("Unknown item")
	if state.inventory.room_for(item) < count:
		return _fail("Your bag is full.")
	state.inventory.add(item, count)
	match ItemDatabase.get_item(item).category:
		"fish":
			state.stats["fish"] += count
		"bug":
			state.stats["bugs"] += count
		_:
			state.stats["gathered"] += count
	return {"ok": true, "message": "Got %s%s" % [ItemDatabase.get_item(item).name, " x%d" % count if count > 1 else ""]}


static func _discard(state: GameState, slot: int) -> Dictionary:
	if state.inventory.is_empty_slot(slot):
		return _fail("Nothing there")
	state.inventory.take(slot, state.inventory.count_at(slot))
	return {"ok": true, "message": ""}


static func _stock_shelf(state: GameState, slot: int, shelf: int) -> Dictionary:
	if shelf < 0 or shelf >= state.shelves.size():
		return _fail("No such shelf")
	if state.inventory.is_empty_slot(slot):
		return _fail("Nothing to stock")
	var item := state.inventory.item_at(slot)
	var current := state.shelves[shelf]
	if not current.is_empty() and current["item"] != item:
		return _fail("That shelf holds something else. Clear it first.")
	var have := int(current.get("count", 0))
	var room := GameState.SHELF_STACK - have
	if room <= 0:
		return _fail("That shelf is full.")
	var taken := state.inventory.take(slot, room)
	state.shelves[shelf] = {"item": item, "count": have + int(taken["count"]), "price": float(current.get("price", 0.5))}
	return {"ok": true, "message": "Stocked %s" % ItemDatabase.get_item(item).name}


static func _unstock_shelf(state: GameState, shelf: int) -> Dictionary:
	var current := state.shelves[shelf]
	if current.is_empty():
		return _fail("That shelf is empty.")
	var left := state.inventory.add(current["item"], int(current["count"]))
	if left == 0:
		state.shelves[shelf] = {}
	else:
		current["count"] = left
		return {"ok": true, "message": "Your bag is full; some stayed on the shelf."}
	return {"ok": true, "message": ""}


static func _set_price(state: GameState, shelf: int, level: float) -> Dictionary:
	if state.shelves[shelf].is_empty():
		return _fail("That shelf is empty.")
	state.shelves[shelf]["price"] = clampf(level, 0.0, 1.0)
	return {"ok": true, "message": ""}


## A customer buys one item from a shelf at its current price. `worth` is
## what they think it's worth today (for reputation).
static func _sell(state: GameState, shelf: int, worth: int) -> Dictionary:
	var current := state.shelves[shelf]
	if current.is_empty():
		return _fail("Sold out")
	var item: String = current["item"]
	var asking := Economy.price(item, float(current["price"]))
	state.stardust += asking
	state.reputation = clampi(state.reputation + Economy.reputation_change(asking, worth, true), 0, 100)
	current["count"] -= 1
	if current["count"] <= 0:
		state.shelves[shelf] = {}
	state.sales_today.append({"item": item, "price": asking})
	state.stats["sold"] += 1
	state.stats["earned"] += asking
	return {"ok": true, "message": "Sold %s for %d Stardust" % [ItemDatabase.get_item(item).name, asking], "price": asking, "item": item}


static func _customer_left(state: GameState, asking: int, worth: int) -> Dictionary:
	state.reputation = clampi(state.reputation + Economy.reputation_change(asking, worth, false), 0, 100)
	return {"ok": true, "message": ""}


static func _pay_debt(state: GameState, amount: int) -> Dictionary:
	var paid := mini(amount, mini(state.stardust, state.debt))
	if paid <= 0:
		return _fail("You don't have any Stardust to pay with." if state.debt > 0 else "You're all paid up.")
	state.stardust -= paid
	state.debt -= paid
	return {"ok": true, "message": "Paid Vessa %d Stardust" % paid, "paid": paid}


static func _place(state: GameState, slot: int, world_slot: int) -> Dictionary:
	if state.inventory.is_empty_slot(slot):
		return _fail("Nothing to place")
	if state.slot_taken(world_slot):
		return _fail("Something's already there.")
	var taken := state.inventory.take(slot, 1)
	var id := state.new_id("obj")
	state.placed[id] = {"item": taken["item"], "slot": world_slot}
	return {"ok": true, "message": "", "id": id}


static func _pick_up(state: GameState, id: String) -> Dictionary:
	if not state.placed.has(id):
		return _fail("It's gone.")
	var item: String = state.placed[id]["item"]
	if state.inventory.room_for(item) < 1:
		return _fail("Your bag is full.")
	state.inventory.add(item, 1)
	state.placed.erase(id)
	return {"ok": true, "message": "Picked up %s" % ItemDatabase.get_item(item).name}


static func _move(from: Inventory, to: Inventory, slot: int, verb: String) -> Dictionary:
	if from.is_empty_slot(slot):
		return _fail("Nothing there")
	var item := from.item_at(slot)
	var count := mini(from.count_at(slot), to.room_for(item))
	if count <= 0:
		return _fail("No room.")
	from.take(slot, count)
	to.add(item, count)
	return {"ok": true, "message": "%s %s" % [verb, ItemDatabase.get_item(item).name]}


## Records one harvest of a prop today; fails once it's been harvested `max`
## times.
static func _harvest(state: GameState, prop: String, most: int) -> Dictionary:
	var record: Dictionary = state.harvests.get(prop, {})
	var count := int(record.get("count", 0)) if int(record.get("day", -1)) == state.day else 0
	if count >= most:
		return _fail("Nothing more here today.")
	state.harvests[prop] = {"day": state.day, "count": count + 1}
	return {"ok": true, "message": ""}


static func _new_day(state: GameState, day: int) -> Dictionary:
	if day == state.day:
		return _fail("Same day")
	state.day = day
	state.sales_today.clear()
	# Forget yesterday's harvests so saves don't grow forever.
	for prop: String in state.harvests.keys():
		if int(state.harvests[prop]["day"]) != day:
			state.harvests.erase(prop)
	return {"ok": true, "message": ""}
