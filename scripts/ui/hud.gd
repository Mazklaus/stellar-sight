class_name Hud
extends CanvasLayer
## Interface en jeu : barre d'empire en haut, fiche du système sélectionné à droite (carte de la
## galaxie), étiquette de survol, notifications, chronique et aide contextuelle des raccourcis en bas.
## Les actions sur les planètes se font dans la vue système (SystemScreen), les bilans dans les
## menus d'empire (EmpireScreens). L'interface ne modifie jamais la partie : elle émet des demandes.

signal open_system_requested(system_id: int)
signal screen_requested(screen_id: String)
signal menu_requested
signal pause_toggled
signal speed_requested(index: int)

const PANEL_WIDTH := 380.0
const MARGIN := 12.0
const HINT_HEIGHT := 30.0
const CHRONICLE_HEIGHT := 34.0
## Hauteur totale réservée en bas (aide + chronique) : la vue système s'arrête au-dessus.
const BOTTOM_RESERVED := HINT_HEIGHT + CHRONICLE_HEIGHT + 2.0 * 8.0
const TOAST_SECONDS := 3.5
const TOAST_MAX := 4
const HINTS_GALAXY := [["Espace", "Pause"], ["1-5", "Vitesse"], ["Clic", "Sélection"], ["Entrée", "Vue système"],
	["Tab", "Système suivant"], ["H", "Capitale"], ["F1", "Économie"], ["F2", "Colonies"], ["ZQSD", "Déplacer"],
	["Molette", "Zoom"], ["Échap", "Menu"]]
const HINTS_SYSTEM := [["Espace", "Pause"], ["1-5", "Vitesse"], ["Flèches", "Planète"], ["Tab", "Système suivant"],
	["H", "Capitale"], ["F1", "Économie"], ["F2", "Colonies"], ["Échap", "Galaxie"]]

var bar: EmpireBar
var _info_panel: PanelContainer
var _sys_emblem: Widgets.Emblem
var _sys_title: Label
var _sys_sub: Label
var _sys_lanes: Label
var _planet_rows: VBoxContainer
var _enter_button: Button
var _hover: PanelContainer
var _hover_title: Label
var _hover_text: Label
var _toasts: VBoxContainer
var _chronicle: Widgets.RichTipPanel
var _chronicle_label: Label
var _hints: PanelContainer
var _system_mode := false
var _system_id := -1
var _state: GameState
var _player := 0


func _ready() -> void:
	bar = EmpireBar.new()
	add_child(bar)
	bar.screen_requested.connect(func(id: String) -> void: screen_requested.emit(id))
	bar.menu_requested.connect(func() -> void: menu_requested.emit())
	bar.pause_toggled.connect(func() -> void: pause_toggled.emit())
	bar.speed_requested.connect(func(i: int) -> void: speed_requested.emit(i))
	_build_info_panel()
	_build_hover()
	_build_bottom()

	_toasts = VBoxContainer.new()
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toasts.offset_top = EmpireBar.HEIGHT + 14.0
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	_toasts.add_theme_constant_override("separation", 6)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)


## Branche l'interface sur une partie (nouvelle ou chargée) et sur l'empire du joueur local.
func set_state(state: GameState, player: int) -> void:
	_state = state
	_player = player
	bar.set_state(state, player)
	show_system(null, state)
	show_hover(null, Vector2.ZERO)


## Met à jour ce qui change avec le temps. Appelé à chaque tick et après chaque ordre.
func refresh() -> void:
	bar.refresh()
	if _system_id >= 0:
		_refresh_system()


func show_system(s: StarSystem, state: GameState) -> void:
	if s == null:
		_system_id = -1
		_info_panel.visible = false
		return
	_state = state
	_system_id = s.id
	_refresh_system()
	_info_panel.visible = not _system_mode


## Vue système ouverte (true) ou carte de la galaxie (false) : la fiche et l'aide s'adaptent.
func set_system_mode(on: bool) -> void:
	_system_mode = on
	_info_panel.visible = not on and _system_id >= 0
	if on:
		show_hover(null, Vector2.ZERO)
	_set_hints(HINTS_SYSTEM if on else HINTS_GALAXY)


## Étiquette qui suit la souris au survol d'un système sur la carte (s = null pour la cacher).
func show_hover(s: StarSystem, screen_pos: Vector2) -> void:
	if s == null or _state == null or _system_mode:
		_hover.visible = false
		return
	var owner := _state.get_empire(_state.system_owner(s.id))
	_hover_title.text = s.system_name
	_hover_title.add_theme_color_override("font_color", owner.color().lightened(0.35) if owner else UiTheme.TEXT)
	var planets := "%d planète%s" % [s.planet_count, "s" if s.planet_count > 1 else ""] if s.planet_count > 0 else "Aucune planète"
	_hover_text.text = "%s  ·  %s\n%s" % [GalaxyGenerator.star_label(s.star_type), planets,
			"Système de %s" % owner.short_name() if owner else "Système libre"]
	_hover.visible = true
	_hover.reset_size()
	var vp := _hover.get_viewport_rect().size
	var pos := screen_pos + Vector2(18, 14)
	pos.x = minf(pos.x, vp.x - _hover.size.x - 8.0)
	pos.y = minf(pos.y, vp.y - _hover.size.y - BOTTOM_RESERVED)
	_hover.position = pos


