class_name VessaPanel
extends GamePanel
## Talking to Vessa, the smuggler who got you here: the welcome on your first
## day, then paying down your debt and asking for tips.

const INTRO := [
	"There you are! The papers held up, then. Nobody out here asks questions. Welcome to Little Haven.",
	"The stall's yours. Four shelves: put whatever you find on them and set your prices. Travellers pass through all day.",
	"Fish off the shore, sneak up on bugs with the net (don't run, they spook), shake trees for fruit, and chop or mine for materials. Tap anywhere to walk there.",
	"Now, the papers, the stall and the ride out here come to 8,000 Stardust. Pay me back when you can. I'm not going anywhere.",
]
const TIPS := [
	"Price near what a thing's worth today and people leave happy. Happy customers talk, and more come by.",
	"Rare fish bite at night. Colder seas up north have different catches than the warm ones.",
	"Glowbugs and moths come out after dark. The jungle has the fanciest beetles.",
	"Rocks give up minerals a few times a day. Pretty ones sell well when folk want shiny things.",
	"The demand board at the stall changes every day. Stock what people are asking for.",
	"Your pod has a storage chest. Keep the good stuff there for when it's in demand.",
]

var _text: Label
var _replies: VBoxContainer
var _page := 0
var _rng := RandomNumberGenerator.new()


func _init(p_game: Game) -> void:
	super(p_game, "Vessa")
	_rng.randomize()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	body.add_child(row)
	var portrait := _Portrait.new()
	portrait.custom_minimum_size = Vector2(130, 130)
	portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(portrait)
	_text = UiTheme.label("", 21)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(520, 130)
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(_text)
	_replies = VBoxContainer.new()
	_replies.custom_minimum_size = Vector2(250, 0)
	_replies.add_theme_constant_override("separation", 8)
	row.add_child(_replies)


func open() -> void:
	_page = 0 if not game.state.flags.has("met_vessa") else -1
	super()
	_show_page()


## Rebuilding on every state change would wipe replies mid-conversation, so
## this panel drives its own updates.
func refresh() -> void:
	pass


func _show_page() -> void:
	for child in _replies.get_children():
		child.queue_free()
	if _page >= 0:
		_text.text = INTRO[_page]
		if _page < INTRO.size() - 1:
			_reply("Go on", func() -> void:
				_page += 1
				_show_page())
		else:
			_reply("I'll pay you back.", func() -> void:
				game.run({"type": "set_flag", "flag": "met_vessa"})
				_page = -1
				_say("Good. Off you go, then. Come find me when you've got Stardust."))
		return
	_say(_status())


func _say(text: String) -> void:
	_text.text = text
	for child in _replies.get_children():
		child.queue_free()
	var state := game.state
	if state.debt > 0:
		for amount in [100, 1000]:
			var b := _reply("Pay %s" % _thousands(amount), func() -> void: _pay(amount))
			b.disabled = state.stardust < amount or state.debt < amount
		var all := _reply("Pay all I can", func() -> void: _pay(mini(state.stardust, state.debt)))
		all.disabled = state.stardust <= 0
	_reply("Any tips?", func() -> void:
		var hints := Economy.hints(state.world_seed, state.day)
		_say("%s  Word is: \"%s\"" % [TIPS[_rng.randi() % TIPS.size()], hints[_rng.randi() % hints.size()]]))
	_reply("See you", func() -> void: close_requested.emit(), true)


func _pay(amount: int) -> void:
	var result := game.run({"type": "pay_debt", "amount": amount})
	if not result["ok"]:
		return
	if game.state.debt == 0:
		game.run({"type": "set_flag", "flag": "debt_paid"})
		_say("Paid in full. I didn't think you had it in you! You're free and clear. Keep the stall. This place suits you.")
	else:
		_say(["Pleasure doing business.", "Every bit helps.", "Look at you, an honest trader."][_rng.randi() % 3] + "  " + _status())


func _status() -> String:
	var state := game.state
	if state.debt <= 0:
		return "You don't owe me a thing. Stock up, the travellers are hungry for bargains."
	return "You owe me %s Stardust. You've got %s on you." % [_thousands(state.debt), _thousands(state.stardust)]


func _reply(text: String, action: Callable, quiet: bool = false) -> Button:
	var b := UiTheme.quiet_button(text, action) if quiet else UiTheme.button(text, action)
	_replies.add_child(b)
	return b


static func _thousands(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	while s.length() > 3:
		out = "," + s.right(3) + out
		s = s.left(s.length() - 3)
	return ("-" if value < 0 else "") + s + out


## Round portrait of Vessa's fox face.
class _Portrait:
	extends Control

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_circle(c, r, UiTheme.NAVY)
		draw_circle(c, r - 4, UiTheme.NAVY_LIGHT)
		var fur := Color("d9793f")
		for side in [-1.0, 1.0]:
			draw_colored_polygon(PackedVector2Array([c + Vector2(side * 0.18, -0.2) * r, c + Vector2(side * 0.5, -0.72) * r, c + Vector2(side * 0.56, -0.12) * r]), fur)
		draw_circle(c + Vector2(0, 0.08) * r, r * 0.52, fur)
		draw_colored_polygon(PackedVector2Array([c + Vector2(-0.3, 0.12) * r, c + Vector2(0.3, 0.12) * r, c + Vector2(0, 0.55) * r]), Color("fbe8cf"))
		draw_circle(c + Vector2(0, 0.46) * r, r * 0.07, Color("2b2020"))
		for side in [-1.0, 1.0]:
			draw_circle(c + Vector2(side * 0.2, -0.02) * r, r * 0.06, Color("2b2020"))
