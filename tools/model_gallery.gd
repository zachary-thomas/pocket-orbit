extends SceneTree
## Renders every model from tools/blender/build_assets.py in a row, lit with
## the game's own surface shader, and saves a PNG. The back row shows each
## model's far-away version.
##
##   godot --path . --script res://tools/model_gallery.gd -- --out=<file.png> [--sun=0.55] [--focus=cottage]
##
## --focus frames one model close up instead of the whole row.

const MODELS := ["tree_round", "tree_pine", "bush", "rock", "lamp_post", "market_stall", "cottage"]
const SPACING := [0.0, 4.2, 3.6, 2.6, 2.4, 3.2, 4.4]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://gallery.png"
	var sun_height := 0.55
	var focus := ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--focus="):
			focus = arg.trim_prefix("--focus=")
		if arg.begins_with("--out="):
			out = arg.trim_prefix("--out=")
		elif arg.begins_with("--sun="):
			sun_height = float(arg.trim_prefix("--sun="))

	var world := Node3D.new()
	root.add_child(world)
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("b9b3c4")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.BLACK
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.glow_enabled = true
	environment.glow_intensity = 0.7
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	world.add_child(world_environment)

	# Sun from the front left, like the concept sheets.
	var sun_direction := Vector3(-0.55, sun_height, 0.75).normalized()
	RenderingServer.global_shader_parameter_set("sun_direction", sun_direction)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color("fff1d6")
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	world.add_child(sun)
	sun.global_transform.basis = Basis.looking_at(-sun_direction, Vector3.UP)

	var material := ShaderMaterial.new()
	material.shader = preload("res://shaders/planet_surface.gdshader")
	material.set_shader_parameter("palette", Palette.make_texture())
	# Put the "planet centre" far below so up is +Y everywhere here.
	material.set_shader_parameter("planet_center", Vector3(0, -100000, 0))
	material.set_shader_parameter("receive_cloud_shadow", false)

	var ground := MeshData.new()
	ground.add_box(Transform3D(Basis.IDENTITY, Vector3(8, -0.5, 2)), Vector3(40, 1, 20), Palette.uv("grass"))
	var ground_instance := MeshInstance3D.new()
	ground_instance.mesh = ground.to_mesh(material)
	world.add_child(ground_instance)

	var x := -2.0
	var focus_x := 0.0
	for i in MODELS.size():
		x += SPACING[i]
		if MODELS[i] == focus:
			focus_x = x
		for lod in 2:
			var md := MeshData.new()
			md.add_arrays(Transform3D(Basis.IDENTITY, Vector3(x, 0, -lod * 7.0)), PropLibrary.arrays(MODELS[i], lod))
			var instance := MeshInstance3D.new()
			instance.mesh = md.to_mesh(material)
			world.add_child(instance)

	var camera := Camera3D.new()
	camera.fov = 40
	world.add_child(camera)
	if focus.is_empty():
		camera.global_position = Vector3(x * 0.5, 7.5, 17.5)
		camera.look_at(Vector3(x * 0.5, 1.2, -2.0))
	else:
		camera.global_position = Vector3(focus_x + 2.5, 3.6, 7.0)
		camera.look_at(Vector3(focus_x, 1.4, 0.0))

	for i in 5:
		await process_frame
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(out)
	print("Gallery saved to ", ProjectSettings.globalize_path(out))
	quit()
