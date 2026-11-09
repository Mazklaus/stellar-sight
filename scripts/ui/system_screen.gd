class_name SystemScreen
extends CanvasLayer
## Écran dédié à un système, avec deux vues que l'on bascule par les onglets du HUD (ou Tab) :
## - la vue orbitale (SystemView) : l'étoile, les planètes en orbite et leurs fiches accrochées ;
## - la vue de gestion (SystemManagePanel) : les planètes alignées en grand pour les comparer.
## Autour : une colonne à gauche (nom du système, renommage, fiche de la planète choisie et ses
## ordres), un bandeau de planètes en bas (vue orbitale) et des flèches pour changer de système.
## Comme le reste de l'interface, il ne modifie jamais la partie : il émet des demandes
## que main.gd transforme en ordres (SimCommands). Les boutons grisés posent la même question
## que la simulation (SimCommands.validate) et affichent sa réponse en infobulle.

signal close_requested
signal rename_requested(system_id: int, new_name: String)
signal colonize_requested(planet_id: int, kind: String)
signal build_requested(planet_id: int, building_id: String)
signal build_ship_requested(planet_id: int, ship_id: String)
## Ordre de trait de faction déjà formé (offrande, vote d'urgence) : main.gd le soumet tel quel.
signal command_requested(cmd: Dictionary)
## Passer au système suivant (1) ou précédent (-1) de l'empire.
signal cycle_requested(step: int)
## La vue affichée a changé : gestion (true) ou orbitale (false). Les onglets du HUD suivent.
signal mode_changed(manage: bool)

## Colonne de gestion, à gauche, sous le panneau d'empire.
const PANEL_WIDTH := EmpireBar.WIDTH
const PANEL_TOP := EmpireBar.MARGIN + EmpireBar.HEIGHT + 8.0
const MARGIN := 10.0
## Début de la scène, à droite de la colonne.
const SCENE_LEFT := PANEL_WIDTH + 2.0 * MARGIN
const CARD_SIZE := Vector2(150, 56)
const ACCENT := UiTheme.ACCENT
const TYPE_DOT_COLORS := {
	"continental": Color(0.3, 0.6, 0.35), "ocean": Color(0.2, 0.45, 0.85), "desert": Color(0.9, 0.65, 0.35),
	"arctic": Color(0.85, 0.92, 1.0), "toxic": Color(0.65, 0.75, 0.2), "gas_giant": Color(0.88, 0.72, 0.5),
	"barren": Color(0.55, 0.53, 0.5), "asteroids": Color(0.6, 0.55, 0.48),
}

var view: SystemView
var manage: SystemManagePanel
## Vue de gestion affichée (true) ou vue orbitale (false). Gardé d'un système à l'autre.
var manage_mode := false
var system_id := -1
var planet_id := -1

var _state: GameState
var _player := 0
var _title: Label
var _subtitle: Label
var _rename_edit: LineEdit
var _rename_button: Button
var _cards: HBoxContainer
var _card_ids: Array[int] = []
var _panel: PanelContainer
var _p_title: Label
var _p_sub: Label
var _hab_title: Label
var _hab_bar: ProgressBar
var _hab_label: Label
var _dep_title: Label
var _dep_label: Label
var _status_title: Label
var _status_label: Label
var _actions_title: Label
var _actions: VBoxContainer
var _actions_sig := ""
var _pot_title: Label
var _pot_view: Control
var _icons := {}
var _panel_box: VBoxContainer


func _ready() -> void:
	layer = 1  # sous l'interface principale (barre du haut, chronique), au-dessus de la carte
	visible = false
	view = SystemView.new()
	# La scène occupe ce qui reste à droite de la colonne, au-dessus du bandeau des planètes.
	view.margins = Vector4(SCENE_LEFT, 64.0, 40.0, CARD_SIZE.y + 2.0 * MARGIN + 20.0)
	view.planet_clicked.connect(select_planet)
	add_child(view)
	manage = SystemManagePanel.new()
	manage.anchor_right = 1.0
	manage.anchor_bottom = 1.0
	# À droite de la colonne, sous les onglets, en laissant le coin du cadran du temps libre.
	# Entre les flèches de changement de système, sous la chronique, au-dessus du cadran.
	manage.offset_left = SCENE_LEFT + 60.0
	manage.offset_top = 110.0
	manage.offset_right = -70.0
	manage.offset_bottom = -TimeDial.SIDE - 10.0
	manage.visible = false
	manage.actions_for = planet_actions
	manage.planet_clicked.connect(select_planet)
	add_child(manage)
	_build_panel()
	_build_header()
	_build_cards()
	_build_nav()


