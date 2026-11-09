class_name Hud
extends CanvasLayer
## Interface en jeu, disposée aux quatre coins comme dans les grands 4X spatiaux :
##   en haut à gauche  le panneau d'empire (menus, ressources, état) ;
##   en haut au centre les onglets de vue (galaxie, lentille économique, gestion du système) ;
##   en haut à droite  la chronique galactique ;
##   en bas à gauche   la fiche du système survolé ou sélectionné, avec son illustration ;
##   en bas à droite   le cadran du temps et le menu du jeu.
## L'interface ne modifie jamais la partie : elle émet des demandes.

signal open_system_requested(system_id: int)
signal close_system_requested
signal screen_requested(screen_id: String)
signal menu_requested
signal pause_toggled
signal speed_requested(index: int)
signal lens_changed(lens: String)

const MARGIN := 10.0
const CARD_WIDTH := 320.0
const CHRONICLE_WIDTH := 360.0
const TOAST_SECONDS := 3.5
const TOAST_MAX := 4
## Place prise en bas à droite par le cadran (la vue système s'arrête avant).
const DIAL_RESERVED := TimeDial.SIDE + 20.0
## Petit texte d'ambiance par type d'étoile, pour la fiche.
const STAR_LORE := {
	"yellow": "Une étoile tranquille, du genre à laisser la vie s'installer sans poser de questions.",
	"red": "Petite, froide et increvable. Elle brillera encore quand tout le monde aura oublié votre nom.",
	"white": "Le cœur nu d'une étoile morte, qui refuse obstinément de s'éteindre.",
	"blue_giant": "Une fournaise colossale. Ses planètes sont riches, et ses colons ne vivent pas vieux.",
	"neutron": "Une étoile écrasée sur elle-même, qui balaie le vide de ses faisceaux. Les cristaux de saut adorent.",
	"black_hole": "Rien ne s'en échappe, pas même les excuses. On y trouve pourtant des cristaux de saut.",
}

var bar: EmpireBar
var dial: TimeDial
var _tabs: HBoxContainer
var _tab_galaxy: Button
var _tab_economy: Button
var _tab_system: Button
var _info_panel: PanelContainer
var _portrait: Widgets.StarPortrait
var _card_title: Label
var _card_kind: Label
var _card_lore: Label
var _card_owner: Label
var _planet_dots: HBoxContainer
var _enter_button: Button
var _toasts: VBoxContainer
var _chronicle: Widgets.RichTipPanel
var _chronicle_label: Label
var _chronicle_date: Label
var _system_mode := false
var _system_id := -1
var _hover_id := -1
var _state: GameState
var _player := 0
var lens := ""


func _ready() -> void:
	bar = EmpireBar.new()
	add_child(bar)
	bar.screen_requested.connect(func(id: String) -> void: screen_requested.emit(id))
	_build_tabs()
	_build_card()
	_build_chronicle()
	_build_dial()

	_toasts = VBoxContainer.new()
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toasts.offset_top = 58.0
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.add_theme_constant_override("separation", 4)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)
	set_system_mode(false)


## Branche l'interface sur une partie (nouvelle ou chargée) et sur l'empire du joueur local.
func set_state(state: GameState, player: int) -> void:
	_state = state
	_player = player
	bar.set_state(state, player)
	_hover_id = -1
	show_system(null, state)


## Met à jour ce qui change avec le temps. Appelé à chaque tick et après chaque ordre.
func refresh() -> void:
	bar.refresh()
	_refresh_card()


## Système sélectionné sur la carte (null = aucun).
func show_system(s: StarSystem, state: GameState) -> void:
	_state = state
	_system_id = s.id if s else -1
	_refresh_card()


## Vue système ouverte (true) ou carte de la galaxie (false).
func set_system_mode(on: bool) -> void:
	_system_mode = on
	_tab_galaxy.visible = not on
	_tab_economy.visible = not on
	_tab_system.visible = on
	if on:
		_hover_id = -1
	_refresh_card()


## Survol d'un système sur la carte : la fiche le montre à la place de la sélection (null = fin du survol).
func show_hover(s: StarSystem, _screen_pos: Vector2) -> void:
	var id := s.id if s else -1
	if id == _hover_id:
		return
	_hover_id = id
	_refresh_card()


## Système affiché par la fiche : celui survolé, sinon celui sélectionné (-1 si aucun).
func card_system() -> int:
	return _hover_id if _hover_id >= 0 else _system_id


