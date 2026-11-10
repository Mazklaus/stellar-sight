class_name Hud
extends CanvasLayer
## Interface en jeu, disposée aux quatre coins comme dans les grands 4X spatiaux :
##   en haut à gauche  le panneau d'empire (menus, ressources, état) ;
##   en haut au centre les onglets de vue (galaxie, lentille économique, gestion du système) ;
##   en haut à droite  la chronique galactique, et dessous la liste des flottes ;
##   en bas à gauche   la fiche du système survolé ou sélectionné, avec son illustration ;
##   en bas à droite   le cadran du temps, le menu du jeu et le rappel des flottes inactives.
## L'interface ne modifie jamais la partie : elle émet des demandes.

signal open_system_requested(system_id: int)
signal close_system_requested
signal screen_requested(screen_id: String)
signal menu_requested
signal pause_toggled
signal speed_requested(index: int)
signal lens_changed(lens: String)
## Onglets de la vue système : gestion (true) ou vue orbitale (false).
signal system_mode_requested(manage: bool)
## Bouton de la fiche de flotte : "explore", "stop", "merge", "split" ou "colonize".
signal fleet_action_requested(action: String, fleet_id: int)
## Liste des flottes : sélectionner une flotte (et y centrer la carte), ou ouvrir son système.
signal fleet_requested(fleet_id: int)
signal fleet_system_requested(fleet_id: int)
## Bouton « flottes inactives » : passer à la prochaine flotte qui attend des ordres.
signal idle_fleet_requested

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
var _tab_orbit: Button
var _tab_manage: Button
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
var _empire_screen := false
var _system_id := -1
var _hover_id := -1
var _state: GameState
var _player := 0
var lens := ""
var _fleet_id := -1
var _fleet_panel: PanelContainer
var _fleet_style: StyleBoxFlat
var _fleet_title: Label
var _fleet_kind: Label
var _fleet_status: Label
var _fleet_stats: Label
var _fleet_hint: Label
var _fleet_buttons: Dictionary = {}
var fleet_list: FleetListPanel
var idle_button: Button
## Mode spectateur : aucun ordre, le tableau des empires remplace la liste des flottes.
var spectator := false
var spectator_panel: SpectatorPanel
var battle_report: BattleReportPanel
var battle_replay: BattleReplayPanel


func _ready() -> void:
	bar = EmpireBar.new()
	add_child(bar)
	bar.screen_requested.connect(func(id: String) -> void: screen_requested.emit(id))
	_build_tabs()
	_build_card()
	_build_fleet_card()
	_build_chronicle()
	_build_fleet_list()
	_build_spectator_panel()
	_build_dial()

	_toasts = VBoxContainer.new()
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_toasts.offset_top = 58.0
	_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toasts.add_theme_constant_override("separation", 4)
	_toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toasts)
	_place_toasts()
	battle_report = BattleReportPanel.new()
	add_child(battle_report)
	battle_replay = BattleReplayPanel.new()
	add_child(battle_replay)
	battle_report.replay_requested.connect(func(r: Dictionary) -> void:
		var state := battle_report._state
		var viewer := battle_report._viewer
		battle_report.hide_report()
		battle_replay.show_replay(state, viewer, r))
	# En quittant la vue, on revient au rapport de la même bataille.
	battle_replay.closed.connect(func() -> void:
		if battle_replay._state != null:
			battle_report.show_report(battle_replay._state, battle_replay._viewer, battle_replay.report))
	set_system_mode(false)


## Branche l'interface sur une partie (nouvelle ou chargée) et sur l'empire du joueur local.
func set_state(state: GameState, player: int) -> void:
	_state = state
	_player = player
	bar.set_state(state, player)
	fleet_list.set_state(state, player)
	spectator_panel.set_state(state if spectator else null, player)
	_hover_id = -1
	show_system(null, state)


## Met à jour ce qui change avec le temps. Appelé à chaque tick et après chaque ordre.
func refresh() -> void:
	bar.refresh()
	fleet_list.refresh()
	if spectator:
		spectator_panel.refresh()
	_refresh_idle_button()
	_refresh_fleet_card()
	_refresh_card()


