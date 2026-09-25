class_name Interactions
extends Node
## What the player can do right now, and doing it.
##
## Every frame it looks for the best nearby target: the stall, Vessa, the
## home door, a placed item, a bug, a tree or rock, or water to fish in. The
## HUD's action button (or E) acts on it. Tapping the screen walks there
## along a TileGraph route first (tap-to-walk), then acts on arrival.
##
## A target is a Dictionary: {"kind", "label", "pos" (world), "reach" (m),
## plus "prop", "node" or "id" depending on the kind}.

signal target_changed(target: Dictionary)
signal panel_requested(panel: String)

const TAP_TIME := 0.35
const TAP_SLOP := 14.0
## Ray-march step when finding where a tap hits the ground, in metres.
const TAP_STEP := 0.2

var game: Game
var camera: PlanetCamera
var fishing: Fishing
var bugs: BugSwarm
var world_items: WorldItems
var vessa: Npc
var material: Material
## Set by the HUD while a menu is open.
var ui_open := false

var current := {}
var _pending := {}
var _busy := 0.0
var _touches := {}
var _marker: MeshInstance3D


func _ready() -> void:
	var md := MeshData.new()
	md.add_prism(Transform3D.IDENTITY, 0.45, 0.45, 0.06, 12, Palette.uv("gold"))
	_marker = MeshInstance3D.new()
	_marker.mesh = md.to_mesh(null)
	var marker_material := StandardMaterial3D.new()
	marker_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker_material.albedo_color = Color(UiTheme.AMBER, 0.75)
	marker_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_marker.material_override = marker_material
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	add_child(_marker)


func _process(delta: float) -> void:
	if game == null or game.state == null or game.player.planet == null:
		return
	_busy = maxf(_busy - delta, 0.0)
	var player := game.player
	if player.is_moving() and not fishing.is_active():
		player.hold("")
	if _marker.visible:
		_marker.scale = _marker.scale.move_toward(Vector3.ZERO, delta * 0.8)
		_marker.visible = _marker.scale.x > 0.05 and player.has_route()
	if not _pending.is_empty():
		_update_pending()
	var best := {} if ui_open or fishing.is_active() else _best_target()
	if fishing.is_active():
		best = {"kind": "reel", "label": "Reel in"}
	if best.get("kind", "") != current.get("kind", "") or best.get("label", "") != current.get("label", "") \
			or best.get("prop", {}).get("id", "") != current.get("prop", {}).get("id", ""):
		current = best
		target_changed.emit(current)
	else:
		current = best


func _unhandled_input(event: InputEvent) -> void:
	if game == null or ui_open:
		return
	if event.is_action_pressed("interact"):
		press_action()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenTouch:
		if event.pressed:
			_touches[event.index] = [event.position, Time.get_ticks_msec()]
		elif _touches.has(event.index):
			var start: Array = _touches[event.index]
			_touches.erase(event.index)
			if (Time.get_ticks_msec() - start[1]) / 1000.0 < TAP_TIME and event.position.distance_to(start[0]) < TAP_SLOP:
				tap(event.position)
	elif event is InputEventScreenDrag and _touches.has(event.index):
		if event.position.distance_to(_touches[event.index][0]) >= TAP_SLOP:
			_touches.erase(event.index)


## The action button: act on the current target.
func press_action() -> void:
	if fishing.is_active():
		fishing.press()
		return
	if current.is_empty():
		game.toast.emit("Nothing to do here. Walk up to trees, rocks, bugs or the shore.")
		return
	perform(current)


func perform(target: Dictionary) -> void:
	if _busy > 0.0:
		return
	_pending = {}
	var player := game.player
	player.set_route(PackedVector3Array())
	if target.has("pos"):
		player.face(target["pos"])
	match target["kind"]:
		"shop":
			panel_requested.emit("shop")
		"vessa":
			vessa.face(player.global_position)
			panel_requested.emit("vessa")
		"home":
			panel_requested.emit("storage")
		"placed":
			game.run({"type": "pick_up", "id": target["id"]})
		"bug":
			_swing_net(target["node"])
		"prop":
			_gather(target)
		"water":
			player.hold("rod")
			player.swing()
			fishing.cast(target["pos"])
			# Look out over the water, so the bobber is in view.
			if camera.surface_forward.dot(player.heading) < 0.5:
				camera.turn_toward(player.heading)


# --- Finding targets -------------------------------------------------------------

