class_name Hud
extends CanvasLayer
## Interface : barre du haut (date, vitesse, ressources de l'empire du joueur), fiche du système
## sélectionné (planètes, colonies, colonisation, construction, renommage), dernière entrée de la
## chronique, notifications et aide en bas.
## L'interface ne modifie jamais la partie : elle émet des demandes (rename_requested,
## colonize_requested, build_requested) que main.gd transforme en ordres pour la simulation.
## Pour griser un bouton, elle pose la même question que la simulation (SimCommands.validate).

signal rename_requested(system_id: int, new_name: String)
signal colonize_requested(planet_id: int, kind: String)
signal build_requested(planet_id: int, building_id: String)

const SPEED_NAMES := ["1", "2", "3", "4", "5"]
const NOTIFY_SECONDS := 3.0
const PANEL_WIDTH := 430.0
const PLANETS_MAX_HEIGHT := 520.0

var _top_label: Label
var _res_label: Label
var _info_panel: PanelContainer
var _info_label: Label
var _planet_scroll: ScrollContainer
var _planet_box: VBoxContainer
var _build_menus: Array[MenuButton] = []
var _name_edit: LineEdit
var _chronicle_label: Label
var _notify_label: Label
var _notify_left := 0.0
var _seed_text := ""
var _system_id := -1
var _state: GameState
var _player := 0
var _refresh_pending := false


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
	_planet_scroll = ScrollContainer.new()
	_planet_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(_planet_scroll)
	_planet_box = VBoxContainer.new()
	_planet_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_planet_box.add_theme_constant_override("separation", 8)
	_planet_scroll.add_child(_planet_box)
	var rename_row := HBoxContainer.new()
	box.add_child(rename_row)
	_name_edit = LineEdit.new()
	_name_edit.max_length = SimCommands.NAME_MAX_LENGTH
	_name_edit.placeholder_text = "Nouveau nom du système"
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
	_notify_label.offset_top = 72.0
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
	if _refresh_pending and not _menu_open():
		_refresh_pending = false
		_refresh_system()


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
		if _menu_open():
			# Ne pas reconstruire un menu ouvert sous le curseur : on attend qu'il se ferme.
			_refresh_pending = true
		else:
			_refresh_system()


func show_system(s: StarSystem, state: GameState) -> void:
	if s == null:
		_system_id = -1
		_name_edit.release_focus()
		_info_panel.visible = false
		return
	_state = state
	if _system_id != s.id:
		_name_edit.text = ""
	_system_id = s.id
	_refresh_system()
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
	for child in _planet_box.get_children():
		_planet_box.remove_child(child)
		child.queue_free()
	_build_menus.clear()
	for pid in s.planet_ids:
		_planet_box.add_child(_planet_row(galaxy.get_planet(pid)))
	_planet_scroll.visible = not s.planet_ids.is_empty()
	# Hauteur de la liste : son contenu, plafonné (on fait défiler au-delà).
	_planet_scroll.custom_minimum_size = Vector2(PANEL_WIDTH - 30.0, minf(PLANETS_MAX_HEIGHT, 96.0 * s.planet_ids.size()))


func _planet_row(p: Planet) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	var me := _state.get_empire(_player)
	var c: Colony = _state.colonies.get(p.id)

	var title := Label.new()
	title.add_theme_font_size_override("font_size", 15)
	title.text = "%s  ·  %s, taille %d" % [p.display_name(_state.galaxy), p.type_label(), p.size]
	if c:
		title.modulate = _state.get_empire(c.owner).color().lightened(0.25)
	row.add_child(title)

	var lines := PackedStringArray()
	if me and p.is_habitable_type():
		var hab := Economy.habitability(p.type, me.faction())
		var cap := Economy.max_pop(_state, p, _player)
		lines.append("Habitable à %d %% pour vous (%d pop max)" % [hab, cap] if cap > 0 else "Inhabitable pour votre espèce")
	elif not p.is_habitable_type():
		lines.append("Inhabitable (avant-poste seulement)")
	if not p.deposits.is_empty():
		var deps := PackedStringArray()
		for d in p.deposits:
			deps.append(String(GameData.deposit(d).get("label", d)))
		lines.append("Gisements : %s" % ", ".join(deps))
	if c:
		lines.append_array(_colony_lines(p, c))
	var details := Label.new()
	details.text = "\n".join(lines)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.custom_minimum_size = Vector2(PANEL_WIDTH - 50.0, 0)
	details.modulate = Color(1, 1, 1, 0.8)
	row.add_child(details)

	var actions := HBoxContainer.new()
	if c == null or (c.owner == _player and not c.is_colony()):
		actions.add_child(_claim_button(p, Colony.KIND_COLONY))
	if c == null:
		actions.add_child(_claim_button(p, Colony.KIND_OUTPOST))
	if c and c.owner == _player and c.is_established():
		actions.add_child(_build_menu(p))
	if actions.get_child_count() > 0:
		row.add_child(actions)
	row.add_child(HSeparator.new())
	return row


