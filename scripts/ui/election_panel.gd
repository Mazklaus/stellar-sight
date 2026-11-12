class_name ElectionPanel
extends CanvasLayer
## Fenêtre d'élection (voir Politics), en trois étapes comme celle d'Endless Space 2 :
## Soutien (l'opinion de l'empire avant le vote, et le courant soutenu ou nommé), Dépouillement
## (les représentants élus par système) et Résultats (l'hémicycle, les courants au pouvoir, la
## redistribution des voix). main.gd l'ouvre après l'élection du joueur (pause automatique en solo).

signal closed
signal senate_requested

const WIDTH := 720.0
const STEPS := ["Soutien", "Dépouillement", "Résultats"]

var step := 2
var step_buttons: Array[Button] = []
var _title: Label
var _when: Label
var _body: VBoxContainer
var _state: GameState
var _player := -1


func _ready() -> void:
	layer = 7
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.03, 0.55)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var window := PanelContainer.new()
	window.theme_type_variation = &"WindowPanel"
	center.add_child(window)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(WIDTH, 0)
	box.add_theme_constant_override("separation", 10)
	window.add_child(box)
	_title = UiTheme.title("", 28)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_when = UiTheme.dim("", 13)
	_when.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_when)
	var steps := HBoxContainer.new()
	steps.alignment = BoxContainer.ALIGNMENT_CENTER
	steps.add_theme_constant_override("separation", 4)
	box.add_child(steps)
	for i in STEPS.size():
		var b := Button.new()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(200, 0)
		b.text = "%d. %s" % [i + 1, STEPS[i]]
		var k := i
		b.pressed.connect(func() -> void: show_step(k))
		steps.add_child(b)
		step_buttons.append(b)
	_body = VBoxContainer.new()
	_body.add_theme_constant_override("separation", 6)
	_body.custom_minimum_size = Vector2(WIDTH, 300)
	box.add_child(_body)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 40)
	box.add_child(buttons)
	var senate := Widgets.RoundButton.new("next", "Ouvrir le Sénat (P)", 14)
	senate.pressed.connect(func() -> void: senate_requested.emit())
	buttons.add_child(senate)
	var close_b := Widgets.RoundButton.new("back", "Fermer", 14)
	close_b.pressed.connect(func() -> void: closed.emit())
	buttons.add_child(close_b)


func open(state: GameState, player: int) -> void:
	_state = state
	_player = player
	var reg := Politics.regime(state, player)
	var en := Politics.emp(state, player)
	_title.text = "Élection : %s" % String(reg["label"])
	_when.text = "%s  ·  %s élection de votre règne" % [GameCalendar.date_string(int(en.get("last", state.tick))), _ordinal(int(en.get("n", 1)))]
	visible = true
	show_step(2)


func show_step(i: int) -> void:
	step = clampi(i, 0, STEPS.size() - 1)
	for k in step_buttons.size():
		step_buttons[k].set_pressed_no_signal(k == step)
	for ch in _body.get_children():
		ch.queue_free()
	if _state == null:
		return
	match step:
		0:
			_fill_support()
		1:
			_fill_count()
		_:
			_fill_results()


func _fill_support() -> void:
	var st := _state
	var en := Politics.emp(st, _player)
	var appoint := Politics.mode(st, _player) == "appoint"
	_body.add_child(UiTheme.paragraph(String(Politics.regime(st, _player).get("text", "")), WIDTH - 20.0, 14))
	_body.add_child(Widgets.NotchHeader.new("Opinion de l'empire aujourd'hui", 14))
	var op := Politics.empire_opinion(st, _player)
	for i in Politics.N:
		var l := Label.new()
		@warning_ignore("integer_division")
		l.text = "%s  %d %%" % [Politics.short(st, _player, i), (int(op[i]) + 5) / 10]
		l.add_theme_color_override("font_color", Politics.color(i).lightened(0.2))
		l.add_theme_font_size_override("font_size", 15)
		_body.add_child(l)
	var top := int(en.get("top", -1))
	if appoint and top >= 0:
		_body.add_child(UiTheme.paragraph("Le peuple a voté %s. Au Conclave ou au Kurultaï, c'est le courant nommé qui gouverne." % Politics.label(st, _player, top), WIDTH - 20.0, 13))
	else:
		_body.add_child(UiTheme.paragraph("Avant le prochain vote, soutenez un courant dans l'écran Sénat (P) : il pèsera davantage dans chaque tirage de représentant.", WIDTH - 20.0, 13))


