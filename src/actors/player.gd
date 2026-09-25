class_name Player
extends GravityBody
## The player: keyboard or on-screen stick input, relative to the camera.
## Placeholder body built from palette-coloured shapes until the real model.

## 4 m/s takes about 3.5 minutes to walk around the equator.
@export var walk_speed := 4.0
@export var sprint_multiplier := 1.8
@export var jump_speed := 6.5
@export var turn_speed := 10.0

var camera: PlanetCamera
var joystick: TouchStick

var _visual: MeshInstance3D
var _walk_cycle := 0.0


func _ready() -> void:
	_visual = MeshInstance3D.new()
	_visual.name = "Body"
	add_child(_visual)


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


func _process(delta: float) -> void:
	if planet == null:
		return
	var input := Input.get_vector("move_left", "move_right", "move_back", "move_forward")
	if joystick:
		input = (input + joystick.value).limit_length(1.0)
	var up := get_up()
	var forward := camera.surface_forward if camera else heading
	var right := forward.cross(up)
	var wish := forward * input.y + right * input.x
	var speed := walk_speed * (sprint_multiplier if Input.is_action_pressed("sprint") else 1.0)
	move_along_surface(wish * speed * delta)
	if wish.length() > 0.05:
		turn_towards(wish, turn_speed * delta)
	if Input.is_action_just_pressed("jump") and on_ground:
		vertical_speed = jump_speed
		on_ground = false
	update_vertical(delta)
	_animate(delta, wish.length())


## A little hop while walking stands in for a walk animation.
func _animate(delta: float, amount: float) -> void:
	if amount > 0.05 and on_ground:
		_walk_cycle += delta * 13.0
	else:
		_walk_cycle = move_toward(_walk_cycle, ceilf(_walk_cycle / PI) * PI, delta * 13.0)
	_visual.position.y = absf(sin(_walk_cycle)) * 0.08
