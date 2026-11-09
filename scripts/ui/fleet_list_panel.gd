class_name FleetListPanel
extends PanelContainer
## Liste de toutes les flottes du joueur, à droite sous la chronique (comme la liste des flottes
## de l'écran militaire d'Endless Space 2, mais toujours à portée de main sur la carte).
## Une ligne par flotte : nom, composition, état (inactive, en route, en exploration) et délai.
## Clic : sélectionner la flotte et y glisser la caméra. Le titre replie ou déplie la liste.
## Le panneau ne modifie jamais la partie : il émet des demandes.

signal fleet_requested(fleet_id: int)
## Double-clic sur une ligne : ouvrir le système où se trouve la flotte.
signal fleet_system_requested(fleet_id: int)

const WIDTH := 360.0
## Au-delà, la liste défile.
const MAX_VISIBLE_ROWS := 7
const ROW_HEIGHT := 44.0
const IDLE_COLOR := UiTheme.WARN
const EXPLORE_COLOR := UiTheme.ACCENT

var collapsed := false
var _state: GameState
var _player := 0
var _selected := -1
var _title: Label
var _count: Label
var _fold: Button
var _scroll: ScrollContainer
var _rows_box: VBoxContainer
var _empty: Label
## fleet_id -> {"button", "name", "status", "detail", "mark"}
var _rows := {}
var _row_order: Array[int] = []


func _ready() -> void:
	var st := UiTheme.box(Color(0.03, 0.04, 0.06, 0.72), UiTheme.LINE, 10, 0)
	st.border_width_left = 2
	st.border_color = Color(UiTheme.ACCENT, 0.6)
	add_theme_stylebox_override("panel", st)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	_title = UiTheme.section("Flottes")
	_title.add_theme_color_override("font_color", UiTheme.TEXT)
	head.add_child(_title)
	_count = UiTheme.dim("", 12)
	_count.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_count)
	_fold = Button.new()
	_fold.flat = true
	_fold.focus_mode = Control.FOCUS_NONE
	_fold.custom_minimum_size = Vector2(26, 0)
	_fold.tooltip_text = "Replier ou déplier la liste des flottes"
	_fold.pressed.connect(func() -> void: set_collapsed(not collapsed))
	head.add_child(_fold)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_scroll)
	_rows_box = VBoxContainer.new()
	_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows_box.add_theme_constant_override("separation", 2)
	_scroll.add_child(_rows_box)
	_empty = UiTheme.paragraph("Aucune flotte. Les chantiers spatiaux des colonies en construisent (vue système).", WIDTH - 24.0, 13)
	_empty.theme_type_variation = &"Dim"
	box.add_child(_empty)
	set_collapsed(false)


func set_state(state: GameState, player: int) -> void:
	_state = state
	_player = player
	_selected = -1
	refresh()


func set_selected(fleet_id: int) -> void:
	_selected = fleet_id
	_restyle_rows()


func set_collapsed(on: bool) -> void:
	collapsed = on
	_fold.text = "+" if on else "-"
	refresh()


## Nombre de lignes affichées (pour les tests).
func row_count() -> int:
	return _row_order.size()


## Texte d'état d'une ligne (pour les tests), "" si la flotte n'est pas listée.
func row_status(fleet_id: int) -> String:
	return (_rows[fleet_id]["status"] as Label).text if _rows.has(fleet_id) else ""


## Bouton d'une ligne (pour les tests).
func row_button(fleet_id: int) -> Button:
	return _rows[fleet_id]["button"] if _rows.has(fleet_id) else null


func refresh() -> void:
	if _rows_box == null:
		return
	var fleets: Array[Fleet] = []
	if _state:
		fleets = Fleets.empire_fleets(_state, _player)
	var idle := 0
	for f in fleets:
		if f.is_idle():
			idle += 1
	_count.text = "%d  ·  %d inactive%s" % [fleets.size(), idle, "s" if idle > 1 else ""] if not fleets.is_empty() else ""
	_scroll.visible = not collapsed and not fleets.is_empty()
	_empty.visible = not collapsed and fleets.is_empty() and _state != null
	var ids: Array[int] = []
	for f in fleets:
		ids.append(f.id)
	if ids != _row_order:
		_rebuild(ids)
	for f in fleets:
		_update_row(f)
	_scroll.custom_minimum_size = Vector2(WIDTH - 24.0, (ROW_HEIGHT + 2.0) * mini(ids.size(), MAX_VISIBLE_ROWS))
	_restyle_rows()


