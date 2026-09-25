class_name Player
extends GravityBody
## The player: keyboard or on-screen stick input relative to the camera, or
## a route to follow after a tap (tap-to-walk). Holds a tool for the current
## action and plays small swing and cheer animations.
## Placeholder body built from palette-coloured shapes until the real model.

## The player took control (stick or keys), cancelling any tap-to-walk.
signal steered

## 4 m/s takes about 3.5 minutes to walk around the equator.
@export var walk_speed := 4.0
@export var sprint_multiplier := 1.8
@export var jump_speed := 6.5
@export var turn_speed := 10.0

var camera: PlanetCamera
var joystick: TouchStick
## Off while a menu is open or during a cutscene.
var input_enabled := true

var _visual: MeshInstance3D
var _hand: Node3D
var _tools := {}
var _walk_cycle := 0.0
var _moving := false
var _swing := 0.0
var _cheer := 0.0


func _ready() -> void:
	_visual = MeshInstance3D.new()
	_visual.name = "Body"
	add_child(_visual)
	_hand = Node3D.new()
	_hand.name = "Hand"
	_hand.position = Vector3(0.42, 0.62, 0)
	_visual.add_child(_hand)


## The body shares the planet's palette material, so it's built once the
## planet exists.
func build_visual(material: Material) -> void:
	var md := MeshData.new()
	var root := Transform3D.IDENTITY
	for side in [-1.0, 1.0]:
		md.add_box(root.translated_local(Vector3(0.14 * side, 0.22, 0)), Vector3(0.2, 0.44, 0.22), Palette.uv("pants"))
	md.add_prism(root.translated_local(Vector3(0, 0.4, 0)), 0.36, 0.3, 0.62, 7, Palette.uv("jacket"))
	md.add_prism(root.translated_local(Vector3(0, 0.98, 0)), 0.3, 0.26, 0.14, 7, Palette.uv("scarf"))
	md.add_blob(root.translated_local(Vector3(0, 1.38, 0)), Vector3(0.36, 0.34, 0.34), Palette.uv("skin"), 1)
	md.add_blob(root.translated_local(Vector3(0, 1.5, 0.06)), Vector3(0.38, 0.24, 0.36), Palette.uv("hair"), 1)
	# Nose, so it's clear which way the placeholder faces (-Z is forward).
	md.add_box(root.translated_local(Vector3(0, 1.36, -0.35)), Vector3(0.1, 0.1, 0.1), Palette.uv("skin"))
	md.add_box(root.translated_local(Vector3(0, 0.72, 0.34)), Vector3(0.44, 0.5, 0.2), Palette.uv("wood"))
	for side in [-1.0, 1.0]:
		md.add_blob(root.translated_local(Vector3(0.42 * side, 0.62, 0)), Vector3(0.12, 0.12, 0.12), Palette.uv("skin"), 0)
	_visual.mesh = md.to_mesh(material)
	_build_tools(material)


func is_moving() -> bool:
	return _moving


## Shows a tool in hand: "rod", "net", "axe", "pick" or "" for none.
func hold(tool: String) -> void:
	for name: String in _tools:
		_tools[name].visible = name == tool


## Plays a quick tool swing.
func swing() -> void:
	_swing = 1.0


## A happy hop, for a good catch or sale.
func cheer() -> void:
	_cheer = 1.0


## Turns to face a world position.
func face(world_position: Vector3) -> void:
	heading = SphereMath.tangent(world_position - global_position, get_up())


func _process(delta: float) -> void:
	if planet == null:
		return
	var input := Vector2.ZERO
	if input_enabled:
		input = Input.get_vector("move_left", "move_right", "move_back", "move_forward")
		if joystick:
			input = (input + joystick.value).limit_length(1.0)
	var up := get_up()
	var wish := Vector3.ZERO
	var sprinting := Input.is_action_pressed("sprint") and input_enabled
	if input.length() > 0.05:
		if has_route():
			set_route(PackedVector3Array())
			steered.emit()
		var forward := camera.surface_forward if camera else heading
		var right := forward.cross(up)
		wish = forward * input.y + right * input.x
		var speed := walk_speed * (sprint_multiplier if sprinting else 1.0)
		move_along_surface(wish * speed * delta)
	elif has_route():
		wish = follow_route(delta, walk_speed * 1.2)
	if wish.length() > 0.05:
		turn_towards(wish, turn_speed * delta)
	if input_enabled and Input.is_action_just_pressed("jump") and on_ground:
		vertical_speed = jump_speed
		on_ground = false
	update_vertical(delta)
	_moving = wish.length() > 0.05
	_animate(delta, wish.length())


