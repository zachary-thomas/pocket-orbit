class_name GameState
extends RefCounted
## Everything that changes as you play, as plain data. The planet itself is
## never saved: it's regenerated from `world_seed`, and only what the player
## changed on it is stored (placed items, what's been harvested today).
## That keeps saves tiny, and the same format can later be sent to a friend's
## game for visits.
##
## Change it only through Commands.execute(), which emits `changed`.

signal changed(what: String)

const VERSION := 2
const STARTING_STARDUST := 300
## What you owe Vessa for the forged papers, the stall and the trip.
const STARTING_DEBT := 8000
## Shelves at the market stall (tier 1) and the general shop (tier 2).
const SHELF_COUNT := 4
const SHOP_SHELF_COUNT := 12
## Most of one item a single shelf holds.
const SHELF_STACK := 5

var world_seed := 1
var next_id := 1
var stardust := STARTING_STARDUST
var debt := STARTING_DEBT
## 0..100. Fair prices raise it; it brings more customers.
var reputation := 10
var inventory := Inventory.new(20)
var storage := Inventory.new(40)
## Each shelf: {} or {"item", "count", "price"} where price is the slider
## position, 0 (bargain) .. 1 (premium).
var shelves: Array[Dictionary] = []
## Placed item id -> {"item", "slot"}; slot is a TileGraph placement slot.
var placed := {}
## Prop id -> {"day", "count"}: how many times it's been harvested today.
var harvests := {}
## Today's sales: {"item", "price"}.
var sales_today: Array[Dictionary] = []
var day := 0
var stats := {"fish": 0, "bugs": 0, "gathered": 0, "sold": 0, "earned": 0}
## Where the player was when saved.
var player_tile := -1
## One-off story and tutorial moments that have happened, e.g. "met_vessa".
var flags := {}

# --- Sanctuary (Phase 2) ---
## 1 market stall, 2 general shop.
var shop_tier := 1
## Opening hours of the general shop, local time at home [open, close).
var open_hours := Vector2i(8, 20)
## Building id -> {"kind", "plot"}. Kinds from data/village.json.
var buildings := {}
## Refugees who live here: {"id", "species", "name", "home", "color",
## "arrived", "friendship", "talked"} (talked = day last spoken to).
var villagers: Array[Dictionary] = []
## Letters, newest last: {"id", "kind", "from", "subject", "body", "day",
## "read", "data"}. Kinds: "note", "move_in", "audit", "parcel".
var mail: Array[Dictionary] = []
## Mail-order items on their way: {"item", "count", "day"} (day ordered).
var orders: Array[Dictionary] = []
## Delivered and waiting at the landing pad: {"item", "count"}.
var parcels: Array[Dictionary] = []
## Every item you've ever had, for the mail-order catalogue.
var seen := {}
## Item id -> day it was donated to the Archive.
var archive := {}
## The Confederation auditor: next visit day, how suspicious they are
## (0..100), and the day of the last finished audit.
var audit := {"next": -1, "suspicion": 0, "done": -1}
## Cottage ids on this planet that can house a villager. Comes from the
## planet (set by Game.start), so it isn't saved.
var cottages: Array[String] = []


func _init() -> void:
	shelves.resize(SHELF_COUNT)
	for i in SHELF_COUNT:
		shelves[i] = {}


## Shelves the current shop has.
static func shelf_count_for(tier: int) -> int:
	return SHOP_SHELF_COUNT if tier >= 2 else SHELF_COUNT


func set_shop_tier(tier: int) -> void:
	shop_tier = tier
	var old := shelves.size()
	shelves.resize(shelf_count_for(tier))
	for i in range(old, shelves.size()):
		shelves[i] = {}


func has_building(kind: String) -> bool:
	for id: String in buildings:
		if buildings[id]["kind"] == kind:
			return true
	return false


func villager(id: String) -> Dictionary:
	for v in villagers:
		if v["id"] == id:
			return v
	return {}


func unread_mail() -> int:
	var count := 0
	for letter in mail:
		if not letter["read"]:
			count += 1
	return count


func letter(id: String) -> Dictionary:
	for l in mail:
		if l["id"] == id:
			return l
	return {}


## A new unique id for something placed in the world, e.g. "obj-12".
func new_id(prefix: String) -> String:
	var id := "%s-%d" % [prefix, next_id]
	next_id += 1
	return id


func slot_taken(slot: int) -> bool:
	for id: String in placed:
		if placed[id]["slot"] == slot:
			return true
	return false


