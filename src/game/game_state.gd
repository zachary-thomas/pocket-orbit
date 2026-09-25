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

const VERSION := 1
const STARTING_STARDUST := 300
## What you owe Vessa for the forged papers, the stall and the trip.
const STARTING_DEBT := 8000
const SHELF_COUNT := 4
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


func _init() -> void:
	shelves.resize(SHELF_COUNT)
	for i in SHELF_COUNT:
		shelves[i] = {}


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
	}


static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.world_seed = int(d.get("world_seed", 1))
	s.next_id = int(d.get("next_id", 1))
	s.stardust = int(d.get("stardust", STARTING_STARDUST))
	s.debt = int(d.get("debt", STARTING_DEBT))
	s.reputation = int(d.get("reputation", 10))
	s.inventory.load_array(d.get("inventory", []))
	s.storage.load_array(d.get("storage", []))
	var saved_shelves: Array = d.get("shelves", [])
	for i in mini(saved_shelves.size(), SHELF_COUNT):
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
	return s
