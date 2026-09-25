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
		"upgrade_shop":
			result = _upgrade_shop(state)
		"build":
			result = _build(state, cmd["kind"], cmd["plot"])
		"set_hours":
			result = _set_hours(state, int(cmd["open"]), int(cmd["close"]))
		"read_mail":
			result = _read_mail(state, cmd["id"])
		"accept_resident":
			result = _answer_request(state, cmd["id"], true)
		"decline_resident":
			result = _answer_request(state, cmd["id"], false)
		"order":
			result = _order(state, cmd["item"], int(cmd.get("count", 1)))
		"open_parcels":
			result = _open_parcels(state)
		"donate":
			result = _donate(state, int(cmd["slot"]))
		"talk_villager":
			result = _talk_villager(state, cmd["id"])
		"audit_answer":
			state.audit["suspicion"] = clampi(state.audit["suspicion"] + int(cmd["points"]), 0, 100)
			result = {"ok": true, "message": ""}
		"finish_audit":
			result = _finish_audit(state)
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
	state.seen[item] = true
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
	var previous := state.day
	state.day = day
	VillageRules.new_day(state, previous, day)
	state.sales_today.clear()
	# Forget yesterday's harvests so saves don't grow forever.
	for prop: String in state.harvests.keys():
		if int(state.harvests[prop]["day"]) != day:
			state.harvests.erase(prop)
	return {"ok": true, "message": ""}


# --- Sanctuary ------------------------------------------------------------------

## Whether you have everything `costs` asks for ({"stardust": n, item: n}),
## counting your bag and home storage.
static func can_afford(state: GameState, costs: Dictionary) -> bool:
	for key: String in costs:
		if key == "stardust":
			if state.stardust < int(costs[key]):
				return false
		elif state.inventory.count_of(key) + state.storage.count_of(key) < int(costs[key]):
			return false
	return true


## Takes `costs`, from the bag first, then storage.
static func _spend(state: GameState, costs: Dictionary) -> void:
	for key: String in costs:
		var amount := int(costs[key])
		if key == "stardust":
			state.stardust -= amount
			continue
		var from_bag := mini(amount, state.inventory.count_of(key))
		state.inventory.remove_item(key, from_bag)
		state.storage.remove_item(key, amount - from_bag)


static func costs_text(costs: Dictionary) -> String:
	var parts := PackedStringArray()
	for key: String in costs:
		if key == "stardust":
			parts.append("%d Stardust" % int(costs[key]))
		else:
			parts.append("%d %s" % [int(costs[key]), ItemDatabase.get_item(key).name])
	return ", ".join(parts)


static func _upgrade_shop(state: GameState) -> Dictionary:
	if state.shop_tier >= 2:
		return _fail("You already have the general shop.")
	if state.debt >= GameState.STARTING_DEBT:
		return _fail("Vessa wants a first payment on your debt before she'll help you expand.")
	var costs: Dictionary = VillageData.building("general_shop")["costs"]
	if not can_afford(state, costs):
		return _fail("The general shop needs %s." % costs_text(costs))
	_spend(state, costs)
	state.set_shop_tier(2)
	return {"ok": true, "message": "Your general shop is open! 12 shelves to fill."}


static func _build(state: GameState, kind: String, plot: String) -> Dictionary:
	var def := VillageData.building(kind)
	if def.is_empty() or def.get("on", "") != "plot":
		return _fail("You can't build that here.")
	for id: String in state.buildings:
		if state.buildings[id]["plot"] == plot:
			return _fail("Something's already built there.")
	if kind != "burrow_house" and state.has_building(kind):
		return _fail("You already have a %s." % def["name"].to_lower())
	if not can_afford(state, def["costs"]):
		return _fail("%s needs %s." % [def["name"], costs_text(def["costs"])])
	_spend(state, def["costs"])
	var id := state.new_id(kind)
	state.buildings[id] = {"kind": kind, "plot": plot}
	return {"ok": true, "message": "Built %s!" % def["name"].to_lower().trim_prefix("the "), "id": id}


static func _set_hours(state: GameState, open: int, close: int) -> Dictionary:
	if state.shop_tier < 2:
		return _fail("The stall keeps market hours.")
	open = clampi(open, 0, 23)
	close = clampi(close, 1, 24)
	if close - open < 4:
		return _fail("Stay open at least 4 hours.")
	state.open_hours = Vector2i(open, close)
	return {"ok": true, "message": ""}


static func _read_mail(state: GameState, id: String) -> Dictionary:
	var letter := state.letter(id)
	if letter.is_empty():
		return _fail("No such letter")
	letter["read"] = true
	return {"ok": true, "message": ""}


