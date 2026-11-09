class_name EmpireScreens
extends CanvasLayer
## Menus d'empire : une grande fenêtre à onglets par-dessus la carte (Économie, Colonies, et bientôt
## Recherche et Diplomatie). Les chiffres viennent d'EmpireReport, qui applique les règles de la
## simulation sans rien modifier. Un clic sur une colonie demande à ouvrir sa vue système.

signal planet_requested(planet_id: int)
signal close_requested
signal screen_changed(screen_id: String)

const WINDOW_SIZE := Vector2(1060, 640)
const COLUMN_WIDTHS := [190.0, 230.0, 130.0, 230.0, 220.0]

var current := ""
var _state: GameState
var _player := 0
var _window: PanelContainer
var _tabs := {}
var _title: Label
var _content: MarginContainer
# Économie
var _res_rows := {}
var _totals := {}
var _trait: Label
var _faction_title: Label
var _faction_sub: Label
var _emblem: Widgets.Emblem
var _alerts: Label
# Colonies
var _col_list: VBoxContainer
var _col_sig := ""
var _col_rows: Array[Dictionary] = []
var _col_empty: Label
var _col_summary: Label


func _ready() -> void:
	layer = 3
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.01, 0.03, 0.62)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			close_requested.emit())
	add_child(dim)

	_window = PanelContainer.new()
	_window.theme_type_variation = &"WindowPanel"
	_window.set_anchors_preset(Control.PRESET_CENTER)
	_window.offset_left = -WINDOW_SIZE.x * 0.5
	_window.offset_right = WINDOW_SIZE.x * 0.5
	_window.offset_top = -WINDOW_SIZE.y * 0.5
	_window.offset_bottom = WINDOW_SIZE.y * 0.5
	add_child(_window)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_window.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 4)
	box.add_child(head)
	_title = UiTheme.title("", 34, UiTheme.TEXT)
	_title.custom_minimum_size = Vector2(220, 0)
	head.add_child(_title)
	for sc in EmpireBar.SCREENS:
		var b := Button.new()
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.text = ("%s  %s" % [sc["label"], sc["key"]]).to_upper()
		b.disabled = not sc["ready"]
		b.tooltip_text = "" if sc["ready"] else String(sc["why"])
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var id: String = sc["id"]
		b.pressed.connect(func() -> void: show_screen(id))
		head.add_child(b)
		_tabs[id] = b
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(spacer)
	var close := Widgets.IconButton.new("close", 34)
	close.tooltip_text = "Fermer  (Échap)"
	close.pressed.connect(func() -> void: close_requested.emit())
	head.add_child(close)
	box.add_child(HSeparator.new())
	_content = MarginContainer.new()
	_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_content)


func open(screen_id: String, state: GameState, player: int) -> void:
	_state = state
	_player = player
	visible = true
	show_screen(screen_id)
	# Petite entrée en fondu : la fenêtre glisse de quelques pixels.
	_window.modulate.a = 0.0
	_window.pivot_offset = WINDOW_SIZE * 0.5
	_window.scale = Vector2(0.98, 0.98)
	var tw := _window.create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_window, "modulate:a", 1.0, 0.16)
	tw.tween_property(_window, "scale", Vector2.ONE, 0.16)


func close() -> void:
	visible = false
	current = ""


func is_open() -> bool:
	return visible and current != ""


func show_screen(screen_id: String) -> void:
	current = screen_id
	for id in _tabs:
		(_tabs[id] as Button).set_pressed_no_signal(id == screen_id)
	for c in _content.get_children():
		_content.remove_child(c)
		c.queue_free()
	_res_rows.clear()
	_totals.clear()
	_col_rows.clear()
	_col_sig = ""
	match screen_id:
		"economy":
			_title.text = "Économie"
			_build_economy()
		"colonies":
			_title.text = "Colonies"
			_build_colonies()
	refresh()
	screen_changed.emit(screen_id)


