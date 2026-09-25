class_name AuditPanel
extends GamePanel
## Inspector Grell's questions. Every answer adds some suspicion (the
## Confederation suspects everyone); vague or cheeky ones add more. Too much
## and the inspector comes back sooner.

const OPENING := "Inspector Grell, Office of Compliance. Routine inspection of trading premises. I'll ask a few questions. Answer clearly."

var _text: Label
var _answers: VBoxContainer
var _questions := []
var _step := 0


func _init(p_game: Game) -> void:
	super(p_game, "Inspection")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	v.custom_minimum_size = Vector2(700, 0)
	body.add_child(v)
	_text = UiTheme.label("", 22)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(680, 110)
	v.add_child(_text)
	_answers = VBoxContainer.new()
	_answers.add_theme_constant_override("separation", 8)
	v.add_child(_answers)


func open() -> void:
	super()
	_questions = VillageRules.audit_questions(game.state)
	_step = -1
	_show(OPENING, [["Of course, Inspector.", func() -> void: _next()]])


## Rebuilding on every state change would reset the questions.
func refresh() -> void:
	pass


func _show(text: String, replies: Array) -> void:
	_text.text = text
	for child in _answers.get_children():
		child.queue_free()
	for reply: Array in replies:
		var b := UiTheme.quiet_button(reply[0], reply[1], Vector2(680, 52))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		_answers.add_child(b)


func _next() -> void:
	_step += 1
	if _step >= _questions.size():
		var result := game.run({"type": "finish_audit"})
		_show("%s\n\n(Suspicion: %s)" % [result.get("verdict", "Carry on."), _suspicion_word(game.state.audit["suspicion"])],
			[["Good day, Inspector.", func() -> void: close_requested.emit()]])
		return
	var q: Dictionary = _questions[_step]
	var replies := []
	for answer: Array in q["answers"]:
		var points: int = answer[1]
		replies.append([answer[0], func() -> void:
			game.run({"type": "audit_answer", "points": points})
			_next()])
	_show("\"%s\"" % q["q"], replies)


static func _suspicion_word(value: int) -> String:
	if value < 20:
		return "low"
	if value < VillageRules.WATCHLIST:
		return "noted"
	return "high"
