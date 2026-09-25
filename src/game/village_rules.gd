class_name VillageRules
extends RefCounted
## The sanctuary's rules: who asks to move in and when, homes, mail-order
## deliveries and the Confederation auditor's schedule. Pure functions on a
## GameState, run by Commands (mostly at the start of each day), so they can
## be tested without the game running and replayed the same way everywhere.

## Mail-order costs a bit more than the item's base value.
const CATALOG_MARKUP := 1.25
## Days from the sanctuary starting (first villager or the general shop)
## until the first audit, then between audits.
const FIRST_AUDIT_AFTER := 3
const AUDIT_GAP_MIN := 5
const AUDIT_GAP_MAX := 8
## Above this suspicion the auditor comes back sooner.
const WATCHLIST := 60
## A declined refugee asks again after this many days.
const ASK_AGAIN_AFTER := 3
## Categories the Archive collects.
const ARCHIVE_CATEGORIES := ["fish", "bug", "mineral", "fossil", "shore"]
## Talking to a villager this many days gets you a gift.
const GIFT_EVERY := 4


static func _rng(state: GameState, salt: String) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([state.world_seed, salt])
	return rng


# --- Homes and move-ins --------------------------------------------------------

## Homes nobody lives in yet: the village's empty cottages, then burrow
## houses you've built.
static func free_homes(state: GameState) -> Array[String]:
	var homes: Array[String] = []
	homes.append_array(state.cottages)
	for id: String in state.buildings:
		if state.buildings[id]["kind"] == "burrow_house":
			homes.append(id)
	for v in state.villagers:
		homes.erase(v["home"])
	return homes


static func is_resident(state: GameState, species_id: String) -> bool:
	for v in state.villagers:
		if v["species"] == species_id:
			return true
	return false


static func pending_request(state: GameState) -> Dictionary:
	for letter in state.mail:
		if letter["kind"] == "move_in" and letter["data"].get("status", "") == "pending":
			return letter
	return {}


static func requirements_met(state: GameState, species: Dictionary) -> bool:
	var req: Dictionary = species["requires"]
	if state.reputation < int(req.get("reputation", 0)):
		return false
	for kind: String in req.get("buildings", []):
		if not state.has_building(kind):
			return false
	return true


## What's still missing before a species will come, in words (for hints).
static func missing(state: GameState, species: Dictionary) -> PackedStringArray:
	var result := PackedStringArray()
	var req: Dictionary = species["requires"]
	if state.reputation < int(req.get("reputation", 0)):
		result.append("reputation %d" % int(req["reputation"]))
	for kind: String in req.get("buildings", []):
		if not state.has_building(kind):
			result.append(VillageData.building(kind).get("name", kind))
	return result


## The next refugee ready to ask: the first species (in arrival order) that
## doesn't live here yet, hasn't been turned down in the last few days and
## whose needs are met. Empty if none, or if there's no free home.
static func next_species(state: GameState, day: int) -> Dictionary:
	if free_homes(state).is_empty():
		return {}
	for species: Dictionary in VillageData.all_species():
		if is_resident(state, species["id"]):
			continue
		if _declined_recently(state, species["id"], day):
			continue
		if requirements_met(state, species):
			return species
	return {}


static func _declined_recently(state: GameState, species_id: String, day: int) -> bool:
	for letter in state.mail:
		if letter["kind"] == "move_in" and letter["data"].get("species", "") == species_id \
				and letter["data"].get("status", "") == "declined" and day - int(letter["day"]) < ASK_AGAIN_AFTER:
			return true
	return false


## Sends the move-in letter for `species`.
static func request_move_in(state: GameState, species: Dictionary, day: int) -> void:
	var rng := _rng(state, "resident:" + species["id"])
	var name: String = species["names"][rng.randi() % species["names"].size()]
	var color: String = species["colors"][rng.randi() % species["colors"].size()]
	var body: String = species["letter"].replace("{name}", name)
	send(state, "move_in", name, "May I move in?", body, day,
		{"species": species["id"], "name": name, "color": color, "status": "pending"})


## Welcomes the refugee from a move-in letter into the first free home.
static func accept(state: GameState, letter: Dictionary) -> Dictionary:
	var homes := free_homes(state)
	if homes.is_empty():
		return {"ok": false, "message": "There's no free home. Build a burrow house first."}
	var data: Dictionary = letter["data"]
	var villager := {
		"id": state.new_id("villager"), "species": data["species"], "name": data["name"], "home": homes[0],
		"color": data["color"], "arrived": state.day, "friendship": 0, "talked": -1,
	}
	state.villagers.append(villager)
	data["status"] = "accepted"
	letter["read"] = true
	var species := VillageData.species(data["species"])
	return {"ok": true, "message": "%s the %s is moving in!" % [data["name"], species.get("name", "")], "villager": villager["id"]}