## Met à jour les chiffres (à chaque tick et après chaque ordre).
func refresh() -> void:
	if not is_open() or _state == null:
		return
	match current:
		"economy":
			_refresh_economy()
		"colonies":
			_refresh_colonies()


## Lignes de la liste des colonies (boutons), pour les tests.
func colony_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for r in _col_rows:
		out.append(r["button"])
	return out


## Texte d'une ligne de ressource de l'économie (pour les tests) : "Matériaux|200|+20|-3|+17|…".
func economy_row_text(resource_id: String) -> String:
	if not _res_rows.has(resource_id):
		return ""
	var parts := PackedStringArray()
	for l: Label in _res_rows[resource_id]:
		parts.append(l.text)
	return "|".join(parts)


# --- Économie -------------------------------------------------------------------------------

func _build_economy() -> void:
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 24)
	_content.add_child(cols)

	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	cols.add_child(left)
	left.add_child(UiTheme.section("Ressources, par mois"))
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 12)
	left.add_child(grid)
	for h in ["", "Stock", "Production", "Entretien", "Bilan", "Tendance"]:
		var l := UiTheme.dim(h, 13)
		if h != "":
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(l)
	for r in GameData.resource_ids():
		var name_box := HBoxContainer.new()
		name_box.add_theme_constant_override("separation", 8)
		name_box.custom_minimum_size = Vector2(170, 0)
		name_box.add_child(ResourceIcon.make(r, 20))
		var name_l := Label.new()
		name_l.text = GameData.resource_label(r)
		name_l.add_theme_font_size_override("font_size", 16)
		name_box.add_child(name_l)
		grid.add_child(name_box)
		var labels: Array[Label] = [name_l]
		for i in 5:
			var l := Label.new()
			l.theme_type_variation = &"Numbers"
			l.add_theme_font_size_override("font_size", 20 if i < 4 else 15)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			l.custom_minimum_size = Vector2(70 if i < 4 else 130, 0)
			grid.add_child(l)
			labels.append(l)
		_res_rows[r] = labels
	left.add_child(HSeparator.new())
	_alerts = UiTheme.paragraph("", 560, 15)
	left.add_child(_alerts)

	var right := PanelContainer.new()
	right.theme_type_variation = &"SidePanel"
	right.custom_minimum_size = Vector2(320, 0)
	cols.add_child(right)
	var rbox := VBoxContainer.new()
	rbox.add_theme_constant_override("separation", 8)
	right.add_child(rbox)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	rbox.add_child(head)
	_emblem = Widgets.Emblem.new(40)
	head.add_child(_emblem)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -2)
	head.add_child(titles)
	_faction_title = UiTheme.title("", 24)
	_faction_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_faction_title.custom_minimum_size = Vector2(230, 0)
	titles.add_child(_faction_title)
	_faction_sub = UiTheme.dim("", 13)
	titles.add_child(_faction_sub)
	_trait = UiTheme.paragraph("", 280, 14)
	_trait.modulate = Color(1, 1, 1, 0.85)
	rbox.add_child(_trait)
	rbox.add_child(HSeparator.new())
	rbox.add_child(UiTheme.section("Empire"))
	var tgrid := GridContainer.new()
	tgrid.columns = 2
	tgrid.add_theme_constant_override("h_separation", 20)
	tgrid.add_theme_constant_override("v_separation", 4)
	rbox.add_child(tgrid)
	for key in ["population", "colonies", "outposts", "systems", "founding"]:
		var label: String = {"population": "Population", "colonies": "Colonies", "outposts": "Avant-postes",
				"systems": "Systèmes", "founding": "Fondations en cours"}[key]
		var k := Label.new()
		k.text = label
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tgrid.add_child(k)
		var v := Label.new()
		v.theme_type_variation = &"Numbers"
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		tgrid.add_child(v)
		_totals[key] = v