## Lecture seule (mode spectateur) : on regarde les planètes, on ne donne aucun ordre.
var read_only := false


## Ouvre l'écran sur un système. La planète du joueur (sa capitale d'abord) est choisie d'office.
func open(state: GameState, s: StarSystem, player: int) -> void:
	_state = state
	_player = player
	system_id = s.id
	planet_id = _default_planet(s)
	_rename_edit.visible = false
	_rename_edit.text = ""
	view.set_system(state, s, player)
	_rebuild_cards()
	var was_open := visible
	visible = true
	manage.set_system(state, s, player)
	set_manage_mode(manage_mode)
	if not was_open:
		# Arrivée en fondu depuis la carte.
		for n: CanvasItem in [view, manage]:
			n.modulate.a = 0.0
			n.create_tween().tween_property(n, "modulate:a", 1.0, 0.25)


func close() -> void:
	visible = false
	system_id = -1
	planet_id = -1
	_rename_edit.release_focus()
	view.set_system(null, null, _player)
	manage.set_system(null, null, _player)


func is_open() -> bool:
	return visible and system_id >= 0


func select_planet(pid: int) -> void:
	planet_id = pid
	refresh()


## Planète suivante (step = 1) ou précédente (-1) dans l'ordre des orbites, en boucle.
func select_adjacent_planet(step: int) -> void:
	if not is_open() or _card_ids.is_empty():
		return
	var i := _card_ids.find(planet_id)
	select_planet(_card_ids[posmod(i + step, _card_ids.size())] if i >= 0 else _card_ids[0])


## Met à jour les textes (appelé à chaque tick et après chaque ordre). Les boutons ne sont
## reconstruits que si leur état change, pour ne pas voler un clic en cours.
func refresh() -> void:
	if not is_open():
		return
	var s := _state.galaxy.get_system(system_id)
	view.selected_planet = planet_id
	manage.selected_planet = planet_id
	_refresh_header(s)
	_refresh_cards()
	_refresh_panel(s)
	if manage_mode:
		manage.refresh()


## Bascule entre la vue orbitale et la vue de gestion.
func set_manage_mode(on: bool) -> void:
	manage_mode = on
	manage.visible = on
	view.show_scene = not on
	_cards.visible = not on
	mode_changed.emit(on)
	refresh()


func toggle_mode() -> void:
	set_manage_mode(not manage_mode)




# --- En-tête ---------------------------------------------------------------------------------

func _build_header() -> void:
	# En tête de la colonne : nom du système (renommable) et sa situation.
	var head := VBoxContainer.new()
	head.add_theme_constant_override("separation", 0)
	_panel_box.add_child(head)
	_panel_box.move_child(head, 0)
	var sep := HSeparator.new()
	_panel_box.add_child(sep)
	_panel_box.move_child(sep, 1)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	head.add_child(row)
	_title = UiTheme.title("", 36)
	_title.clip_text = true
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_title)
	_rename_button = Button.new()
	_rename_button.text = "Renommer"
	_rename_button.flat = true
	_rename_button.focus_mode = Control.FOCUS_NONE
	_rename_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rename_button.add_theme_color_override("font_color", Color(ACCENT, 0.8))
	_rename_button.pressed.connect(_toggle_rename)
	row.add_child(_rename_button)
	_rename_edit = LineEdit.new()
	_rename_edit.max_length = SimCommands.NAME_MAX_LENGTH
	_rename_edit.placeholder_text = "Nouveau nom, puis Entrée"
	_rename_edit.custom_minimum_size = Vector2(180, 0)
	_rename_edit.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_rename_edit.visible = false
	_rename_edit.text_submitted.connect(func(_t: String) -> void: submit_rename())
	row.add_child(_rename_edit)
	_subtitle = UiTheme.paragraph("", PANEL_WIDTH - 40.0, 13)
	_subtitle.theme_type_variation = &"Dim"
	head.add_child(_subtitle)