# --- Mail ----------------------------------------------------------------------

static func send(state: GameState, kind: String, from: String, subject: String, body: String, day: int, data: Dictionary = {}) -> Dictionary:
	var letter := {
		"id": state.new_id("mail"), "kind": kind, "from": from, "subject": subject, "body": body,
		"day": day, "read": false, "data": data,
	}
	state.mail.append(letter)
	# Keep the last 40 letters, but never an unanswered request.
	while state.mail.size() > 40:
		var dropped := false
		for i in state.mail.size():
			var old: Dictionary = state.mail[i]
			if old["data"].get("status", "") != "pending":
				state.mail.remove_at(i)
				dropped = true
				break
		if not dropped:
			break
	return letter


static func catalog_price(item_id: String) -> int:
	var item := ItemDatabase.get_item(item_id)
	return 0 if item == null else ceili(item.value * CATALOG_MARKUP)


## Items in the mail-order catalogue: everything you've had, except fossils
## (every one is unique) and anything a drone can't carry alive.
static func catalog(state: GameState) -> Array[String]:
	var result: Array[String] = []
	for item in ItemDatabase.all():
		if state.seen.has(item.id) and item.category in ["material", "fruit", "mineral", "shore"]:
			result.append(item.id)
	return result


# --- The auditor -----------------------------------------------------------------

static func sanctuary_started(state: GameState) -> bool:
	return not state.villagers.is_empty() or state.shop_tier >= 2


static func schedule_audit(state: GameState, from_day: int, soon: bool) -> void:
	var rng := _rng(state, "audit:%d" % from_day)
	var gap := 3 if soon else rng.randi_range(AUDIT_GAP_MIN, AUDIT_GAP_MAX)
	state.audit["next"] = from_day + gap


## Is the auditor in the village today, waiting to be spoken to?
static func auditor_here(state: GameState) -> bool:
	return state.audit["next"] == state.day and state.audit["done"] != state.day


## Three of the auditor's questions for this visit.
static func audit_questions(state: GameState) -> Array:
	var all: Array = VillageData.audit_questions().duplicate()
	var rng := _rng(state, "questions:%d" % state.audit["next"])
	var picked := []
	while picked.size() < 3 and not all.is_empty():
		picked.append(all.pop_at(rng.randi() % all.size()))
	return picked


static func audit_verdict(suspicion: int) -> String:
	if suspicion < 30:
		return "Everything appears to be in order. Carry on."
	if suspicion < WATCHLIST:
		return "Hm. I'll be keeping an eye on this planet."
	return "I'm filing a report. Expect me back very soon."


# --- Daily --------------------------------------------------------------------------

## Everything that happens overnight: parcels land, a refugee may write, and
## the auditor's visit is scheduled and announced. `previous_day` is the last
## day the game was played.
static func new_day(state: GameState, previous_day: int, day: int) -> void:
	_deliver(state, day)
	if pending_request(state).is_empty():
		var species := next_species(state, day)
		if not species.is_empty():
			request_move_in(state, species, day)
	_audit_schedule(state, previous_day, day)


static func _deliver(state: GameState, day: int) -> void:
	var arrived := 0
	for order in state.orders.duplicate():
		if int(order["day"]) < day:
			state.parcels.append({"item": order["item"], "count": order["count"]})
			state.orders.erase(order)
			arrived += 1
	if arrived > 0:
		send(state, "parcel", "Drone Mail", "Your parcel has landed",
			"Good morning! Your order is waiting on the landing pad. Tap the parcel to open it.\n\n- Drone Mail, deliveries across the system", day)


static func _audit_schedule(state: GameState, previous_day: int, day: int) -> void:
	if not sanctuary_started(state):
		return
	var next: int = state.audit["next"]
	if next == -1:
		state.audit["next"] = day + FIRST_AUDIT_AFTER
		next = state.audit["next"]
	elif next < day and state.audit["done"] < next:
		if previous_day >= next:
			# The auditor came while you were about, and nobody spoke to them.
			state.audit["suspicion"] = mini(100, state.audit["suspicion"] + 10)
			send(state, "note", "Office of Compliance", "Missed inspection",
				"Our inspector visited your settlement and was not received. This has been noted.\n\nA follow-up inspection will be scheduled shortly.", day)
			schedule_audit(state, day, true)
		else:
			# You were away; they'll come another day.
			schedule_audit(state, day, false)
		next = state.audit["next"]
	if next == day + 1:
		send(state, "audit", "Office of Compliance", "Inspection tomorrow",
			"By order of the Galactic Confederation, a routine inspection of your trading premises will take place tomorrow during opening hours.\n\nPlease have your papers in order.\n\n- Inspector Grell, Office of Compliance", day)