func to_dict() -> Dictionary:
	return {
		"version": VERSION,
		"world_seed": world_seed,
		"next_id": next_id,
		"stardust": stardust,
		"debt": debt,
		"reputation": reputation,
		"inventory": inventory.to_array(),
		"storage": storage.to_array(),
		"shelves": shelves.duplicate(true),
		"placed": placed.duplicate(true),
		"harvests": harvests.duplicate(true),
		"sales_today": sales_today.duplicate(true),
		"day": day,
		"stats": stats.duplicate(),
		"player_tile": player_tile,
		"flags": flags.duplicate(),
		"shop_tier": shop_tier,
		"open_hours": [open_hours.x, open_hours.y],
		"buildings": buildings.duplicate(true),
		"villagers": villagers.duplicate(true),
		"mail": mail.duplicate(true),
		"orders": orders.duplicate(true),
		"parcels": parcels.duplicate(true),
		"seen": seen.duplicate(),
		"archive": archive.duplicate(),
		"audit": audit.duplicate(),
	}


static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.world_seed = int(d.get("world_seed", 1))
	s.next_id = int(d.get("next_id", 1))
	s.stardust = int(d.get("stardust", STARTING_STARDUST))
	s.debt = int(d.get("debt", STARTING_DEBT))
	s.reputation = int(d.get("reputation", 10))
	s.set_shop_tier(int(d.get("shop_tier", 1)))
	s.inventory.load_array(d.get("inventory", []))
	s.storage.load_array(d.get("storage", []))
	var saved_shelves: Array = d.get("shelves", [])
	for i in mini(saved_shelves.size(), s.shelves.size()):
		var shelf: Dictionary = saved_shelves[i]
		if shelf.has("item") and ItemDatabase.has(shelf["item"]):
			s.shelves[i] = {"item": shelf["item"], "count": int(shelf["count"]), "price": float(shelf.get("price", 0.5))}
	var saved_placed: Dictionary = d.get("placed", {})
	for id: String in saved_placed:
		var p: Dictionary = saved_placed[id]
		if ItemDatabase.has(p.get("item", "")):
			s.placed[id] = {"item": p["item"], "slot": int(p["slot"])}
	var saved_harvests: Dictionary = d.get("harvests", {})
	for id: String in saved_harvests:
		s.harvests[id] = {"day": int(saved_harvests[id]["day"]), "count": int(saved_harvests[id]["count"])}
	for sale: Dictionary in d.get("sales_today", []):
		s.sales_today.append({"item": sale["item"], "price": int(sale["price"])})
	s.day = int(d.get("day", 0))
	var saved_stats: Dictionary = d.get("stats", {})
	for key: String in s.stats:
		s.stats[key] = int(saved_stats.get(key, 0))
	s.player_tile = int(d.get("player_tile", -1))
	var saved_flags: Dictionary = d.get("flags", {})
	for key: String in saved_flags:
		s.flags[key] = saved_flags[key]
	var hours: Array = d.get("open_hours", [8, 20])
	s.open_hours = Vector2i(int(hours[0]), int(hours[1]))
	var saved_buildings: Dictionary = d.get("buildings", {})
	for id: String in saved_buildings:
		s.buildings[id] = {"kind": str(saved_buildings[id]["kind"]), "plot": str(saved_buildings[id].get("plot", ""))}
	for v: Dictionary in d.get("villagers", []):
		s.villagers.append({
			"id": str(v["id"]), "species": str(v["species"]), "name": str(v["name"]), "home": str(v["home"]),
			"color": str(v.get("color", "ffffff")), "arrived": int(v.get("arrived", 0)),
			"friendship": int(v.get("friendship", 0)), "talked": int(v.get("talked", -1)),
		})
	for l: Dictionary in d.get("mail", []):
		s.mail.append({
			"id": str(l["id"]), "kind": str(l.get("kind", "note")), "from": str(l.get("from", "")),
			"subject": str(l.get("subject", "")), "body": str(l.get("body", "")), "day": int(l.get("day", 0)),
			"read": bool(l.get("read", false)), "data": (l.get("data", {}) as Dictionary).duplicate(true),
		})
	for o: Dictionary in d.get("orders", []):
		if ItemDatabase.has(o.get("item", "")):
			s.orders.append({"item": o["item"], "count": int(o["count"]), "day": int(o["day"])})
	for p: Dictionary in d.get("parcels", []):
		if ItemDatabase.has(p.get("item", "")):
			s.parcels.append({"item": p["item"], "count": int(p["count"])})
	for item: String in d.get("seen", {}):
		s.seen[item] = true
	var saved_archive: Dictionary = d.get("archive", {})
	for item: String in saved_archive:
		s.archive[item] = int(saved_archive[item])
	var saved_audit: Dictionary = d.get("audit", {})
	for key: String in s.audit:
		s.audit[key] = int(saved_audit.get(key, s.audit[key]))
	return s
