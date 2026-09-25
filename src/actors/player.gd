class_name Player
extends GravityBody
## The player: keyboard or on-screen stick input relative to the camera, or
## a route to follow after a tap (tap-to-walk). Holds a tool for the current
## action and plays small swing and cheer animations.
## The body follows the explorer turnaround sheet: big head with goggles,
## patched flight jacket, red scarf, green trousers, boots and a backpack with
## a bedroll. It's built from palette-coloured shapes, with the arms and legs
## as separate pieces so they can swing while walking.

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
var _legs: Array[MeshInstance3D] = []
var _arms: Array[MeshInstance3D] = []
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
	for side in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		leg.position = Vector3(0.13 * side, 0.46, 0)
		_visual.add_child(leg)
		_legs.append(leg)
		var arm := MeshInstance3D.new()
		arm.position = Vector3(0.3 * side, 0.86, 0)
		_visual.add_child(arm)
		_arms.append(arm)
	_hand = Node3D.new()
	_hand.name = "Hand"
	# In the right arm, at the hand.
	_hand.position = Vector3(0.08, -0.28, 0)
	_arms[1].add_child(_hand)


## The body shares the planet's palette material, so it's built once the
## planet exists. -Z is forward.
func build_visual(material: Material) -> void:
	var md := MeshData.new()
	var root := Transform3D.IDENTITY
	# Jacket with a belt, buckle and pockets; cream shirt at the collar.
	md.add_prism(root.translated_local(Vector3(0, 0.42, 0)), 0.33, 0.27, 0.5, 8, Palette.uv("jacket"))
	md.add_prism(root.translated_local(Vector3(0, 0.5, 0)), 0.335, 0.33, 0.07, 8, Palette.uv("boots"))
	md.add_box(root.translated_local(Vector3(0, 0.535, -0.33)), Vector3(0.1, 0.07, 0.03), Palette.uv("goggle_rim"))
	for side in [-1.0, 1.0]:
		var pocket := root.translated_local(Vector3(0.17 * side, 0.64, -0.28)).rotated_local(Vector3.UP, 0.35 * side)
		md.add_box(pocket, Vector3(0.14, 0.12, 0.05), Palette.uv("jacket"))
		md.add_box(pocket.translated_local(Vector3(0, 0.05, -0.01)), Vector3(0.14, 0.04, 0.05), Palette.uv("bag"))
	md.add_box(root.translated_local(Vector3(0, 0.8, -0.2)), Vector3(0.16, 0.14, 0.1), Palette.uv("cuff"))
	md.add_box(root.translated_local(Vector3(0.22, 0.74, 0.19)).rotated_local(Vector3.UP, 0.8), Vector3(0.1, 0.08, 0.02), Palette.uv("scarf"))
	# Scarf: a ring round the neck with a tail hanging down the front.
	md.add_prism(root.translated_local(Vector3(0, 0.86, 0)), 0.25, 0.21, 0.13, 8, Palette.uv("scarf"))
	md.add_box(root.translated_local(Vector3(0.12, 0.72, -0.25)).rotated_local(Vector3.FORWARD, 0.1), Vector3(0.1, 0.28, 0.04), Palette.uv("scarf"))
	# Big round head: hair on top with a fringe and a tuft, ears, face.
	var head := root.translated_local(Vector3(0, 1.28, 0))
	md.add_blob(head, Vector3(0.42, 0.39, 0.4), Palette.uv("skin"), 1)
	md.add_blob(head.translated_local(Vector3(0, 0.13, 0.05)), Vector3(0.45, 0.33, 0.42), Palette.uv("hair"), 1)
	for k in 5:
		var a := -0.9 + k * 0.45
		md.add_blob(head.translated_local(Vector3(sin(a) * 0.3, 0.18, -cos(a) * 0.3)).rotated_local(Vector3.RIGHT, -0.5), Vector3(0.12, 0.15, 0.08), Palette.uv("hair"))
	md.add_prism(head.translated_local(Vector3(0.02, 0.38, 0.04)).rotated_local(Vector3.BACK, -0.25), 0.1, 0.0, 0.16, 5, Palette.uv("hair"))
	for side in [-1.0, 1.0]:
		md.add_blob(head.translated_local(Vector3(0.41 * side, -0.02, 0.02)), Vector3(0.07, 0.1, 0.07), Palette.uv("skin"))
		md.add_blob(head.translated_local(Vector3(0.15 * side, -0.03, -0.37)), Vector3(0.05, 0.075, 0.03), Palette.uv("eye"))
		md.add_blob(head.translated_local(Vector3(0.25 * side, -0.13, -0.32)), Vector3(0.06, 0.035, 0.03), Palette.uv("blush"))
	md.add_box(head.translated_local(Vector3(0, -0.14, -0.385)), Vector3(0.07, 0.015, 0.02), Palette.uv("eye"))
	# Goggles pushed up on the forehead, with the strap round the head.
	md.add_prism(head.translated_local(Vector3(0, 0.19, 0)), 0.455, 0.44, 0.08, 10, Palette.uv("jacket"))
	for side in [-1.0, 1.0]:
		var goggle := head.translated_local(Vector3(0.15 * side, 0.25, -0.33)).rotated_local(Vector3.RIGHT, -PI * 0.5 + 0.35)
		md.add_prism(goggle, 0.14, 0.13, 0.08, 10, Palette.uv("goggle_rim"))
		md.add_prism(goggle.translated_local(Vector3(0, 0.05, 0)), 0.1, 0.09, 0.04, 8, Palette.uv("goggle_lens"))
	# Backpack with a flap, a rolled bedroll on top and a little star charm.
	md.add_box(root.translated_local(Vector3(0, 0.62, 0.33)), Vector3(0.42, 0.4, 0.2), Palette.uv("bag"))
	md.add_box(root.translated_local(Vector3(0, 0.66, 0.44)), Vector3(0.28, 0.16, 0.05), Palette.uv("jacket"))
	md.add_prism(root.translated_local(Vector3(-0.3, 0.89, 0.32)).rotated_local(Vector3.BACK, -PI * 0.5), 0.1, 0.1, 0.6, 8, Palette.uv("bedroll"))
	md.add_blob(root.translated_local(Vector3(0.22, 0.46, 0.45)), Vector3(0.05, 0.05, 0.02), Palette.uv("gold"))
	_visual.mesh = md.to_mesh(material)

	# Legs hang from the hip: trouser, cream boot cuff, chunky boot.
	var leg := MeshData.new()
	leg.add_prism(Transform3D(Basis.IDENTITY, Vector3(0, -0.3, 0)), 0.1, 0.11, 0.3, 7, Palette.uv("pants"))
	leg.add_prism(Transform3D(Basis.IDENTITY, Vector3(0, -0.36, 0)), 0.12, 0.12, 0.1, 7, Palette.uv("cuff"))
	leg.add_blob(Transform3D(Basis.IDENTITY, Vector3(0, -0.38, -0.04)), Vector3(0.12, 0.08, 0.17), Palette.uv("boots"), 1)
	leg.add_prism(Transform3D(Basis.IDENTITY, Vector3(0, -0.46, -0.04)), 0.13, 0.13, 0.03, 8, Palette.uv("cuff"))
	var leg_mesh := leg.to_mesh(material)
	for part in _legs:
		part.mesh = leg_mesh
	# Arms hang from the shoulder, angled out a little: sleeve, cuff, hand.
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var arm := MeshData.new()
		var out := Transform3D(Basis(Vector3.BACK, 0.25 * side), Vector3.ZERO)
		arm.add_prism(out.translated_local(Vector3(0, -0.22, 0)), 0.085, 0.1, 0.22, 7, Palette.uv("jacket"))
		arm.add_prism(out.translated_local(Vector3(0, -0.25, 0)), 0.095, 0.095, 0.06, 7, Palette.uv("cuff"))
		arm.add_blob(out.translated_local(Vector3(0, -0.3, 0)), Vector3(0.1, 0.1, 0.1), Palette.uv("skin"), 1)
		_arms[i].mesh = arm.to_mesh(material)
	_build_tools(material)


