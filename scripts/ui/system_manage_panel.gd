class_name SystemManagePanel
extends Control
## Vue de gestion d'un système : les planètes alignées en grand, côte à côte, pour comparer
## d'un coup d'œil. Au-dessus de chacune, ses rendements (ou son potentiel si elle n'est pas
## à vous) ; autour, la jauge de population ; en dessous, sa disponibilité et l'ordre principal.
## Simple affichage : elle signale les clics, et SystemScreen transforme les ordres en demandes.

signal planet_clicked(planet_id: int)

const MAX_SPHERE := 150.0

var state: GameState
var system: StarSystem
var player := 0
var selected_planet := -1
## Fabrique les ordres d'une planète (fournie par SystemScreen) : Array[Dictionary] comme dans sa fiche.
var actions_for: Callable

var _row: HBoxContainer
var _columns := {}
var _action_sigs := {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_row = HBoxContainer.new()
	# Rangée centrée verticalement ; ses colonnes gardent la même hauteur, alignées en haut.
	_row.set_anchors_and_offsets_preset(Control.PRESET_HCENTER_WIDE)
	_row.grow_vertical = Control.GROW_DIRECTION_BOTH
	_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_row.add_theme_constant_override("separation", 10)
	_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_row)


func set_system(value_state: GameState, s: StarSystem, viewer: int) -> void:
	state = value_state
	system = s
	player = viewer
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	_columns.clear()
	_action_sigs.clear()
	if s == null:
		return
	var n := maxi(s.planet_count, 1)
	var col_w := clampf((size.x - 10.0 * (n - 1)) / n, 96.0, 230.0)
	var sphere := minf(MAX_SPHERE, col_w - 40.0)
	for pid in s.planet_ids:
		var col := _make_column(state.galaxy.get_planet(pid), col_w, sphere)
		_row.add_child(col["root"])
		_columns[pid] = col
	refresh()


func refresh() -> void:
	if system == null:
		return
	for pid in system.planet_ids:
		_refresh_column(state.galaxy.get_planet(pid), _columns[pid])


func _make_column(p: Planet, width: float, sphere: float) -> Dictionary:
	var root := PanelContainer.new()
	root.custom_minimum_size = Vector2(width, 0)
	root.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			planet_clicked.emit(p.id))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(box)

	var title := _label(box, 17)
	var sub := _label(box, 12)
	sub.modulate = Color(0.8, 0.84, 0.94, 0.85)
	var yields := GridContainer.new()
	yields.columns = 2
	yields.add_theme_constant_override("h_separation", 6)
	yields.add_theme_constant_override("v_separation", 1)
	yields.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(yields)
	var yield_labels := {}
	for r in GameData.resource_ids():
		var name_l := Label.new()
		name_l.text = GameData.resource_label(r, true)
		name_l.add_theme_font_size_override("font_size", 11)
		name_l.add_theme_color_override("font_color", PlanetInfo.RESOURCE_COLORS.get(r, Color.WHITE))
		yields.add_child(name_l)
		var cell := HBoxContainer.new()
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		yields.add_child(cell)
		var val := Label.new()
		val.add_theme_font_size_override("font_size", 11)
		cell.add_child(val)
		var pips := Control.new()
		pips.custom_minimum_size = Vector2(5 * 9, 12)
		pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var rc: Color = PlanetInfo.RESOURCE_COLORS.get(r, Color.WHITE)
		pips.draw.connect(func() -> void:
			var v := int(pips.get_meta("value", 0))
			for i in 5:
				pips.draw_rect(Rect2(i * 9.0, 3.0, 7.0, 6.0), rc if i < v else Color(rc, 0.14)))
		cell.add_child(pips)
		yield_labels[r] = {"value": val, "pips": pips}

	# La planète, avec sa jauge de population dessinée autour.
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(sphere + 18.0, sphere + 18.0)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(holder)
	var body := ColorRect.new()
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.material = SystemView.make_planet_material(p)
	var body_frac := float((body.material as ShaderMaterial).get_shader_parameter("body"))
	var side := sphere / body_frac
	body.size = Vector2(side, side)
	body.position = (holder.custom_minimum_size - body.size) * 0.5
	(body.material as ShaderMaterial).set_shader_parameter("light_dir", Vector3(-0.8, -0.25, 0.45))
	holder.add_child(body)
	holder.draw.connect(_draw_gauge.bind(holder, p, sphere))

	var status := _label(box, 13)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var actions := VBoxContainer.new()
	actions.add_theme_constant_override("separation", 3)
	box.add_child(actions)
	return {"root": root, "title": title, "sub": sub, "yields": yield_labels, "holder": holder,
			"status": status, "actions": actions}