func _refresh_economy() -> void:
	var me := _state.get_empire(_player)
	if me == null:
		return
	for r: Dictionary in EmpireReport.resources(_state, _player):
		var labels: Array[Label] = []
		labels.assign(_res_rows[r["id"]])
		labels[1].text = str(r["stock"])
		labels[2].text = "+%d" % r["gross"] if int(r["gross"]) > 0 else "0"
		labels[2].add_theme_color_override("font_color", UiTheme.GOOD if int(r["gross"]) > 0 else UiTheme.TEXT_DIM)
		labels[3].text = "-%d" % r["upkeep"] if int(r["upkeep"]) > 0 else "0"
		labels[3].add_theme_color_override("font_color", UiTheme.BAD if int(r["upkeep"]) > 0 else UiTheme.TEXT_DIM)
		labels[4].text = "%+d" % r["net"]
		labels[4].add_theme_color_override("font_color", UiTheme.delta_color(int(r["net"])))
		var trend := ""
		var col := UiTheme.TEXT_DIM
		if int(r["months_left"]) >= 0:
			trend = "épuisé dans %d mois" % r["months_left"]
			col = UiTheme.WARN if int(r["months_left"]) > 2 else UiTheme.BAD
		elif int(r["net"]) > 0:
			trend = "en hausse"
			col = UiTheme.GOOD
		else:
			trend = "stable"
		if int(r["bonus_pct"]) != 0:
			labels[2].tooltip_text = "Bonus de faction : %+d %%" % r["bonus_pct"]
			labels[2].mouse_filter = Control.MOUSE_FILTER_STOP
		labels[5].text = trend
		labels[5].add_theme_color_override("font_color", col)
	var alerts := PackedStringArray()
	if me.starving:
		alerts.append("Famine : les réserves de nourriture sont vides et la population décline. Construisez des fermes ou colonisez un monde fertile.")
	if me.blackout:
		alerts.append("Pénurie d'énergie : tous les chantiers sont à l'arrêt tant que le stock reste vide.")
	if alerts.is_empty():
		alerts.append("Aucune crise en vue. Les comptables de l'empire s'ennuient, ce qui est bon signe.")
	_alerts.text = "\n".join(alerts)
	_alerts.add_theme_color_override("font_color", UiTheme.BAD if me.starving or me.blackout else UiTheme.TEXT_DIM)

	_emblem.color = me.color()
	_emblem.queue_redraw()
	_faction_title.text = me.display_name()
	_faction_title.add_theme_color_override("font_color", me.color().lightened(0.3))
	_faction_sub.text = String(me.faction().get("registre", ""))
	_trait.text = String(me.faction().get("trait", ""))
	var t := EmpireReport.totals(_state, _player)
	(_totals["population"] as Label).text = str(t["population"])
	(_totals["colonies"] as Label).text = str(t["colonies"])
	(_totals["outposts"] as Label).text = str(t["outposts"])
	(_totals["systems"] as Label).text = str(t["systems"])
	(_totals["founding"] as Label).text = "%d / %d" % [t["founding"], t["max_projects"]]


# --- Colonies -------------------------------------------------------------------------------

func _build_colonies() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_content.add_child(box)
	_col_summary = UiTheme.dim("", 14)
	box.add_child(_col_summary)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	box.add_child(header)
	var indent := Control.new()
	indent.custom_minimum_size = Vector2(10, 0)  # même retrait que le texte des lignes
	header.add_child(indent)
	var titles := ["Planète", "Type", "Population", "Chantier", "Bilan par mois"]
	for i in titles.size():
		var l := UiTheme.section(titles[i])
		l.custom_minimum_size = Vector2(COLUMN_WIDTHS[i], 0)
		header.add_child(l)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_col_list = VBoxContainer.new()
	_col_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_col_list)
	_col_empty = UiTheme.paragraph("Aucune colonie. L'empire tient tout entier dans un carnet d'adresses d'une ligne.", 600)
	_col_empty.visible = false
	box.add_child(_col_empty)
	box.add_child(UiTheme.key_hints([["Clic", "Ouvrir la vue système de la planète"]]))


