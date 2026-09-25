extends SceneTree
## Headless checks for the planet code. Run from the project folder:
##
##   godot --headless --import            (once, so Godot knows the classes)
##   godot --headless --script res://tests/run_tests.gd
##
## Exits with the number of failed checks (0 = all passed).

var _failures := 0


func _initialize() -> void:
	# Nodes only enter the tree once the main loop is running.
	_run_all.call_deferred()


func _run_all() -> void:
	_test_hex_sphere()
	_test_find_tile()
	_test_generator()
	_test_mesher()
	_test_walking()
	_test_items_and_inventory()
	_test_economy()
	_test_commands_and_save()
	_test_tile_graph()
	_test_props()
	_test_shop_rules()
	print("\n%s" % ("All checks passed." if _failures == 0 else "%d check(s) FAILED." % _failures))
	quit(_failures)


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures += 1


func _test_hex_sphere() -> void:
	print("HexSphere")
	var sphere := HexSphere.new(16)
	_check(sphere.tile_count() == 2562, "frequency 16 gives 2,562 tiles (got %d)" % sphere.tile_count())
	var pentagons := 0
	var bad_shape := 0
	var asymmetric := 0
	var unshared_edges := 0
	for t in sphere.tile_count():
		var count := sphere.corner_count(t)
		if count == 5:
			pentagons += 1
		elif count != 6:
			bad_shape += 1
		var s := sphere.corner_start[t]
		for k in count:
			var n := sphere.edge_neighbors[s + k]
			if not t in sphere.neighbors(n):
				asymmetric += 1
			# The two corners of this edge must also be corners of the neighbour.
			var a := sphere.corners[s + k]
			var b := sphere.corners[s + (k + 1) % count]
			var theirs := sphere.tile_corners(n)
			if not (_has_point(theirs, a) and _has_point(theirs, b)):
				unshared_edges += 1
	_check(pentagons == 12, "exactly 12 pentagons (got %d)" % pentagons)
	_check(bad_shape == 0, "every other tile is a hexagon")
	_check(asymmetric == 0, "neighbours are mutual")
	_check(unshared_edges == 0, "neighbouring tiles share both corners of their edge")
	var again := HexSphere.new(16)
	_check(again.centers == sphere.centers and again.corners == sphere.corners, "building twice gives identical tiles")


func _test_find_tile() -> void:
	print("find_tile")
	var sphere := HexSphere.new(16)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var wrong := 0
	var hint := 0
	for i in 3000:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var found := sphere.find_tile(dir, hint)
		if not sphere.contains(found, dir):
			wrong += 1
		hint = found
	_check(wrong == 0, "3,000 random points land in a tile that contains them (%d wrong)" % wrong)
	var covered := 0
	for i in 500:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var owners := 0
		for t in sphere.tile_count():
			if sphere.contains(t, dir):
				owners += 1
		if owners >= 1:
			covered += 1
	_check(covered == 500, "no gaps: every sampled point is inside some tile")


func _test_generator() -> void:
	print("PlanetGenerator")
	var a := PlanetGenerator.generate(7)
	var b := PlanetGenerator.generate(7)
	var c := PlanetGenerator.generate(8)
	_check(a.level == b.level and a.biome == b.biome and a.home_tile == b.home_tile, "same seed gives the same planet")
	_check(a.level != c.level, "different seeds give different planets")
	var water := 0
	for t in a.tile_count():
		if a.is_water(t):
			water += 1
	var share := float(water) / a.tile_count()
	_check(share > 0.3 and share < 0.45, "ocean covers 30-45%% of tiles (%.0f%%)" % (share * 100.0))
	var home := a.home_tile
	_check(not a.is_water(home) and a.biome[home] == Biome.GRASSLAND, "home is on dry grassland")
	var counts := {}
	for t in a.tile_count():
		counts[a.biome[t]] = counts.get(a.biome[t], 0) + 1
	for id in [Biome.POLAR, Biome.TUNDRA, Biome.GRASSLAND, Biome.DESERT, Biome.JUNGLE]:
		_check(counts.get(id, 0) > 0, "%s appears" % Biome.NAMES[id])
	for world_seed in [1, 2, 3, 42, 1234]:
		var p := PlanetGenerator.generate(world_seed)
		_check(p.home_tile >= 0 and not p.is_water(p.home_tile), "seed %d has a dry home tile" % world_seed)


