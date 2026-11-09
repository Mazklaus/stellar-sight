class_name BattleReportPanel
extends PanelContainer
## Rapport de bataille, comme l'écran de fin de bataille d'Endless Space 2 : où, quand, qui a gagné,
## et pour chaque camp les vaisseaux engagés, les pertes et les dégâts infligés.
## Simple lecture de state.battle_reports : rien ici ne touche à la simulation.

signal closed

const WIDTH := 660.0

var report: Dictionary = {}
var _title: Label
var _when: Label
var _outcome: Label
var _sides: VBoxContainer
var _state: GameState
var _viewer := 0


func _ready() -> void:
	visible = false
	add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL, UiTheme.LINE_STRONG, 18, 1, 2))
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	custom_minimum_size = Vector2(WIDTH, 0)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	box.add_child(UiTheme.section("Rapport de bataille"))
	_title = UiTheme.title("", 30)
	box.add_child(_title)
	_when = UiTheme.dim("", 14)
	box.add_child(_when)
	_outcome = Label.new()
	_outcome.add_theme_font_size_override("font_size", 18)
	box.add_child(_outcome)
	_sides = VBoxContainer.new()
	_sides.add_theme_constant_override("separation", 10)
	box.add_child(_sides)
	var help := UiTheme.paragraph("Une bataille dure six jours : deux à longue portée (missiles), deux à moyenne (rayons), deux à courte (canons). La tactique de chaque flotte, choisie avant, décide à quelle portée elle donne le meilleur d'elle-même.", WIDTH - 40.0, 13)
	help.theme_type_variation = &"Dim"
	box.add_child(help)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(foot)
	var close := Button.new()
	close.text = "FERMER"
	close.tooltip_text = "Fermer le rapport  (Échap ou B)"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(hide_report)
	foot.add_child(close)


func show_report(state: GameState, viewer: int, r: Dictionary) -> void:
	if r.is_empty():
		return
	_state = state
	_viewer = viewer
	report = r
	_title.text = "Bataille de %s" % String(r.get("system_name", "?"))
	var days := int(r["day"])
	_when.text = "Du %s au %s  ·  %d jour%s de combat" % [GameCalendar.date_string(int(r["start"])), GameCalendar.date_string(int(r["end"])),
			days, "s" if days > 1 else ""]
	var winner := int(r.get("winner", -1))
	if winner < 0:
		_outcome.text = "Issue indécise : les deux camps tiennent encore le système."
		_outcome.add_theme_color_override("font_color", UiTheme.WARN)
	else:
		var we := state.get_empire(winner)
		_outcome.text = "Victoire de %s%s" % [we.display_name(), "  ·  la vôtre" if winner == viewer else ""]
		_outcome.add_theme_color_override("font_color", UiTheme.GOOD if winner == viewer else (UiTheme.BAD if _fought(r, viewer) else UiTheme.TEXT))
	for c in _sides.get_children():
		_sides.remove_child(c)
		c.queue_free()
	for s: Dictionary in r["sides"]:
		_sides.add_child(_side_row(s))
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)


func hide_report() -> void:
	if visible:
		visible = false
		closed.emit()


static func _fought(r: Dictionary, empire_id: int) -> bool:
	for s: Dictionary in r["sides"]:
		if int(s["empire"]) == empire_id:
			return true
	return false


func _side_row(s: Dictionary) -> Control:
	var e := _state.get_empire(int(s["empire"]))
	var panel := PanelContainer.new()
	var style := UiTheme.box(Color(1, 1, 1, 0.035), Color(0, 0, 0, 0), 10, 0)
	style.border_width_left = 3
	style.border_color = e.color()
	panel.add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	var name_box := VBoxContainer.new()
	name_box.custom_minimum_size = Vector2(190, 0)
	row.add_child(name_box)
	var n := UiTheme.title(e.short_name(), 20, e.color().lightened(0.3))
	name_box.add_child(n)
	name_box.add_child(UiTheme.dim("Dégâts infligés : %d" % int(s["dealt"]), 13))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(grid)
	grid.add_child(UiTheme.dim("Engagés", 13))
	grid.add_child(_value(Combat.ships_text(s["engaged"]), UiTheme.TEXT))
	grid.add_child(UiTheme.dim("Perdus", 13))
	var lost: Dictionary = s["lost"]
	grid.add_child(_value(Combat.ships_text(lost) if not lost.is_empty() else "aucun", UiTheme.BAD if not lost.is_empty() else UiTheme.GOOD))
	return panel


func _value(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(320, 0)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", color)
	return l
