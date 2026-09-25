class_name ItemMeshes
extends RefCounted
## Small 3D versions of items, for shelves, things placed on the ground and
## catches held up. Built from a few shapes per category and coloured with
## the item's colour, so a new fish in items.json gets a model for free.
## About 0.3-0.5 m long: sized to sit on the stall counter.

static var _cache := {}


static func mesh(item_id: String, material: Material) -> ArrayMesh:
	if _cache.has(item_id):
		return _cache[item_id]
	var md := MeshData.new()
	build(md, ItemDatabase.get_item(item_id), Transform3D.IDENTITY)
	var result := md.to_mesh(material)
	_cache[item_id] = result
	return result


## Adds the item's shape, standing on `xf`'s origin.
static func build(md: MeshData, item: ItemDatabase.ItemDef, xf: Transform3D) -> void:
	if item == null:
		md.add_box(xf.translated_local(Vector3(0, 0.12, 0)), Vector3(0.24, 0.24, 0.24), Palette.uv("wood"))
		return
	var color := item.color.srgb_to_linear()
	var uv := Palette.uv("lamp_glow") if "glowing" in item.tags else Palette.uv("white")
	match item.category:
		"fish":
			_fish(md, xf, color, uv, 0.75 + 0.14 * item.size, item.id)
		"bug":
			_bug(md, xf, color, uv, item.id)
		"mineral":
			_mineral(md, xf, color, uv, item.id)
		"material":
			_material(md, xf, color, item.id)
		"fruit":
			_fruit(md, xf, color, item.id)
		"fossil":
			_fossil(md, xf, color, uv, item.id)
		"shore":
			_shore(md, xf, color, uv, item.id)
	md.tint = Color.WHITE


static func _fish(md: MeshData, xf: Transform3D, color: Color, uv: Vector2, k: float, id: String) -> void:
	var y := 0.13 * k
	var flat := id in ["lagoon_ray", "duskray"]
	var jelly := id == "nebula_jelly"
	md.tint = color
	if jelly:
		md.add_blob(xf.translated_local(Vector3(0, 0.22, 0)), Vector3(0.16, 0.12, 0.16), uv, 1)
		for i in 5:
			var a := TAU * i / 5.0
			md.add_prism(xf.translated_local(Vector3(cos(a) * 0.08, 0.02, sin(a) * 0.08)), 0.025, 0.02, 0.16, 4, uv)
		return
	var body := Vector3(0.21, 0.035 if flat else 0.1, 0.18 if flat else 0.065) * k
	md.add_blob(xf.translated_local(Vector3(0, y, 0)), body, uv, 1)
	# Tail and fins, a little darker, drawn on both sides.
	md.tint = color.darkened(0.25)
	var tail := xf.translated_local(Vector3(-0.19 * k, y, 0))
	_fin(md, tail, Vector3(0, 0, 0), Vector3(-0.13 * k, 0.09 * k, 0), Vector3(-0.13 * k, -0.09 * k, 0), uv)
	if not flat:
		var top := xf.translated_local(Vector3(0.02 * k, y + 0.085 * k, 0))
		_fin(md, top, Vector3(0.06 * k, 0, 0), Vector3(-0.08 * k, 0.07 * k, 0), Vector3(-0.08 * k, 0, 0), uv)
	md.tint = Color(0.08, 0.07, 0.1)
	for side in [-1.0, 1.0]:
		md.add_blob(xf.translated_local(Vector3(0.13 * k, y + 0.025 * k, body.z * 0.8 * side)), Vector3.ONE * 0.018 * k, Palette.uv("white"))


## A thin triangle visible from both sides.
static func _fin(md: MeshData, xf: Transform3D, a: Vector3, b: Vector3, c: Vector3, uv: Vector2) -> void:
	var n := xf.basis.z.normalized()
	md.add_tri_facing(xf * a, xf * b, xf * c, n, uv)
	md.add_tri_facing(xf * a, xf * b, xf * c, -n, uv)


static func _bug(md: MeshData, xf: Transform3D, color: Color, uv: Vector2, id: String) -> void:
	var s := 1.4
	var winged := id.contains("moth") or id.contains("butterfly") or id.contains("bee") or id.contains("fly") or id.contains("cicada")
	md.tint = color
	md.add_blob(xf.translated_local(Vector3(0, 0.08, 0)), Vector3(0.05, 0.045, 0.09) * s, uv, 1)
	md.add_blob(xf.translated_local(Vector3(0, 0.09, 0.12)), Vector3(0.04, 0.038, 0.04) * s, uv, 0)
	md.tint = color.darkened(0.45)
	for side in [-1.0, 1.0]:
		for leg in 3:
			var at := xf.translated_local(Vector3(0.05 * side * s, 0.0, (leg - 1) * 0.05 * s))
			md.add_box(at.translated_local(Vector3(0, 0.035, 0)), Vector3(0.012, 0.07, 0.012), Palette.uv("white"))
		# Antennae.
		md.add_box(xf.translated_local(Vector3(0.02 * side, 0.15, 0.17)).rotated_local(Vector3.RIGHT, 0.6), Vector3(0.01, 0.07, 0.01), Palette.uv("white"))
	if winged:
		md.tint = color.lightened(0.35)
		for side in [-1.0, 1.0]:
			var wing := xf.translated_local(Vector3(0.1 * side * s, 0.14, -0.01)).rotated_local(Vector3.BACK, 0.35 * side)
			md.add_blob(wing, Vector3(0.1, 0.01, 0.075) * s, uv)
	else:
		# Shell split down the middle.
		md.tint = color.lightened(0.15)
		md.add_blob(xf.translated_local(Vector3(0, 0.11, -0.01)), Vector3(0.06, 0.035, 0.085) * s, uv, 1)