func _test_mesher() -> void:
	print("PlanetMesher")
	var data := PlanetGenerator.generate(1)
	var built := PlanetMesher.build(data)
	var counts := {}
	for part in ["terrain", "near", "far"]:
		var triangles := 0
		for chunk in built[part]:
			triangles += chunk.triangle_count()
		counts[part] = triangles
	print("  info  triangles: terrain %d, near props %d, far props %d; %d lamps" % [counts["terrain"], counts["near"], counts["far"], built["lamps"].size()])
	_check(counts["near"] > 0 and counts["far"] > 0, "models load from assets/models")
	_check(counts["far"] < counts["near"] / 3, "far-away props are much lighter than close-up ones")
	_check(counts["terrain"] + counts["far"] < 200000, "whole planet at far detail is under 200k triangles")
	_check(built["lamps"].size() > 0 and built["lamps"].size() <= 8, "village has 1-8 lamps (Mobile limit is 8 lights per mesh)")


## Walks a body out from home in 12 directions and checks the movement rules:
## never into water, never up more than one terrace in a step, and feet back on
## the ground once it lands.
func _test_walking() -> void:
	print("GravityBody")
	var planet := Planet.new()
	root.add_child(planet)
	planet.generate(1)
	var body := GravityBody.new()
	root.add_child(body)
	var into_water := 0
	var big_climbs := 0
	var tiles_visited := {}
	for i in 12:
		body.spawn(planet, planet.data.home_tile)
		body.heading = SphereMath.basis_from_up(body.get_up(), TAU * i / 12.0).z
		for step in 1500:
			var before := body.tile
			body.move_along_surface(body.heading * 0.1)
			body.update_vertical(1.0 / 60.0)
			tiles_visited[body.tile] = true
			if planet.data.is_water(body.tile):
				into_water += 1
			if planet.data.level[body.tile] - planet.data.level[before] > 1:
				big_climbs += 1
	for i in 120:
		body.update_vertical(1.0 / 60.0)
	var feet := planet.up_at(body.global_position).dot(body.global_position - planet.global_position)
	_check(into_water == 0, "never walks into water")
	_check(big_climbs == 0, "never climbs more than one terrace at a time")
	_check(tiles_visited.size() > 30, "actually gets around (%d tiles visited)" % tiles_visited.size())
	_check(absf(feet - planet.ground_radius(body.tile)) < 0.01, "ends standing on the ground")
	body.queue_free()
	planet.queue_free()


func _test_items_and_inventory() -> void:
	print("Items and inventory")
	var items := ItemDatabase.all()
	_check(items.size() >= 60, "item data loads (%d items)" % items.size())
	var ids := {}
	for item in items:
		ids[item.id] = true
	_check(ids.size() == items.size(), "item ids are unique")
	for water in ["cold", "temperate", "warm"]:
		var fish := 0
		for item in ItemDatabase.in_category("fish"):
			if water in item.waters:
				fish += 1
		_check(fish >= 5, "at least 5 fish in %s water" % water)
	var inv := Inventory.new(3)
	_check(inv.add("stone", 45) == 0 and inv.count_of("stone") == 45, "materials stack (45 stone in 2 slots)")
	_check(inv.add("frostfin", 2) == 1, "fish take a whole slot; the extra doesn't fit")
	_check(inv.remove_item("stone", 40) and inv.count_of("stone") == 5, "removing from stacks")
	var night := ItemDatabase.get_item("glowbug")
	_check(night.available_at(22.0) and night.available_at(2.0) and not night.available_at(12.0), "hours wrap past midnight")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var warm_fish := CatchTables.fish(rng, "warm", 12.0)
	_check(warm_fish != null and "warm" in warm_fish.waters, "catch tables pick a matching fish")
	_check(CatchTables.bug(rng, Biome.DESERT, 12.0).found_in(Biome.DESERT), "catch tables pick a matching bug")