func candidates(around_tile: int) -> Array[Dictionary]:
	var data := game.planet.data
	var center := game.planet.global_position
	var village := data.village
	var list: Array[Dictionary] = [
		{"kind": "shop", "label": "Shop", "pos": center + village["stall_front"], "reach": 2.4, "size": 1.6, "height": 2.4},
		{"kind": "home", "label": "Storage", "pos": center + village["home_door"], "reach": 2.4, "size": 1.8, "height": 2.4},
	]
	if vessa:
		list.append({"kind": "vessa", "label": "Talk", "pos": vessa.global_position, "reach": 2.8, "size": 0.7, "height": 1.8})
	var placed := world_items.placed_positions()
	for id: String in placed:
		list.append({"kind": "placed", "label": "Pick up", "pos": center + placed[id], "reach": 1.9, "id": id, "size": 0.6, "height": 0.6})
	for bug in bugs.bugs():
		list.append({"kind": "bug", "label": "Catch", "pos": bug.global_position, "reach": 2.7, "node": bug, "size": 0.7, "height": 0.4})
	var seen := {}
	for tile in [around_tile, game.player.tile]:
		for prop: Dictionary in data.props_near(tile):
			if prop["source"] == "" or seen.has(prop["id"]):
				continue
			seen[prop["id"]] = true
			var label := _prop_action(prop)
			if label != "":
				list.append({"kind": "prop", "label": label, "pos": center + (prop["xf"] as Transform3D).origin, "reach": prop["radius"] + 1.3,
					"prop": prop, "size": maxf(prop["radius"] + 0.5, 0.8), "height": 3.5})
	return list


func _best_target() -> Dictionary:
	var player := game.player
	var best := {}
	var best_score := INF
	for target in candidates(player.tile):
		var dist := ground_distance(player.global_position, target["pos"])
		if dist > target["reach"]:
			continue
		var facing := player.heading.dot(SphereMath.tangent(target["pos"] - player.global_position, player.get_up()))
		var score := dist - facing
		if score < best_score:
			best_score = score
			best = target
	if best.is_empty():
		var water := water_spot(player.heading)
		if water != Vector3.ZERO:
			best = {"kind": "water", "label": "Fish", "pos": water}
	return best


## Distance along the ground between two points, ignoring height.
func ground_distance(a: Vector3, b: Vector3) -> float:
	var planet := game.planet
	return planet.up_at(a).angle_to(planet.up_at(b)) * planet.ground_radius(game.player.tile)


## A point on the water surface the player could cast to, preferring the
## direction `facing`; zero if there's no water close by.
func water_spot(facing: Vector3) -> Vector3:
	var planet := game.planet
	var player := game.player
	if not planet.data.is_coast(player.tile):
		return Vector3.ZERO
	var up := player.get_up()
	var r := planet.ground_radius(player.tile)
	for turn: float in [0.0, 0.5, -0.5, 1.0, -1.0, 1.6, -1.6, 2.3, -2.3, PI]:
		var dir := facing.rotated(up, turn)
		for dist: float in [3.0, 4.5, 6.0]:
			var spot := (up * r + dir * dist).normalized()
			if planet.data.is_water(planet.find_tile_dir(spot, player.tile)):
				return planet.global_position + spot * planet.data.sea_level_radius
	return Vector3.ZERO


## What acting on a tree or rock would do now ("Shake", "Chop", "Mine",
## "Harvest"), or "" if it's done for today.
func _prop_action(prop: Dictionary) -> String:
	var source: String = prop["source"]
	if source in ["tree_round", "jungle_tree"] and _harvested_today(prop["id"] + ":shake") < 1:
		return "Shake"
	if _harvested_today(prop["id"]) >= CatchTables.harvests_per_day(source, false):
		return ""
	match source:
		"rock":
			return "Mine"
		"cactus":
			return "Harvest"
	return "Chop"


func _harvested_today(id: String) -> int:
	var record: Dictionary = game.state.harvests.get(id, {})
	return int(record.get("count", 0)) if int(record.get("day", -1)) == game.state.day else 0


# --- Actions ---------------------------------------------------------------------

func _gather(target: Dictionary) -> void:
	var player := game.player
	var prop: Dictionary = target["prop"]
	var shake: bool = target["label"] == "Shake"
	var source: String = prop["source"]
	player.hold("" if shake else ("pick" if source == "rock" else "axe"))
	player.swing()
	_busy = 0.45
	await get_tree().create_timer(0.3).timeout
	var harvest_id: String = prop["id"] + (":shake" if shake else "")
	var result := Commands.execute(game.state, {"type": "harvest", "prop": harvest_id, "max": CatchTables.harvests_per_day(source, shake)})
	if not result["ok"]:
		game.toast.emit(result["message"])
		return
	var found := CatchTables.gather(game.rng(), source, game.planet.data.biome[prop["tile"]], shake)
	if found.is_empty():
		game.toast.emit("Nothing fell out this time." if shake else "Nothing useful this time.")
		return
	var collected := game.run({"type": "collect", "item": found[0], "count": found[1]})
	if collected["ok"]:
		var at: Vector3 = target["pos"]
		WorldItems.pop(get_parent(), found[0], at, game.planet.up_at(at), material)