func _fill_count() -> void:
	var st := _state
	var shown := 0
	for sid in Stability.systems_of(st, _player):
		var en := Politics.sys_entry(st, sid)
		var reps: Array = en.get("reps", [])
		if reps.is_empty():
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var nl := Label.new()
		nl.text = st.galaxy.systems[sid].system_name
		nl.custom_minimum_size = Vector2(200, 0)
		nl.add_theme_font_size_override("font_size", 15)
		row.add_child(nl)
		for i in Politics.N:
			if int(reps[i]) <= 0:
				continue
			var l := Label.new()
			l.text = "%s %d" % [Politics.short(st, _player, i), int(reps[i])]
			l.add_theme_color_override("font_color", Politics.color(i).lightened(0.2))
			l.add_theme_font_size_override("font_size", 14)
			row.add_child(l)
		_body.add_child(row)
		shown += 1
		if shown >= 14:
			_body.add_child(UiTheme.dim("… le détail complet est dans l'écran Sénat (P).", 13))
			break
	if shown == 0:
		_body.add_child(UiTheme.dim("Aucun représentant élu.", 14))


func _fill_results() -> void:
	var st := _state
	var en := Politics.emp(st, _player)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	_body.add_child(row)
	var h := SenateScreen.Hemicycle.new()
	var colors := []
	for i in Politics.N:
		colors.append(Politics.color(i))
	h.counts = (en.get("votes", []) as Array).duplicate()
	h.colors = colors
	h.ruling = Politics.ruling(st, _player)
	row.add_child(h)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	row.add_child(side)
	side.add_child(UiTheme.dim("Au pouvoir", 14))
	var final: Array = en.get("final", [])
	var votes: Array = en.get("votes", [])
	for i in Politics.ruling(st, _player):
		var l := Label.new()
		var v := int(final[int(i)]) if not final.is_empty() else 0
		var raw := int(votes[int(i)]) if not votes.is_empty() else 0
		l.text = "%s  %d%s" % [Politics.short(st, _player, int(i)), v, ("  (+%d reçues)" % (v - raw)) if v > raw else ""]
		l.add_theme_color_override("font_color", Politics.color(int(i)).lightened(0.2))
		l.add_theme_font_size_override("font_size", 18)
		side.add_child(l)
	var top := int(en.get("top", -1))
	if Politics.mode(st, _player) == "appoint" and top >= 0 and not Politics.in_power(st, _player, top):
		side.add_child(UiTheme.paragraph("Le peuple avait voté %s.%s" % [Politics.label(st, _player, top),
				(" La nomination a coûté %d de ferveur." % int(en.get("fervor", 0))) if int(en.get("fervor", 0)) > 0 else ""], 260.0, 13))
	else:
		side.add_child(UiTheme.paragraph("Les courants battus donnent leurs voix au vainqueur le plus proche sur la roue, jamais à l'opposé.", 260.0, 12))
	var plus := 0
	var minus := 0
	for sid in Stability.systems_of(st, _player):
		var p := Politics.stability_part(st, sid, _player)
		if p.is_empty():
			continue
		if int(p[1]) > 0:
			plus += 1
		elif int(p[1]) < 0:
			minus += 1
	_body.add_child(UiTheme.paragraph("%d système%s représenté%s au pouvoir (stabilité en hausse), %d dans l'opposition (stabilité en baisse)." % [
			plus, "s" if plus > 1 else "", "s" if plus > 1 else "", minus], WIDTH - 20.0, 14))


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible


static func _ordinal(n: int) -> String:
	return "1re" if n == 1 else "%de" % n
