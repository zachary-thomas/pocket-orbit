extends Node
## Scripted playthrough of the Phase 1 loop, driving the real game through
## its own controls (tap-to-walk targets and the action button): meet Vessa,
## gather, fish, catch a bug, stock the stall, watch customers buy, pay the
## debt. Then the Phase 2 sanctuary: build on a plot, order by drone mail,
## welcome a refugee and chat, upgrade to the general shop, dig for fossils,
## search a tide pool at low tide and get through an inspection. Saves
## screenshots along the way, prints a report and quits.
##
##   godot --path . -- --playtest=<output folder>

var output_dir := "user://playtest"

var _main: Node
var _game: Game
var _player: Player
var _planet: Planet
var _actions: Interactions
var _hud: GameHud
var _failures := 0


func _ready() -> void:
	_main = get_parent()
	_game = _main.game
	_player = _main.player
	_planet = _main.planet
	_actions = _main.interactions
	_hud = _main.game_hud
	_game.toast.connect(func(text: String) -> void: print("        toast: ", text))
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output_dir)
	Engine.time_scale = 2.0
	_main.sky.set_home_hours(10.5)
	_main.sky.paused = true
	await _frames(20)
	await _save("p01_start")

	# Meet Vessa.
	var vessa := _find_target("vessa")
	_actions.walk_to_target(vessa)
	await _until(func() -> bool: return _hud.is_panel_open(), 25.0)
	_check(_hud.is_panel_open(), "walked to Vessa and started talking")
	await _frames(5)
	await _save("p02_vessa_intro")
	_game.run({"type": "set_flag", "flag": "met_vessa"})
	_hud.close_panel()

	# Gather from trees and rocks.
	var before := _bag_total()
	for source in ["tree_round", "rock"]:
		var prop := _nearest_prop(source)
		if prop.is_empty():
			print("  (no %s near home)" % source)
			continue
		for i in 4:
			var target := _target_for_prop(prop)
			if target.is_empty():
				break
			_actions.walk_to_target(target)
			await _until(func() -> bool: return not _player.has_route(), 25.0)
			await _wait(0.8)
	_check(_bag_total() > before, "gathered from trees and rocks (%d items)" % (_bag_total() - before))
	await _save("p03_gathering")

	# Fishing from the nearest shore.
	var shore := _nearest_coast()
	_player.spawn(_planet, shore)
	# A bug fluttering by would take the action button instead of the rod.
	_main.bugs.clear()
	_main.bugs.set_process(false)
	await _frames(3)
	var water := _actions.water_spot(_player.heading)
	_check(water != Vector3.ZERO, "found water to fish in")
	var fish_before: int = _game.state.stats["fish"]
	for attempt in 3:
		if _game.state.stats["fish"] > fish_before:
			break
		_player.face(_actions.water_spot(_player.heading))
		await _frames(2)
		_actions.press_action()
		await _until(func() -> bool: return _main.fishing.stage == Fishing.Stage.WAITING, 3.0)
		if attempt == 0:
			await _wait(0.5)
			await _save("p04_fishing")
		await _until(func() -> bool: return _main.fishing.stage == Fishing.Stage.BITING, 10.0)
		await _wait(0.2)
		_actions.press_action()
		await _wait(0.5)
	_check(_game.state.stats["fish"] > fish_before, "caught a fish")
	_main.bugs.set_process(true)

	# Catch a bug: go back home, wait for one, sneak up.
	_player.spawn(_planet, _planet.data.village["street_tile"])
	var bugs_before: int = _game.state.stats["bugs"]
	for attempt in 4:
		await _until(func() -> bool: return not _main.bugs.bugs().is_empty(), 15.0)
		if _main.bugs.bugs().is_empty():
			break
		var bug: Node3D = _nearest_bug()
		if bug == null:
			continue
		_actions.walk_to_target({"kind": "bug", "label": "Catch", "pos": bug.global_position, "reach": 2.7, "node": bug})
		var ref: WeakRef = weakref(bug)
		await _until(func() -> bool: return _game.state.stats["bugs"] > bugs_before or ref.get_ref() == null or ref.get_ref().is_queued_for_deletion(), 20.0)
		await _wait(0.6)
		if _game.state.stats["bugs"] > bugs_before:
			break
	_check(_game.state.stats["bugs"] > bugs_before, "caught a bug")

	_hud.open_panel("bag")
	await _frames(4)
	await _save("p05_backpack")
	_hud.close_panel()

	# Stock the stall.
	_player.spawn(_planet, _planet.data.village["street_tile"])
	_actions.walk_to_target(_find_target("shop"))
	await _until(func() -> bool: return _hud.is_panel_open(), 25.0)
	_check(_hud.is_panel_open(), "walked to the stall and opened it")
	var shelf := 0
	for slot in _game.state.inventory.size():
		if shelf >= GameState.SHELF_COUNT:
			break
		if not _game.state.inventory.is_empty_slot(slot):
			if _game.run({"type": "stock_shelf", "slot": slot, "shelf": shelf})["ok"]:
				_game.run({"type": "set_price", "shelf": shelf, "level": 0.45})
				shelf += 1
	await _frames(4)
	await _save("p06_stall")
	_hud.close_panel()
	_check(shelf > 0, "stocked %d shelves" % shelf)

	# Customers.
	var sold_before: int = _game.state.stats["sold"]
	_main.customers._timer = 0.0
	await _until(func() -> bool: return _main.customers.count() > 0, 5.0)
	_check(_main.customers.count() > 0, "a customer came")
	var shot := false
	var deadline := Time.get_ticks_msec() + 150000
	while Time.get_ticks_msec() < deadline and _game.state.stats["sold"] < sold_before + 2:
		for customer in _main.customers.get_children():
			if not shot and customer.stage == Customers.Stage.BROWSING:
				_player.face(customer.global_position)
				_main.camera.reset_behind()
				await _frames(3)
				await _save("p07_customer")
				shot = true
		if _main.customers.count() == 0:
			_main.customers._timer = 0.0
		await _frames(1)
	_check(_game.state.stats["sold"] > sold_before, "customers bought %d items (%d Stardust, reputation %d)" % [
		_game.state.stats["sold"] - sold_before, _game.state.stats["earned"], _game.state.reputation])

	# Pay Vessa.
	var debt := _game.state.debt
	_game.run({"type": "pay_debt", "amount": 100})
	_check(_game.state.debt == debt - 100, "paid Vessa 100")
	_hud.open_panel("vessa")
	await _frames(4)
	await _save("p08_vessa_debt")
	_hud.close_panel()

	# Night at the village.
	_main.sky.set_home_hours(21.5)
	_player.spawn(_planet, _planet.data.village["street_tile"])
	_player.face(_planet.global_position + (_planet.data.village["stall"] as Transform3D).origin)
	_main.camera.reset_behind()
	await _frames(6)
	await _save("p09_night_stall")

	await _sanctuary()

	# Saving round trip.
	var path := "user://playtest_save.json"
	_check(SaveSystem.save(_game.state, path), "saved")
	var loaded := SaveSystem.load_state(path)
	_check(loaded != null and JSON.stringify(loaded.to_dict()) == JSON.stringify(_game.state.to_dict()), "loads back the same")
	SaveSystem.delete(path)

	print("\nPlaytest: %s" % ("all good." if _failures == 0 else "%d problem(s)." % _failures))
	print("Stats: ", _game.state.stats, "  Stardust ", _game.state.stardust, "  debt ", _game.state.debt)
	get_tree().quit(_failures)