func _refresh_column(p: Planet, col: Dictionary) -> void:
	var c: Colony = Intel.shown_colony(state, p.id)
	var selected := p.id == selected_planet
	(col["root"] as PanelContainer).add_theme_stylebox_override("panel", _style(selected))
	var title: Label = col["title"]
	title.text = p.display_name(state.galaxy)
	title.add_theme_color_override("font_color", SystemView.SELECT_COLOR if selected
			else (state.get_empire(c.owner).color().lightened(0.3) if c else Color(0.94, 0.95, 1.0)))
	(col["sub"] as Label).text = "%s, taille %d" % ["Astéroïdes" if p.type == "asteroids" else p.type_label(), p.size]

	# Rendement réel par mois pour une planète à soi, sinon le potentiel en barres.
	var mine := c != null and c.owner == player and c.is_established()
	var net := PlanetInfo.net_yields(state, c) if mine else {}
	var pot := PlanetInfo.potential(p)
	for r in GameData.resource_ids():
		var l: Label = col["yields"][r]["value"]
		var pips: Control = col["yields"][r]["pips"]
		l.visible = mine
		pips.visible = not mine
		if mine:
			l.text = "%+d / mois" % int(net.get(r, 0))
			l.modulate = Color(1, 1, 1, 0.95 if int(net.get(r, 0)) != 0 else 0.4)
		else:
			pips.set_meta("value", int(pot[r]))
			pips.queue_redraw()

	var avail := PlanetInfo.availability(state, p, player)
	var status: Label = col["status"]
	status.text = avail["text"]
	if c and c.is_colony() and c.is_established():
		status.text += " · %d/%d pop" % [c.population, Economy.max_pop(state, p, c.owner, c.buildings)]
	status.add_theme_color_override("font_color", PlanetInfo.AVAILABILITY_COLORS.get(avail["kind"], Color.WHITE))
	(col["holder"] as Control).queue_redraw()

	# Ordre principal : coloniser ou poser un avant-poste (les chantiers restent dans la fiche).
	var acts: Array = actions_for.call(p) if actions_for.is_valid() else []
	acts = acts.filter(func(a: Dictionary) -> bool: return not a.has("detail"))
	var sig := PackedStringArray()
	for a in acts:
		sig.append("%s|%s" % [a["text"], a["reason"]])
	var joined := "\n".join(sig)
	if _action_sigs.get(p.id, "") == joined and (col["actions"] as Node).get_child_count() == acts.size():
		return
	_action_sigs[p.id] = joined
	var box: VBoxContainer = col["actions"]
	for child in box.get_children():
		box.remove_child(child)
		child.queue_free()
	for a in acts:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.text = String(a["text"]).get_slice("  (", 0).replace("Poser un avant-poste", "Avant-poste")
		b.clip_text = true
		b.add_theme_font_size_override("font_size", 13)
		b.disabled = a["reason"] != ""
		b.tooltip_text = "%s\n%s" % [a["text"], a["tooltip"]]
		b.pressed.connect(a["action"])
		box.add_child(b)


## Jauge autour de la planète : population pour une colonie, anneau plein pour un avant-poste,
## pointillé pendant une fondation.
func _draw_gauge(holder: Control, p: Planet, sphere: float) -> void:
	var c: Colony = Intel.shown_colony(state, p.id) if state else null
	var center := holder.size * 0.5
	var radius := sphere * 0.5 + 8.0
	holder.draw_arc(center, radius, PI * 0.75, PI * 2.25, 64, Color(1, 1, 1, 0.08), 3.0, true)
	if c == null:
		return
	var col := state.get_empire(c.owner).color()
	if not c.is_established():
		for i in 16:
			var a := TAU * i / 16.0
			holder.draw_arc(center, radius, a, a + TAU / 32.0, 6, col, 3.0, true)
	elif c.is_colony():
		var cap := maxi(Economy.max_pop(state, p, c.owner, c.buildings), 1)
		var frac := clampf(float(c.population) / float(cap), 0.0, 1.0)
		holder.draw_arc(center, radius, PI * 0.75, PI * 0.75 + PI * 1.5 * frac, 64, col, 4.0, true)
	else:
		holder.draw_arc(center, radius, PI * 0.75, PI * 2.25, 64, Color(col, 0.8), 2.0, true)


func _label(parent: Control, fs: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _style(selected: bool) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.03, 0.04, 0.08, 0.55 if selected else 0.3)
	st.border_color = Color(SystemView.SELECT_COLOR, 0.8) if selected else Color(0.6, 0.75, 1.0, 0.15)
	st.set_border_width_all(0)
	st.border_width_top = 2
	st.set_content_margin_all(10)
	return st
