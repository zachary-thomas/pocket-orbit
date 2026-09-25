class_name Economy
extends RefCounted
## Prices, daily demand and how customers decide. Pure functions of their
## inputs (seed, day, reputation...), so the same day always has the same
## demand and the rules can be tested without the game running.
##
## Each day every category gets a demand multiplier (0.7..1.5), one tag is in
## fashion (x1.35) and one is out (x0.8). The demand board shows three hints
## about that. What an item is worth today = base value x category demand x
## tag demand. Your price is the base value scaled by the shelf slider, from
## x0.6 (bargain) through x1 (the middle) to x1.8 (premium). Customers
## compare your price with today's worth.

const TAGS := ["cold", "shiny", "sweet", "glowing", "spiky", "tiny", "big"]
const PRICE_MIN := 0.6
const PRICE_MAX := 1.8
## Shop hours, local time at home.
const OPENS_AT := 8.0
const CLOSES_AT := 20.0


static func _rng(world_seed: int, day: int, salt: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, day, salt])
	return rng


static func category_demand(world_seed: int, day: int, category: String) -> float:
	var rng := _rng(world_seed, day, "demand:" + category)
	return snappedf(rng.randf_range(0.7, 1.5), 0.05)


static func hot_tag(world_seed: int, day: int) -> String:
	return TAGS[_rng(world_seed, day, "hot").randi() % TAGS.size()]


static func cold_tag(world_seed: int, day: int) -> String:
	var hot := hot_tag(world_seed, day)
	var rng := _rng(world_seed, day, "cold")
	var tag: String = TAGS[rng.randi() % TAGS.size()]
	while tag == hot:
		tag = TAGS[rng.randi() % TAGS.size()]
	return tag


static func tag_demand(world_seed: int, day: int, tags: PackedStringArray) -> float:
	var m := 1.0
	if hot_tag(world_seed, day) in tags:
		m *= 1.35
	if cold_tag(world_seed, day) in tags:
		m *= 0.8
	return m


## What an item is worth to customers today.
static func value_today(item_id: String, world_seed: int, day: int) -> int:
	var item := ItemDatabase.get_item(item_id)
	if item == null:
		return 0
	return maxi(1, roundi(item.value * category_demand(world_seed, day, item.category) * tag_demand(world_seed, day, item.tags)))


## Your asking price at a slider position (0 bargain .. 1 premium). The
## middle of the slider is the base value.
static func price(item_id: String, level: float) -> int:
	var item := ItemDatabase.get_item(item_id)
	if item == null:
		return 0
	level = clampf(level, 0.0, 1.0)
	var scale := lerpf(PRICE_MIN, 1.0, level * 2.0) if level < 0.5 else lerpf(1.0, PRICE_MAX, level * 2.0 - 1.0)
	return maxi(1, roundi(item.value * scale))


## How a customer sees a price compared with today's worth.
static func price_feel(asking: int, worth: int) -> String:
	var ratio := float(asking) / maxf(worth, 1.0)
	if ratio <= 0.85:
		return "bargain"
	if ratio <= 1.15:
		return "fair"
	if ratio <= 1.45:
		return "pricey"
	return "too much"


## Chance a browsing customer buys an item at `asking`. Cheap relative to its
## worth sells almost always; far above it almost never. Reputation helps.
static func purchase_chance(asking: int, worth: int, reputation: int) -> float:
	var ratio := float(asking) / maxf(worth, 1.0)
	return clampf(1.6 - 0.95 * ratio + reputation * 0.003, 0.03, 0.97)


## Reputation change when a customer buys at `asking` (fair or cheap prices
## earn goodwill) or walks away from it (only a steep price costs any).
static func reputation_change(asking: int, worth: int, bought: bool) -> int:
	var ratio := float(asking) / maxf(worth, 1.0)
	if bought:
		if ratio <= 0.9:
			return 2
		if ratio <= 1.15:
			return 1
		return 0
	return -1 if ratio >= 1.45 else 0


## Real seconds between customers turning up at the stall. Better reputation
## brings them more often; fewer come at night. (Real seconds rather than game
## hours, since game hours follow the real clock and a session is short.)
static func seconds_between_customers(reputation: int, night: bool) -> float:
	var seconds := lerpf(45.0, 14.0, clampf(reputation / 100.0, 0.0, 1.0))
	return seconds * (2.5 if night else 1.0)


## What one browsing customer does: looks over the stocked shelves, picks one
## (good deals catch the eye more often) and decides whether to buy it.
## Returns {} if every shelf is empty, else {"shelf", "asking", "worth", "buy"}.
static func customer_choice(rng: RandomNumberGenerator, state: GameState) -> Dictionary:
	var options: Array[Dictionary] = []
	var total := 0.0
	for i in state.shelves.size():
		var shelf: Dictionary = state.shelves[i]
		if shelf.is_empty():
			continue
		var worth := value_today(shelf["item"], state.world_seed, state.day)
		var asking := price(shelf["item"], float(shelf["price"]))
		var weight := 0.5 + purchase_chance(asking, worth, state.reputation)
		options.append({"shelf": i, "asking": asking, "worth": worth, "weight": weight})
		total += weight
	if options.is_empty():
		return {}
	var roll := rng.randf() * total
	var choice: Dictionary = options[-1]
	for option in options:
		roll -= option["weight"]
		if roll <= 0.0:
			choice = option
			break
	choice.erase("weight")
	choice["buy"] = rng.randf() < purchase_chance(choice["asking"], choice["worth"], state.reputation)
	return choice


static func is_open(local_hours: float) -> bool:
	return local_hours >= OPENS_AT and local_hours < CLOSES_AT


## The three demand-board hints for a day.
static func hints(world_seed: int, day: int) -> PackedStringArray:
	var best := ""
	var worst := ""
	for category in ItemDatabase.categories():
		var d := category_demand(world_seed, day, category)
		if best == "" or d > category_demand(world_seed, day, best):
			best = category
		if worst == "" or d < category_demand(world_seed, day, worst):
			worst = category
	return PackedStringArray([
		"Everyone's asking for %s today." % ItemDatabase.category_name(best).to_lower(),
		"Customers are craving %s things." % hot_tag(world_seed, day),
		"Nobody wants %s right now." % ItemDatabase.category_name(worst).to_lower(),
	])