func _rebuild(ids: Array[int]) -> void:
	for c in _rows_box.get_children():
		_rows_box.remove_child(c)
		c.queue_free()
	_rows.clear()
	_row_order = ids.duplicate()
	for fid in ids:
		_rows_box.add_child(_make_row(fid))


func _make_row(fid: int) -> Control:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, ROW_HEIGHT)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.toggle_mode = true
	b.tooltip_text = "Clic : sélectionner la flotte et centrer la carte dessus\nDouble-clic : ouvrir le système où elle se trouve"
	b.gui_input.connect(func(ev: InputEvent) -> void:
		var mb := ev as InputEventMouseButton
		if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click:
			fleet_system_requested.emit(fid))
	b.pressed.connect(func() -> void: fleet_requested.emit(fid))
	var m := MarginContainer.new()
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_theme_constant_override("margin_left", 8)
	m.add_theme_constant_override("margin_right", 8)
	m.add_theme_constant_override("margin_top", 3)
	m.add_theme_constant_override("margin_bottom", 3)
	b.add_child(m)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	m.add_child(row)
	# Filet vertical à gauche : couleur de l'état (orange = attend des ordres).
	var mark := ColorRect.new()
	mark.custom_minimum_size = Vector2(3, 0)
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(mark)
	var col := VBoxContainer.new()
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	var top := HBoxContainer.new()
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(top)
	var name_l := Label.new()
	name_l.add_theme_font_size_override("font_size", 15)
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.clip_text = true
	top.add_child(name_l)
	var status := Label.new()
	status.add_theme_font_size_override("font_size", 12)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(status)
	var detail := UiTheme.dim("", 12)
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail.clip_text = true
	col.add_child(detail)
	_rows[fid] = {"button": b, "name": name_l, "status": status, "detail": detail, "mark": mark}
	return b


func _update_row(f: Fleet) -> void:
	var r: Dictionary = _rows[f.id]
	(r["name"] as Label).text = f.fleet_name
	var status := r["status"] as Label
	var detail := r["detail"] as Label
	var color := UiTheme.TEXT_DIM
	var eta := Fleets.eta_days(_state, f)
	if f.is_exploring():
		status.text = "EXPLORATION AUTO"
		color = EXPLORE_COLOR
		detail.text = "%s  ·  vers %s, %d j" % [Fleets.composition(f), _label(f.destination()), eta] if f.is_moving() else Fleets.composition(f)
	elif f.is_moving():
		status.text = "EN ROUTE  ·  %d j" % eta
		detail.text = "%s  ·  vers %s" % [Fleets.composition(f), _label(f.destination())]
	elif not Combat.battle_at(_state, f.system_id).is_empty():
		status.text = "EN BATAILLE"
		color = UiTheme.BAD
		detail.text = "%s  ·  à %s" % [Fleets.composition(f), _label(f.system_id)]
	elif Combat.is_besieged(_state, f.system_id) and _state.system_owner(f.system_id) != f.owner and Combat.is_armed(f):
		status.text = "SIÈGE  ·  GARNISON %d" % Combat.garrison(_state, f.system_id)
		color = UiTheme.WARN
		detail.text = "%s  ·  à %s" % [Fleets.composition(f), _label(f.system_id)]
	else:
		status.text = "ATTEND DES ORDRES"
		color = IDLE_COLOR
		detail.text = "%s  ·  à %s" % [Fleets.composition(f), _label(f.system_id)]
	status.add_theme_color_override("font_color", color)
	(r["mark"] as ColorRect).color = Color(color, 0.9 if f.is_idle() or f.is_exploring() else 0.35)


func _restyle_rows() -> void:
	for fid in _rows:
		(_rows[fid]["button"] as Button).set_pressed_no_signal(fid == _selected)


func _label(id: int) -> String:
	return _state.galaxy.systems[id].system_name if Fleets.is_explored(_state, _player, id) else "l'inconnu"
