class_name Village
extends Node3D
## The sanctuary in the world, drawn from the game state: the stall or the
## general shop, what stands on each village plot, parcels on the landing
## pad (and the drone that brings them), the villagers going about their day
## and, on inspection days, Inspector Grell.
##
## Rebuilt when the state says something was built; villagers keep walking
## between rebuilds.

## Beyond this the simple (lod1) version of a building is drawn.
const DETAIL_DISTANCE := 60.0
## Seconds a villager browses the shop before deciding.
const BROWSE_SECONDS := 2.6
## Where the inspector waits, in the stall's space.
const AUDITOR_SPOT := Vector3(2.9, 0, 2.6)
## The inspector keeps office hours.
const AUDITOR_HOURS := Vector2(9.0, 19.0)
## Hours villagers are up and about. Glims are night folk.
const AWAKE_HOURS := {"mossback": Vector2(7.0, 20.0), "glim": Vector2(16.0, 26.0), "burrl": Vector2(6.5, 21.0)}
## Collision circles for the general shop (it's wider than the stall), in the
## stall's space.
const SHOP_BLOCKERS := [Vector4(-1.15, 0, -0.1, 1.5), Vector4(1.15, 0, -0.1, 1.5)]

var game: Game
var customers: Customers
var _material: Material
var _npc_material: Material
var _rng := RandomNumberGenerator.new()
var _built: Node3D
var _drone: Node3D
var _villagers := {}
var auditor: Npc
var _auditor_leaving := false


class Villager:
	extends Npc
	var id := ""
	var species := ""
	## "idle", "walk", "to_shop", "browse", "going_home", "home"
	var doing := "idle"
	var wait := 0.0


func setup(p_game: Game, p_customers: Customers, prop_material: Material, npc_material: Material) -> void:
	game = p_game
	customers = p_customers
	_material = prop_material
	_npc_material = npc_material
	_rng.randomize()
	for child in get_children():
		child.queue_free()
	_villagers.clear()
	auditor = null
	_drone = null
	_built = Node3D.new()
	_built.name = "Buildings"
	add_child(_built)
	game.state.changed.connect(_on_changed)
	rebuild()
	for v: Dictionary in game.state.villagers:
		_spawn_villager(v, false)


## Where the village's special places are, in world space.
func stall_transform() -> Transform3D:
	return Transform3D(Basis.IDENTITY, game.planet.global_position) * (game.planet.data.village["stall"] as Transform3D)


func plot_transform(plot: Dictionary) -> Transform3D:
	return Transform3D(Basis.IDENTITY, game.planet.global_position) * (plot["xf"] as Transform3D)


func plots() -> Array:
	return game.planet.data.village.get("plots", [])


## The building standing on a plot: {"id", "kind", "plot"} or {}.
func building_on(plot_id: String) -> Dictionary:
	for id: String in game.state.buildings:
		var b: Dictionary = game.state.buildings[id]
		if b["plot"] == plot_id:
			return {"id": id, "kind": b["kind"], "plot": plot_id}
	return {}


func plot_by_id(plot_id: String) -> Dictionary:
	for plot: Dictionary in plots():
		if plot["id"] == plot_id:
			return plot
	return {}


## World position of the landing pad's centre, or zero if there isn't one.
func pad_position() -> Vector3:
	for plot: Dictionary in plots():
		if building_on(plot["id"]).get("kind", "") == "landing_pad":
			return plot_transform(plot).origin
	return Vector3.ZERO


## The door of a villager's home (a cottage or a burrow house).
func home_door(home: String) -> Vector3:
	var planet := game.planet
	for prop: Dictionary in planet.data.props:
		if prop["id"] == home:
			return planet.global_position + (prop["xf"] as Transform3D) * Vector3(0, 0, 2.7)
	if game.state.buildings.has(home):
		var plot := plot_by_id(game.state.buildings[home]["plot"])
		if not plot.is_empty():
			return plot_transform(plot) * Vector3(0, 0, 2.7)
	return planet.global_position + game.planet.data.village["stall_front"]


func villager_nodes() -> Array:
	return _villagers.values()


# --- Buildings -------------------------------------------------------------------

func _on_changed(what: String) -> void:
	match what:
		"upgrade_shop", "build", "open_parcels", "order":
			rebuild()
		"new_day":
			rebuild()
			if not game.state.parcels.is_empty() and pad_position() != Vector3.ZERO:
				fly_drone()
		"accept_resident":
			for v: Dictionary in game.state.villagers:
				if not _villagers.has(v["id"]):
					_spawn_villager(v, true)
		"finish_audit":
			_send_auditor_away()


func rebuild() -> void:
	for child in _built.get_children():
		child.queue_free()
	var state := game.state
	var data := game.planet.data
	var stall: Dictionary = {}
	for prop: Dictionary in data.props_by_tile.get(data.home_tile, []):
		if prop["id"] == "stall":
			stall = prop
	var shop_model := "general_shop" if state.shop_tier >= 2 else "market_stall"
	_add_model(shop_model, stall_transform())
	if state.shop_tier >= 2 and not stall.is_empty() and stall["radius"] > 0.0:
		# The shop is wider than the stall: swap its one collision circle for two.
		stall["radius"] = 0.0
		for i in SHOP_BLOCKERS.size():
			var c: Vector4 = SHOP_BLOCKERS[i]
			var at := (data.village["stall"] as Transform3D) * Vector3(c.x, c.y, c.z)
			_add_blocker(data, "shop-%d" % i, at, data.home_tile, c.w)
	for plot: Dictionary in plots():
		var building := building_on(plot["id"])
		var xf := plot_transform(plot)
		if building.is_empty():
			_add_model("plot_marker", xf)
			continue
		_add_model(building["kind"], xf)
		var radius: float = PropPlacer.RADIUS.get(building["kind"], 0.0)
		if radius > 0.0 and not game.graph.is_blocked(plot["tile"]):
			game.graph.block(plot["tile"])
			_add_blocker(data, "bld-" + plot["id"], (plot["xf"] as Transform3D).origin, plot["tile"], radius)
		if building["kind"] == "landing_pad":
			_add_parcels(xf)


func _add_model(model: String, xf: Transform3D) -> void:
	var holder := Node3D.new()
	holder.name = model
	_built.add_child(holder)
	holder.global_transform = xf
	for lod in 2:
		var mesh := MeshInstance3D.new()
		mesh.mesh = PropLibrary.mesh(model, lod, _material)
		if lod == 0:
			mesh.visibility_range_end = DETAIL_DISTANCE
			mesh.visibility_range_end_margin = 5.0
		else:
			mesh.visibility_range_begin = DETAIL_DISTANCE
			mesh.visibility_range_begin_margin = 5.0
		holder.add_child(mesh)


## An invisible collision circle, like a prop without a model.
func _add_blocker(data: PlanetData, id: String, at: Vector3, tile: int, radius: float) -> void:
	for prop: Dictionary in data.props_by_tile.get(tile, []):
		if prop["id"] == id:
			return
	var prop := {"id": id, "model": "", "xf": Transform3D(Basis.IDENTITY, at), "tile": tile, "radius": radius, "source": ""}
	data.props.append(prop)
	if not data.props_by_tile.has(tile):
		data.props_by_tile[tile] = []
	data.props_by_tile[tile].append(prop)


## Parcels waiting on the pad: a stack of taped boxes.
func _add_parcels(pad: Transform3D) -> void:
	var count := game.state.parcels.size()
	if count == 0:
		return
	var md := MeshData.new()
	for i in mini(count, 4):
		var at := Transform3D.IDENTITY.translated(Vector3((i % 2) * 0.62 - 0.31, 0.2 + 0.5 * int(i / 2.0) + 0.23, (i % 3) * 0.1 - 0.1)).rotated_local(Vector3.UP, i * 0.4)
		_parcel_mesh(md, at)
	var mesh := MeshInstance3D.new()
	mesh.mesh = md.to_mesh(_npc_material)
	_built.add_child(mesh)
	mesh.global_transform = pad


