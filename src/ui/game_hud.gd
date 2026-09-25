class_name GameHud
extends CanvasLayer
## The in-game interface, laid out like the U2 mockup: time and date top
## left, Stardust top right, the stick bottom left, and a big action button
## with the backpack button bottom right. Toasts appear top centre. Menus
## (bag, stall, storage, Vessa) open over a dimmed game.

signal ui_open_changed(open: bool)

var game: Game
var interactions: Interactions
var joystick: TouchStick

var _root: Control
var _time: Label
var _date: Label
var _stardust: Label
var _debt: Label
var _action: Button
var _action_hint: Label
var _toasts: VBoxContainer
var _dim: ColorRect
var _panel_host: CenterContainer
var _panels := {}
var _open: GamePanel
var _shown_stardust := -1.0


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiTheme.get_theme()
	add_child(_root)

	# Top left: time and date.
	var time_pill := PanelContainer.new()
	time_pill.add_theme_stylebox_override("panel", UiTheme.pill_style())
	time_pill.position = Vector2(24, 20)
	_root.add_child(time_pill)
	var time_box := VBoxContainer.new()
	time_box.add_theme_constant_override("separation", -4)
	time_pill.add_child(time_box)
	_time = UiTheme.label("", 30, UiTheme.CREAM)
	time_box.add_child(_time)
	_date = UiTheme.label("", 15, Color(UiTheme.CREAM, 0.8))
	time_box.add_child(_date)

	# Top right: Stardust, and the debt under it.
	var money := VBoxContainer.new()
	money.anchor_left = 1.0
	money.anchor_right = 1.0
	money.offset_left = -300
	money.offset_right = -24
	money.offset_top = 20
	money.alignment = BoxContainer.ALIGNMENT_END
	_root.add_child(money)
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UiTheme.pill_style())
	pill.size_flags_horizontal = Control.SIZE_SHRINK_END
	money.add_child(pill)
	var pill_row := HBoxContainer.new()
	pill_row.add_theme_constant_override("separation", 10)
	pill.add_child(pill_row)
	var star := _StarIcon.new()
	star.custom_minimum_size = Vector2(30, 30)
	star.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pill_row.add_child(star)
	_stardust = UiTheme.label("", 28, UiTheme.CREAM)
	pill_row.add_child(_stardust)
	_debt = UiTheme.label("", 15, UiTheme.CREAM)
	_debt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_debt.add_theme_constant_override("outline_size", 6)
	_debt.add_theme_color_override("font_outline_color", Color(UiTheme.NAVY, 0.8))
	money.add_child(_debt)

	# Bottom left: the stick.
	joystick = TouchStick.new()
	joystick.anchor_top = 1.0
	joystick.anchor_bottom = 1.0
	joystick.offset_left = 48.0
	joystick.offset_right = 48.0 + joystick.radius * 2.0
	joystick.offset_top = -48.0 - joystick.radius * 2.0
	joystick.offset_bottom = -48.0
	_root.add_child(joystick)

	# Bottom right: action and backpack.
	_action = Button.new()
	_action.focus_mode = Control.FOCUS_NONE
	_action.anchor_left = 1.0
	_action.anchor_right = 1.0
	_action.anchor_top = 1.0
	_action.anchor_bottom = 1.0
	_action.offset_left = -196
	_action.offset_right = -48
	_action.offset_top = -196
	_action.offset_bottom = -48
	_action.add_theme_font_size_override("font_size", 26)
	var round := UiTheme.box(UiTheme.AMBER, 74, UiTheme.CREAM, 5, 5)
	_action.add_theme_stylebox_override("normal", round)
	_action.add_theme_stylebox_override("hover", UiTheme.box(UiTheme.AMBER_LIGHT, 74, UiTheme.CREAM, 5, 5))
	_action.add_theme_stylebox_override("pressed", UiTheme.box(UiTheme.AMBER_DARK, 74, UiTheme.CREAM, 5, 0))
	_action.add_theme_stylebox_override("disabled", UiTheme.box(Color(UiTheme.CREAM_DARK, 0.7), 74, Color(UiTheme.CREAM, 0.6), 5, 5))
	_action.pressed.connect(func() -> void: interactions.press_action())
	_action.add_to_group("ui_blocker")
	_root.add_child(_action)
	_action_hint = UiTheme.label("", 15, UiTheme.CREAM)
	_action_hint.add_theme_constant_override("outline_size", 6)
	_action_hint.add_theme_color_override("font_outline_color", Color(UiTheme.NAVY, 0.8))
	_action_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_action_hint.anchor_left = 1.0
	_action_hint.anchor_right = 1.0
	_action_hint.anchor_top = 1.0
	_action_hint.anchor_bottom = 1.0
	_action_hint.offset_left = -230
	_action_hint.offset_right = -14
	_action_hint.offset_top = -44
	_action_hint.offset_bottom = -16
	_root.add_child(_action_hint)

	var bag := UiTheme.quiet_button("Bag", func() -> void: toggle_panel("bag"), Vector2(96, 96))
	bag.anchor_left = 1.0
	bag.anchor_right = 1.0
	bag.anchor_top = 1.0
	bag.anchor_bottom = 1.0
	bag.offset_left = -320
	bag.offset_right = -224
	bag.offset_top = -150
	bag.offset_bottom = -54
	bag.add_theme_stylebox_override("normal", UiTheme.box(UiTheme.NAVY, 48, UiTheme.CREAM, 4, 4))
	bag.add_to_group("ui_blocker")
	_root.add_child(bag)

	# Toasts, bottom centre between the stick and the buttons.
	_toasts = VBoxContainer.new()
	_toasts.anchor_left = 0.5
	_toasts.anchor_right = 0.5
	_toasts.anchor_top = 1.0
	_toasts.anchor_bottom = 1.0
	_toasts.offset_left = -330
	_toasts.offset_right = 330
	_toasts.offset_top = -230
	_toasts.offset_bottom = -30
	_toasts.alignment = BoxContainer.ALIGNMENT_END
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toasts.add_theme_constant_override("separation", 8)
	_root.add_child(_toasts)

	# Menus.
	_dim = ColorRect.new()
	_dim.color = Color(0.06, 0.05, 0.14, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	_dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			close_panel())
	_root.add_child(_dim)
	_panel_host = CenterContainer.new()
	_panel_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel_host)
	# Toasts stay above menus.
	_root.move_child(_toasts, -1)