## Flèches de part et d'autre de la scène : système précédent / suivant de l'empire.
func _build_nav() -> void:
	for step in [-1, 1]:
		var b := Widgets.IconButton.new("prev" if step < 0 else "next", 40)
		b.theme_type_variation = &""
		b.tooltip_text = "Système %s de l'empire  (%s)" % ["précédent" if step < 0 else "suivant", "Maj+Tab" if step < 0 else "Tab"]
		b.anchor_top = 0.5
		b.anchor_bottom = 0.5
		b.offset_top = -20.0
		b.offset_bottom = 20.0
		if step < 0:
			b.offset_left = SCENE_LEFT + 6.0
			b.offset_right = SCENE_LEFT + 46.0
		else:
			b.anchor_left = 1.0
			b.anchor_right = 1.0
			b.offset_left = -46.0
			b.offset_right = -6.0
		var st: int = step
		b.pressed.connect(func() -> void: cycle_requested.emit(st))
		add_child(b)


func _refresh_header(s: StarSystem) -> void:
	_title.text = s.system_name
	var owner := _state.get_empire(_state.system_owner(s.id))
	_title.add_theme_color_override("font_color", owner.color().lightened(0.35) if owner else Color(0.95, 0.96, 1.0))
	var parts := PackedStringArray([GalaxyGenerator.star_label(s.star_type)])
	parts.append("%d planète%s" % [s.planet_count, "s" if s.planet_count > 1 else ""] if s.planet_count > 0 else "aucune planète")
	parts.append("Système de %s" % owner.display_name() if owner else "Système libre")
	parts.append("à portée" if Economy.in_range(_state, _player, s.id) else "hors de portée")
	var names := PackedStringArray()
	for f in Fleets.fleets_at(_state, s.id):
		if f.owner == _player or Fleets.fleet_visible(_state, _player, f, Fleets.visible_systems(_state, _player)):
			names.append(f.fleet_name if f.owner == _player else "%s (%s)" % [f.fleet_name, _state.get_empire(f.owner).short_name()])
	if not names.is_empty():
		parts.append("en orbite : %s" % ", ".join(names))
	_subtitle.text = "  ·  ".join(parts)


func _toggle_rename() -> void:
	_rename_edit.visible = not _rename_edit.visible
	if _rename_edit.visible:
		_rename_edit.text = ""
		_rename_edit.grab_focus()
	else:
		_rename_edit.release_focus()


func submit_rename() -> void:
	var new_name := _rename_edit.text.strip_edges()
	_rename_edit.release_focus()
	_rename_edit.visible = false
	if system_id >= 0 and not new_name.is_empty():
		rename_requested.emit(system_id, new_name)
	_rename_edit.text = ""


## Vrai si le champ de renommage a le clavier (main.gd ne doit alors pas traiter les touches).
func is_typing() -> bool:
	return _rename_edit.has_focus()


# --- Bandeau des planètes --------------------------------------------------------------------

func _build_cards() -> void:
	_cards = HBoxContainer.new()
	_cards.add_theme_constant_override("separation", 8)
	_cards.anchor_top = 1.0
	_cards.anchor_bottom = 1.0
	_cards.offset_left = SCENE_LEFT
	_cards.offset_top = -MARGIN - CARD_SIZE.y
	_cards.offset_bottom = -MARGIN
	add_child(_cards)