## Mode spectateur (partie sans joueur) ou partie normale. À appeler avant set_state().
func set_spectator(on: bool) -> void:
	spectator = on
	_refresh_side_visibility()


## Empire suivi par le spectateur : le panneau d'empire et la fiche de flotte le regardent.
func follow_empire(state: GameState, empire_id: int) -> void:
	_state = state
	_player = empire_id
	bar.set_state(state, empire_id)
	fleet_list.set_state(state, empire_id)
	spectator_panel.set_followed(empire_id)
	refresh()


## Flotte sélectionnée sur la carte (-1 = aucune) : sa fiche s'affiche en bas à gauche.
func show_fleet(fleet_id: int) -> void:
	_fleet_id = fleet_id
	fleet_list.set_selected(fleet_id)
	_refresh_fleet_card()
	_refresh_card()


func fleet_card_visible() -> bool:
	return _fleet_panel.visible


## Bouton de la fiche de flotte, pour les tests ("stop", "merge", "split", "colonize").
func fleet_button(action: String) -> Button:
	return _fleet_buttons.get(action)


## Système sélectionné sur la carte (null = aucun).
func show_system(s: StarSystem, state: GameState) -> void:
	_state = state
	_system_id = s.id if s else -1
	_refresh_card()


## Écran d'empire ouvert : il a son propre onglet et sa colonne, la fiche et la chronique s'effacent.
func set_empire_screen_open(on: bool) -> void:
	_empire_screen = on
	_tabs.visible = not on
	_chronicle.visible = not on
	_place_toasts()
	_refresh_side_visibility()
	_refresh_fleet_card()
	_refresh_card()


## Vue système ouverte (true) ou carte de la galaxie (false).
func set_system_mode(on: bool) -> void:
	_system_mode = on
	# Dans la vue système, « Vue galaxie » ramène à la carte ; la lentille laisse place aux deux vues du système.
	_tab_galaxy.set_pressed_no_signal(not on and lens == "")
	_tab_economy.visible = not on
	_tab_orbit.visible = on
	_tab_manage.visible = on
	if on:
		_hover_id = -1
	_refresh_side_visibility()
	_refresh_fleet_card()
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
	_style_toast(toast)
	while _toasts.get_child_count() > TOAST_MAX:
		var old := _toasts.get_child(0)
		_toasts.remove_child(old)
		old.queue_free()
	var tw := toast.create_tween()
	tw.tween_interval(TOAST_SECONDS)
	tw.tween_property(toast, "modulate:a", 0.0, 0.5)
	tw.tween_callback(toast.queue_free)


## Les avis s'affichent en haut au centre sur la carte. Quand un écran d'empire est ouvert, ils se
## rangent en bas à droite, au-dessus du cadran, pour ne jamais couvrir le contenu (comme dans
## Endless Space 2, où rien ne flotte au-dessus de l'arbre des technologies).
func _place_toasts() -> void:
	if _empire_screen:
		_toasts.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		_toasts.offset_right = -14.0
		_toasts.offset_bottom = -TimeDial.SIDE - 40.0
		_toasts.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		_toasts.grow_vertical = Control.GROW_DIRECTION_BEGIN
		_toasts.alignment = BoxContainer.ALIGNMENT_END
	else:
		_toasts.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
		_toasts.offset_top = 58.0
		_toasts.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_toasts.grow_vertical = Control.GROW_DIRECTION_END
		_toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	for t in _toasts.get_children():
		_style_toast(t as PanelContainer)


## Avis compacts (texte plus petit, retour à la ligne) quand ils sont rangés sur le côté.
func _style_toast(toast: PanelContainer) -> void:
	var l := toast.get_child(0) as Label
	if _empire_screen:
		l.add_theme_font_size_override("font_size", 13)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.custom_minimum_size = Vector2(300, 0)
	else:
		l.remove_theme_font_size_override("font_size")
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size = Vector2.ZERO


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


## Onglet de la vue système affichée (suit SystemScreen.mode_changed).
func set_manage_tab(manage: bool) -> void:
	_tab_orbit.set_pressed_no_signal(not manage)
	_tab_manage.set_pressed_no_signal(manage)