## Affiche la dernière entrée de chronique ({"tick", "text"}) ; l'infobulle donne les précédentes.
func show_chronicle(entry: Dictionary) -> void:
	if entry.is_empty():
		_chronicle_date.text = ""
		_chronicle_label.text = "La chronique attend son premier scandale."
		_chronicle.tooltip_text = ""
		return
	_chronicle_date.text = GameCalendar.date_string(int(entry["tick"]))
	_chronicle_label.text = String(entry["text"])
	if _state:
		var lines := PackedStringArray(["[b]Chronique galactique[/b]"])
		var from := maxi(0, _state.chronicle.size() - 6)
		for i in range(_state.chronicle.size() - 1, from - 1, -1):
			var e: Dictionary = _state.chronicle[i]
			lines.append("[color=#%s]%s[/color]  %s" % [UiTheme.TEXT_DIM.to_html(false), GameCalendar.date_string(int(e["tick"])), e["text"]])
		_chronicle.tooltip_text = "\n".join(lines)


## Petit message temporaire sous les onglets. kind : "info", "good", "bad".
func notify(text: String, kind := "info") -> void:
	var toast := PanelContainer.new()
	var accent: Color = {"good": UiTheme.GOOD, "bad": UiTheme.BAD}.get(kind, UiTheme.ACCENT)
	var st := UiTheme.box(Color(0.03, 0.04, 0.06, 0.9), accent, 8, 0)
	st.border_width_left = 2
	st.content_margin_left = 14
	st.content_margin_right = 14
	toast.add_theme_stylebox_override("panel", st)
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


## Nombre de pastilles de planètes de la fiche (pour les tests).
func planet_row_count() -> int:
	return _planet_dots.get_child_count()


## Lentille de la carte : "" (vue galaxie) ou "economy".
func set_lens(value: String) -> void:
	lens = value
	_tab_galaxy.set_pressed_no_signal(value == "")
	_tab_economy.set_pressed_no_signal(value == "economy")
	lens_changed.emit(value)


# --- Construction ---------------------------------------------------------------------------

func _build_tabs() -> void:
	_tabs = HBoxContainer.new()
	_tabs.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_tabs.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tabs.add_theme_constant_override("separation", 2)
	add_child(_tabs)
	_tab_galaxy = _tab("Vue galaxie", "La carte des systèmes")
	_tab_galaxy.pressed.connect(func() -> void: set_lens(""))
	_tab_economy = _tab("Lentille économique", "Bilan mensuel de chacun de vos systèmes, sur la carte  (L)")
	_tab_economy.pressed.connect(func() -> void: set_lens("" if lens == "economy" else "economy"))
	_tab_system = _tab("Gestion du système   ×", "Revenir à la galaxie  (Échap)")
	_tab_system.pressed.connect(func() -> void: close_system_requested.emit())
	_tab_galaxy.set_pressed_no_signal(true)


func _tab(text: String, tip: String) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"TabButton"
	b.text = text.to_upper()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = tip
	_tabs.add_child(b)
	return b


func _build_card() -> void:
	_info_panel = PanelContainer.new()
	_info_panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL, UiTheme.LINE, 0, 1))
	_info_panel.anchor_top = 1.0
	_info_panel.anchor_bottom = 1.0
	_info_panel.offset_left = MARGIN
	_info_panel.offset_right = MARGIN + CARD_WIDTH
	_info_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_info_panel.offset_bottom = -MARGIN
	_info_panel.offset_top = -MARGIN
	_info_panel.visible = false
	add_child(_info_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	_info_panel.add_child(box)
	_portrait = Widgets.StarPortrait.new(Vector2(CARD_WIDTH - 2.0, 128))
	box.add_child(_portrait)
	var body := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		body.add_theme_constant_override("margin_" + side, 12)
	box.add_child(body)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	body.add_child(inner)
	_card_title = UiTheme.title("", 28)
	inner.add_child(_card_title)
	_card_kind = Label.new()
	_card_kind.add_theme_font_size_override("font_size", 14)
	inner.add_child(_card_kind)
	_card_owner = UiTheme.dim("", 13)
	inner.add_child(_card_owner)
	_planet_dots = HBoxContainer.new()
	_planet_dots.add_theme_constant_override("separation", 6)
	inner.add_child(_planet_dots)
	_card_lore = UiTheme.paragraph("", CARD_WIDTH - 26.0, 13)
	_card_lore.theme_type_variation = &"Dim"
	inner.add_child(_card_lore)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	inner.add_child(gap)
	_enter_button = Button.new()
	_enter_button.theme_type_variation = &"PrimaryButton"
	_enter_button.text = "ENTRER DANS LE SYSTÈME"
	_enter_button.tooltip_text = "Ouvrir la vue système  (Entrée ou double-clic)"
	_enter_button.focus_mode = Control.FOCUS_NONE
	_enter_button.pressed.connect(func() -> void:
		if _system_id >= 0:
			open_system_requested.emit(_system_id))
	inner.add_child(_enter_button)


func _build_chronicle() -> void:
	_chronicle = Widgets.RichTipPanel.new()
	_chronicle.tip_width = 460.0
	_chronicle.anchor_left = 1.0
	_chronicle.anchor_right = 1.0
	_chronicle.offset_left = -CHRONICLE_WIDTH - MARGIN
	_chronicle.offset_right = -MARGIN
	_chronicle.offset_top = MARGIN
	var st := UiTheme.box(Color(0.03, 0.04, 0.06, 0.72), UiTheme.LINE, 10, 0)
	st.border_width_left = 2
	st.border_color = Color(UiTheme.ACCENT, 0.6)
	_chronicle.add_theme_stylebox_override("panel", st)
	_chronicle.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_chronicle)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chronicle.add_child(box)
	var head := HBoxContainer.new()
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(head)
	var tag := UiTheme.section("Chronique galactique")
	tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag.add_theme_color_override("font_color", UiTheme.TEXT)
	head.add_child(tag)
	_chronicle_date = UiTheme.dim("", 12)
	head.add_child(_chronicle_date)
	_chronicle_label = UiTheme.paragraph("", CHRONICLE_WIDTH - 24.0, 14)
	_chronicle_label.add_theme_color_override("font_color", Color(UiTheme.TEXT, 0.85))
	box.add_child(_chronicle_label)


