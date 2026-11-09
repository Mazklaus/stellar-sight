class_name Hud
extends CanvasLayer
## Interface : barre du haut (date, vitesse), fiche du système sélectionné, aide en bas.

const SPEED_NAMES := ["1", "2", "3", "4", "5"]

var _top_label: Label
var _info_panel: PanelContainer
var _info_label: Label
var _seed_text := ""


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
	add_child(_info_panel)
	_info_label = Label.new()
	_info_label.custom_minimum_size = Vector2(300, 0)
	_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_info_panel.add_child(_info_label)

	var help := Label.new()
	help.anchor_top = 1.0
	help.anchor_bottom = 1.0
	help.offset_top = -34.0
	help.offset_left = 16.0
	help.modulate = Color(1, 1, 1, 0.7)
	help.text = "Espace : pause   1 à 5 : vitesse   Clic gauche : sélectionner   Clic droit glissé, ZQSD ou flèches : se déplacer   Molette : zoom   R : nouvelle galaxie"
	add_child(help)

	GameClock.day_passed.connect(func(_day: int) -> void: _refresh_top())
	GameClock.speed_changed.connect(func(_speed: int) -> void: _refresh_top())
	GameClock.pause_changed.connect(func(_paused: bool) -> void: _refresh_top())
	_refresh_top()


func set_galaxy_info(seed_value: int, system_count: int) -> void:
	_seed_text = "Graine %d  ·  %d systèmes" % [seed_value, system_count]
	_refresh_top()


func show_system(s: StarSystem, galaxy: Galaxy) -> void:
	if s == null:
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
	_info_panel.visible = true


func _refresh_top() -> void:
	if _top_label == null:
		return
	var state := "EN PAUSE" if GameClock.paused else "Vitesse %s" % SPEED_NAMES[GameClock.speed_index]
	_top_label.text = "  STELLAR SIGTH (prototype)    |    %s    |    %s    |    %s" % [
		GameClock.date_string(), state, _seed_text,
	]
