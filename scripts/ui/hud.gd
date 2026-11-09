class_name Hud
extends CanvasLayer
## Interface : barre du haut (date, vitesse, ressources de l'empire du joueur), fiche résumée du
## système sélectionné sur la carte (avec l'accès à sa vue système), dernière entrée de la
## chronique, notifications et aide en bas.
## Les actions sur les planètes (colonisation, construction, renommage) se font dans la vue système
## (SystemScreen). L'interface ne modifie jamais la partie : elle émet des demandes.

signal open_system_requested(system_id: int)

const SPEED_NAMES := ["1", "2", "3", "4", "5"]
const NOTIFY_SECONDS := 3.0
const PANEL_WIDTH := 430.0
const HELP_GALAXY := "Espace : pause   1 à 5 : vitesse   Clic : sélectionner   Double-clic ou Entrée : vue système   Clic droit glissé ou ZQSD : se déplacer   Molette : zoom   F5 / F9 : sauver / charger   R : nouvelle galaxie"
const HELP_SYSTEM := "Espace : pause   1 à 5 : vitesse   Clic sur une planète : la choisir   Tab : vue orbitale / gestion   Échap : retour à la galaxie   F5 / F9 : sauvegarder / charger"

var _top_label: Label
var _res_label: Label
var _info_panel: PanelContainer
var _info_label: Label
var _planet_label: Label
var _enter_button: Button
var _help: Label
var _system_mode := false
var _chronicle_label: Label
var _notify_label: Label
var _notify_left := 0.0
var _seed_text := ""
var _system_id := -1
var _state: GameState
var _player := 0


func _ready() -> void:
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE  # simple affichage : les clics passent à la carte
	add_child(top)
	var top_box := VBoxContainer.new()
	top_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(top_box)
	_top_label = Label.new()
	_top_label.add_theme_font_size_override("font_size", 16)
	top_box.add_child(_top_label)
	_res_label = Label.new()
	_res_label.add_theme_font_size_override("font_size", 15)
	_res_label.modulate = Color(0.85, 0.92, 1.0)
	top_box.add_child(_res_label)

	_info_panel = PanelContainer.new()
	_info_panel.anchor_left = 1.0
	_info_panel.anchor_right = 1.0
	_info_panel.offset_left = -PANEL_WIDTH - 16.0
	_info_panel.offset_right = -16.0
	_info_panel.offset_top = 72.0
	_info_panel.visible = false
	_info_panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(_info_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_info_panel.add_child(box)
	_info_label = Label.new()
	_info_label.custom_minimum_size = Vector2(PANEL_WIDTH - 30.0, 0)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info_label)
	_planet_label = Label.new()
	_planet_label.custom_minimum_size = Vector2(PANEL_WIDTH - 30.0, 0)
	_planet_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_planet_label.modulate = Color(1, 1, 1, 0.82)
	box.add_child(_planet_label)
	_enter_button = Button.new()
	_enter_button.text = "Entrer dans le système  (Entrée)"
	_enter_button.focus_mode = Control.FOCUS_NONE
	_enter_button.pressed.connect(func() -> void:
		if _system_id >= 0:
			open_system_requested.emit(_system_id))
	box.add_child(_enter_button)

	_chronicle_label = Label.new()
	_chronicle_label.anchor_top = 1.0
	_chronicle_label.anchor_bottom = 1.0
	_chronicle_label.anchor_right = 1.0
	_chronicle_label.offset_top = -64.0
	_chronicle_label.offset_left = 16.0
	_chronicle_label.offset_right = -16.0
	_chronicle_label.modulate = Color(1.0, 0.88, 0.6, 0.9)
	_chronicle_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	add_child(_chronicle_label)

	_notify_label = Label.new()
	_notify_label.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_notify_label.offset_top = 72.0
	_notify_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notify_label.add_theme_font_size_override("font_size", 18)
	_notify_label.visible = false
	add_child(_notify_label)

	_help = Label.new()
	_help.anchor_top = 1.0
	_help.anchor_bottom = 1.0
	_help.offset_top = -34.0
	_help.offset_left = 16.0
	_help.modulate = Color(1, 1, 1, 0.7)
	_help.text = HELP_GALAXY
	add_child(_help)

	GameClock.day_passed.connect(func(_day: int) -> void: _refresh_top())
	GameClock.speed_changed.connect(func(_speed: int) -> void: _refresh_top())
	GameClock.pause_changed.connect(func(_paused: bool) -> void: _refresh_top())
	_refresh_top()


