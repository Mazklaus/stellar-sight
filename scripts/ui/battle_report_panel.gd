class_name BattleReportPanel
extends PanelContainer
## Rapport de bataille, comme l'écran de fin de bataille d'Endless Space 2 : où, quand, qui a gagné,
## et pour chaque camp les vaisseaux engagés, les pertes et les dégâts infligés.
## Simple lecture de state.battle_reports : rien ici ne touche à la simulation.

signal closed
## Le joueur veut revoir la bataille dans la vue de replay.
signal replay_requested(report: Dictionary)

const WIDTH := 660.0

var report: Dictionary = {}
var _title: Label
var _when: Label
var _outcome: Label
var _sides: VBoxContainer
var _state: GameState
var _viewer := 0
var _replay_btn: Button


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
	foot.add_theme_constant_override("separation", 8)
	box.add_child(foot)
	_replay_btn = Button.new()
	_replay_btn.text = "REVOIR LA BATAILLE"
	_replay_btn.tooltip_text = "Rejouer la bataille jour par jour  (R)"
	_replay_btn.focus_mode = Control.FOCUS_NONE
	_replay_btn.pressed.connect(request_replay)
	foot.add_child(_replay_btn)
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
	# Terrain (voir Terrain) : ce qui a pesé sur la bataille, en tête du rapport.
	for tid in r.get("terrain", []):
		var td := Terrain.def(String(tid))
		_when.text += "\nTerrain · %s : %s" % [String(td.get("label", tid)), String(td.get("bad", ""))]
	var winner := int(r.get("winner", -1))
	if winner < 0:
		_outcome.text = "Issue indécise : les deux camps tiennent encore le système."
		_outcome.add_theme_color_override("font_color", UiTheme.WARN)
	else:
		var we := state.get_empire(winner)
		_outcome.text = "Victoire de %s%s" % [we.display_name(), "  ·  la vôtre" if winner == viewer else ""]
		var wrecks: Array = r.get("wrecks", [])
		if not wrecks.is_empty() and (winner == viewer or viewer < 0):
			_outcome.text += "\nÉpaves étudiées : %s." % ", ".join(PackedStringArray(wrecks))
		_outcome.add_theme_color_override("font_color", UiTheme.GOOD if winner == viewer else (UiTheme.BAD if _fought(r, viewer) else UiTheme.TEXT))
	var fallen: Array = r.get("fallen", [])
	if not fallen.is_empty():
		_outcome.text += "\nTombé%s au combat : %s." % ["s" if fallen.size() > 1 else "", ", ".join(PackedStringArray(fallen))]
	for c in _sides.get_children():
		_sides.remove_child(c)
		c.queue_free()
	for s: Dictionary in r["sides"]:
		_sides.add_child(_side_row(s))
	_replay_btn.visible = BattleReplayPanel.has_log(r)
	visible = true
	modulate.a = 0.0
	create_tween().tween_property(self, "modulate:a", 1.0, 0.15)


func hide_report() -> void:
	if visible:
		visible = false
		closed.emit()


## Demande la vue de replay (si le rapport a un journal) ; le HUD masque alors le rapport.
func request_replay() -> void:
	if visible and BattleReplayPanel.has_log(report):
		replay_requested.emit(report)


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
	name_box.add_child(_vignettes(e, s))
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


## Coques de peuple (prop. 37) : une vignette par classe engagée, au style du peuple ; les perdues
## sont assombries, les prises d'abordage marquées d'un liseré d'or.
func _vignettes(e: Empire, s: Dictionary) -> Control:
	var box := HFlowContainer.new()
	box.custom_minimum_size = Vector2(190, 0)
	var style := SpeciesLook.hull_style(e.faction_id)
	var lost: Dictionary = s["lost"]
	var classes: Array = (s["engaged"] as Dictionary).keys()
	classes.sort_custom(func(a, b) -> bool: return Fleet.max_hp_of(String(a)) > Fleet.max_hp_of(String(b)))
	for cls in classes.slice(0, 8):
		var t := TextureRect.new()
		t.texture = HullArt.icon(style, String(cls), e.color())
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Vector2(22, 34)
		var n := int((s["engaged"] as Dictionary)[cls])
		var l := int(lost.get(cls, 0))
		if l >= n:
			t.modulate = Color(0.45, 0.45, 0.45, 0.7)
		t.tooltip_text = "%s : %d engagé(s), %d perdu(s)" % [String(GameData.ship(String(cls)).get("label", cls)), n, l]
		box.add_child(t)
	for c in (s.get("captured", {}) as Dictionary).keys():
		var t := TextureRect.new()
		t.texture = HullArt.icon(style, String(c), Color(0.95, 0.78, 0.36))
		t.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		t.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		t.custom_minimum_size = Vector2(22, 34)
		t.tooltip_text = "Pris à l'abordage : %s" % String(GameData.ship(String(c)).get("label", c))
		box.add_child(t)
	return box


func _value(text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(320, 0)
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", color)
	return l