func _swing_net(bug: Node3D) -> void:
	var player := game.player
	player.hold("net")
	player.swing()
	_busy = 0.5
	await get_tree().create_timer(0.25).timeout
	if not is_instance_valid(bug) or bug.is_queued_for_deletion():
		game.toast.emit("Missed!")
		return
	if ground_distance(player.global_position, bug.global_position) > 3.2:
		game.toast.emit("Missed! Creep up closer.")
		bug.set("fleeing", 1.5)
		return
	var item := bugs.catch(bug)
	var result := game.run({"type": "collect", "item": item})
	if result["ok"]:
		WorldItems.pop(get_parent(), item, player.global_position, player.get_up(), material)
		player.cheer()


# --- Tap to walk -----------------------------------------------------------------

func tap(screen_position: Vector2) -> void:
	var from := camera.project_ray_origin(screen_position)
	var dir := camera.project_ray_normal(screen_position)
	var hit := ground_hit(from, dir)
	var hit_tile := game.player.tile if hit == Vector3.ZERO else game.planet.find_tile(hit, game.player.tile)
	var picked := _pick(from, dir, hit_tile)
	if not picked.is_empty():
		walk_to_target(picked)
	elif hit != Vector3.ZERO:
		if game.planet.data.is_water(hit_tile):
			walk_to_target({"kind": "water_tap", "pos": hit, "reach": 0.0})
		else:
			walk_to(hit)


## Walks toward a target and acts on it on arrival (or right away if close).
func walk_to_target(target: Dictionary) -> void:
	if ground_distance(game.player.global_position, target["pos"]) <= target["reach"]:
		perform(target)
		return
	_pending = target
	if not walk_to(target["pos"]):
		_pending = {}


## Starts walking to a world position. False if there's no way there.
func walk_to(world_position: Vector3) -> bool:
	var player := game.player
	var points := game.graph.route(player.tile, game.planet.up_at(world_position))
	if points.is_empty():
		game.toast.emit("Can't get there from here.")
		return false
	if fishing.is_active():
		fishing.stop()
	player.set_route(points)
	var up := game.planet.up_at(points[-1])
	var tile := game.planet.find_tile_dir(up, player.tile)
	_marker.global_transform = Transform3D(SphereMath.basis_from_up(up), game.planet.global_position + up * (game.planet.ground_radius(tile) + 0.03))
	_marker.scale = Vector3.ONE
	_marker.visible = true
	return true


func _update_pending() -> void:
	var player := game.player
	var target := _pending
	if target["kind"] == "bug" and not is_instance_valid(target.get("node")):
		_pending = {}
		return
	if target["kind"] == "bug":
		target["pos"] = target["node"].global_position
	if target["kind"] != "water_tap" and ground_distance(player.global_position, target["pos"]) <= target["reach"]:
		perform(target)
		return
	if player.has_route():
		return
	_pending = {}
	if target["kind"] == "water_tap":
		var toward := SphereMath.tangent(target["pos"] - player.global_position, player.get_up())
		var water := water_spot(toward)
		if water == Vector3.ZERO:
			game.toast.emit("Walk up to the shore to fish.")
		else:
			perform({"kind": "water", "label": "Fish", "pos": water})


## Where a camera ray first meets the ground or the sea, or zero if it
## misses the planet.
func ground_hit(from: Vector3, dir: Vector3) -> Vector3:
	var planet := game.planet
	var data := planet.data
	var center := planet.global_position
	var top := data.radius + PlanetGenerator.MAX_LEVEL * data.level_height + 1.0
	# Start where the ray enters the sphere around the highest terrain.
	var oc := from - center
	var b := oc.dot(dir)
	var c := oc.length_squared() - top * top
	var disc := b * b - c
	if disc < 0.0:
		return Vector3.ZERO
	var t := maxf(-b - sqrt(disc), 0.0)
	var t_end := -b + sqrt(disc)
	var hint := game.player.tile
	while t < t_end:
		var p := from + dir * t
		var d := p - center
		var r := d.length()
		hint = data.sphere.find_tile(d / r, hint)
		if r <= maxf(data.top_radius(hint), data.sea_level_radius):
			return p
		t += TAP_STEP
	return Vector3.ZERO


## The target a tap ray passes closest to, if any: each target is treated
## as an upright capsule of its own size and height.
func _pick(from: Vector3, dir: Vector3, hit_tile: int) -> Dictionary:
	var best := {}
	var best_t := INF
	for target in candidates(hit_tile):
		var base: Vector3 = target["pos"]
		var up := game.planet.up_at(base)
		var d := _ray_to_segment(from, dir, base, base + up * float(target["height"]))
		if d.x < float(target["size"]) and d.y < best_t:
			best_t = d.y
			best = target
	return best


## (distance, ray t) between a ray and a segment, sampled along the segment.
static func _ray_to_segment(from: Vector3, dir: Vector3, a: Vector3, b: Vector3) -> Vector2:
	var best := Vector2(INF, INF)
	for i in 6:
		var p := a.lerp(b, i / 5.0)
		var t := maxf((p - from).dot(dir), 0.0)
		var dist := (from + dir * t).distance_to(p)
		if dist < best.x:
			best = Vector2(dist, t)
	return best
