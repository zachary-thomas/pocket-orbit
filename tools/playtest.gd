extends Node
## Scripted playthrough of the Phase 1 loop, driving the real game through
## its own controls (tap-to-walk targets and the action button): meet Vessa,
## gather, fish, catch a bug, stock the stall, watch customers buy, pay the
## debt. Saves screenshots along the way, prints a report and quits.
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
		var ref := weakref(bug)
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
	var deadline := Time.get_ticks_msec() + 90000
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

	# Saving round trip.
	var path := "user://playtest_save.json"
	_check(SaveSystem.save(_game.state, path), "saved")
	var loaded := SaveSystem.load_state(path)
	_check(loaded != null and JSON.stringify(loaded.to_dict()) == JSON.stringify(_game.state.to_dict()), "loads back the same")
	SaveSystem.delete(path)

	print("\nPlaytest: %s" % ("all good." if _failures == 0 else "%d problem(s)." % _failures))
	print("Stats: ", _game.state.stats, "  Stardust ", _game.state.stardust, "  debt ", _game.state.debt)
	get_tree().quit(_failures)


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
