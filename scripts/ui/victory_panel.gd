class_name VictoryPanel
extends CanvasLayer
## Fin de partie : le vainqueur, sa victoire, le mot du chroniqueur et le classement final.
## main.gd l'ouvre quand un vainqueur est proclamé (la partie se met en pause). On peut continuer
## la partie (plus aucune victoire ne sera proclamée) ou revenir au menu principal.

signal continue_requested
signal main_menu_requested

var title_label: Label
var _who: Label
var _how: Label
var _story: Label
var _ranking: VBoxContainer
var _art: Widgets.ArtSlot


func _ready() -> void:
	layer = 8
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.03, 0.78)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var window := PanelContainer.new()
	window.theme_type_variation = &"WindowPanel"
	center.add_child(window)
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(560, 0)
	box.add_theme_constant_override("separation", 10)
	window.add_child(box)
	# Emplacement d'illustration (images générées en fin de projet : assets/art/victory).
	_art = Widgets.ArtSlot.new("victory", Vector2(560, 150), Color(1.0, 0.85, 0.45), "faction")
	box.add_child(_art)
	title_label = UiTheme.title("", 34)
	title_label.add_theme_font_override("font", UiTheme.font(300, 4))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title_label)
	_who = UiTheme.title("", 24)
	_who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_who)
	_how = UiTheme.dim("", 15)
	_how.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_how)
	box.add_child(Widgets.NotchHeader.new("", 4))
	_story = UiTheme.paragraph("", 540, 15)
	_story.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_story)
	box.add_child(Widgets.NotchHeader.new("Classement final", 16))
	_ranking = VBoxContainer.new()
	_ranking.add_theme_constant_override("separation", 4)
	box.add_child(_ranking)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 40)
	box.add_child(buttons)
	var cont := Widgets.RoundButton.new("next", "Continuer la partie", 16)
	cont.tooltip_text = "La galaxie continue, mais aucune autre victoire ne sera proclamée."
	cont.pressed.connect(func() -> void: continue_requested.emit())
	buttons.add_child(cont)
	var menu := Widgets.RoundButton.new("back", "Menu principal", 16)
	menu.pressed.connect(func() -> void: main_menu_requested.emit())
	buttons.add_child(menu)


## Affiche la fin de partie vue par viewer (-1 = spectateur).
func open(state: GameState, viewer: int) -> void:
	var w := state.winner
	if w.is_empty():
		return
	var we := state.get_empire(int(w["empire"]))
	var id := String(w["victory"])
	if viewer < 0:
		title_label.text = "FIN DE PARTIE"
	elif int(w["empire"]) == viewer:
		title_label.text = "VICTOIRE" if Array(w.get("allies", [])).is_empty() else "VICTOIRE PARTAGÉE"
	elif Victory.is_winner(state, viewer):
		title_label.text = "VICTOIRE PARTAGÉE"
	else:
		title_label.text = "DÉFAITE"
	_who.text = we.display_name()
	_who.add_theme_color_override("font_color", we.color().lightened(0.25))
	_how.text = "%s  ·  %s" % [Victory.label(id).to_upper(), GameCalendar.date_string(int(w["tick"]))]
	_story.text = Victory.chronicle_text(id, we, w.get("allies", []), state)
	for c in _ranking.get_children():
		_ranking.remove_child(c)
		c.queue_free()
	var rank := Victory.ranking(state)
	for i in rank.size():
		var e := state.get_empire(int(rank[i]["id"]))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var n := Label.new()
		n.text = "%d.  %s" % [i + 1, e.display_name()]
		n.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		n.add_theme_color_override("font_color", e.color().lightened(0.25))
		row.add_child(n)
		var s := Label.new()
		s.theme_type_variation = &"Numbers"
		s.text = "%d" % int(rank[i]["score"])
		row.add_child(s)
		_ranking.add_child(row)
	for e in state.empires:
		if e.eliminated:
			var l := UiTheme.dim("%s : disparu" % e.display_name(), 13)
			_ranking.add_child(l)
	visible = true


func close() -> void:
	visible = false


func is_open() -> bool:
	return visible