func setup(p_game: Game, p_interactions: Interactions) -> void:
	game = p_game
	interactions = p_interactions
	close_panel()
	for panel in _panels.values():
		panel.queue_free()
	_panels = {
		"bag": BagPanel.new(game),
		"shop": ShopPanel.new(game),
		"storage": StoragePanel.new(game),
		"vessa": VessaPanel.new(game),
	}
	for panel: GamePanel in _panels.values():
		panel.visible = false
		panel.close_requested.connect(close_panel)
		_panel_host.add_child(panel)
	if not game.toast.is_connected(show_toast):
		game.toast.connect(show_toast)
	if not interactions.panel_requested.is_connected(open_panel):
		interactions.panel_requested.connect(open_panel)
		interactions.target_changed.connect(_on_target)
	_on_target(interactions.current)
	_shown_stardust = game.state.stardust


func is_panel_open() -> bool:
	return _open != null


func open_panel(name: String) -> void:
	close_panel()
	_open = _panels[name]
	_open.visible = true
	_open.open()
	_dim.visible = true
	ui_open_changed.emit(true)


func close_panel() -> void:
	if _open:
		_open.closed()
		_open.visible = false
		_open = null
	if _dim:
		_dim.visible = false
	ui_open_changed.emit(false)


func toggle_panel(name: String) -> void:
	if _open == _panels.get(name):
		close_panel()
	else:
		open_panel(name)


func show_toast(text: String) -> void:
	var pill := PanelContainer.new()
	pill.add_theme_stylebox_override("panel", UiTheme.box(Color(UiTheme.CREAM, 0.95), 20, UiTheme.WOOD, 3, 2))
	pill.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var label := UiTheme.label(text, 20)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if text.length() > 48:
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size = Vector2(560, 0)
	pill.add_child(label)
	_toasts.add_child(pill)
	while _toasts.get_child_count() > 3:
		var oldest := _toasts.get_child(0)
		_toasts.remove_child(oldest)
		oldest.queue_free()
	var tween := pill.create_tween()
	pill.modulate.a = 0.0
	tween.tween_property(pill, "modulate:a", 1.0, 0.15)
	tween.tween_interval(2.8)
	tween.tween_property(pill, "modulate:a", 0.0, 0.4)
	tween.tween_callback(pill.queue_free)


func _unhandled_input(event: InputEvent) -> void:
	if game == null:
		return
	if event.is_action_pressed("bag"):
		toggle_panel("bag")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel") and _open:
		close_panel()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if game == null or game.state == null:
		return
	var hours := game.home_hours()
	var minutes := int(hours * 60.0)
	@warning_ignore("integer_division")
	_time.text = "%02d:%02d" % [minutes / 60, minutes % 60]
	_date.text = "%s  ·  %s" % [date_label(game.sky.day_index), "stall busy" if not game.is_night_at_home() else "night, fewer customers"]
	# Count Stardust up or down toward the real amount.
	var target := float(game.state.stardust)
	_shown_stardust = move_toward(_shown_stardust, target, maxf(absf(target - _shown_stardust) * 6.0, 30.0) * delta)
	_stardust.text = VessaPanel._thousands(roundi(_shown_stardust))
	_debt.text = "Owe Vessa %s" % VessaPanel._thousands(game.state.debt) if game.state.debt > 0 else "Debt paid!"


func _on_target(target: Dictionary) -> void:
	var label: String = target.get("label", "")
	_action.text = label if label != "" else "·"
	_action.disabled = label == ""
	_action_hint.text = "" if label == "" else "E / tap"


## "Tue 24 Sep" for a day index (days since 1 Jan 1970).
static func date_label(day_index: int) -> String:
	var d := Time.get_datetime_dict_from_unix_time(day_index * 86400)
	var weekdays := ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
	var months := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
	return "%s %d %s" % [weekdays[d.weekday], d.day, months[d.month - 1]]


## The four-pointed Stardust star.
class _StarIcon:
	extends Control

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		var points := PackedVector2Array()
		for i in 8:
			var a := -PI / 2 + TAU * i / 8.0
			points.append(c + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.38))
		draw_colored_polygon(points, UiTheme.AMBER_LIGHT)
		draw_circle(c, r * 0.18, Color.WHITE)
