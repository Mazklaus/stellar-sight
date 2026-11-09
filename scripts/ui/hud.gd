class_name Hud
extends CanvasLayer
## Interface : barre du haut (date, vitesse), fiche du système sélectionné (avec renommage),
## dernière entrée de la chronique, notifications et aide en bas.
## L'interface ne modifie jamais la partie : elle émet des demandes (rename_requested)
## que main.gd transforme en ordres pour la simulation.

signal rename_requested(system_id: int, new_name: String)

const SPEED_NAMES := ["1", "2", "3", "4", "5"]
const NOTIFY_SECONDS := 3.0

var _top_label: Label
var _info_panel: PanelContainer
var _info_label: Label
var _name_edit: LineEdit
var _chronicle_label: Label
var _notify_label: Label
var _notify_left := 0.0
var _seed_text := ""
var _system_id := -1


func _ready() -> void:
	var top := PanelContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	add_child(top)
	_top_label = Label.new()
	_top_label.add_theme_font_size_override("font_size", 16)
	top.add_child(_top_label)

	_info_panel = PanelContainer.new()
	_info_panel.anchor_left = 1.0
	_info_panel.anchor_right = 1.0
	_info_panel.offset_left = -336.0
	_info_panel.offset_right = -16.0
	_info_panel.offset_top = 56.0
	_info_panel.visible = false
	_info_panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(_info_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_info_panel.add_child(box)
	_info_label = Label.new()
	_info_label.custom_minimum_size = Vector2(300, 0)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_info_label)
	var rename_row := HBoxContainer.new()
	box.add_child(rename_row)
	_name_edit = LineEdit.new()
	_name_edit.max_length = SimCommands.NAME_MAX_LENGTH
	_name_edit.placeholder_text = "Nouveau nom"
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.text_submitted.connect(func(_t: String) -> void: _submit_rename())
	rename_row.add_child(_name_edit)
	var rename_button := Button.new()
	rename_button.text = "Renommer"
	rename_button.focus_mode = Control.FOCUS_NONE
	rename_button.pressed.connect(_submit_rename)
	rename_row.add_child(rename_button)

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
	_notify_label.offset_top = 48.0
	_notify_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_notify_label.add_theme_font_size_override("font_size", 18)
	_notify_label.visible = false
	add_child(_notify_label)

	var help := Label.new()
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_top = -34.0
	help.offset_left = 16.0
	help.modulate = Color(1, 1, 1, 0.7)
	help.text = "Espace : pause   1 à 5 : vitesse   Clic gauche : sélectionner   Clic droit glissé, ZQSD ou flèches : se déplacer   Molette : zoom   F5 : sauvegarder   F9 : charger   R : nouvelle galaxie"
	add_child(help)

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


func set_galaxy_info(seed_value: int, system_count: int) -> void:
	_seed_text = "Graine %d  ·  %d systèmes" % [seed_value, system_count]
	_refresh_top()


func show_system(s: StarSystem, galaxy: Galaxy) -> void:
	if s == null:
		_system_id = -1
		_name_edit.release_focus()
		_info_panel.visible = false
		return
	var neighbor_names := PackedStringArray()
	for n in s.neighbors:
		neighbor_names.append(galaxy.systems[n].system_name)
	_info_label.text = "%s\n\nÉtoile : %s\nPlanètes : %d\nRoutes de saut (%d) : %s" % [
		s.system_name,
		GalaxyGenerator.star_label(s.star_type),
		s.planet_count,
		s.neighbors.size(),
		", ".join(neighbor_names),
	]
	if _system_id != s.id:
		_name_edit.text = ""
	_system_id = s.id
	_info_panel.visible = true


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


func _submit_rename() -> void:
	var new_name := _name_edit.text.strip_edges()
	if _system_id < 0 or new_name.is_empty():
		return
	rename_requested.emit(_system_id, new_name)
	_name_edit.text = ""
	_name_edit.release_focus()


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
