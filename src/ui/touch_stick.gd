class_name TouchStick
extends Control
## On-screen stick for touch screens. (Named TouchStick because Godot 4.7 has
## a built-in VirtualJoystick node.) On PC the mouse drives it too, through
## "emulate touch from mouse" in the project settings.

@export var radius := 80.0

## x = right, y = forward (up on screen), length 0..1.
var value := Vector2.ZERO

var _touch := -1
var _knob := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_to_group("ui_blocker")


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and _touch == -1 and get_global_rect().has_point(event.position):
			_touch = event.index
			_move_knob(event.position)
			get_viewport().set_input_as_handled()
		elif not event.pressed and event.index == _touch:
			_touch = -1
			_knob = Vector2.ZERO
			value = Vector2.ZERO
			queue_redraw()
			get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and event.index == _touch:
		_move_knob(event.position)
		get_viewport().set_input_as_handled()


func _move_knob(point: Vector2) -> void:
	_knob = (point - get_global_rect().get_center()).limit_length(radius)
	value = Vector2(_knob.x, -_knob.y) / radius
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	draw_circle(c, radius, Color(1, 1, 1, 0.14))
	draw_arc(c, radius, 0.0, TAU, 48, Color(1, 0.97, 0.9, 0.4), 3.0, true)
	draw_circle(c + _knob, radius * 0.42, Color(1, 0.96, 0.88, 0.5))