## Whether no tool is out (the tool arm swings freely when walking).
func _tools_hidden() -> bool:
	for name: String in _tools:
		if _tools[name].visible:
			return false
	return true


func is_moving() -> bool:
	return _moving


## Shows a tool in hand: "rod", "net", "axe", "pick", "shovel" or "" for none.
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


## Walk cycle: legs and arms swing opposite each other, with a small bob.
func _animate(delta: float, amount: float) -> void:
	if amount > 0.05 and on_ground:
		_walk_cycle += delta * 11.0
	else:
		_walk_cycle = move_toward(_walk_cycle, roundf(_walk_cycle / PI) * PI, delta * 11.0)
	var stride := sin(_walk_cycle) * 0.7
	_legs[0].rotation.x = stride
	_legs[1].rotation.x = -stride
	_arms[0].rotation.x = -stride * 0.8
	_arms[1].rotation.x = stride * 0.8 if _tools_hidden() else 0.0
	_visual.position.y = absf(sin(_walk_cycle)) * 0.05
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
		"shovel": func(md: MeshData) -> void:
			var shaft := Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3.ZERO)
			md.add_prism(shaft, 0.03, 0.03, 0.9, 5, handle)
			md.add_box(shaft.translated_local(Vector3(0, -0.02, 0)), Vector3(0.16, 0.04, 0.04), handle)
			md.add_box(shaft.translated_local(Vector3(0, 1.0, 0)), Vector3(0.22, 0.26, 0.03), Palette.uv("stone_light")),
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