## A little hop while walking stands in for a walk animation.
func _animate(delta: float, amount: float) -> void:
	if amount > 0.05 and on_ground:
		_walk_cycle += delta * 13.0
	else:
		_walk_cycle = move_toward(_walk_cycle, ceilf(_walk_cycle / PI) * PI, delta * 13.0)
	_visual.position.y = absf(sin(_walk_cycle)) * 0.08
	if _cheer > 0.0:
		_cheer = maxf(_cheer - delta * 1.6, 0.0)
		_visual.position.y += sin(_cheer * PI * 2.0) ** 2 * 0.35
	# Tool swing: raise back, then chop forward.
	if _swing > 0.0:
		_swing = maxf(_swing - delta * 2.6, 0.0)
		var t := 1.0 - _swing
		_hand.rotation.x = (t / 0.35 * 1.4) if t < 0.35 else lerpf(1.4, -1.1, minf((t - 0.35) / 0.3, 1.0))
	else:
		_hand.rotation.x = move_toward(_hand.rotation.x, 0.0, delta * 4.0)


func _build_tools(material: Material) -> void:
	for tool in _tools.values():
		tool.queue_free()
	_tools.clear()
	var handle := Palette.uv("wood")
	var shapes := {
		"rod": func(md: MeshData) -> void:
			md.add_prism(Transform3D(Basis(Vector3.RIGHT, -0.9), Vector3.ZERO), 0.035, 0.015, 1.9, 5, handle)
			md.add_prism(Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0.06, 0.05, 0)), 0.07, 0.07, 0.06, 8, Palette.uv("stone_dark")),
		"net": func(md: MeshData) -> void:
			md.add_prism(Transform3D(Basis(Vector3.RIGHT, -0.7), Vector3.ZERO), 0.03, 0.03, 1.3, 5, handle)
			var hoop := Transform3D(Basis(Vector3.RIGHT, -0.7), Vector3.ZERO).translated_local(Vector3(0, 1.5, 0))
			md.add_prism(hoop.rotated_local(Vector3.RIGHT, PI / 2).translated_local(Vector3(0, -0.02, 0)), 0.26, 0.26, 0.04, 10, Palette.uv("awning_white"))
			md.add_prism(hoop.rotated_local(Vector3.RIGHT, PI / 2).translated_local(Vector3(0, -0.36, 0)), 0.02, 0.24, 0.34, 8, Palette.uv("cloud")),
		"axe": func(md: MeshData) -> void:
			md.add_prism(Transform3D(Basis(Vector3.RIGHT, -0.4), Vector3.ZERO), 0.035, 0.03, 0.8, 5, handle)
			md.add_box(Transform3D(Basis(Vector3.RIGHT, -0.4), Vector3.ZERO).translated_local(Vector3(0, 0.72, -0.1)), Vector3(0.05, 0.2, 0.24), Palette.uv("stone_light")),
		"pick": func(md: MeshData) -> void:
			md.add_prism(Transform3D(Basis(Vector3.RIGHT, -0.4), Vector3.ZERO), 0.035, 0.03, 0.8, 5, handle)
			md.add_box(Transform3D(Basis(Vector3.RIGHT, -0.4), Vector3.ZERO).translated_local(Vector3(0, 0.74, 0)), Vector3(0.06, 0.07, 0.56), Palette.uv("stone_light")),
	}
	for name: String in shapes:
		var md := MeshData.new()
		shapes[name].call(md)
		var tool := MeshInstance3D.new()
		tool.name = name
		tool.mesh = md.to_mesh(material)
		tool.visible = false
		_hand.add_child(tool)
		_tools[name] = tool