func _refresh_colonies() -> void:
	var list := EmpireReport.colonies(_state, _player)
	var ids := PackedStringArray()
	for c in list:
		ids.append(str(c["planet_id"]))
	var sig := ",".join(ids)
	if sig != _col_sig:
		_col_sig = sig
		_rebuild_colony_rows(list)
	_col_empty.visible = list.is_empty()
	var t := EmpireReport.totals(_state, _player)
	_col_summary.text = "%d colonie%s, %d avant-poste%s, %d en fondation (%d au maximum à la fois)  ·  %d population sur %d système%s" % [
		t["colonies"], "s" if t["colonies"] > 1 else "", t["outposts"], "s" if t["outposts"] > 1 else "",
		t["founding"], t["max_projects"], t["population"], t["systems"], "s" if t["systems"] > 1 else ""]
	for i in list.size():
		_fill_colony_row(_col_rows[i], list[i])


func _rebuild_colony_rows(list: Array[Dictionary]) -> void:
	for c in _col_list.get_children():
		_col_list.remove_child(c)
		c.queue_free()
	_col_rows.clear()
	for c in list:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(0, 44)
		b.add_theme_stylebox_override("normal", UiTheme.box(Color(1, 1, 1, 0.035), Color(0, 0, 0, 0), 8, 0))
		var pid: int = c["planet_id"]
		b.pressed.connect(func() -> void: planet_requested.emit(pid))
		b.tooltip_text = "Ouvrir la vue système"
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 10
		row.add_theme_constant_override("separation", 0)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(row)
		var cells: Array[Control] = []
		for i in COLUMN_WIDTHS.size():
			var cell: Control
			if i == 4:
				cell = HBoxContainer.new()
				(cell as HBoxContainer).add_theme_constant_override("separation", 10)
			else:
				cell = Label.new()
			cell.custom_minimum_size = Vector2(COLUMN_WIDTHS[i], 0)
			cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(cell)
			cells.append(cell)
		(cells[0] as Label).theme_type_variation = &"Title"
		(cells[0] as Label).add_theme_font_size_override("font_size", 20)
		_col_list.add_child(b)
		_col_rows.append({"button": b, "cells": cells, "net_sig": ""})


func _fill_colony_row(row: Dictionary, c: Dictionary) -> void:
	var cells: Array = row["cells"]
	var me := _state.get_empire(_player)
	(cells[0] as Label).text = String(c["name"])
	(cells[0] as Label).add_theme_color_override("font_color", me.color().lightened(0.3) if me else UiTheme.TEXT)
	(cells[1] as Label).text = String(c["type_label"]) + ("  (capitale)" if c["capital"] else "")
	var pop := ""
	if not c["established"]:
		pop = "fondation : %d j" % c["days_left"]
	elif c["kind"] == Colony.KIND_COLONY:
		pop = "%d / %d" % [c["population"], c["max_pop"]]
	else:
		pop = "avant-poste"
	(cells[2] as Label).text = pop
	(cells[2] as Label).add_theme_color_override("font_color", UiTheme.WARN if not c["established"] else UiTheme.TEXT)
	(cells[3] as Label).text = "%s (%d j)" % [c["construction"], c["construction_days"]] if c["construction"] != "" else "—"
	(cells[3] as Label).add_theme_color_override("font_color", UiTheme.TEXT if c["construction"] != "" else UiTheme.TEXT_DIM)
	# Bilan : une icône et un nombre par ressource non nulle (reconstruit seulement s'il change).
	var net: Dictionary = c["net"]
	var sig := str(net)
	if sig == row["net_sig"]:
		return
	row["net_sig"] = sig
	var box := cells[4] as HBoxContainer
	for ch in box.get_children():
		box.remove_child(ch)
		ch.queue_free()
	for r in GameData.resource_ids():
		var v := int(net.get(r, 0))
		if v == 0:
			continue
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 3)
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pair.add_child(ResourceIcon.make(r, 14))
		var l := Label.new()
		l.text = "%+d" % v
		l.theme_type_variation = &"Numbers"
		l.add_theme_font_size_override("font_size", 16)
		l.add_theme_color_override("font_color", UiTheme.delta_color(v))
		pair.add_child(l)
		box.add_child(pair)