func _rebuild_cards() -> void:
	for child in _cards.get_children():
		_cards.remove_child(child)
		child.queue_free()
	_card_ids.clear()
	var s := _state.galaxy.get_system(system_id)
	# Les cartes se partagent la largeur libre à gauche de la fiche.
	var free_width := view.size.x - SCENE_LEFT - Hud.DIAL_RESERVED - 50.0
	var width := clampf((free_width - 8.0 * (s.planet_count - 1)) / maxf(s.planet_count, 1), 90.0, CARD_SIZE.x)
	for pid in s.planet_ids:
		var p := _state.galaxy.get_planet(pid)
		var card := Button.new()
		card.toggle_mode = true
		card.focus_mode = Control.FOCUS_NONE
		card.clip_text = true
		card.custom_minimum_size = Vector2(width, CARD_SIZE.y)
		card.alignment = HORIZONTAL_ALIGNMENT_LEFT
		card.icon = _type_icon(p.type)
		card.add_theme_font_size_override("font_size", 13)
		card.add_theme_stylebox_override("normal", _box(UiTheme.PANEL, UiTheme.LINE))
		card.add_theme_stylebox_override("hover", _box(Color(0.09, 0.11, 0.15, 0.92), UiTheme.LINE_STRONG))
		var on := _box(Color(0.06, 0.09, 0.12, 0.95), ACCENT)
		on.border_width_bottom = 2
		card.add_theme_stylebox_override("pressed", on)
		card.add_theme_stylebox_override("hover_pressed", on)
		card.pressed.connect(select_planet.bind(pid))
		_cards.add_child(card)
		_card_ids.append(pid)


func _refresh_cards() -> void:
	for i in _card_ids.size():
		var pid := _card_ids[i]
		var p := _state.galaxy.get_planet(pid)
		var card: Button = _cards.get_child(i)
		var roman: String = Planet.ROMAN[p.index] if p.index < Planet.ROMAN.size() else str(p.index + 1)
		var type_name := "Astéroïdes" if p.type == "asteroids" else p.type_label()
		card.text = "%s  %s\n%s" % [roman, type_name, "taille %d · %s" % [p.size, PlanetInfo.short_status(_state, p, _player)] if not _state.colonies.has(p.id) else PlanetInfo.short_status(_state, p, _player)]
		card.set_pressed_no_signal(pid == planet_id)
		var c: Colony = _state.colonies.get(pid)
		var col := _state.get_empire(c.owner).color().lightened(0.35) if c else Color(0.88, 0.9, 0.96)
		card.add_theme_color_override("font_color", col)
		card.add_theme_color_override("font_hover_color", col.lightened(0.2))
		card.add_theme_color_override("font_pressed_color", SystemView.SELECT_COLOR)
		card.add_theme_color_override("font_hover_pressed_color", SystemView.SELECT_COLOR)


# --- Fiche de la planète ---------------------------------------------------------------------

func _build_panel() -> void:
	_panel = PanelContainer.new()
	_panel.anchor_bottom = 1.0
	_panel.offset_left = MARGIN
	_panel.offset_right = MARGIN + PANEL_WIDTH
	_panel.offset_top = PANEL_TOP
	_panel.offset_bottom = -MARGIN
	_panel.theme_type_variation = &"SidePanel"
	add_child(_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)
	# Marge à droite : la barre de défilement ne doit pas recouvrir le texte.
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_right", 14)
	scroll.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	margin.add_child(box)
	_panel_box = box

	_p_title = UiTheme.title("", 26)
	box.add_child(_p_title)
	_p_sub = _text_label(box)
	_p_sub.modulate = Color(0.75, 0.8, 0.92)
	box.add_child(HSeparator.new())
	_hab_title = _section(box, "Pour votre espèce")
	_hab_bar = ProgressBar.new()
	_hab_bar.max_value = 100
	_hab_bar.show_percentage = false
	_hab_bar.custom_minimum_size = Vector2(0, 8)
	box.add_child(_hab_bar)
	_hab_label = _text_label(box)
	_pot_title = _section(box, "Potentiel")
	_pot_view = Control.new()
	_pot_view.custom_minimum_size = Vector2(0, GameData.resource_ids().size() * 16.0)
	_pot_view.draw.connect(_draw_potential)
	box.add_child(_pot_view)
	_dep_title = _section(box, "Gisements")
	_dep_label = _text_label(box)
	_status_title = _section(box, "Statut")
	_status_label = _text_label(box)
	_actions_title = _section(box, "Ordres")
	_actions = VBoxContainer.new()
	_actions.add_theme_constant_override("separation", 4)
	box.add_child(_actions)


func _refresh_panel(s: StarSystem) -> void:
	var p := _state.galaxy.get_planet(planet_id) if planet_id >= 0 else null
	for n: Control in [_hab_title, _hab_bar, _hab_label, _pot_title, _pot_view, _dep_title, _dep_label, _actions_title]:
		n.visible = p != null
	if p == null:
		_p_title.text = GalaxyGenerator.star_label(s.star_type)
		_p_title.add_theme_color_override("font_color", GalaxyView.STAR_COLORS.get(s.star_type, Color.WHITE))
		_p_sub.text = "Aucune planète en orbite. Rien que le vide, et une étoile qui s'en moque éperdument." \
				if s.planet_count == 0 else "Choisissez une planète."
		_status_title.visible = false
		_status_label.text = ""
		_set_actions([])
		return
	var c: Colony = _state.colonies.get(p.id)
	_p_title.text = p.display_name(_state.galaxy)
	_p_title.add_theme_color_override("font_color", _state.get_empire(c.owner).color().lightened(0.3) if c else Color(0.95, 0.96, 1.0))
	_p_sub.text = "%s  ·  taille %d  ·  orbite %d" % [p.type_label(), p.size, p.index + 1]

	var hab := PlanetInfo.habitability(_state, p, _player)
	_hab_bar.value = int(hab["pct"])
	_hab_bar.visible = int(hab["pct"]) > 0
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.9, 0.35, 0.3).lerp(Color(0.4, 0.9, 0.5), float(hab["pct"]) / 100.0)
	fill.set_corner_radius_all(3)
	_hab_bar.add_theme_stylebox_override("fill", fill)
	_hab_label.text = hab["text"]

	_pot_view.set_meta("potential", PlanetInfo.potential(p))
	_pot_view.queue_redraw()

	var deps := PlanetInfo.deposit_labels(p)
	_dep_label.text = ", ".join(deps) if not deps.is_empty() else "Aucun gisement notable"

	_status_title.visible = true
	_status_label.text = "\n".join(PlanetInfo.colony_lines(_state, p, c, _player)) if c else "Aucune revendication. Elle n'attend que vous (ou un voisin plus rapide)."

	var actions := planet_actions(p)
	_set_actions(actions)
	_actions_title.visible = not actions.is_empty()


## Ordres possibles sur une planète (colonisation, avant-poste, chantiers), avec leur raison de refus.
func planet_actions(p: Planet) -> Array[Dictionary]:
	var c: Colony = _state.colonies.get(p.id)
	var actions: Array[Dictionary] = []
	if read_only:
		return actions
	# Coloniser n'est proposé que là où l'espèce du joueur peut vivre.
	var livable := Economy.max_pop(_state, p, _player) > 0
	if livable and (c == null or (c.owner == _player and not c.is_colony())):
		actions.append(_claim_action(p, Colony.KIND_COLONY))
	if c == null:
		actions.append(_claim_action(p, Colony.KIND_OUTPOST))
	var me := _state.get_empire(_player)
	if me and c and c.owner == _player and c.is_established():
		var f := me.faction()
		if FactionTraits.can_rush(f) and c.construction != "":
			actions.append(_rush_action(p, FactionTraits.RUSH_BUILDING))
		if FactionTraits.can_rush(f) and c.ship_build != "":
			actions.append(_rush_action(p, FactionTraits.RUSH_SHIP))
		if FactionTraits.has_fervor(f) and c.is_colony():
			actions.append(_sacrifice_action(p))
	if c and c.owner == _player and c.is_established() and c.is_colony():
		for sid in FactionTraits.ship_ids_for(me.faction_id):
			actions.append(_ship_action(p, sid))
	if c and c.owner == _player and c.is_established():
		for bid in GameData.buildings():
			var b := GameData.building(bid)
			if b.get("buildable", true):
				actions.append(_build_action(p, bid, b))
	return actions