## Affiche la dernière entrée de chronique ({"tick", "text"}) ; l'infobulle donne les précédentes.
func show_chronicle(entry: Dictionary) -> void:
	if entry.is_empty():
		_chronicle_label.text = "La chronique attend son premier scandale."
		_chronicle.tooltip_text = ""
		return
	_chronicle_label.text = "%s  —  %s" % [GameCalendar.date_string(int(entry["tick"])), entry["text"]]
	if _state:
		var lines := PackedStringArray(["[b]Chronique galactique[/b]"])
		var from := maxi(0, _state.chronicle.size() - 6)
		for i in range(_state.chronicle.size() - 1, from - 1, -1):
			var e: Dictionary = _state.chronicle[i]
			lines.append("[color=#%s]%s[/color]  %s" % [UiTheme.TEXT_DIM.to_html(false), GameCalendar.date_string(int(e["tick"])), e["text"]])
		_chronicle.tooltip_text = "\n".join(lines)


## Petit message temporaire sous la barre d'empire. kind : "info", "good", "bad".
func notify(text: String, kind := "info") -> void:
	var toast := PanelContainer.new()
	var border: Color = {"good": UiTheme.GOOD, "bad": UiTheme.BAD}.get(kind, UiTheme.ACCENT)
	toast.add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.045, 0.085, 0.95), Color(border, 0.8), 10, 5))
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_child(l)
	_toasts.add_child(toast)
	while _toasts.get_child_count() > TOAST_MAX:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var tw := toast.create_tween()
	tw.tween_interval(TOAST_SECONDS)
	tw.tween_property(toast, "modulate:a", 0.0, 0.5)
	tw.tween_callback(toast.queue_free)


## Texte des notifications affichées (pour les tests).
func toast_texts() -> PackedStringArray:
	var out := PackedStringArray()
	for t in _toasts.get_children():
		if not t.is_queued_for_deletion():
			out.append((t.get_child(0) as Label).text)
	return out


func planet_row_count() -> int:
	return _planet_rows.get_child_count()


# --- Construction ---------------------------------------------------------------------------

func _build_info_panel() -> void:
	_info_panel = PanelContainer.new()
	_info_panel.theme_type_variation = &"SidePanel"
	_info_panel.anchor_left = 1.0
	_info_panel.anchor_right = 1.0
	_info_panel.offset_left = -PANEL_WIDTH - MARGIN
	_info_panel.offset_right = -MARGIN
	_info_panel.offset_top = EmpireBar.HEIGHT + MARGIN
	_info_panel.visible = false
	add_child(_info_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_info_panel.add_child(box)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	box.add_child(head)
	_sys_emblem = Widgets.Emblem.new(30)
	_sys_emblem.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(_sys_emblem)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", -2)
	head.add_child(titles)
	_sys_title = UiTheme.title("", 28)
	titles.add_child(_sys_title)
	_sys_sub = UiTheme.dim("")
	titles.add_child(_sys_sub)
	box.add_child(HSeparator.new())
	box.add_child(UiTheme.section("Routes de saut"))
	_sys_lanes = UiTheme.paragraph("", PANEL_WIDTH - 40.0, 14)
	box.add_child(_sys_lanes)
	box.add_child(UiTheme.section("Planètes"))
	_planet_rows = VBoxContainer.new()
	_planet_rows.add_theme_constant_override("separation", 3)
	box.add_child(_planet_rows)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	box.add_child(gap)
	_enter_button = Button.new()
	_enter_button.theme_type_variation = &"PrimaryButton"
	_enter_button.text = "Entrer dans le système"
	_enter_button.tooltip_text = "Ouvrir la vue système  (Entrée ou double-clic)"
	_enter_button.focus_mode = Control.FOCUS_NONE
	_enter_button.pressed.connect(func() -> void:
		if _system_id >= 0:
			open_system_requested.emit(_system_id))
	box.add_child(_enter_button)


func _build_hover() -> void:
	_hover = PanelContainer.new()
	_hover.add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.045, 0.085, 0.94), UiTheme.LINE_STRONG, 8, 5))
	_hover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover.visible = false
	add_child(_hover)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hover.add_child(box)
	_hover_title = UiTheme.title("", 19)
	box.add_child(_hover_title)
	_hover_text = UiTheme.dim("", 13)
	box.add_child(_hover_text)