func _test_economy() -> void:
	print("Economy")
	_check(Economy.category_demand(1, 100, "fish") == Economy.category_demand(1, 100, "fish"), "demand is the same for the same day")
	var varies := false
	for d in 10:
		if Economy.category_demand(1, d, "fish") != Economy.category_demand(1, 0, "fish"):
			varies = true
	_check(varies, "demand changes from day to day")
	_check(Economy.hints(1, 100).size() == 3, "three demand-board hints")
	var worth := 200
	_check(Economy.purchase_chance(120, worth, 10) > Economy.purchase_chance(200, worth, 10), "cheaper sells more often")
	_check(Economy.purchase_chance(500, worth, 10) < 0.1, "far too pricey almost never sells")
	_check(Economy.price("meadow_trout", 0.0) < Economy.price("meadow_trout", 1.0), "price slider goes from bargain to premium")


func _test_commands_and_save() -> void:
	print("Commands and saving")
	var state := GameState.new()
	state.world_seed = 3
	_check(Commands.execute(state, {"type": "collect", "item": "meadow_trout"})["ok"], "collect a fish")
	var slot := 0
	_check(Commands.execute(state, {"type": "stock_shelf", "slot": slot, "shelf": 0})["ok"], "stock it on a shelf")
	_check(state.inventory.count_of("meadow_trout") == 0 and state.shelves[0]["item"] == "meadow_trout", "it moved to the shelf")
	Commands.execute(state, {"type": "set_price", "shelf": 0, "level": 0.25})
	var before := state.stardust
	var sale := Commands.execute(state, {"type": "sell", "shelf": 0, "worth": 200})
	_check(sale["ok"] and state.stardust == before + int(sale["price"]) and state.shelves[0].is_empty(), "a sale pays and empties the shelf")
	var paid := Commands.execute(state, {"type": "pay_debt", "amount": 100})
	_check(paid["ok"] and state.debt == GameState.STARTING_DEBT - 100, "paying Vessa lowers the debt")
	_check(not Commands.execute(state, {"type": "pay_debt", "amount": 999999})["ok"] or state.stardust == 0, "can't pay more than you have")
	Commands.execute(state, {"type": "collect", "item": "stone", "count": 3})
	var placed := Commands.execute(state, {"type": "place", "slot": state.inventory.slots.find(state.inventory.slots.filter(func(x): return x.get("item", "") == "stone")[0]), "world_slot": 700})
	_check(placed["ok"] and state.slot_taken(700), "place an item on a spot")
	_check(not Commands.execute(state, {"type": "place", "slot": 0, "world_slot": 700})["ok"], "can't place two things on one spot")
	_check(Commands.execute(state, {"type": "harvest", "prop": "t5-0", "max": 1})["ok"], "harvest a tree")
	_check(not Commands.execute(state, {"type": "harvest", "prop": "t5-0", "max": 1})["ok"], "only once a day")
	Commands.execute(state, {"type": "new_day", "day": state.day + 1})
	_check(Commands.execute(state, {"type": "harvest", "prop": "t5-0", "max": 1})["ok"], "again the next day")

	var path := "user://test_save.json"
	_check(SaveSystem.save(state, path), "save writes a file")
	var loaded := SaveSystem.load_state(path)
	_check(loaded != null and JSON.stringify(loaded.to_dict()) == JSON.stringify(state.to_dict()), "load gives back exactly what was saved")
	SaveSystem.delete(path)


