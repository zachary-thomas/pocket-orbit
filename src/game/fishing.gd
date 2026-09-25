class_name Fishing
extends Node3D
## Fishing: cast the bobber into the water, wait for a bite, then press the
## action button while it's under. What bites depends on how cold the water
## is (latitude) and the local time (CatchTables.fish).

signal finished

enum Stage { IDLE, CASTING, WAITING, BITING }

const CAST_TIME := 0.6
const BITE_WINDOW := 1.1

var game: Game
var stage := Stage.IDLE

var _material: Material
var _bobber: MeshInstance3D
var _alert: Label3D
var _line: MeshInstance3D
var _line_mesh := ImmediateMesh.new()
var _target := Vector3.ZERO
var _timer := 0.0
var _rng := RandomNumberGenerator.new()


func setup(p_game: Game, material: Material) -> void:
	game = p_game
	_material = material
	_rng.randomize()
	if _bobber:
		return
	var md := MeshData.new()
	md.add_blob(Transform3D.IDENTITY.translated(Vector3(0, 0.06, 0)), Vector3(0.12, 0.08, 0.12), Palette.uv("awning_white"), 1)
	md.add_blob(Transform3D.IDENTITY.translated(Vector3(0, 0.13, 0)), Vector3(0.09, 0.06, 0.09), Palette.uv("awning_red"), 1)
	_bobber = MeshInstance3D.new()
	_bobber.mesh = md.to_mesh(material)
	add_child(_bobber)
	_alert = Label3D.new()
	_alert.text = "!"
	_alert.font_size = 96
	_alert.pixel_size = 0.008
	_alert.outline_size = 20
	_alert.modulate = UiTheme.AMBER
	_alert.outline_modulate = UiTheme.TEXT
	_alert.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_alert.no_depth_test = true
	_alert.position = Vector3(0, 0.7, 0)
	_bobber.add_child(_alert)
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color = Color(1, 1, 1, 0.8)
	line_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_line = MeshInstance3D.new()
	_line.mesh = _line_mesh
	_line.material_override = line_material
	_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_line)
	_set_visible(false)


func is_active() -> bool:
	return stage != Stage.IDLE


## Casts toward a point on the water surface (world position).
func cast(target: Vector3) -> void:
	_target = target
	stage = Stage.CASTING
	_timer = CAST_TIME
	_set_visible(true)
	_alert.visible = false


## The action button while fishing: hooks the fish during a bite, otherwise
## reels in empty.
func press() -> void:
	match stage:
		Stage.BITING:
			_land_fish()
		Stage.WAITING, Stage.CASTING:
			game.toast.emit("Reeled in. Wait for the bobber to dip!")
			stop()


func stop() -> void:
	stage = Stage.IDLE
	_set_visible(false)
	finished.emit()


func _process(delta: float) -> void:
	if stage == Stage.IDLE:
		return
	var player := game.player
	var up := game.planet.up_at(_target)
	_timer -= delta
	var bob := sin(Time.get_ticks_msec() * 0.004) * 0.04
	var tip := _rod_tip()
	match stage:
		Stage.CASTING:
			var t := 1.0 - _timer / CAST_TIME
			_bobber.global_position = tip.lerp(_target, t) + up * sin(t * PI) * 2.0
			if _timer <= 0.0:
				stage = Stage.WAITING
				_timer = _rng.randf_range(2.0, 6.5)
		Stage.WAITING:
			# The odd nibble before the real bite.
			var nibble := -0.06 if fmod(_timer, 1.7) < 0.12 else 0.0
			_bobber.global_position = _target + up * (bob + nibble)
			if _timer <= 0.0:
				stage = Stage.BITING
				_timer = BITE_WINDOW
				_alert.visible = true
		Stage.BITING:
			_bobber.global_position = _target + up * (-0.22 + bob)
			if _timer <= 0.0:
				game.toast.emit("It got away...")
				stop()
				return
	_bobber.global_transform.basis = SphereMath.basis_from_up(up)
	_draw_line(tip, _bobber.global_position + up * 0.12)
	if player.is_moving():
		stop()


func _rod_tip() -> Vector3:
	var player := game.player
	return player.global_position + player.get_up() * 1.9 + player.heading * 1.1


func _land_fish() -> void:
	var lat := SphereMath.latitude_degrees(game.planet.up_at(_target))
	var fish := CatchTables.fish(_rng, CatchTables.water_kind(lat), game.hours_at(_target), game.season_at(_target))
	if fish == null:
		game.toast.emit("Nothing's biting here right now.")
	else:
		var result := game.run({"type": "collect", "item": fish.id})
		if result.get("ok", false):
			WorldItems.pop(get_parent(), fish.id, game.player.global_position, game.player.get_up(), _material)
			game.player.cheer()
	stop()


func _draw_line(from: Vector3, to: Vector3) -> void:
	_line_mesh.clear_surfaces()
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var up := game.player.get_up()
	for i in 13:
		var t := i / 12.0
		# A little sag in the middle of the line.
		_line_mesh.surface_add_vertex(from.lerp(to, t) - up * sin(t * PI) * 0.35)
	_line_mesh.surface_end()


func _set_visible(on: bool) -> void:
	_bobber.visible = on
	_line.visible = on
	if not on:
		_line_mesh.clear_surfaces()