func _build_dial() -> void:
	dial = TimeDial.new()
	dial.anchor_left = 1.0
	dial.anchor_right = 1.0
	dial.anchor_top = 1.0
	dial.anchor_bottom = 1.0
	dial.offset_left = -TimeDial.SIDE - MARGIN
	dial.offset_right = -MARGIN
	dial.offset_top = -TimeDial.SIDE - MARGIN
	dial.offset_bottom = -MARGIN
	dial.pause_toggled.connect(func() -> void: pause_toggled.emit())
	dial.speed_requested.connect(func(i: int) -> void: speed_requested.emit(i))
	add_child(dial)
	var menu := Widgets.IconButton.new("menu", 36)
	menu.theme_type_variation = &""
	menu.anchor_left = 1.0
	menu.anchor_right = 1.0
	menu.anchor_top = 1.0
	menu.anchor_bottom = 1.0
	menu.offset_left = -MARGIN - 36.0
	menu.offset_right = -MARGIN
	menu.offset_top = -TimeDial.SIDE - MARGIN - 40.0
	menu.offset_bottom = -TimeDial.SIDE - MARGIN - 4.0
	menu.tooltip_text = "Menu du jeu  (Échap)"
	menu.pressed.connect(func() -> void: menu_requested.emit())
	add_child(menu)


func _refresh_card() -> void:
	if _info_panel == null:
		return
	var id := card_system()
	if _state == null or id < 0 or _system_mode:
		_info_panel.visible = false
		return
	_info_panel.visible = true
	var galaxy := _state.galaxy
	var s := galaxy.get_system(id)
	var owner := _state.get_empire(_state.system_owner(s.id))
	_portrait.set_star(s.star_type, fmod(float(s.id) * 0.731, 7.0))
	_card_title.text = s.system_name
	_card_title.add_theme_color_override("font_color", owner.color().lightened(0.35) if owner else UiTheme.TEXT)
	_card_kind.text = "Système stellaire (%s)" % GalaxyGenerator.star_label(s.star_type)
	_card_owner.text = "%s  ·  %s" % [
		"Système de %s" % owner.short_name() if owner else "Système libre",
		"à portée" if Economy.in_range(_state, _player, s.id) else "hors de portée",
	]
	_card_lore.text = String(STAR_LORE.get(s.star_type, ""))
	# Une pastille par planète, à la couleur de son type ; un anneau à la couleur du propriétaire.
	var dots := _planet_dots.get_children()
	if dots.size() != s.planet_count:
		for d in dots:
			_planet_dots.remove_child(d)
			d.queue_free()
		for i in s.planet_count:
			var dot := Widgets.Dot.new(Color.WHITE, 14)
			dot.mouse_filter = Control.MOUSE_FILTER_STOP
			_planet_dots.add_child(dot)
	for i in s.planet_count:
		var p := galaxy.get_planet(s.planet_ids[i])
		var dot := _planet_dots.get_child(i) as Widgets.Dot
		dot.color = SystemScreen.TYPE_DOT_COLORS.get(p.type, Color.GRAY)
		var c: Colony = _state.colonies.get(p.id)
		dot.ring = _state.get_empire(c.owner).color() if c else Color(0, 0, 0, 0)
		dot.tooltip_text = "%s  ·  %s  ·  taille %d\n%s" % [p.display_name(galaxy), p.type_label(), p.size, PlanetInfo.status_line(_state, p)]
		dot.queue_redraw()
	# Le bouton n'a de sens que pour le système sélectionné (pas pour un simple survol).
	_enter_button.visible = id == _system_id
	_enter_button.text = "CONTEMPLER LE VIDE" if s.planet_count == 0 else "ENTRER DANS LE SYSTÈME"