## Vote d'urgence (Concorde de Vael) : achever le chantier en cours contre de l'influence.
func _rush_action(p: Planet, what: String) -> Dictionary:
	var c: Colony = _state.colonies[p.id]
	var cmd := SimCommands.rush(_player, p.id, what)
	var reason := SimCommands.validate(_state, cmd)
	var label := String(GameData.building(c.construction).get("label", c.construction)) if what == FactionTraits.RUSH_BUILDING \
			else String(GameData.ship(c.ship_build).get("label", c.ship_build))
	var days := c.construction_days if what == FactionTraits.RUSH_BUILDING else c.ship_days
	return {
		"text": "Vote d'urgence : %s" % label,
		"detail": "%d influence  »  achevé demain au lieu de dans %d j" % [FactionTraits.rush_cost(_state, _player, p.id, what), days],
		"reason": reason,
		"tooltip": reason if reason != "" else "L'Assemblée vote les crédits en séance de nuit. Le discours d'ouverture est, exceptionnellement, court.",
		"action": func() -> void: command_requested.emit(cmd),
	}


## Offrande (Chœur Éternel) : un fidèle de moins, de la ferveur en plus.
func _sacrifice_action(p: Planet) -> Dictionary:
	var me := _state.get_empire(_player)
	var cmd := SimCommands.sacrifice(_player, p.id)
	var reason := SimCommands.validate(_state, cmd)
	var fv: Dictionary = me.faction()["fervor"]
	return {
		"text": "Offrande au dieu-machine",
		"detail": "-1 population  »  +%d ferveur (%d / %d)" % [int(fv["sacrifice_gain"]), me.fervor, int(fv["max"])],
		"reason": reason,
		"tooltip": reason if reason != "" else "Un fidèle rejoint le dieu-machine. La ferveur remonte ; la natalité, elle, prend note.",
		"action": func() -> void: command_requested.emit(cmd),
	}


func _ship_action(p: Planet, ship_id: String) -> Dictionary:
	var sd := GameData.ship(ship_id)
	var reason := SimCommands.validate(_state, SimCommands.build_ship(_player, p.id, ship_id))
	var pid := p.id
	var price := GameData.format_amounts(sd.get("cost", {}))
	if int(sd.get("pop_cost", 0)) > 0:
		price += ", %d pop" % int(sd["pop_cost"])
	@warning_ignore("integer_division")
	var spd := int(sd["speed"]) * FactionTraits.fleet_speed_pct(_state, _player) / 100
	var detail := "%s, %d j  »  vitesse %d, vision %d saut%s" % [price, int(sd["days"]),
			spd, int(sd["vision"]), "s" if int(sd["vision"]) > 1 else ""]
	var tip := String(sd.get("description", ""))
	if Combat.is_military(ship_id):
		detail = "%s, %d j  »  puissance %d, vitesse %d" % [price, int(sd["days"]), Combat.ship_strength(ship_id), spd]
		tip += "\n\n%s" % Combat.ship_summary(ship_id)
	return {
		"text": "Chantier spatial : %s" % sd["label"],
		"detail": detail,
		"reason": reason,
		"tooltip": ("%s\n\n%s" % [reason, tip]) if reason != "" else tip,
		"action": func() -> void: build_ship_requested.emit(pid, ship_id),
	}


## Barres de potentiel (0 à 5) par ressource, avec un mot pour les lire.
func _draw_potential() -> void:
	var pot: Dictionary = _pot_view.get_meta("potential", {})
	var font := UiTheme.body_font()
	var y := 0.0
	for r in GameData.resource_ids():
		var rc: Color = PlanetInfo.RESOURCE_COLORS.get(r, Color.WHITE)
		var v := int(pot.get(r, 0))
		_pot_view.draw_string(font, Vector2(0, y + 12), GameData.resource_label(r), HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(rc, 0.95))
		for i in 5:
			_pot_view.draw_rect(Rect2(100.0 + i * 22.0, y + 5.0, 18.0, 5.0), rc if i < v else Color(rc, 0.12))
		_pot_view.draw_string(font, Vector2(218, y + 12), PlanetInfo.potential_label(v), HORIZONTAL_ALIGNMENT_LEFT, -1, 12,
				Color(1, 1, 1, 0.75 if v > 0 else 0.35))
		y += 16.0