func _colony_lines(p: Planet, c: Colony) -> PackedStringArray:
	var lines := PackedStringArray()
	var owner := _state.get_empire(c.owner)
	var kind_label := "Colonie" if c.is_colony() else "Avant-poste"
	if not c.is_established():
		lines.append("%s de %s en fondation : %d j" % [kind_label, owner.short_name(), c.days_left])
		return lines
	if c.is_colony():
		var cap := Economy.max_pop(_state, p, c.owner, c.buildings)
		@warning_ignore("integer_division")
		var growth := "" if c.population >= cap else ", croissance %d %%" % (100 * c.growth / Economy.growth_threshold(c.population))
		lines.append("%s de %s : %d/%d pop%s" % [kind_label, owner.short_name(), c.population, cap, growth])
	else:
		lines.append("%s de %s" % [kind_label, owner.short_name()])
	if not c.buildings.is_empty():
		var names := PackedStringArray()
		for b in c.buildings:
			names.append(String(GameData.building(b).get("label", b)))
		lines.append("Bâtiments (%d/%d) : %s" % [Economy.building_slots_used(c), Economy.building_slots(_state, c), ", ".join(names)])
	if c.construction != "":
		lines.append("Chantier : %s (%d j)" % [GameData.building(c.construction).get("label", c.construction), c.construction_days])
	if c.owner == _player:
		var y := Economy.colony_yields(_state, c)
		var net := {}
		for r in y["gross"]:
			net[r] = int(y["gross"][r]) - int(y["upkeep"][r])
		lines.append("Par mois (avant bonus) : %s" % GameData.format_amounts(net, true))
	return lines


func _claim_button(p: Planet, kind: String) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	var cost := GameData.format_amounts(Economy.claim_cost(kind))
	var upgrade: bool = _state.colonies.has(p.id)
	b.text = "%s (%s)" % ["Fonder une colonie" if upgrade else ("Coloniser" if kind == Colony.KIND_COLONY else "Avant-poste"), cost]
	var reason := SimCommands.validate(_state, SimCommands.colonize(_player, p.id, kind))
	b.disabled = reason != ""
	b.tooltip_text = reason if reason != "" else "%d jours. %s" % [Economy.claim_days(kind),
			"Une colonie accueille une population." if kind == Colony.KIND_COLONY else "Un avant-poste revendique le système et exploite la planète, sans population."]
	b.pressed.connect(func() -> void: colonize_requested.emit(p.id, kind))
	return b


func _build_menu(p: Planet) -> MenuButton:
	var menu := MenuButton.new()
	menu.text = "Construire…"
	menu.flat = false
	menu.focus_mode = Control.FOCUS_NONE
	var popup := menu.get_popup()
	var ids: Array[String] = []
	for bid in GameData.buildings():
		var b := GameData.building(bid)
		if not b.get("buildable", true):
			continue
		var reason := SimCommands.validate(_state, SimCommands.build(_player, p.id, bid))
		var gain := GameData.format_amounts(b.get("yields", {}), true)
		if b.has("max_pop"):
			gain = "+%d pop max" % int(b["max_pop"])
		popup.add_item("%s : %s, %d j (%s)" % [b["label"], GameData.format_amounts(b.get("cost", {})), int(b["days"]), gain], ids.size())
		var idx := popup.item_count - 1
		popup.set_item_disabled(idx, reason != "")
		popup.set_item_tooltip(idx, reason)
		ids.append(bid)
	popup.id_pressed.connect(func(id: int) -> void: build_requested.emit(p.id, ids[id]))
	popup.popup_hide.connect(func() -> void: _refresh_pending = true)
	_build_menus.append(menu)
	return menu


func _menu_open() -> bool:
	for m in _build_menus:
		if is_instance_valid(m) and m.get_popup().visible:
			return true
	return false


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