# --- Phase 2: the sanctuary ------------------------------------------------------

func _sanctuary() -> void:
	var state := _game.state
	var village: Village = _main.village
	_main.sky.set_home_hours(10.0)
	# Skip the grind: enough Stardust and materials for everything.
	state.stardust += 20000
	state.debt = maxi(0, state.debt - 1000)
	state.reputation = 25
	for item: String in ["wood", "stone", "clay", "copper_ore"]:
		_game.run({"type": "collect", "item": item, "count": 40 if item != "copper_ore" else 4})

	# Build a landing pad on the nearest plot, through the plot's Build button.
	var plots := village.plots()
	_check(plots.size() >= 3, "the village has %d building plots" % plots.size())
	if plots.is_empty():
		return
	var plot: Dictionary = plots[0]
	_player.spawn(_planet, _planet.data.village["street_tile"])
	var build := _target_where(func(t: Dictionary) -> bool: return t["kind"] == "plot" and t["id"] == plot["id"], plot["tile"])
	_walk(build)
	await _until(func() -> bool: return _hud.is_panel_open(), 25.0)
	_check(_hud.is_panel_open() and _game.ui_subject == plot["id"], "walked to a plot and opened Build")
	await _frames(4)
	await _save("p10_build_panel")
	_game.run({"type": "build", "kind": "landing_pad", "plot": plot["id"]})
	_hud.close_panel()
	await _frames(2)
	_check(village.building_on(plot["id"]).get("kind", "") == "landing_pad" and village.pad_position() != Vector3.ZERO, "built a landing pad")

	# Drone mail: order, sleep, the drone lands the parcel, open it.
	state.seen["stone"] = true
	_hud.open_panel("mail")
	await _frames(3)
	_check(_game.run({"type": "order", "item": "stone", "count": 5})["ok"], "ordered stone from the catalogue")
	_hud.close_panel()
	await _next_day()
	await _frames(30)
	_check(not state.parcels.is_empty() and village._drone != null, "the parcel arrived by drone")
	await _save("p11_drone")
	var stone := state.inventory.count_of("stone")
	var parcels := _target_where(func(t: Dictionary) -> bool: return t["kind"] == "parcels", plot["tile"])
	_walk(parcels)
	await _until(func() -> bool: return state.parcels.is_empty(), 25.0)
	_check(state.parcels.is_empty() and state.inventory.count_of("stone") >= stone + 5, "walked to the pad and unpacked the parcel")

	# A refugee writes; welcome them; they walk home; have a chat.
	if VillageRules.pending_request(state).is_empty():
		await _next_day()
	var letter := VillageRules.pending_request(state)
	_check(not letter.is_empty(), "a refugee wrote asking to move in")
	if not letter.is_empty():
		_hud.open_panel("mail")
		await _frames(4)
		await _save("p12_move_in_letter")
		_game.run({"type": "accept_resident", "id": letter["id"]})
		_hud.close_panel()
		await _frames(2)
		var nodes := village.villager_nodes()
		_check(nodes.size() == 1, "the new villager turned up")
		if nodes.size() == 1:
			var villager: Village.Villager = nodes[0]
			await _until(func() -> bool: return villager.doing != "going_home", 60.0)
			_check(villager.doing != "going_home", "and walked home")
			var talk := _target_where(func(t: Dictionary) -> bool: return t["kind"] == "villager", villager.tile)
			_walk(talk)
			await _until(func() -> bool: return _hud.is_panel_open(), 30.0)
			_check(_hud.is_panel_open() and state.villager(villager.id)["friendship"] == 1, "chatted with %s" % state.villager(villager.id)["name"])
			await _frames(4)
			await _save("p13_villager_chat")
			_hud.close_panel()

	# The general shop: 12 shelves and opening hours.
	_check(_game.run({"type": "upgrade_shop"})["ok"] and state.shelves.size() == 12, "upgraded to the general shop")
	_game.run({"type": "set_hours", "open": 7, "close": 21})
	_check(Economy.opening_hours(state) == Vector2i(7, 21), "set opening hours")
	_player.spawn(_planet, _planet.data.village["street_tile"])
	_player.face(village.stall_transform().origin)
	_main.camera.reset_behind()
	await _frames(6)
	await _save("p14_general_shop")

	# Dig for fossils.
	var spots: Dictionary = _main.dig_spots.spots()
	_check(not spots.is_empty(), "%d dig spots today" % spots.size())
	if not spots.is_empty():
		var id: String = spots.keys()[0]
		for key: String in spots:
			if _actions.ground_distance(_player.global_position, spots[key]) < _actions.ground_distance(_player.global_position, spots[id]):
				id = key
		var at: Vector3 = spots[id]
		var bag := _bag_total()
		_walk({"kind": "dig", "label": "Dig", "pos": at, "reach": 1.9, "id": id, "size": 0.7, "height": 0.5})
		print("        dig: %.1f m away, walking %s" % [_actions.ground_distance(_player.global_position, at), _player.has_route()])
		await _until(func() -> bool: return not _main.dig_spots.spots().has(id), 90.0)
		await _frames(30)
		_check(_bag_total() > bag, "dug up something")

	# A tide pool, at low tide.
	var pool := {}
	var around := _planet.data.tiles_within(_planet.data.home_tile, 14)
	for prop: Dictionary in _planet.data.props:
		if prop["model"] == "tide_pool" and around.has(prop["tile"]) and (pool.is_empty() or around[prop["tile"]] < around[pool["tile"]]):
			pool = prop
	if pool.is_empty():
		print("  (no tide pool near home)")
	else:
		for step in 100:
			_main.sky.set_home_hours(6.0 + step * 0.25)
			if _main.sky.water_depth(pool["tile"]) <= Tides.WADE_DEPTH - 0.1:
				break
		var shore := -1
		for n in _planet.data.sphere.neighbors(pool["tile"]):
			if not _planet.data.is_water(n):
				shore = n
		_player.spawn(_planet, shore)
		await _frames(2)
		var search := _target_where(func(t: Dictionary) -> bool: return t["kind"] == "prop" and t["prop"]["id"] == pool["id"], pool["tile"])
		print("        pool %s: depth %.2f at %.2f h, shore %d, player tile %d, %.1f m away" % [pool["id"], _main.sky.water_depth(pool["tile"]), _game.home_hours(), shore, _player.tile, _actions.ground_distance(_player.global_position, _planet.global_position + (pool["xf"] as Transform3D).origin)])
		_check(search.get("label", "") == "Search", "a tide pool can be searched at low tide")
		if not search.is_empty():
			var bag := _bag_total()
			_walk(search)
			await _until(func() -> bool: return _bag_total() > bag, 20.0)
			_check(_bag_total() > bag, "found something in the tide pool")
			await _save("p15_tide_pool")

	# The inspector.
	var guard := 0
	while not VillageRules.auditor_here(state) and guard < 15:
		await _next_day()
		guard += 1
	_main.sky.set_home_hours(11.0)
	await _until(func() -> bool: return village.auditor != null, 5.0)
	_check(village.auditor != null, "Inspector Grell arrived")
	if village.auditor:
		await _until(func() -> bool: return not village.auditor.has_route(), 60.0)
		_player.spawn(_planet, _planet.data.village["street_tile"])
		var grell := _target_where(func(t: Dictionary) -> bool: return t["kind"] == "auditor", village.auditor.tile)
		_walk(grell)
		await _until(func() -> bool: return _hud.is_panel_open(), 30.0)
		_check(_hud.is_panel_open(), "talked to the inspector")
		await _frames(4)
		await _save("p16_inspection")
		var panel: AuditPanel = _hud._panels["audit"]
		for i in 4:
			var buttons := panel._answers.get_children().filter(func(b: Node) -> bool: return not b.is_queued_for_deletion())
			if buttons.is_empty():
				break
			(buttons[0] as Button).pressed.emit()
			await _frames(2)
		_check(state.audit["done"] == state.day, "answered the questions: %s" % panel._text.text.get_slice("\n", 0))
		_hud.close_panel()