# --- Construction ---------------------------------------------------------------------------

func _build_tabs() -> void:
	_tabs = HBoxContainer.new()
	_tabs.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_tabs.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tabs.add_theme_constant_override("separation", 2)
	add_child(_tabs)
	_tab_galaxy = _tab("Vue galaxie", "La carte des systèmes")
	_tab_galaxy.pressed.connect(func() -> void:
		if _system_mode:
			_tab_galaxy.set_pressed_no_signal(false)
			close_system_requested.emit()
		else:
			set_lens(""))
	_tab_economy = _tab("Lentille économique", "Bilan mensuel de chacun de vos systèmes, sur la carte  (L)")
	_tab_economy.pressed.connect(func() -> void: set_lens("" if lens == "economy" else "economy"))
	_tab_orbit = _tab("Vue orbitale", "L'étoile et ses planètes en orbite  (Tab)")
	_tab_orbit.pressed.connect(func() -> void: system_mode_requested.emit(false))
	_tab_manage = _tab("Gestion du système", "Les planètes côte à côte, pour comparer  (Tab)")
	_tab_manage.pressed.connect(func() -> void: system_mode_requested.emit(true))
	_tab_orbit.visible = false
	_tab_manage.visible = false
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


func _build_fleet_card() -> void:
	_fleet_panel = PanelContainer.new()
	_fleet_style = UiTheme.box(UiTheme.PANEL, UiTheme.LINE, 12, 0)
	_fleet_style.border_width_top = 2  # filet à la couleur de l'empire
	_fleet_panel.add_theme_stylebox_override("panel", _fleet_style)
	_fleet_panel.anchor_top = 1.0
	_fleet_panel.anchor_bottom = 1.0
	_fleet_panel.offset_left = MARGIN
	_fleet_panel.offset_right = MARGIN + CARD_WIDTH
	_fleet_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_fleet_panel.offset_bottom = -MARGIN
	_fleet_panel.offset_top = -MARGIN
	_fleet_panel.visible = false
	add_child(_fleet_panel)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 4)
	_fleet_panel.add_child(inner)
	var tag := UiTheme.section("Flotte")
	inner.add_child(tag)
	_fleet_title = UiTheme.title("", 26)
	inner.add_child(_fleet_title)
	_fleet_kind = Label.new()
	_fleet_kind.add_theme_font_size_override("font_size", 14)
	inner.add_child(_fleet_kind)
	_fleet_status = UiTheme.paragraph("", CARD_WIDTH - 26.0, 14)
	inner.add_child(_fleet_status)
	_fleet_stats = UiTheme.dim("", 13)
	_fleet_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fleet_stats.custom_minimum_size = Vector2(CARD_WIDTH - 26.0, 0)
	inner.add_child(_fleet_stats)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 4)
	inner.add_child(grid)
	for a in [["explore", "EXPLORATION AUTO", "La flotte part seule vers les systèmes inexplorés les plus proches, et continue jusqu'à ce qu'il n'y en ait plus  (E)"],
			["colonize", "COLONISER ICI", "Ouvrir le système pour choisir la planète où fonder la revendication"],
			["stop", "ARRÊTER", "S'arrêter au système le plus proche sur la route"],
			["merge", "RASSEMBLER", "Réunir dans cette flotte les autres flottes à l'arrêt dans ce système"],
			["split", "DÉTACHER", "Détacher un vaisseau dans une nouvelle flotte"],
			["report", "RAPPORT", "Dernier rapport de bataille de vos flottes  (B)"],
			["tactic", "TACTIQUE", "Changer de tactique de combat (choisie avant la bataille, appliquée sans votre intervention)  (T)"],
			["invade", "ENVAHIR", "Débarquer les troupes : le système change de mains si elles sont plus nombreuses que la garnison"]]:
		var b := Button.new()
		b.text = a[1]
		b.tooltip_text = a[2]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if a[0] == "colonize" or a[0] == "invade":
			b.theme_type_variation = &"PrimaryButton"
		if a[0] == "explore":
			b.toggle_mode = true
		var action: String = a[0]
		b.pressed.connect(func() -> void: fleet_action_requested.emit(action, _fleet_id))
		# Tactique et invasion prennent toute la largeur, sous la grille.
		if action == "tactic" or action == "invade":
			b.clip_text = true
			inner.add_child(b)
		else:
			grid.add_child(b)
		_fleet_buttons[action] = b
	_fleet_hint = UiTheme.paragraph("Clic droit sur un système : y envoyer la flotte.  F : flotte suivante.  I : flotte inactive suivante.  T : tactique.", CARD_WIDTH - 26.0, 12)
	_fleet_hint.theme_type_variation = &"Dim"
	inner.add_child(_fleet_hint)


