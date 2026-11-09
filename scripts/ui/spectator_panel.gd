class_name SpectatorPanel
extends PanelContainer
## Tableau des empires du mode spectateur, à droite sous la chronique (à la place de la liste des
## flottes). On y suit la course de tous les peuples d'un coup d'œil :
## - une ligne par empire : couleur, nom, niveau de l'IA, score, systèmes, colonies, population,
##   flottes, sa jauge de peuple (ferveur, fiefs…) et ce que son IA est en train de faire ;
## - une courbe du score de chaque empire, relevée chaque mois depuis l'ouverture de la partie ;
## - deux façons de regarder : la vue d'ensemble (toute la galaxie, sans brouillard) ou les yeux
##   de l'empire suivi (son brouillard, ce qu'il sait vraiment).
## Clic sur une ligne : suivre cet empire (panneau d'empire, flottes) ; double-clic : aller à sa capitale.
## Le panneau ne modifie jamais la partie. Le même tableau servira aux spectateurs en multijoueur.

signal empire_followed(empire_id: int)
signal capital_requested(empire_id: int)
## Vue d'ensemble (false) ou brouillard de l'empire suivi (true).
signal fog_requested(fog: bool)

const WIDTH := 360.0
const CHART_HEIGHT := 70.0
## Points gardés pour la courbe (un par mois : 20 ans).
const HISTORY_MAX := 240

var followed := 0
var fog := false
var _state: GameState
var _rows := {}
var _box: VBoxContainer
var _rows_box: VBoxContainer
var _chart: _ScoreChart
var _overview_button: Button
var _eyes_button: Button
var _last_month := -1
## empire_id -> Array[int], scores mensuels.
var history := {}


func _ready() -> void:
	var st := UiTheme.box(Color(0.03, 0.04, 0.06, 0.78), UiTheme.LINE, 10, 0)
	st.border_width_left = 2
	st.border_color = Color(UiTheme.ACCENT, 0.6)
	add_theme_stylebox_override("panel", st)
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(WIDTH, 0)
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 6)
	add_child(_box)
	var head := HBoxContainer.new()
	_box.add_child(head)
	var title := UiTheme.section("Tableau des empires")
	title.add_theme_color_override("font_color", UiTheme.TEXT)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UiTheme.dim("SPECTATEUR", 11))
	_rows_box = VBoxContainer.new()
	_rows_box.add_theme_constant_override("separation", 3)
	_box.add_child(_rows_box)
	_box.add_child(UiTheme.dim("Score au fil des mois", 11))
	_chart = _ScoreChart.new()
	_chart.panel = self
	_chart.custom_minimum_size = Vector2(WIDTH - 24.0, CHART_HEIGHT)
	_box.add_child(_chart)
	var views := HBoxContainer.new()
	views.add_theme_constant_override("separation", 4)
	_box.add_child(views)
	_overview_button = _view_button("VUE D'ENSEMBLE", "Toute la galaxie, sans brouillard  (V)")
	_overview_button.pressed.connect(func() -> void: set_fog(false, true))
	views.add_child(_overview_button)
	_eyes_button = _view_button("YEUX DE L'EMPIRE", "Seulement ce que sait l'empire suivi : son brouillard de guerre  (V)")
	_eyes_button.pressed.connect(func() -> void: set_fog(true, true))
	views.add_child(_eyes_button)
	var hint := UiTheme.paragraph("Clic : suivre un empire.  Double-clic : sa capitale.  Tab : empire suivant.", WIDTH - 24.0, 12)
	hint.theme_type_variation = &"Dim"
	_box.add_child(hint)
	set_fog(false)