func _test_tile_graph() -> void:
	print("TileGraph")
	var data := PlanetGenerator.generate(1)
	var graph := TileGraph.new(data)
	var area := data.tiles_within(data.home_tile, 6)
	var far_tile := -1
	for t: int in area:
		if area[t] == 6 and not data.is_water(t):
			far_tile = t
			break
	var path := graph.find_path(data.home_tile, far_tile)
	_check(path.size() >= 7 and path[0] == data.home_tile and path[-1] == far_tile, "finds a route six rings out (%d tiles)" % path.size())
	var legal := true
	for i in path.size() - 1:
		if not graph.can_step(path[i], path[i + 1]):
			legal = false
	_check(legal, "every step on the route is walkable")
	var water := -1
	for n in area:
		if data.is_water(n):
			water = n
			break
	if water != -1:
		var to_water := graph.find_path(data.home_tile, water)
		_check(to_water.size() > 0 and not data.is_water(to_water[-1]), "a route to the water stops on the shore")
	var slot := graph.nearest_slot(data.home_tile, data.sphere.centers[data.home_tile])
	_check(graph.slot_tile(slot) == data.home_tile and slot % TileGraph.SLOTS_PER_TILE == 0, "the centre spot of a tile")


func _test_props() -> void:
	print("PropPlacer")
	var a := PlanetGenerator.generate(4)
	var b := PlanetGenerator.generate(4)
	_check(a.props.size() > 300, "the planet has plenty of props (%d)" % a.props.size())
	var same := a.props.size() == b.props.size()
	for i in mini(a.props.size(), b.props.size()):
		if a.props[i]["id"] != b.props[i]["id"] or not (a.props[i]["xf"] as Transform3D).is_equal_approx(b.props[i]["xf"]):
			same = false
			break
	_check(same, "same seed, same props and ids")
	_check(a.village.has("stall_front") and a.village.has("vessa") and a.village.has("home_door"), "village layout is recorded")
	var ids := {}
	for prop: Dictionary in a.props:
		ids[prop["id"]] = true
	_check(ids.size() == a.props.size(), "prop ids are unique")


func _test_shop_rules() -> void:
	print("Shop rules")
	var state := GameState.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	_check(Economy.customer_choice(rng, state).is_empty(), "no choice with empty shelves")
	state.shelves[2] = {"item": "frostfin", "count": 3, "price": 0.0}
	var bought_cheap := 0
	for i in 300:
		var choice := Economy.customer_choice(rng, state)
		if choice["buy"]:
			bought_cheap += 1
		if choice["shelf"] != 2:
			bought_cheap = -10000
	state.shelves[2]["price"] = 1.0
	var bought_dear := 0
	for i in 300:
		if Economy.customer_choice(rng, state)["buy"]:
			bought_dear += 1
	_check(bought_cheap > 200, "bargains usually sell (%d/300)" % bought_cheap)
	_check(bought_dear < bought_cheap / 2, "premium prices sell less (%d/300)" % bought_dear)
	_check(Economy.seconds_between_customers(100, false) < Economy.seconds_between_customers(0, false), "reputation brings customers sooner")

	state.flags["met_vessa"] = true
	Commands.execute(state, {"type": "set_flag", "flag": "debt_paid"})
	var copy := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	_check(copy.flags.has("met_vessa") and copy.flags.has("debt_paid"), "story flags survive saving")

	var data := PlanetGenerator.generate(1)
	var graph := TileGraph.new(data)
	var around := data.tiles_within(data.home_tile, 5)
	var far := -1
	for t: int in around:
		if around[t] == 5 and not data.is_water(t):
			far = t
			break
	var target: Vector3 = data.village["stall_front"].normalized()
	var route := graph.route(far, target)
	_check(route.size() >= 4 and route[-1].is_equal_approx(target), "a traveller can route to the stall (%d waypoints)" % route.size())

	var empty := 0
	for item in ItemDatabase.all():
		var md := MeshData.new()
		ItemMeshes.build(md, item, Transform3D.IDENTITY)
		if md.triangle_count() < 8:
			empty += 1
	_check(empty == 0, "every item has a 3D model")


static func _has_point(points: PackedVector3Array, p: Vector3) -> bool:
	for q in points:
		if q.is_equal_approx(p):
			return true
	return false