func _refresh_fleet_card() -> void:
	if _fleet_panel == null:
		return
	var f: Fleet = _state.fleets.get(_fleet_id) if _state else null
	_fleet_panel.visible = f != null and not _system_mode and not _empire_screen
	# La fiche du système survolé se range à droite de celle de la flotte.
	_info_panel.offset_left = MARGIN + (CARD_WIDTH + MARGIN if _fleet_panel.visible else 0.0)
	_info_panel.offset_right = _info_panel.offset_left + CARD_WIDTH
	if not _fleet_panel.visible:
		return
	var g := _state.galaxy
	var owner := _state.get_empire(f.owner)
	var mine := f.owner == _player and not spectator
	_fleet_style.border_color = owner.color()
	_fleet_title.text = f.fleet_name
	_fleet_title.add_theme_color_override("font_color", owner.color().lightened(0.35))
	_fleet_kind.text = Fleets.composition(f) if mine else "%s  ·  %s" % [owner.short_name(), Fleets.composition(f)]
	if f.is_exploring() and mine:
		var eta := Fleets.eta_days(_state, f)
		_fleet_status.text = "Exploration automatique : cap sur %s (%d jour%s)." % [_system_label(f.destination()), eta, "s" if eta > 1 else ""] \
				if f.is_moving() else "Exploration automatique : en quête du prochain système."
	elif f.is_moving():
		var eta := Fleets.eta_days(_state, f)
		_fleet_status.text = "En route vers %s, arrivée dans %d jour%s (prochain saut : %s)." % [
				_system_label(f.destination()), eta, "s" if eta > 1 else "", _system_label(f.next_system())]
	else:
		_fleet_status.text = "En orbite de %s." % _system_label(f.system_id)
	_fleet_status.text += combat_status(_state, f)
	var v := Fleets.vision(f)
	_fleet_stats.text = "%d vaisseau%s  ·  vitesse %d  ·  vision %d saut%s" % [f.ships.size(), "x" if f.ships.size() > 1 else "",
			Fleets.speed(f, _state), v, "s" if v > 1 else ""]
	if Combat.is_armed(f) or f.total_hp() < f.total_max_hp():
		@warning_ignore("integer_division")
		_fleet_stats.text += "\nPuissance %d  ·  coque %d %%  ·  troupes %d/%d  ·  %s" % [Combat.fleet_power(f),
				f.total_hp() * 100 / maxi(1, f.total_max_hp()), f.troops, Combat.max_troops(f, _state), Combat.tactic_label(Combat.fleet_tactic(f))]
	var can_colonize := mine and not f.is_moving() and Fleets.colonizer_ship(f) != ""
	if can_colonize:
		can_colonize = false
		for pid in g.systems[f.system_id].planet_ids:
			for kind in [Colony.KIND_OUTPOST, Colony.KIND_COLONY]:
				if Economy.check_colonize(_state, _player, pid, kind) == "":
					can_colonize = true
	var others := Fleets.fleets_at(_state, f.system_id, _player).size() > 1
	_fleet_buttons["colonize"].visible = mine and Fleets.colonizer_ship(f) != ""
	_fleet_buttons["colonize"].disabled = not can_colonize
	_fleet_buttons["explore"].visible = mine
	_fleet_buttons["explore"].set_pressed_no_signal(f.is_exploring())
	_fleet_buttons["explore"].text = "EXPLORATION : ACTIVE" if f.is_exploring() else "EXPLORATION AUTO"
	_fleet_buttons["explore"].disabled = mine and not f.is_exploring() and Fleets.explore_target(_state, f) == -1
	_fleet_buttons["stop"].visible = mine
	_fleet_buttons["stop"].disabled = not f.is_moving()
	_fleet_buttons["merge"].visible = mine
	_fleet_buttons["merge"].disabled = f.is_moving() or not others
	_fleet_buttons["split"].visible = mine
	_fleet_buttons["split"].disabled = f.is_moving() or f.ships.size() < 2
	var armed := Combat.is_armed(f)
	_fleet_buttons["tactic"].visible = mine and armed
	_fleet_buttons["tactic"].text = "TACTIQUE : %s" % Combat.tactic_label(Combat.fleet_tactic(f)).to_upper()
	_fleet_buttons["tactic"].tooltip_text = "%s\n\nClic : tactique suivante  (T)" % String(Combat.tactic(Combat.fleet_tactic(f)).get("desc", ""))
	var enemy_owner := _state.system_owner(f.system_id)
	var invade_why := Combat.check_invade(_state, _player, f.id) if mine else "x"
	_fleet_buttons["invade"].visible = mine and not f.is_moving() and enemy_owner >= 0 and Combat.at_war(_state, _player, enemy_owner)
	_fleet_buttons["invade"].disabled = invade_why != ""
	_fleet_buttons["invade"].tooltip_text = "Débarquer les troupes : le système change de mains.\n%s" % (invade_why if invade_why != "" else "%d troupes contre une garnison de %d : la place est à vous." % [f.troops, Combat.garrison(_state, f.system_id)])
	_fleet_buttons["report"].visible = mine and armed
	_fleet_buttons["report"].disabled = last_report(_state, _player).is_empty()
	_fleet_hint.visible = mine