func _process(delta: float) -> void:
	if _notify_left > 0.0:
		_notify_left -= delta
		_notify_label.modulate.a = clampf(_notify_left, 0.0, 1.0)
		if _notify_left <= 0.0:
			_notify_label.visible = false


## Branche l'interface sur une partie (nouvelle ou chargée) et sur l'empire du joueur local.
func set_state(state: GameState, player: int) -> void:
	_state = state
	_player = player
	_refresh_top()


func set_galaxy_info(seed_value: int, system_count: int) -> void:
	_seed_text = "Graine %d  ·  %d systèmes" % [seed_value, system_count]
	_refresh_top()


## Met à jour ce qui change avec le temps (ressources, fiche ouverte). Appelé à chaque tick et après chaque ordre.
func refresh() -> void:
	_refresh_top()
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


## Vue système ouverte (true) ou carte de la galaxie (false) : la fiche résumée et l'aide s'adaptent.
func set_system_mode(on: bool) -> void:
	_system_mode = on
	_info_panel.visible = not on and _system_id >= 0
	_help.text = HELP_SYSTEM if on else HELP_GALAXY


## Affiche une entrée de chronique ({"tick", "text"}), ou efface la ligne si l'entrée est vide.
func show_chronicle(entry: Dictionary) -> void:
	if entry.is_empty():
		_chronicle_label.text = ""
		return
	_chronicle_label.text = "Chronique, %s : %s" % [GameCalendar.date_string(int(entry["tick"])), entry["text"]]


func notify(text: String) -> void:
	_notify_label.text = text
	_notify_label.visible = true
	_notify_label.modulate.a = 1.0
	_notify_left = NOTIFY_SECONDS


func _refresh_system() -> void:
	if _state == null or _system_id < 0:
		return
	var galaxy := _state.galaxy
	var s := galaxy.get_system(_system_id)
	var neighbor_names := PackedStringArray()
	for n in s.neighbors:
		neighbor_names.append(galaxy.systems[n].system_name)
	var owner := _state.get_empire(_state.system_owner(s.id))
	_info_label.text = "%s\n%s  ·  %s\nÉtoile : %s  ·  Planètes : %d\nRoutes de saut (%d) : %s" % [
		s.system_name,
		"Système de %s" % owner.display_name() if owner else "Système libre",
		"à portée" if Economy.in_range(_state, _player, s.id) else "hors de portée",
		GalaxyGenerator.star_label(s.star_type),
		s.planet_count,
		s.neighbors.size(),
		", ".join(neighbor_names),
	]
	var lines := PackedStringArray()
	for pid in s.planet_ids:
		var p := galaxy.get_planet(pid)
		lines.append("%s  ·  %s  ·  %s" % [p.display_name(galaxy), p.type_label(), PlanetInfo.status_line(_state, p)])
	_planet_label.text = "\n".join(lines) if not lines.is_empty() else "Aucune planète."


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.1, 0.94)
	style.border_color = Color(0.55, 0.7, 1.0, 0.35)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.set_content_margin_all(12)
	return style


func _refresh_top() -> void:
	if _top_label == null:
		return
	var state := "EN PAUSE" if GameClock.paused else "Vitesse %s" % SPEED_NAMES[GameClock.speed_index]
	_top_label.text = "  STELLAR SIGTH (prototype)    |    %s    |    %s    |    %s" % [
		GameClock.date_string(), state, _seed_text,
	]
	var me := _state.get_empire(_player) if _state else null
	if me == null:
		_res_label.text = ""
		return
	var net: Dictionary = Economy.empire_income(_state, _player)["net"]
	var parts := PackedStringArray()
	for r in GameData.resource_ids():
		parts.append("%s %d (%+d)" % [GameData.resource_label(r), int(me.resources[r]), int(net[r])])
	var alerts := ""
	if me.starving:
		alerts += "    FAMINE"
	if me.blackout:
		alerts += "    PÉNURIE D'ÉNERGIE"
	_res_label.text = "  %s    |    %s    (par mois)%s" % [me.display_name(), "   ".join(parts), alerts]