func _view_button(text: String, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func set_state(state: GameState, follow := 0) -> void:
	_state = state
	followed = follow
	history.clear()
	_last_month = -1
	for r in _rows.values():
		(r["button"] as Control).queue_free()
	_rows.clear()
	if state == null:
		return
	for e in state.empires:
		_rows[e.id] = _make_row(e)
	refresh()


func set_followed(empire_id: int, emit := false) -> void:
	followed = empire_id
	_restyle()
	if emit:
		empire_followed.emit(empire_id)


func set_fog(on: bool, emit := false) -> void:
	fog = on
	if _overview_button:
		_overview_button.set_pressed_no_signal(not on)
		_eyes_button.set_pressed_no_signal(on)
	if emit:
		fog_requested.emit(on)


func row_count() -> int:
	return _rows.size()


## Texte d'une ligne (pour les tests et les captures).
func row_text(empire_id: int) -> String:
	if not _rows.has(empire_id):
		return ""
	var r: Dictionary = _rows[empire_id]
	return "%s | %s | %s" % [(r["name"] as Label).text, (r["stats"] as Label).text, (r["intent"] as Label).text]


func row_button(empire_id: int) -> Button:
	return _rows[empire_id]["button"] if _rows.has(empire_id) else null


func refresh() -> void:
	if _state == null or _rows_box == null:
		return
	var month := _state.tick / int(GameData.rules()["month_days"])
	if month != _last_month:
		_last_month = month
		for e in _state.empires:
			var h: Array = history.get(e.id, [])
			h.append(EmpireReport.score(_state, e.id))
			while h.size() > HISTORY_MAX:
				h.pop_front()
			history[e.id] = h
		_chart.queue_redraw()
	# Classement : le score le plus haut en premier.
	var order: Array = _state.empires.duplicate()
	order.sort_custom(func(a: Empire, b: Empire) -> bool:
		var sa := EmpireReport.score(_state, a.id)
		var sb := EmpireReport.score(_state, b.id)
		return sa > sb or (sa == sb and a.id < b.id))
	for i in order.size():
		var e: Empire = order[i]
		var r: Dictionary = _rows[e.id]
		_rows_box.move_child(r["button"], i)
		var t := EmpireReport.totals(_state, e.id)
		(r["name"] as Label).text = "%d. %s" % [i + 1, e.short_name()]
		(r["level"] as Label).text = ("IA %s · %s" % [AiLevels.label(e.ai_level), AiLevels.temperament_label(e)]) if e.is_ai() else "Joueur"
		(r["score"] as Label).text = "%d" % EmpireReport.score(_state, e.id)
		var gauge := FactionTraits.gauge(_state, e.id)
		var stats := "%d sys · %d col · %d av · %d pop · %d flottes" % [t["systems"], t["colonies"], t["outposts"],
				t["population"], Fleets.empire_fleets(_state, e.id).size()]
		if not gauge.is_empty():
			stats += " · %s %s" % [gauge["label"], gauge["value"]]
		(r["stats"] as Label).text = stats
		(r["stats"] as Label).add_theme_color_override("font_color", UiTheme.BAD if not gauge.is_empty() and gauge.get("bad", false) else UiTheme.TEXT_DIM)
		var intent := e.ai_intent if e.ai_intent != "" else ("En réflexion…" if e.is_ai() else "")
		(r["intent"] as Label).text = intent
		(r["button"] as Button).tooltip_text = "%s\n%s\n%s\nTempérament %s : %s %s" % [e.display_name(),
				AiLevels.level(e.ai_level).get("desc", "") if e.is_ai() else "Joueur humain",
				String(AiLevels.personality(e).get("style", "")), AiLevels.temperament_label(e),
				AiLevels.temperament(e.ai_temperament).get("desc", ""),
				String(AiLevels.personality(e).get("temperament", {}).get("text", ""))]
	_restyle()


func _make_row(e: Empire) -> Dictionary:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(WIDTH - 24.0, 58)
	b.clip_contents = true
	var id := e.id
	b.pressed.connect(func() -> void: set_followed(id, true))
	b.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb and mb.pressed and mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
			capital_requested.emit(id))
	_rows_box.add_child(b)
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", 10)
	m.add_theme_constant_override("margin_right", 8)
	m.add_theme_constant_override("margin_top", 4)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(top)
	var name := Label.new()
	name.add_theme_font_size_override("font_size", 15)
	name.add_theme_color_override("font_color", e.color().lightened(0.3))
	name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(name)
	var level := UiTheme.dim("", 11)
	level.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	level.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(level)
	var score := Label.new()
	score.add_theme_font_size_override("font_size", 15)
	score.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(score)
	var stats := UiTheme.dim("", 11)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(stats)
	var intent := UiTheme.dim("", 11)
	intent.add_theme_color_override("font_color", Color(UiTheme.ACCENT, 0.8))
	intent.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	intent.custom_minimum_size = Vector2(WIDTH - 50.0, 0)
	intent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(intent)
	var stripe := ColorRect.new()
	stripe.color = e.color()
	stripe.anchor_bottom = 1.0
	stripe.offset_right = 3
	stripe.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(stripe)
	return {"button": b, "name": name, "level": level, "score": score, "stats": stats, "intent": intent}


func _restyle() -> void:
	for id in _rows:
		(_rows[id]["button"] as Button).set_pressed_no_signal(id == followed)


## Courbes du score de chaque empire, à sa couleur ; l'empire suivi en trait épais.
class _ScoreChart extends Control:
	var panel: SpectatorPanel

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.25))
		if panel == null or panel._state == null:
			return
		var top := 1
		var n := 0
		for id in panel.history:
			for v in panel.history[id]:
				top = maxi(top, int(v))
			n = maxi(n, (panel.history[id] as Array).size())
		if n < 2:
			draw_string(UiTheme.body_font(), Vector2(8, size.y / 2 + 5), "Les courbes apparaissent au fil des mois.", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, UiTheme.TEXT_DIM)
			return
		for e in panel._state.empires:
			var h: Array = panel.history.get(e.id, [])
			if h.size() < 2:
				continue
			var pts := PackedVector2Array()
			for i in h.size():
				pts.append(Vector2(size.x * i / float(n - 1), size.y - 3.0 - (size.y - 6.0) * float(h[i]) / float(top)))
			draw_polyline(pts, e.color(), 2.5 if e.id == panel.followed else 1.2, true)