## Ligne de combat d'une flotte à l'arrêt : bataille en cours, siège mené.
static func combat_status(state: GameState, f: Fleet) -> String:
	if f.is_moving():
		return ""
	var b := Combat.battle_at(state, f.system_id)
	if not b.is_empty():
		var day := int(b["day"])
		return "\nEN BATAILLE : jour %d sur %d, %s." % [day, Combat.battle_days(), Combat.phase_label(Combat.phase_index(day)).to_lower()]
	var owner := state.system_owner(f.system_id)
	if owner >= 0 and Combat.at_war(state, f.owner, owner) and Combat.is_besieged(state, f.system_id) and Combat.is_armed(f):
		return "\nSIÈGE : garnison %d / %d." % [Combat.garrison(state, f.system_id), Combat.garrison_max(state, f.system_id)]
	return ""


## Dernier rapport de bataille où l'empire a combattu ({} s'il n'y en a pas).
static func last_report(state: GameState, empire_id: int) -> Dictionary:
	for i in range(state.battle_reports.size() - 1, -1, -1):
		var r: Dictionary = state.battle_reports[i]
		for s: Dictionary in r["sides"]:
			if int(s["empire"]) == empire_id:
				return r
	return {}


## Nom d'un système tel que le joueur le connaît (pas de nom dans le brouillard).
func _system_label(id: int) -> String:
	return _state.galaxy.systems[id].system_name if Fleets.is_explored(_state, _player, id) else "un système inexploré"


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


func _build_fleet_list() -> void:
	fleet_list = FleetListPanel.new()
	fleet_list.anchor_left = 1.0
	fleet_list.anchor_right = 1.0
	fleet_list.offset_left = -CHRONICLE_WIDTH - MARGIN
	fleet_list.offset_right = -MARGIN
	add_child(fleet_list)
	fleet_list.fleet_requested.connect(func(fid: int) -> void: fleet_requested.emit(fid))
	fleet_list.fleet_system_requested.connect(func(fid: int) -> void: fleet_system_requested.emit(fid))
	# La liste se range juste sous la chronique, dont la hauteur suit la longueur du texte.
	_chronicle.resized.connect(_place_fleet_list)
	_place_fleet_list()


func _place_fleet_list() -> void:
	fleet_list.offset_top = _chronicle.offset_top + _chronicle.size.y + 6.0
	if spectator_panel:
		spectator_panel.offset_top = fleet_list.offset_top