static func _mineral(md: MeshData, xf: Transform3D, color: Color, uv: Vector2, id: String) -> void:
	if id in ["pebble", "flint", "obsidian"]:
		md.tint = color
		md.add_blob(xf.translated_local(Vector3(0, 0.08, 0)), Vector3(0.14, 0.08, 0.11), uv)
		return
	if id.ends_with("_ore") or id == "geode":
		md.tint = Palette.linear("rock")
		md.add_blob(xf.translated_local(Vector3(0, 0.1, 0)), Vector3(0.15, 0.1, 0.13), Palette.uv("white"))
		md.tint = color
		for p: Vector3 in [Vector3(0.09, 0.14, 0.05), Vector3(-0.06, 0.16, 0.06), Vector3(0.02, 0.12, -0.11)]:
			md.add_blob(xf.translated_local(p), Vector3.ONE * 0.045, uv)
		return
	# Crystals: a cluster of pointed prisms.
	md.tint = color
	var shards := [[Vector3(0, 0, 0), 0.07, 0.3, 0.0], [Vector3(0.08, 0, 0.03), 0.05, 0.2, -0.45], [Vector3(-0.07, 0, -0.03), 0.05, 0.22, 0.4]]
	for shard: Array in shards:
		var at := xf.translated_local(shard[0]).rotated_local(Vector3.BACK, shard[3])
		md.add_prism(at, shard[1], shard[1], shard[2] * 0.7, 6, uv)
		md.add_prism(at.translated_local(Vector3(0, shard[2] * 0.7, 0)), shard[1], 0.0, shard[2] * 0.3, 6, uv)


static func _material(md: MeshData, xf: Transform3D, color: Color, id: String) -> void:
	md.tint = color
	match id:
		"wood", "softwood", "hardwood":
			for i in 2:
				var log := xf.translated_local(Vector3(0.18, 0.07 + i * 0.12, (i - 0.5) * 0.05)).rotated_local(Vector3.BACK, PI / 2)
				md.add_prism(log, 0.065, 0.065, 0.36, 7, Palette.uv("white"))
		"clay":
			md.add_blob(xf.translated_local(Vector3(0, 0.08, 0)), Vector3(0.15, 0.08, 0.14), Palette.uv("white"), 1)
		"stone":
			md.add_blob(xf.translated_local(Vector3(0, 0.1, 0)), Vector3(0.15, 0.1, 0.13), Palette.uv("white"))
		_:
			# A stoppered jar.
			md.add_prism(xf, 0.09, 0.08, 0.2, 8, Palette.uv("white"))
			md.tint = Color.WHITE
			md.add_prism(xf.translated_local(Vector3(0, 0.2, 0)), 0.045, 0.045, 0.06, 6, Palette.uv("wood_light"))


static func _fruit(md: MeshData, xf: Transform3D, color: Color, id: String) -> void:
	md.tint = color
	match id:
		"starfruit":
			md.add_prism(xf.translated_local(Vector3(0, 0.02, 0)), 0.14, 0.11, 0.12, 5, Palette.uv("white"))
		"coconut":
			md.add_blob(xf.translated_local(Vector3(0, 0.12, 0)), Vector3(0.13, 0.12, 0.13), Palette.uv("white"), 1)
		_:
			for p: Vector3 in [Vector3(-0.07, 0.08, 0), Vector3(0.08, 0.08, 0.03), Vector3(0, 0.2, 0.01)]:
				md.add_blob(xf.translated_local(p), Vector3.ONE * 0.08, Palette.uv("white"), 1)
	md.tint = Color.WHITE
	md.add_box(xf.translated_local(Vector3(0, 0.29 if id == "apple" else 0.25, 0.01)), Vector3(0.02, 0.06, 0.02), Palette.uv("trunk"))
	md.add_blob(xf.translated_local(Vector3(0.04, 0.3 if id == "apple" else 0.26, 0.01)), Vector3(0.05, 0.012, 0.025), Palette.uv("leaf"))