## Walks to a target and acts on it; says so if there's no target.
func _walk(target: Dictionary) -> void:
	if target.is_empty():
		print("        (no target to walk to)")
		return
	_actions.walk_to_target(target)


## Moves the sky clock on a day; the game notices and starts the new day.
func _next_day() -> void:
	_main.sky.day_index += 1
	await _frames(2)


## The first interaction target matching `test` around a tile.
func _target_where(test: Callable, tile: int) -> Dictionary:
	for target in _actions.candidates(tile):
		if test.call(target):
			return target
	return {}


func _check(ok: bool, what: String) -> void:
	print(("  ok    " if ok else "  FAIL  ") + what)
	if not ok:
		_failures += 1


func _find_target(kind: String) -> Dictionary:
	for target in _actions.candidates(_player.tile):
		if target["kind"] == kind:
			return target
	return {}


func _target_for_prop(prop: Dictionary) -> Dictionary:
	for target in _actions.candidates(prop["tile"]):
		if target["kind"] == "prop" and target["prop"]["id"] == prop["id"]:
			return target
	return {}


func _nearest_prop(source: String) -> Dictionary:
	var data := _planet.data
	var around := data.tiles_within(data.home_tile, 5)
	var best := {}
	var best_ring := 99
	for t: int in around:
		for prop: Dictionary in data.props_by_tile.get(t, []):
			if prop["source"] == source and around[t] < best_ring and _game.graph.find_path(_player.tile, t).size() > 0:
				best = prop
				best_ring = around[t]
	return best


func _nearest_coast() -> int:
	var data := _planet.data
	var around := data.tiles_within(data.home_tile, 12)
	var best := data.home_tile
	var best_ring := 99
	for t: int in around:
		if data.is_coast(t) and around[t] < best_ring:
			best = t
			best_ring = around[t]
	return best


func _nearest_bug() -> Node3D:
	var best: Node3D = null
	for bug in _main.bugs.bugs():
		if best == null or bug.global_position.distance_to(_player.global_position) < best.global_position.distance_to(_player.global_position):
			best = bug
	return best


func _bag_total() -> int:
	var total := 0
	for slot in _game.state.inventory.slots:
		total += int(slot.get("count", 0))
	return total


func _until(condition: Callable, seconds: float) -> void:
	var deadline := Time.get_ticks_msec() + seconds * 1000.0 / Engine.time_scale
	while not condition.call() and Time.get_ticks_msec() < deadline:
		await get_tree().process_frame


func _wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout


func _save(file: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	image.save_png(output_dir.path_join(file + ".png"))


func _frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame
