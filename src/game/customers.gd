class_name Customers
extends Node3D
## Passing travellers who shop at the stall. While something is on the
## shelves, one turns up every so often (sooner with a better reputation,
## less often at night), walks to the counter along a TileGraph route,
## browses, and buys or walks off depending on price (Economy.customer_choice).

const MAX_AT_ONCE := 3
const BROWSE_SECONDS := 2.6
## Tiles this many rings from home are where travellers arrive from and leave to.
const EDGE_RING := 5

enum Stage { ARRIVING, BROWSING, LEAVING }

var game: Game
var _material: Material
var _rng := RandomNumberGenerator.new()
var _timer := 4.0


class Customer:
	extends Npc
	var stage := 0
	var spot := 0
	var wait := 0.0


func setup(p_game: Game, material: Material) -> void:
	game = p_game
	_material = material
	_rng.randomize()
	for child in get_children():
		child.queue_free()
	_timer = 4.0


func count() -> int:
	return get_child_count()


func _process(delta: float) -> void:
	if game == null or game.state == null:
		return
	_timer -= delta
	if _timer <= 0.0:
		_timer = Economy.seconds_between_customers(game.state.reputation, game.is_night_at_home()) * _rng.randf_range(0.7, 1.3)
		if get_child_count() < MAX_AT_ONCE and _has_stock():
			spawn()
	for customer: Customer in get_children():
		match customer.stage:
			Stage.BROWSING:
				customer.wait -= delta
				customer.face(game.planet.global_position + (game.planet.data.village["stall"] as Transform3D).origin)
				if customer.wait <= 0.0:
					_decide(customer)
			Stage.ARRIVING:
				if not customer.has_route():
					customer.stage = Stage.BROWSING
					customer.wait = BROWSE_SECONDS
					customer.say("...", BROWSE_SECONDS)


## Sends a new customer toward the stall. Returns it (or null if there was
## nowhere for them to come from).
func spawn() -> Customer:
	var start := _edge_tile()
	if start == -1:
		return null
	var spot := _free_spot()
	var target := _spot_position(spot)
	var route := game.graph.route(start, game.planet.up_at(target))
	if route.is_empty():
		return null
	var customer := Customer.new()
	add_child(customer)
	customer.build(Npc.Look.TRAVELER, _material, _rng)
	customer.spawn(game.planet, start)
	customer.spot = spot
	customer.stage = Stage.ARRIVING
	customer.set_route(route)
	return customer


func _decide(customer: Customer) -> void:
	var choice := Economy.customer_choice(_rng, game.state)
	if choice.is_empty():
		customer.say("All sold out?")
	else:
		var feel := Economy.price_feel(choice["asking"], choice["worth"])
		if choice["buy"]:
			var result := game.run({"type": "sell", "shelf": choice["shelf"], "worth": choice["worth"]})
			if result["ok"]:
				customer.say({"bargain": "What a deal!", "fair": "Lovely!", "pricey": "Pricey, but okay.", "too much": "Ouch... fine."}[feel], 3.0)
		else:
			game.run({"type": "customer_left", "asking": choice["asking"], "worth": choice["worth"]})
			customer.say("Too pricey..." if feel in ["pricey", "too much"] else "Maybe later.", 3.0)
	_leave(customer)


func _leave(customer: Customer) -> void:
	customer.stage = Stage.LEAVING
	var away := _edge_tile()
	var route := game.graph.route(customer.tile, game.planet.tile_center(away)) if away != -1 else PackedVector3Array()
	if route.is_empty():
		customer.queue_free()
		return
	customer.set_route(route)
	customer.arrived.connect(customer.queue_free, CONNECT_ONE_SHOT)


func _has_stock() -> bool:
	for shelf in game.state.shelves:
		if not shelf.is_empty():
			return true
	return false


## A random land tile on the ring EDGE_RING tiles out from home.
func _edge_tile() -> int:
	var data := game.planet.data
	var ring: Array[int] = []
	var around := data.tiles_within(data.home_tile, EDGE_RING)
	for t: int in around:
		if around[t] == EDGE_RING and not data.is_water(t) and not game.graph.is_blocked(t):
			ring.append(t)
	if ring.is_empty():
		return -1
	return ring[_rng.randi() % ring.size()]


## Spots in front of the counter: middle, left, right.
func _free_spot() -> int:
	var taken := {}
	for customer: Customer in get_children():
		if customer.stage != Stage.LEAVING:
			taken[customer.spot] = true
	for spot in 3:
		if not taken.has(spot):
			return spot
	return _rng.randi() % 3


func _spot_position(spot: int) -> Vector3:
	var stall: Transform3D = game.planet.data.village["stall"]
	var side: float = [0.0, -1.1, 1.1][spot]
	return game.planet.global_position + stall * Vector3(side, 0, 2.3)
