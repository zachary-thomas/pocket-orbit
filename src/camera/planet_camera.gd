class_name PlanetCamera
extends Camera3D
## Third-person camera that works anywhere on a sphere.
##
## It never refers to a global "north". It keeps its own heading, a unit
## vector in the ground plane under the player, and every frame re-projects
## that heading onto the new ground plane (parallel transport). Walking over a
## pole, the view simply carries on instead of spinning around.
##
## The camera sits low and a little behind, so the horizon visibly curves.
## Orbit view pulls back to see the whole planet.

@export var distance := 8.5
@export var min_distance := 4.0
@export var max_distance := 22.0
## Angle above the ground plane, looking down at the player.
@export var pitch_degrees := 16.0
@export var focus_height := 1.3
@export var drag_sensitivity := 0.006
@export var key_turn_speed := 2.0
## Orbit view blend speed (full transition in 1 / speed seconds).
@export var orbit_blend_speed := 0.9

var target: GravityBody
var planet: Planet
## The camera's heading along the ground; the player moves relative to it.
var surface_forward := Vector3.FORWARD
var orbit_mode := false

var _orbit_blend := 0.0
var _orbit_dir := Vector3.UP
var _orbit_up := Vector3.FORWARD
var _orbit_distance := 400.0
var _camera_tile := 0
var _drag_touch := -1
## Ground direction the camera is easing round to face, or zero.
var _turn_toward := Vector3.ZERO


func _ready() -> void:
	near = 0.1
	far = 5000.0
	fov = 55.0


## Put the camera behind the target, looking the way it faces.
func reset_behind() -> void:
	surface_forward = target.heading
	orbit_mode = false
	_orbit_blend = 0.0


func set_orbit_mode(enabled: bool, instant: bool = false) -> void:
	if enabled and not orbit_mode:
		# Start straight above the player, with their forward pointing up.
		_orbit_dir = target.get_up()
		_orbit_up = surface_forward
		_orbit_distance = planet.data.radius * 3.4
	orbit_mode = enabled
	if instant:
		_orbit_blend = 1.0 if enabled else 0.0


## Eases the view round to look along `direction` (a ground-plane vector),
## e.g. toward where the player is fishing. Dragging the camera cancels it.
func turn_toward(direction: Vector3) -> void:
	_turn_toward = direction


## Orbit view from a given direction (used by the screenshot tour).
func look_from(direction: Vector3, up_hint: Vector3, radii: float) -> void:
	orbit_mode = true
	_orbit_blend = 1.0
	_orbit_dir = direction.normalized()
	_orbit_up = SphereMath.tangent(up_hint, _orbit_dir)
	_orbit_distance = planet.data.radius * radii


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_RIGHT:
		_drag(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom(-1.0)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom(1.0)
	elif event is InputEventScreenTouch:
		if event.pressed and _drag_touch == -1 and not _is_over_ui(event.position):
			_drag_touch = event.index
		elif not event.pressed and event.index == _drag_touch:
			_drag_touch = -1
	elif event is InputEventScreenDrag and event.index == _drag_touch:
		_drag(event.relative)


func _process(delta: float) -> void:
	if target == null or planet == null:
		return
	var up := target.get_up()
	surface_forward = SphereMath.tangent(surface_forward, up)
	var turn := Input.get_axis("camera_left", "camera_right")
	if turn != 0.0 and not orbit_mode:
		surface_forward = surface_forward.rotated(up, -turn * key_turn_speed * delta)
		_turn_toward = Vector3.ZERO
	if _turn_toward != Vector3.ZERO:
		var goal := SphereMath.tangent(_turn_toward, up)
		surface_forward = SphereMath.tangent(surface_forward.slerp(goal, minf(delta * 2.5, 1.0)), up)
		if surface_forward.angle_to(goal) < 0.02:
			_turn_toward = Vector3.ZERO

	_orbit_blend = move_toward(_orbit_blend, 1.0 if orbit_mode else 0.0, delta * orbit_blend_speed)
	var t := smoothstep(0.0, 1.0, _orbit_blend)
	if t <= 0.0:
		global_transform = _surface_transform(up)
	elif t >= 1.0:
		global_transform = _orbit_transform()
	else:
		global_transform = _surface_transform(up).interpolate_with(_orbit_transform(), t)


func _surface_transform(up: Vector3) -> Transform3D:
	var center := planet.global_position
	var focus := target.global_position + up * focus_height
	var pitch := deg_to_rad(pitch_degrees)
	var pos := focus + (-surface_forward * cos(pitch) + up * sin(pitch)) * distance
	# Keep the camera above whatever terrain (or water) it ends up over.
	var from_center := pos - center
	var dir := from_center.normalized()
	_camera_tile = planet.find_tile_dir(dir, _camera_tile)
	var min_radius := maxf(planet.ground_radius(_camera_tile), planet.data.sea_level_radius) + 0.7
	if from_center.length() < min_radius:
		pos = center + dir * min_radius
	return Transform3D(Basis.looking_at(focus - pos, up), pos)


func _orbit_transform() -> Transform3D:
	var pos := planet.global_position + _orbit_dir * _orbit_distance
	return Transform3D(Basis.looking_at(-_orbit_dir, _orbit_up), pos)


func _drag(relative: Vector2) -> void:
	if orbit_mode:
		# Spin the globe: turn around the screen's up axis, then tilt.
		_orbit_dir = _orbit_dir.rotated(_orbit_up, -relative.x * drag_sensitivity).normalized()
		var right := _orbit_up.cross(_orbit_dir).normalized()
		_orbit_dir = _orbit_dir.rotated(right, -relative.y * drag_sensitivity).normalized()
		_orbit_up = SphereMath.tangent(_orbit_up.rotated(right, -relative.y * drag_sensitivity), _orbit_dir)
	else:
		_turn_toward = Vector3.ZERO
		surface_forward = surface_forward.rotated(target.get_up(), -relative.x * drag_sensitivity)
		pitch_degrees = clampf(pitch_degrees + relative.y * drag_sensitivity * 40.0, 4.0, 60.0)


func _zoom(direction: float) -> void:
	var factor := pow(1.12, direction)
	if orbit_mode:
		var r := planet.data.radius
		_orbit_distance = clampf(_orbit_distance * factor, r * 1.6, r * 7.0)
	else:
		distance = clampf(distance * factor, min_distance, max_distance)


func _is_over_ui(point: Vector2) -> bool:
	for node in get_tree().get_nodes_in_group("ui_blocker"):
		var control := node as Control
		if control and control.is_visible_in_tree() and control.get_global_rect().has_point(point):
			return true
	return false