static func _parcel_mesh(md: MeshData, at: Transform3D) -> void:
	md.tint = Color.WHITE
	md.add_box(at, Vector3(0.52, 0.46, 0.52), Palette.uv("wood_light"))
	md.add_box(at, Vector3(0.54, 0.48, 0.12), Palette.uv("pad_stripe"))
	md.add_box(at.translated_local(Vector3(0, 0.235, 0)), Vector3(0.2, 0.02, 0.2), Palette.uv("canvas"))


# --- The delivery drone -----------------------------------------------------------

## A drone flies down to the pad with the parcels, and off again.
func fly_drone() -> void:
	var pad := pad_position()
	if pad == Vector3.ZERO:
		return
	if _drone:
		_drone.queue_free()
	var md := MeshData.new()
	md.tint = Color.WHITE
	md.add_blob(Transform3D.IDENTITY, Vector3(0.45, 0.22, 0.45), Palette.uv("pad_metal"), 1)
	for i in 4:
		var arm := Transform3D.IDENTITY.rotated(Vector3.UP, PI / 4 + i * PI / 2)
		md.add_box(arm.translated_local(Vector3(0, 0, 0.55)), Vector3(0.1, 0.08, 0.7), Palette.uv("lamp_post"))
		md.add_prism(arm.translated_local(Vector3(0, 0.06, 0.95)), 0.36, 0.36, 0.03, 8, Palette.uv("stone_light"))
	md.add_blob(Transform3D.IDENTITY.translated(Vector3(0, 0.05, -0.4)), Vector3.ONE * 0.1, Palette.uv("lamp_glow"))
	_parcel_mesh(md, Transform3D.IDENTITY.translated(Vector3(0, -0.5, 0)))
	var drone := MeshInstance3D.new()
	drone.mesh = md.to_mesh(_npc_material)
	add_child(drone)
	_drone = drone
	var up := game.planet.up_at(pad)
	var basis := SphereMath.basis_from_up(up)
	var above := pad + up * 30.0 + basis.x * 12.0
	var hover := pad + up * 1.2
	drone.global_transform = Transform3D(basis, above)
	var tween := drone.create_tween()
	tween.tween_property(drone, "global_position", hover, 4.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_interval(0.8)
	tween.tween_property(drone, "global_position", pad + up * 30.0 - basis.x * 12.0, 3.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tween.tween_callback(drone.queue_free)


# --- Villagers --------------------------------------------------------------------

func _spawn_villager(v: Dictionary, arriving: bool) -> Villager:
	var planet := game.planet
	var villager := Villager.new()
	villager.name = "Villager_%s" % v["id"]
	villager.id = v["id"]
	villager.species = v["species"]
	villager.walk_speed = 1.6 if v["species"] == "mossback" else 2.2
	add_child(villager)
	villager.build(Npc.SPECIES_LOOKS.get(v["species"], Npc.Look.TRAVELER), _npc_material, _rng, v.get("color", ""))
	_villagers[v["id"]] = villager
	var door := home_door(v["home"])
	var start := planet.find_tile(door, planet.data.home_tile)
	if arriving:
		var edge := customers.edge_tile()
		if edge != -1:
			start = edge
	villager.spawn(planet, start)
	if arriving:
		var route := game.graph.route(villager.tile, planet.up_at(door))
		villager.set_route(route)
		villager.doing = "going_home"
		villager.say("Hello!", 3.0)
	else:
		villager.global_position = door
		villager.doing = "idle"
		villager.wait = _rng.randf_range(0.5, 4.0)
	return villager


func _awake(species: String, hours: float) -> bool:
	var span: Vector2 = AWAKE_HOURS.get(species, Vector2(7.0, 20.0))
	return (hours >= span.x and hours < span.y) or (span.y > 24.0 and hours < span.y - 24.0)


func _process(delta: float) -> void:
	if game == null or game.state == null:
		return
	var hours := game.home_hours()
	for villager: Villager in _villagers.values():
		_update_villager(villager, delta, hours)
	_update_auditor(hours)


func _update_villager(v: Villager, delta: float, hours: float) -> void:
	var awake := _awake(v.species, hours)
	var record := game.state.villager(v.id)
	if record.is_empty():
		return
	if not awake and v.doing not in ["going_home", "home"]:
		v.doing = "going_home"
		v.set_route(game.graph.route(v.tile, game.planet.up_at(home_door(record["home"]))))
		return
	match v.doing:
		"home":
			if awake:
				v.visible = true
				v.doing = "idle"
				v.wait = _rng.randf_range(0.5, 3.0)
		"going_home":
			if not v.has_route():
				if awake:
					v.doing = "idle"
					v.wait = _rng.randf_range(2.0, 5.0)
				else:
					v.visible = false
					v.doing = "home"
		"idle":
			v.wait -= delta
			if v.wait <= 0.0:
				_next_errand(v)
		"walk":
			if not v.has_route():
				v.doing = "idle"
				v.wait = _rng.randf_range(4.0, 10.0)
		"to_shop":
			if not v.has_route():
				v.doing = "browse"
				v.wait = BROWSE_SECONDS
				v.say("...", BROWSE_SECONDS)
		"browse":
			v.face(stall_transform().origin)
			v.wait -= delta
			if v.wait <= 0.0:
				customers.serve(v, v.species)
				v.doing = "idle"
				v.wait = _rng.randf_range(6.0, 12.0)


## Off to the shop now and then (if it's open and has stock), otherwise a
## stroll somewhere around the village.
func _next_errand(v: Villager) -> void:
	var planet := game.planet
	var state := game.state
	var open := state.shop_tier < 2 or game.is_shop_open()
	if open and customers.has_stock() and _rng.randf() < 0.35:
		var side := _rng.randf_range(-1.8, 1.8)
		var spot := stall_transform() * Vector3(side, 0, 3.4)
		var route := game.graph.route(v.tile, planet.up_at(spot))
		if not route.is_empty():
			v.set_route(route)
			v.doing = "to_shop"
			return
	var around := planet.data.tiles_within(planet.data.home_tile, 2).keys()
	for attempt in 6:
		var t: int = around[_rng.randi() % around.size()]
		if planet.data.is_water(t) or game.graph.is_blocked(t):
			continue
		var route := game.graph.route(v.tile, planet.tile_center(t))
		if not route.is_empty():
			v.set_route(route)
			v.doing = "walk"
			return
	v.wait = 3.0


# --- The inspector ----------------------------------------------------------------

func _update_auditor(hours: float) -> void:
	var here := VillageRules.auditor_here(game.state) and hours >= AUDITOR_HOURS.x and hours < AUDITOR_HOURS.y
	if here and auditor == null:
		_spawn_auditor()
	elif not here and auditor != null and not _auditor_leaving:
		_send_auditor_away()
	if auditor and not _auditor_leaving and not auditor.has_route():
		auditor.face(game.planet.global_position + game.planet.data.village["stall_front"])


func _spawn_auditor() -> void:
	var planet := game.planet
	auditor = Npc.new()
	auditor.name = "Auditor"
	auditor.walk_speed = 2.0
	add_child(auditor)
	auditor.build(Npc.Look.AUDITOR, _npc_material, _rng)
	_auditor_leaving = false
	var spot := stall_transform() * AUDITOR_SPOT
	var edge := customers.edge_tile()
	auditor.spawn(planet, edge if edge != -1 else planet.data.home_tile)
	var route := game.graph.route(auditor.tile, planet.up_at(spot))
	if route.is_empty():
		auditor.spawn(planet, planet.find_tile(spot, planet.data.home_tile))
		auditor.global_position = spot
	else:
		auditor.set_route(route)
	auditor.say("Inspection!", 3.0)


func _send_auditor_away() -> void:
	if auditor == null:
		return
	_auditor_leaving = true
	var leaving := auditor
	auditor = null
	var edge := customers.edge_tile()
	var route := game.graph.route(leaving.tile, game.planet.tile_center(edge)) if edge != -1 else PackedVector3Array()
	if route.is_empty():
		leaving.queue_free()
	else:
		leaving.set_route(route)
		leaving.arrived.connect(leaving.queue_free, CONNECT_ONE_SHOT)
	_auditor_leaving = false
