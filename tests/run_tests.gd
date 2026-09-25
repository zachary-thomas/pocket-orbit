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
	var triangles := 0
	for md: MeshData in built["chunks"]:
		triangles += md.triangle_count()
	print("  info  %d triangles across %d chunks, %d lamps" % [triangles, built["chunks"].size(), built["lamps"].size()])
	# Horizon culling draws at most about half of this at once.
	_check(triangles > 10000 and triangles < 160000, "whole-planet mesh is under 160k triangles")
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


static func _has_point(points: PackedVector3Array, p: Vector3) -> bool:
	for q in points:
		if q.is_equal_approx(p):
			return true
	return false