## Fossils sit on a slab of the rock they came out of.
static func _fossil(md: MeshData, xf: Transform3D, color: Color, uv: Vector2, id: String) -> void:
	md.tint = Palette.linear("sand")
	md.add_box(xf.translated_local(Vector3(0, 0.03, 0)), Vector3(0.34, 0.06, 0.26), Palette.uv("white"))
	md.tint = color
	var top := xf.translated_local(Vector3(0, 0.06, 0))
	match id:
		"ammonite":
			# A coiled shell: shrinking rings in a spiral.
			for i in 7:
				var a := i * 0.9
				var r := 0.1 * (1.0 - i * 0.12)
				md.add_blob(top.translated_local(Vector3(cos(a) * r, 0.05, sin(a) * r)), Vector3.ONE * (0.055 - i * 0.006), uv)
		"amber_bug":
			md.add_blob(top.translated_local(Vector3(0, 0.06, 0)), Vector3(0.1, 0.07, 0.08), uv, 1)
			md.tint = Palette.linear("trunk")
			md.add_blob(top.translated_local(Vector3(0, 0.07, 0)), Vector3(0.035, 0.02, 0.02), Palette.uv("white"))
		"raptor_claw":
			for i in 4:
				md.add_prism(top.translated_local(Vector3(-0.08 + i * 0.04, 0.02 + i * 0.03, 0)).rotated_local(Vector3.BACK, -0.9 - i * 0.2),
					0.035 - i * 0.007, 0.03 - i * 0.007, 0.06, 6, uv)
		"shellback_skull", "skywhale_bone":
			md.add_blob(top.translated_local(Vector3(-0.05, 0.05, 0)), Vector3(0.1, 0.06, 0.08), uv)
			md.add_blob(top.translated_local(Vector3(0.09, 0.04, 0)), Vector3(0.06, 0.04, 0.05), uv)
		_:
			# A flat impression: a spine and ribs (fern, trilobite, star lizard).
			md.add_box(top.translated_local(Vector3(0, 0.01, 0)), Vector3(0.24, 0.02, 0.03), uv)
			for i in 5:
				md.add_box(top.translated_local(Vector3(-0.09 + i * 0.045, 0.01, 0)).rotated_local(Vector3.UP, 0.3), Vector3(0.02, 0.018, 0.16 - absf(i - 2) * 0.03), uv)


static func _shore(md: MeshData, xf: Transform3D, color: Color, uv: Vector2, id: String) -> void:
	md.tint = color
	match id:
		"starfish":
			for i in 5:
				var arm := xf.rotated_local(Vector3.UP, i * TAU / 5.0).translated_local(Vector3(0, 0.025, 0.07))
				md.add_box(arm, Vector3(0.05, 0.035, 0.13), uv)
			md.add_blob(xf.translated_local(Vector3(0, 0.03, 0)), Vector3(0.05, 0.03, 0.05), uv)
		"sea_urchin":
			md.add_blob(xf.translated_local(Vector3(0, 0.07, 0)), Vector3(0.09, 0.07, 0.09), uv, 1)
			for i in 10:
				var d := Vector3(cos(i * 2.4), 0.6 + 0.4 * sin(i * 1.7), sin(i * 2.4)).normalized()
				md.add_prism(Transform3D(SphereMath.basis_from_up(d, 0.0), xf * Vector3(0, 0.07, 0) + d * 0.07), 0.012, 0.0, 0.07, 3, uv)
		"conch", "hermit_crab":
			md.add_prism(xf.translated_local(Vector3(0, 0.08, 0)).rotated_local(Vector3.BACK, PI / 2), 0.09, 0.0, 0.22, 7, uv)
			md.add_prism(xf.translated_local(Vector3(0, 0.08, 0)).rotated_local(Vector3.BACK, -PI / 2), 0.09, 0.05, 0.06, 7, uv)
			if id == "hermit_crab":
				md.tint = Palette.linear("scarf")
				for side in [-1.0, 1.0]:
					md.add_blob(xf.translated_local(Vector3(-0.1, 0.03, side * 0.05)), Vector3(0.035, 0.03, 0.03), Palette.uv("white"))
		"sea_glass":
			for p: Vector3 in [Vector3(0, 0.02, 0), Vector3(0.07, 0.02, 0.04), Vector3(-0.05, 0.02, 0.05)]:
				md.add_blob(xf.translated_local(p), Vector3(0.05, 0.02, 0.04), Palette.uv("lamp_glow"))
		"pearl_oyster":
			md.add_blob(xf.translated_local(Vector3(0, 0.04, 0)), Vector3(0.12, 0.04, 0.1), uv)
			md.tint = Color.WHITE
			md.add_blob(xf.translated_local(Vector3(0, 0.09, 0)), Vector3.ONE * 0.035, Palette.uv("lamp_glow"), 1)
		_:
			# A fan-shaped scallop: ribs splaying from the hinge.
			for i in 7:
				var rib := xf.rotated_local(Vector3.UP, (i - 3) * 0.28).translated_local(Vector3(0, 0.03, 0.07))
				md.add_box(rib.rotated_local(Vector3.RIGHT, 0.18), Vector3(0.035, 0.03, 0.15), uv)