static func _answer_request(state: GameState, id: String, yes: bool) -> Dictionary:
	var letter := state.letter(id)
	if letter.is_empty() or letter["kind"] != "move_in" or letter["data"].get("status", "") != "pending":
		return _fail("That request has been answered.")
	if yes:
		return VillageRules.accept(state, letter)
	letter["data"]["status"] = "declined"
	letter["read"] = true
	return {"ok": true, "message": "You wrote back kindly. Maybe another time."}


static func _order(state: GameState, item: String, count: int) -> Dictionary:
	if not state.has_building("landing_pad"):
		return _fail("Drones need a landing pad to deliver to.")
	if not item in VillageRules.catalog(state):
		return _fail("That isn't in the catalogue.")
	var cost := VillageRules.catalog_price(item) * count
	if state.stardust < cost:
		return _fail("That costs %d Stardust." % cost)
	state.stardust -= cost
	state.orders.append({"item": item, "count": count, "day": state.day})
	return {"ok": true, "message": "Ordered %s. It'll land tomorrow morning." % ItemDatabase.get_item(item).name}


static func _open_parcels(state: GameState) -> Dictionary:
	if state.parcels.is_empty():
		return _fail("No parcels waiting.")
	var got := PackedStringArray()
	for parcel in state.parcels.duplicate():
		var room := state.inventory.room_for(parcel["item"])
		var count := mini(room, int(parcel["count"]))
		if count <= 0:
			continue
		state.inventory.add(parcel["item"], count)
		got.append(ItemDatabase.get_item(parcel["item"]).name)
		parcel["count"] -= count
		if parcel["count"] <= 0:
			state.parcels.erase(parcel)
	if got.is_empty():
		return _fail("Your bag is full.")
	return {"ok": true, "message": "Unpacked %s%s" % [", ".join(got), "" if state.parcels.is_empty() else ". Some didn't fit."]}


static func _donate(state: GameState, slot: int) -> Dictionary:
	if not state.has_building("archive"):
		return _fail("There's no Archive yet.")
	if state.inventory.is_empty_slot(slot):
		return _fail("Nothing there")
	var item := ItemDatabase.get_item(state.inventory.item_at(slot))
	if not item.category in VillageRules.ARCHIVE_CATEGORIES:
		return _fail("The Archive doesn't collect %s." % ItemDatabase.category_name(item.category).to_lower())
	if state.archive.has(item.id):
		return _fail("The Archive already has a %s." % item.name)
	state.inventory.take(slot, 1)
	state.archive[item.id] = state.day
	state.reputation = mini(100, state.reputation + 1)
	return {"ok": true, "message": "Donated %s to the Archive. Thank you!" % item.name}


## The first chat each day makes friends a little; every few days they bring
## you something they like.
static func _talk_villager(state: GameState, id: String) -> Dictionary:
	var v := state.villager(id)
	if v.is_empty():
		return _fail("They've gone.")
	var species := VillageData.species(v["species"])
	var lines: Array = species["lines"]
	var line: String = lines[(state.day + v["friendship"]) % lines.size()]
	var result := {"ok": true, "message": "", "line": line}
	if int(v["talked"]) == state.day:
		return result
	v["talked"] = state.day
	v["friendship"] = int(v["friendship"]) + 1
	if int(v["friendship"]) % VillageRules.GIFT_EVERY == 0:
		var gift := _gift_for(state, v)
		if gift != "" and state.inventory.room_for(gift) > 0:
			state.inventory.add(gift, 1)
			state.seen[gift] = true
			result["gift"] = gift
			result["message"] = "%s gave you a %s!" % [v["name"], ItemDatabase.get_item(gift).name]
	return result


## Something common a villager likes, chosen by how long you've been friends.
static func _gift_for(state: GameState, v: Dictionary) -> String:
	var options: Array[String] = []
	for item in ItemDatabase.all():
		if item.rarity <= 2 and item.category != "fossil" and VillageData.liking(v["species"], item.id) > 1.0:
			options.append(item.id)
	if options.is_empty():
		return ""
	return options[hash([state.world_seed, v["id"], v["friendship"]]) % options.size()]


static func _finish_audit(state: GameState) -> Dictionary:
	if not VillageRules.auditor_here(state):
		return _fail("There's no inspection today.")
	var suspicion: int = state.audit["suspicion"]
	state.audit["done"] = state.day
	var soon := suspicion >= VillageRules.WATCHLIST
	VillageRules.schedule_audit(state, state.day, soon)
	if suspicion < 30:
		state.reputation = mini(100, state.reputation + 2)
	# Suspicion fades a little after each inspection that goes by.
	state.audit["suspicion"] = maxi(0, suspicion - 10)
	return {"ok": true, "message": "", "verdict": VillageRules.audit_verdict(suspicion)}