func _claim_action(p: Planet, kind: String) -> Dictionary:
	var upgrade: bool = _state.colonies.has(p.id)
	var label := "Fonder une colonie" if upgrade else ("Coloniser" if kind == Colony.KIND_COLONY else "Poser un avant-poste")
	var reason := SimCommands.validate(_state, SimCommands.colonize(_player, p.id, kind))
	var pid := p.id
	var by_ship := Economy.needs_ship(_state, _player, p.id)
	var tip := "Une colonie accueille une population." if kind == Colony.KIND_COLONY \
			else "Un avant-poste revendique le système et exploite la planète, sans population."
	if by_ship:
		tip += "\nLe vaisseau colon en orbite se démonte pour la fonder."
	return {
		"text": "%s  (%s%s, %d j)" % [label, GameData.format_amounts(Economy.claim_cost_for(_state, _player, p.id, kind)),
				" + vaisseau colon" if by_ship else "", Economy.claim_days(kind)],
		"reason": reason,
		"tooltip": reason if reason != "" else tip,
		"action": func() -> void: colonize_requested.emit(pid, kind),
	}


func _build_action(p: Planet, bid: String, b: Dictionary) -> Dictionary:
	var reason := SimCommands.validate(_state, SimCommands.build(_player, p.id, bid))
	var gain := GameData.format_amounts(b.get("yields", {}), true)
	if b.has("max_pop"):
		gain = "+%d pop max" % int(b["max_pop"])
	var pid := p.id
	return {
		"text": "Construire : %s" % b["label"],
		"detail": "%s, %d j  »  %s" % [GameData.format_amounts(b.get("cost", {})), int(b["days"]), gain],
		"reason": reason,
		"tooltip": reason,
		"action": func() -> void: build_requested.emit(pid, bid),
	}


func _set_actions(actions: Array[Dictionary]) -> void:
	var sig := PackedStringArray([str(planet_id)])
	for a in actions:
		sig.append("%s|%s|%s" % [a["text"], a.get("detail", ""), a["reason"]])
	var joined := "\n".join(sig)
	if joined == _actions_sig:
		return
	_actions_sig = joined
	for child in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	for a in actions:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = a["text"] if not a.has("detail") else "%s\n%s" % [a["text"], a["detail"]]
		b.disabled = a["reason"] != ""
		b.tooltip_text = a["tooltip"]
		b.pressed.connect(a["action"])
		_actions.add_child(b)


## Bouton d'action par son texte (début), pour les tests.
func find_action(prefix: String) -> Button:
	for b in _actions.get_children():
		if b is Button and (b as Button).text.begins_with(prefix):
			return b
	return null


# --- Outils ----------------------------------------------------------------------------------

func _default_planet(s: StarSystem) -> int:
	var me := _state.get_empire(_player)
	if me and s.planet_ids.has(me.capital_planet):
		return me.capital_planet
	for pid in s.planet_ids:
		var c: Colony = _state.colonies.get(pid)
		if c and c.owner == _player:
			return pid
	return s.planet_ids[0] if not s.planet_ids.is_empty() else -1


func _section(parent: Control, text: String) -> Label:
	var l := UiTheme.section(text)
	parent.add_child(l)
	return l


func _text_label(parent: Control) -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(PANEL_WIDTH - 60.0, 0)
	parent.add_child(l)
	return l


func _box(bg: Color, border: Color, margin := 8) -> StyleBoxFlat:
	return UiTheme.box(bg, border, margin, 1)


## Petite pastille de couleur pour le type de planète (bandeau du bas).
func _type_icon(type: String) -> Texture2D:
	if _icons.has(type):
		return _icons[type]
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var base: Color = TYPE_DOT_COLORS.get(type, Color.GRAY)
	for y in n:
		for x in n:
			var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
			if d <= 1.0:
				var shade := clampf(1.1 - Vector2(x - n * 0.3, y - n * 0.3).length() / n, 0.35, 1.0)
				img.set_pixel(x, y, Color(base * shade, clampf((1.0 - d) * 8.0, 0.0, 1.0)))
	var tex := ImageTexture.create_from_image(img)
	_icons[type] = tex
	return tex