func _build_spectator_panel() -> void:
	spectator_panel = SpectatorPanel.new()
	spectator_panel.anchor_left = 1.0
	spectator_panel.anchor_right = 1.0
	spectator_panel.offset_left = -CHRONICLE_WIDTH - MARGIN
	spectator_panel.offset_right = -MARGIN
	spectator_panel.visible = false
	add_child(spectator_panel)
	_place_fleet_list()


func _refresh_side_visibility() -> void:
	if fleet_list:
		fleet_list.visible = not _system_mode and not _empire_screen and not spectator
	if spectator_panel:
		spectator_panel.visible = spectator and not _system_mode and not _empire_screen
	_refresh_idle_button()


func _refresh_idle_button() -> void:
	if idle_button == null:
		return
	var n := Fleets.idle_fleets(_state, _player).size() if _state else 0
	idle_button.visible = n > 0 and not _system_mode and not _empire_screen and not spectator
	idle_button.text = "%d FLOTTE%s INACTIVE%s" % [n, "S" if n > 1 else "", "S" if n > 1 else ""]


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
	# Comme le bouton au-dessus de la fin de tour d'Endless Space 2 : aller aux flottes sans ordres.
	idle_button = Button.new()
	idle_button.focus_mode = Control.FOCUS_NONE
	idle_button.anchor_left = 1.0
	idle_button.anchor_right = 1.0
	idle_button.anchor_top = 1.0
	idle_button.anchor_bottom = 1.0
	idle_button.offset_right = -MARGIN - 44.0
	idle_button.offset_left = idle_button.offset_right - 210.0
	idle_button.offset_top = -TimeDial.SIDE - MARGIN - 40.0
	idle_button.offset_bottom = -TimeDial.SIDE - MARGIN - 4.0
	idle_button.add_theme_color_override("font_color", FleetListPanel.IDLE_COLOR)
	idle_button.tooltip_text = "Passer à la prochaine flotte qui attend des ordres  (I)"
	idle_button.pressed.connect(func() -> void: idle_fleet_requested.emit())
	idle_button.visible = false
	add_child(idle_button)


func _refresh_card() -> void:
	if _info_panel == null:
		return
	var id := card_system()
	if _state == null or id < 0 or _system_mode or _empire_screen:
		_info_panel.visible = false
		return
	_info_panel.visible = true
	var galaxy := _state.galaxy
	var s := galaxy.get_system(id)
	if not Fleets.is_explored(_state, _player, id):
		_portrait.visible = false
		_card_title.text = "Système inexploré"
		_card_title.add_theme_color_override("font_color", UiTheme.TEXT)
		_card_kind.text = "Une lueur repérée par vos capteurs"
		_card_owner.text = "Dans le brouillard"
		_card_lore.text = "Les cartes s'arrêtent ici. Au-delà, il y a peut-être des mondes, ou des dragons. Envoyez un éclaireur (clic droit avec une flotte sélectionnée)."
		for d in _planet_dots.get_children():
			_planet_dots.remove_child(d)
			d.queue_free()
		_enter_button.visible = false
		return
	_portrait.visible = true
	var owner := _state.get_empire(_state.system_owner(s.id))
	_portrait.set_star(s.star_type, fmod(float(s.id) * 0.731, 7.0))
	_card_title.text = s.system_name
	_card_title.add_theme_color_override("font_color", owner.color().lightened(0.35) if owner else UiTheme.TEXT)
	_card_kind.text = "Système stellaire (%s)" % GalaxyGenerator.star_label(s.star_type)
	_card_owner.text = "%s  ·  %s" % [
		"Système de %s" % owner.short_name() if owner else "Système libre",
		"à portée" if Economy.in_range(_state, _player, s.id) else "hors de portée",
	]
	if owner:
		var war := owner.id != _player and Combat.at_war(_state, _player, owner.id)
		_card_owner.text += "%s\nGarnison %d / %d%s" % ["  ·  EN GUERRE" if war else "", Combat.garrison(_state, s.id), Combat.garrison_max(_state, s.id),
				"  ·  ASSIÉGÉ" if Combat.is_besieged(_state, s.id) else ""]
	if not Combat.battle_at(_state, s.id).is_empty():
		_card_owner.text += "\nBataille en cours"
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