func _build_bottom() -> void:
	_hints = PanelContainer.new()
	_hints.anchor_top = 1.0
	_hints.anchor_bottom = 1.0
	_hints.anchor_right = 1.0
	_hints.offset_top = -HINT_HEIGHT
	var st := StyleBoxFlat.new()
	st.bg_color = Color(0.015, 0.022, 0.042, 0.85)
	st.border_color = UiTheme.LINE
	st.border_width_top = 1
	st.content_margin_left = 14
	_hints.add_theme_stylebox_override("panel", st)
	_hints.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hints)
	_set_hints(HINTS_GALAXY)

	_chronicle = Widgets.RichTipPanel.new()
	_chronicle.tip_width = 520.0
	_chronicle.anchor_top = 1.0
	_chronicle.anchor_bottom = 1.0
	_chronicle.offset_left = MARGIN
	_chronicle.offset_right = 760.0
	_chronicle.offset_top = -HINT_HEIGHT - 8.0 - CHRONICLE_HEIGHT
	_chronicle.offset_bottom = -HINT_HEIGHT - 8.0
	_chronicle.add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.04, 0.075, 0.8), Color(UiTheme.GOLD, 0.25), 6, 5))
	_chronicle.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_chronicle)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chronicle.add_child(row)
	var tag := Label.new()
	tag.text = "CHRONIQUE"
	tag.theme_type_variation = &"Section"
	tag.add_theme_color_override("font_color", Color(UiTheme.GOLD, 0.85))
	row.add_child(tag)
	_chronicle_label = Label.new()
	_chronicle_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chronicle_label.clip_text = true
	_chronicle_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_chronicle_label.add_theme_font_size_override("font_size", 14)
	_chronicle_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7, 0.92))
	row.add_child(_chronicle_label)


func _set_hints(hints: Array) -> void:
	for c in _hints.get_children():
		_hints.remove_child(c)
		c.queue_free()
	var row := UiTheme.key_hints(hints)
	row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_hints.add_child(row)


func _refresh_system() -> void:
	if _state == null or _system_id < 0:
		return
	var galaxy := _state.galaxy
	var s := galaxy.get_system(_system_id)
	var owner := _state.get_empire(_state.system_owner(s.id))
	_sys_emblem.color = owner.color() if owner else Color(0.5, 0.55, 0.65)
	_sys_emblem.queue_redraw()
	_sys_title.text = s.system_name
	_sys_title.add_theme_color_override("font_color", owner.color().lightened(0.35) if owner else UiTheme.TEXT)
	_sys_sub.text = "%s  ·  %s  ·  %s" % [
		GalaxyGenerator.star_label(s.star_type),
		owner.short_name() if owner else "Système libre",
		"à portée" if Economy.in_range(_state, _player, s.id) else "hors de portée",
	]
	var neighbor_names := PackedStringArray()
	for n in s.neighbors:
		neighbor_names.append(galaxy.systems[n].system_name)
	_sys_lanes.text = ", ".join(neighbor_names)

	# Une ligne par planète : pastille du type, rang et type, statut à la couleur du propriétaire.
	var rows := _planet_rows.get_children()
	if rows.size() != s.planet_count:
		for r in rows:
			_planet_rows.remove_child(r)
			r.queue_free()
		for i in s.planet_count:
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 8)
			row.add_child(Widgets.Dot.new(Color.WHITE, 12))
			var name_l := Label.new()
			name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			name_l.add_theme_font_size_override("font_size", 14)
			row.add_child(name_l)
			var status_l := Label.new()
			status_l.add_theme_font_size_override("font_size", 14)
			row.add_child(status_l)
			_planet_rows.add_child(row)
	if s.planet_count == 0:
		_enter_button.text = "Contempler le vide"
	else:
		_enter_button.text = "Entrer dans le système"
	for i in s.planet_count:
		var p := galaxy.get_planet(s.planet_ids[i])
		var row := _planet_rows.get_child(i)
		var dot := row.get_child(0) as Widgets.Dot
		dot.color = SystemScreen.TYPE_DOT_COLORS.get(p.type, Color.GRAY)
		dot.queue_redraw()
		var roman: String = Planet.ROMAN[p.index] if p.index < Planet.ROMAN.size() else str(p.index + 1)
		(row.get_child(1) as Label).text = "%s  %s  ·  taille %d" % [roman, p.type_label(), p.size]
		var c: Colony = _state.colonies.get(p.id)
		var status := row.get_child(2) as Label
		status.text = PlanetInfo.short_status(_state, p, _player)
		status.add_theme_color_override("font_color", _state.get_empire(c.owner).color().lightened(0.3) if c else UiTheme.TEXT_DIM)
