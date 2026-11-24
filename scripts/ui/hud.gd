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
## Clic sur le suivi des quêtes : ouvrir les Chroniques sur l'onglet Quêtes.
signal quests_requested
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
## Navigateur : aller à un système (open : l'ouvrir), ou à ce qui attend une décision.
signal nav_system_requested(system_id: int, open: bool)
signal todo_requested(item: Dictionary)
## Lien « Système : … » de la fiche de flotte : passer à la fiche du système où elle se trouve.
signal fleet_place_requested(fleet_id: int)
## Bouton « flottes inactives » : passer à la prochaine flotte qui attend des ordres.
signal idle_fleet_requested
## Clic sur une pastille de la barre d'alertes (voir AlertBar).
signal alert_requested(kind: String, arg: int)
## Un calque de la carte est coché ou décoché (voir GalaxyView.LAYERS).
signal layer_toggled(id: String, on: bool)
## Un des trois boutons de palier de zoom est pressé (voir GalaxyView.TIER_*).
signal zoom_tier_requested(tier: int)

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

## Lentilles de la carte, rangées en cinq familles (refonte, A3) : [famille, [[identifiant, nom], …]].
const LENS_FAMILIES := [
	["Territoires", [["", "Empires"], ["borders", "Frontières et passages"], ["amph", "Assemblée"]]],
	["Richesse", [["economy", "Économie"], ["trade", "Commerce"], ["private", "Économie privée"], ["ports", "Spatioports"]]],
	["Ordre", [["stability", "Stabilité"], ["corruption", "Corruption"], ["fiscal", "Fiscalité"], ["politics", "Politique"]]],
	["Peuples", [["peoples", "Peuples"], ["faith", "Foi"], ["psionics", "Songe"], ["culture", "Rayonnement"]]],
	["Guerre", [["war", "Guerre et occupations"], ["sensors", "Senseurs"]]],
]
## Ce que montre chaque lentille (infobulle du bouton et ligne du panneau).
const LENS_TIPS := {
	"": "La carte des empires : à qui appartient chaque système.",
	"borders": "Votre droit de passage chez chaque voisin (vert : vos flottes de guerre passent, ambre : vaisseaux sans armes seulement, rouge : frontière close) et les intrus chez vous.  (A ; Q en QWERTY)",
	"amph": "Les empires membres de l'Amphictyonie (or), les hors-la-loi (rouge) et ceux qui restent dehors (gris), avec leurs voix.  (X)",
	"economy": "Le bilan mensuel de chacun de vos systèmes.  (L)",
	"trade": "Vos routes commerciales (couleur du traité, rouge si bloquée) et le risque pirate le long du chemin.  (G)",
	"private": "L'économie privée : stations, cargos, filiales, repaires.  (G, deux fois)",
	"ports": "Le réseau de distribution des spatioports : desserte, portées, liaisons.",
	"stability": "La stabilité de chacun de vos systèmes, et les mondes libres.  (K)",
	"corruption": "La corruption de chacun de vos systèmes (Administration).  (K, deux fois)",
	"fiscal": "La fiscalité : franchises, grèves, fuite fiscale.",
	"politics": "Le courant qui domine l'opinion de chacun de vos systèmes, et ses représentants au pouvoir ou non.  (O)",
	"peoples": "La part de chaque espèce dans vos systèmes, et l'espèce majoritaire.  (U)",
	"faith": "La part de chaque croyance dans vos systèmes, la majoritaire, et les mondes saints connus.  (N)",
	"psionics": "Les sensitifs, les écrans, le Phare, l'ambre et les mondes hantés.  (U, deux fois)",
	"culture": "Chez chaque empire, le palier de votre culture (gris Inconnu, bleu Exotique, vert Familier, or En vogue, orange Influent, rouge Dominant) ; chez vous, la culture étrangère dominante et les défections en cours.",
	"war": "Les systèmes de vos ennemis (rouge), vos revendications (pointillé or), les systèmes occupés hachurés à la couleur de l'occupant.  (W ; Z en QWERTY)",
	"sensors": "La couverture de vos senseurs (furtivité).  (W, deux fois)",
}

## Ordres de flotte par groupe (refonte, B3) : identifiant, titre, ordres. Tout ordre absent d'ici va
## dans « Autres ordres ».
## Rangées de composition affichées avant de résumer le reste.
const FLEET_ROWS_MAX := 6
const FLEET_GROUPS := [
	["move", "Déplacement", ["explore", "patrol", "guard", "stop"]],
	["here", "Sur place", ["colonize", "embark", "disembark", "requisition", "bomb", "invade"]],
	["conduct", "Conduite", ["stance", "posture", "tactic"]],
	["more", "Autres ordres", []],
]

var bar: EmpireBar
var dial: TimeDial
var turn_players: TurnPlayersPanel
var _tabs: HBoxContainer
var _tab_galaxy: Button
## Sélecteur de lentilles (refonte, A3) : un bouton qui nomme la lentille, et son panneau par familles.
var _lens_button: Button
var _lens_panel: PanelContainer
var _lens_note: Label
## Boutons du panneau, par identifiant de lentille ("" = la carte des empires).
var lens_buttons := {}
## Cases des calques, par identifiant, et légende de la lentille active.
var layer_boxes := {}
var _legend: PanelContainer
var _legend_box: VBoxContainer
## Boutons de palier de zoom, à gauche du cadran.
var tier_buttons: Array[Button] = []
var _tier_box: VBoxContainer
var _fleet_comp: VBoxContainer
var fleet_place_link: LinkButton
var _fleet_comp_sig := ""
var _fleet_group_heads := {}
var _fleet_group_boxes := {}
var _fleet_more_button: Button
var _fleet_more_open := false
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
var quest_tracker: QuestTracker
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
## Panneau de droite réduit à une barre d'alertes (refonte, A4), et la languette qui bascule.
var side_reduced := false
var alert_bar: AlertBar
var side_toggle: Button
var idle_button: Button
## Mode spectateur : aucun ordre, le tableau des empires remplace la liste des flottes.
var spectator := false
var spectator_panel: SpectatorPanel
var battle_report: BattleReportPanel
var battle_replay: BattleReplayPanel
var ground_replay: GroundReplayPanel


func _ready() -> void:
	bar = EmpireBar.new()
	add_child(bar)
	bar.screen_requested.connect(func(id: String) -> void: screen_requested.emit(id))
	_build_tabs()
	_build_card()
	_build_fleet_card()
	_build_chronicle()
	_build_quest_tracker()
	_build_fleet_list()
	_build_spectator_panel()
	_build_side_toggle()
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
	ground_replay = GroundReplayPanel.new()
	add_child(ground_replay)
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
	alert_bar.set_state(state, player)
	quest_tracker.set_state(state, player)
	spectator_panel.set_state(state if spectator else null, player)
	_refresh_lens_panel()
	_hover_id = -1
	show_system(null, state)


## Met à jour ce qui change avec le temps. Appelé à chaque tick et après chaque ordre.
func refresh() -> void:
	bar.refresh()
	fleet_list.refresh()
	if alert_bar.visible:
		alert_bar.refresh()
	quest_tracker.refresh()
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
	if on:
		_lens_panel.visible = false
	_place_toasts()
	_refresh_side_visibility()
	_refresh_fleet_card()
	_refresh_card()


## Vue système ouverte (true) ou carte de la galaxie (false).
func set_system_mode(on: bool) -> void:
	_system_mode = on
	# Dans la vue système, « Vue galaxie » ramène à la carte ; la lentille laisse place aux deux vues du système.
	_tab_galaxy.set_pressed_no_signal(not on and lens == "")
	_lens_button.visible = not on
	if on:
		_lens_panel.visible = false
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
## Seules comptent les nouvelles que l'empire regardé peut connaître (Espionage.can_read) : une entrée
## qu'il ne peut pas lire est ignorée, l'encadré garde la précédente.
func show_chronicle(entry: Dictionary) -> void:
	if not entry.is_empty() and not Espionage.can_read(entry, Intel.lens):
		return
	if entry.is_empty() and _state:
		var last := Espionage.readable(_state, Intel.lens, 1)
		if not last.is_empty():
			entry = last[0]
	if entry.is_empty():
		_chronicle_date.text = ""
		_chronicle_label.text = "La chronique attend son premier scandale."
		_chronicle.tooltip_text = ""
		return
	_chronicle_date.text = GameCalendar.date_string(int(entry["tick"]))
	_chronicle_label.text = String(entry["text"])
	if _state:
		var lines := PackedStringArray(["[b]Chronique galactique[/b]"])
		for e in Espionage.readable(_state, Intel.lens, 6):
			lines.append("[color=#%s]%s[/color]  %s" % [UiTheme.TEXT_DIM.to_html(false), GameCalendar.date_string(int(e["tick"])), e["text"]])
		_chronicle.tooltip_text = "\n".join(lines)


## Petit message temporaire sous les onglets. kind : "info", "good", "bad".
## on_click : l'avis devient cliquable (annonces, prop. 10 de l'étude de la fenêtre d'événement) ;
## seconds < 0 : durée par défaut ; color : liseré imposé (couleur du besoin de l'annonce).
func notify(text: String, kind := "info", on_click := Callable(), seconds := -1.0, color := Color(0, 0, 0, 0)) -> void:
	var toast := PanelContainer.new()
	var accent: Color = {"good": UiTheme.GOOD, "bad": UiTheme.BAD}.get(kind, UiTheme.ACCENT)
	if color.a > 0.0:
		accent = color
	var st := UiTheme.box(Color(0.03, 0.04, 0.06, 0.9), accent, 8, 0)
	st.border_width_left = 2
	st.content_margin_left = 14
	st.content_margin_right = 14
	toast.add_theme_stylebox_override("panel", st)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if on_click.is_valid():
		toast.mouse_filter = Control.MOUSE_FILTER_STOP
		toast.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		toast.tooltip_text = "Clic : ouvrir l'annonce"
		toast.gui_input.connect(func(ev: InputEvent) -> void:
			var mb := ev as InputEventMouseButton
			if mb and mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				toast.accept_event()
				toast.queue_free()
				on_click.call())
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
	tw.tween_interval(TOAST_SECONDS if seconds < 0.0 else seconds)
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


## Onglet Stabilité (et touche K) : vue galaxie → stabilité → corruption (si le pilier Administration
## est complet pour le joueur) → vue galaxie.
func cycle_stability_lens() -> void:
	var fiscal := _state != null and Finance.full(_state) and Finance.applies(_state, _player)
	if lens == "stability" and _state != null and Admin.full(_state) and Admin.has_corruption(_state, _player):
		set_lens("corruption")
	elif (lens == "stability" or lens == "corruption") and fiscal:
		set_lens("fiscal")  # mode « Fiscalité » : franchises, grèves, fuite fiscale
	elif lens == "stability" or lens == "corruption" or lens == "fiscal":
		set_lens("")
	else:
		set_lens("stability")


## Onglet Commerce (et touche G) : vue galaxie → commerce → économie privée (si le joueur a un
## secteur privé) → vue galaxie.
func cycle_trade_lens() -> void:
	var ports_on := _state != null and Ports.enabled(_state)
	if lens == "trade" and _state != null and Private.applies(_state, _player):
		set_lens("private")
	elif (lens == "trade" or lens == "private") and ports_on:
		set_lens("ports")
	elif lens == "trade" or lens == "private" or lens == "ports":
		set_lens("")
	else:
		set_lens("trade")


## Onglet Peuples : peuples, puis lentille psionique si le pilier est en jeu (sensitifs, écrans, Phare,
## ambre, mondes hantés), puis la vue galaxie.
func cycle_peoples_lens() -> void:
	if lens == "peoples" and _state != null and Psionics.applies(_state, _player):
		set_lens("psionics")
	elif lens == "peoples" or lens == "psionics":
		set_lens("")
	else:
		set_lens("peoples")


## Onglet Guerre (et touche W) : guerre, puis couverture des senseurs si la furtivité est en jeu
## (furtivité, prop. 37), puis la vue galaxie.
func cycle_war_lens() -> void:
	if lens == "war" and _state != null and Stealth.enabled(_state):
		set_lens("sensors")
	elif lens == "war" or lens == "sensors":
		set_lens("")
	else:
		set_lens("war")


## Lentille de la carte : "" (vue galaxie), "economy", "stability", "politics", "trade", "peoples", "faith", "amph" ou "war".
func set_lens(value: String) -> void:
	lens = value
	_tab_galaxy.set_pressed_no_signal(value == "")
	_lens_button.text = ("Lentille : %s" % lens_label(value)).to_upper()
	_lens_button.set_pressed_no_signal(value != "")
	for id: String in lens_buttons:
		(lens_buttons[id] as Button).set_pressed_no_signal(id == value)
	if _lens_note:
		_lens_note.text = String(LENS_TIPS.get(value, ""))
	_refresh_legend()
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
	_tabs.add_theme_constant_override("separation", 0)
	add_child(_tabs)
	_tab_galaxy = _tab("Vue galaxie", "La carte des systèmes")
	_tab_galaxy.pressed.connect(func() -> void:
		if _system_mode:
			_tab_galaxy.set_pressed_no_signal(false)
			close_system_requested.emit()
		else:
			set_lens(""))
	_lens_button = _tab("Lentille : empires", "Choisir ce que la carte montre : cinq familles de lentilles. Les touches L, K, O, G, U, N, X, W et A restent.")
	_lens_button.pressed.connect(func() -> void:
		_lens_button.set_pressed_no_signal(lens != "")
		_lens_panel.visible = not _lens_panel.visible
		_refresh_lens_panel()
		_refresh_legend())
	_tab_orbit = _tab("Vue orbitale", "L'étoile et ses planètes en orbite  (Tab)")
	_tab_orbit.pressed.connect(func() -> void: system_mode_requested.emit(false))
	_tab_manage = _tab("Gestion du système", "Les planètes côte à côte, pour comparer  (Tab)")
	_tab_manage.pressed.connect(func() -> void: system_mode_requested.emit(true))
	_tab_orbit.visible = false
	_tab_manage.visible = false
	_tab_galaxy.set_pressed_no_signal(true)
	_build_lens_panel()


## Panneau du sélecteur : une ligne par famille, ses lentilles en boutons, puis ce que montre la lentille.
func _build_lens_panel() -> void:
	_lens_panel = PanelContainer.new()
	_lens_panel.add_theme_stylebox_override("panel", UiTheme.box(UiTheme.PANEL, UiTheme.LINE, 10, 1))
	_lens_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_lens_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_lens_panel.offset_top = 40.0
	_lens_panel.visible = false
	add_child(_lens_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	_lens_panel.add_child(box)
	for fam: Array in LENS_FAMILIES:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		box.add_child(row)
		var name_label := Label.new()
		name_label.theme_type_variation = &"Section"
		name_label.text = String(fam[0]).to_upper()
		name_label.custom_minimum_size = Vector2(110, 0)
		row.add_child(name_label)
		for l: Array in fam[1]:
			var id := String(l[0])
			var b := Button.new()
			b.text = String(l[1])
			b.toggle_mode = true
			b.focus_mode = Control.FOCUS_NONE
			b.tooltip_text = String(LENS_TIPS.get(id, ""))
			b.pressed.connect(func() -> void:
				_lens_panel.visible = false
				set_lens(id))
			row.add_child(b)
			lens_buttons[id] = b
	box.add_child(HSeparator.new())
	# Calques : ce que la carte superpose, quelle que soit la lentille.
	var layers := HBoxContainer.new()
	layers.add_theme_constant_override("separation", 10)
	box.add_child(layers)
	var layers_label := Label.new()
	layers_label.theme_type_variation = &"Section"
	layers_label.text = "CALQUES"
	layers_label.custom_minimum_size = Vector2(110, 0)
	layers.add_child(layers_label)
	for l: Array in GalaxyView.LAYERS:
		var id := String(l[0])
		var c := CheckBox.new()
		c.text = String(l[1])
		c.tooltip_text = String(l[2])
		c.button_pressed = true
		c.focus_mode = Control.FOCUS_NONE
		c.toggled.connect(func(on: bool) -> void: layer_toggled.emit(id, on))
		layers.add_child(c)
		layer_boxes[id] = c
	box.add_child(HSeparator.new())
	_lens_note = UiTheme.paragraph("", 620.0, 13)
	box.add_child(_lens_note)
	_legend = PanelContainer.new()
	_legend.add_theme_stylebox_override("panel", UiTheme.box(Color(0.03, 0.04, 0.06, 0.82), UiTheme.LINE, 8, 1))
	_legend.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_legend.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_legend.offset_top = 40.0
	_legend.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.visible = false
	add_child(_legend)
	_legend_box = VBoxContainer.new()
	_legend_box.add_theme_constant_override("separation", 2)
	_legend_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_legend.add_child(_legend_box)
	set_lens(lens)


## Légende d'une lentille : [[couleur, ce qu'elle veut dire], ...] (vide pour la carte des empires).
static func lens_legend(id: String) -> Array:
	var grey := Color(0.62, 0.64, 0.68)
	var red := Color(0.86, 0.33, 0.31)
	var gold := Color(0.92, 0.76, 0.36)
	match id:
		"borders":
			return [[GalaxyView.BORDER_OPEN_COLOR, "Vos flottes de guerre passent"], [GalaxyView.BORDER_GUARDED_COLOR, "Vaisseaux sans armes seulement"],
					[GalaxyView.BORDER_CLOSED_COLOR, "Frontière close"], [Color.WHITE, "Vos systèmes"]]
		"amph":
			return [[gold, "Membre de l'Amphictyonie"], [red, "Hors-la-loi"], [Color(0.55, 0.58, 0.62), "Reste dehors"]]
		"economy":
			return [[Color(0.85, 0.88, 0.93), "Bilan mensuel du système, sous l'étoile"]]
		"trade":
			return [[GalaxyView.TRADE_INTERNAL_COLOR, "Route intérieure"], [GalaxyView.TRADE_TIER_COLORS[1], "Traité de premier palier"],
					[GalaxyView.TRADE_TIER_COLORS[2], "Deuxième palier"], [GalaxyView.TRADE_TIER_COLORS[3], "Troisième palier"],
					[GalaxyView.BATTLE_COLOR, "Route bloquée"], [Color(0.95, 0.45, 0.3), "Arc : risque pirate"]]
		"private":
			return [[GalaxyView.PRIVATE_MINE_COLOR, "Station minière"], [GalaxyView.PRIVATE_RESORT_COLOR, "Station touristique"],
					[GalaxyView.PRIVATE_BRANCH_COLOR, "Filiale"], [red, "Zone militaire, repaire"]]
		"ports":
			var out := []
			for i in PortsUi.STATE_COLORS.size():
				out.append([PortsUi.STATE_COLORS[i], Ports.state_label(i)])
			return out
		"stability":
			var out := []
			var tiers: Array = Stability.data()["tiers"]
			for i in range(tiers.size() - 1, -1, -1):
				var t: Dictionary = tiers[i]
				out.append([Color.html(String(t.get("color", "#a9b4c2"))), "%s (à partir de %d)" % [String(t["label"]), int(t["min"])]])
			out.append([grey, "Monde libre"])
			return out
		"corruption":
			return [[AdminUi.corruption_color(0), "Moins de 10"], [AdminUi.corruption_color(10), "De 10 à 19"],
					[AdminUi.corruption_color(20), "De 20 à 29"], [AdminUi.corruption_color(30), "30 et plus"], [Color(0.95, 0.78, 0.36), "Anneau : siège d'administration"]]
		"fiscal":
			return [[Color(0.92, 0.78, 0.36), "Franchise fiscale"], [Color(0.88, 0.57, 0.23), "Fuite fiscale"], [red, "Grève fiscale"],
					[Color(0.55, 0.58, 0.62), "Rien à signaler"]]
		"politics":
			return [[Color(0.85, 0.88, 0.93), "Couleur du courant dominant ; trait plein s'il est au pouvoir, pointillé sinon"]]
		"peoples":
			return [[Color(0.85, 0.88, 0.93), "Anneau partagé selon la part de chaque espèce"]]
		"faith":
			return [[Color(0.85, 0.88, 0.93), "Anneau partagé selon la part de chaque croyance"], [gold, "Monde saint"]]
		"psionics":
			return [[Color(0.72, 0.6, 0.95), "Sensitifs et écrans"], [Color(1.0, 0.9, 0.5), "Portée du Phare"], [Color(1.0, 0.7, 0.2), "Ambre"],
					[Color(0.8, 0.3, 0.9), "Monde hanté"]]
		"culture":
			var out := []
			for i in Culture.tiers().size():
				out.append([Culture.tier_color(i), Culture.tier_label(i)])
			out.append([Color(0.95, 0.5, 0.9), "Défection en cours"])
			return out
		"war":
			return [[red, "Système ennemi"], [Color(0.95, 0.8, 0.35), "Pointillé : votre revendication"], [grey, "Hachures : occupé, à la couleur de l'occupant"]]
		"sensors":
			return [[Color(0.35, 0.85, 0.95), "Couvert par vos senseurs, plus net où ils portent mieux"], [Color.WHITE, "Anneau : poste d'écoute"]]
	return []


func _refresh_legend() -> void:
	if _legend == null:
		return
	var list := lens_legend(lens)
	_legend.visible = not list.is_empty() and not _lens_panel.visible and not _system_mode and not _empire_screen
	if not _legend.visible:
		return
	for c in _legend_box.get_children():
		_legend_box.remove_child(c)
		c.queue_free()
	for e: Array in list:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var chip := ColorRect.new()
		chip.color = e[0]
		chip.custom_minimum_size = Vector2(12, 12)
		chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(chip)
		var text := Label.new()
		text.text = String(e[1])
		text.add_theme_font_size_override("font_size", 13)
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(text)
		_legend_box.add_child(row)
	_legend.reset_size()


## Textes de la légende affichée (pour les tests).
func legend_texts() -> PackedStringArray:
	var out := PackedStringArray()
	if _legend and _legend.visible:
		for row in _legend_box.get_children():
			out.append((row.get_child(1) as Label).text)
	return out


## Règle les cases des calques sans émettre (la carte fait foi).
func set_layers(layers: Dictionary) -> void:
	for id: String in layer_boxes:
		(layer_boxes[id] as CheckBox).set_pressed_no_signal(bool(layers.get(id, true)))


## Trois boutons de palier à gauche du cadran (B1) : Galaxie, Région, Système.
func _build_tier_buttons() -> void:
	_tier_box = VBoxContainer.new()
	_tier_box.add_theme_constant_override("separation", 2)
	_tier_box.anchor_left = 1.0
	_tier_box.anchor_right = 1.0
	_tier_box.anchor_top = 1.0
	_tier_box.anchor_bottom = 1.0
	_tier_box.offset_right = -TimeDial.SIDE - MARGIN - 8.0
	_tier_box.offset_left = _tier_box.offset_right - 86.0
	_tier_box.offset_bottom = -MARGIN - 46.0
	_tier_box.offset_top = _tier_box.offset_bottom - 80.0
	_tier_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_tier_box)
	var tips := ["Les empires vus de loin : territoires, capitales, fronts", "Les systèmes et les flottes", "Au plus près : silhouettes des flottes, cargos sur les routes"]
	for i in GalaxyView.TIER_NAMES.size():
		var b := Button.new()
		b.theme_type_variation = &"BarButton"
		b.text = GalaxyView.TIER_NAMES[i].to_upper()
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.tooltip_text = tips[i]
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func() -> void: zoom_tier_requested.emit(i))
		_tier_box.add_child(b)
		tier_buttons.append(b)


## Palier de zoom affiché par la carte : son bouton s'allume.
func set_zoom_tier(tier: int) -> void:
	for i in tier_buttons.size():
		tier_buttons[i].set_pressed_no_signal(i == tier)


## Nom d'une lentille pour le joueur.
static func lens_label(id: String) -> String:
	for fam: Array in LENS_FAMILIES:
		for l: Array in fam[1]:
			if String(l[0]) == id:
				return String(l[1])
	return id


## La lentille est-elle offerte dans cette partie, pour cet empire ?
func lens_offered(id: String) -> bool:
	if _state == null:
		return true
	match id:
		"borders":
			return Borders.active(_state)
		"private":
			return Private.applies(_state, _player)
		"ports":
			return Ports.enabled(_state)
		"corruption":
			return Admin.full(_state) and Admin.has_corruption(_state, _player)
		"fiscal":
			return Finance.full(_state) and Finance.applies(_state, _player)
		"psionics":
			return Psionics.applies(_state, _player)
		"culture":
			return Culture.enabled(_state)
		"sensors":
			return Stealth.enabled(_state)
	return true


## Referme le sélecteur de lentilles ; vrai s'il était ouvert (Échap).
func close_lens_panel() -> bool:
	var was := _lens_panel.visible
	_lens_panel.visible = false
	return was


func _refresh_lens_panel() -> void:
	for id: String in lens_buttons:
		(lens_buttons[id] as Button).visible = lens_offered(id)


func _tab(text: String, tip: String) -> Button:
	var b := Button.new()
	b.theme_type_variation = &"LensTab"
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
	fleet_place_link = LinkButton.new()
	fleet_place_link.focus_mode = Control.FOCUS_NONE
	fleet_place_link.underline = LinkButton.UNDERLINE_MODE_ON_HOVER
	fleet_place_link.add_theme_font_size_override("font_size", 13)
	fleet_place_link.tooltip_text = "Passer à la fiche de ce système"
	fleet_place_link.pressed.connect(func() -> void: fleet_place_requested.emit(_fleet_id))
	inner.add_child(fleet_place_link)
	_fleet_stats = UiTheme.dim("", 13)
	_fleet_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_fleet_stats.custom_minimum_size = Vector2(CARD_WIDTH - 26.0, 0)
	inner.add_child(_fleet_stats)
	# Composition (refonte, B3) : une rangée par classe, avec sa silhouette, son nombre et l'état des coques.
	_fleet_comp = VBoxContainer.new()
	_fleet_comp.add_theme_constant_override("separation", 2)
	inner.add_child(_fleet_comp)
	# Ordres rangés par usage ; les plus rares attendent derrière « Autres ordres ».
	var grids := {}
	for gdef: Array in FLEET_GROUPS:
		var gid := String(gdef[0])
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		if gid == "more":
			_fleet_more_button = Button.new()
			_fleet_more_button.focus_mode = Control.FOCUS_NONE
			_fleet_more_button.toggle_mode = true
			_fleet_more_button.theme_type_variation = &"BarButton"
			_fleet_more_button.tooltip_text = "Les ordres dont on se sert rarement : ralliement, abordage, prises, balise, rassembler, détacher, rapport, remise à niveau."
			_fleet_more_button.pressed.connect(func() -> void:
				_fleet_more_open = not _fleet_more_open
				_refresh_fleet_groups())
			inner.add_child(_fleet_more_button)
		else:
			var head := UiTheme.section(String(gdef[1]))
			inner.add_child(head)
			_fleet_group_heads[gid] = head
		inner.add_child(box)
		var gg := GridContainer.new()
		gg.columns = 2
		gg.add_theme_constant_override("h_separation", 4)
		gg.add_theme_constant_override("v_separation", 4)
		box.add_child(gg)
		grids[gid] = gg
		_fleet_group_boxes[gid] = box
	for a in [["explore", "EXPLORATION AUTO", "La flotte part seule vers les systèmes inexplorés les plus proches, et continue jusqu'à ce qu'il n'y en ait plus  (E)"],
			["colonize", "COLONISER ICI", "Ouvrir le système pour choisir la planète où fonder la revendication"],
			["stop", "ARRÊTER", "S'arrêter au système le plus proche sur la route"],
			["patrol", "PATROUILLE", "Aller-retour permanent entre la position de la flotte et un système : cliquez, puis clic droit sur le système (ou Maj + clic droit). Les pirates évitent les systèmes gardés."],
			["guard", "GARDER", "Défenses spatiales complètes : garder ce système. La flotte y reçoit +10 % de dégâts, la couverture de la station, et y revient si on l'en attire."],
			["stance", "CONSIGNE", "Consigne d'engagement, tenue sans votre intervention : engager, éviter le combat (la flotte rompt dès qu'il s'engage) ou se replier si elle est surclassée. Clic : consigne suivante."],
			["rally", "RALLIEMENT ICI", "Point de ralliement des chantiers : vos vaisseaux armés neufs viennent d'eux-mêmes dans ce système. Clic : le poser ici, ou l'enlever."],
			["posture", "POSTURE", "Furtivité : changer de posture (aucune, Silence radio, Balayage actif, Embuscade). Clic : posture suivante."],
			["board", "ABORDAGE", "Prises de guerre : posture d'abordage. La flotte dépense ses troupes pour prendre les vaisseaux ennemis très abîmés au lieu de les achever."],
			["prizes", "PRISES", "Prises de guerre : remettre en état, refondre, démanteler ou vendre les vaisseaux pris (au chantier d'une de vos colonies)."],
			["insolite", "PEUPLE", "Peuples insolites : chantier embarqué, Pilotes des Kraal, délégué au Grand Numéro."],
			["beacon", "BALISE D'ÉCOUTE", "Furtivité complète : un éclaireur sans armes à l'arrêt pose une balise camouflée qui voit à un saut (Senseurs tachyoniques, 30 matériaux et 20 énergie, 6 au plus)."],
			["merge", "RASSEMBLER", "Réunir dans cette flotte les autres flottes à l'arrêt dans ce système"],
			["split", "DÉTACHER", "Détacher un vaisseau dans une nouvelle flotte"],
			["report", "RAPPORT", "Dernier rapport de bataille de vos flottes  (B)"],
			["tactic", "TACTIQUE", "Changer de tactique de combat (choisie avant la bataille, appliquée sans votre intervention)  (T)"],
			["refit", "REMISE À NIVEAU", "Donner aux vaisseaux les dernières marques d'armes et de défenses, dans le chantier d'une de vos colonies"],
			["embark", "EMBARQUER", "Faire monter à bord les régiments qui attendent dans ce système, dans la limite des places des transports"],
			["disembark", "DÉPOSER", "Déposer les régiments à bord dans un de vos systèmes"],
			["bomb", "BOMBARDEMENT", "Posture de bombardement pendant un siège (combat au sol complet)"],
			["requisition", "RÉQUISITIONNER", "Logistique complète : refaire le plein sur le système ennemi peuplé qu'on assiège (dévastation, stabilité, rancune, crime de guerre sous les Mondes protégés)"],
			["invade", "ENVAHIR", "Débarquer les troupes : le système change de mains si elles sont plus nombreuses que la garnison"]]:
		var b := Button.new()
		b.text = a[1]
		b.tooltip_text = a[2]
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if a[0] == "colonize" or a[0] == "invade":
			b.theme_type_variation = &"PrimaryButton"
		if a[0] == "explore" or a[0] == "patrol" or a[0] == "guard" or a[0] == "board":
			b.toggle_mode = true
		var action: String = a[0]
		b.pressed.connect(func() -> void: fleet_action_requested.emit(action, _fleet_id))
		var group := fleet_group_of(action)
		# Tactique et invasion prennent toute la largeur, sous la grille de leur groupe.
		if action == "tactic" or action == "invade" or action == "refit" or action == "bomb":
			b.clip_text = true
			(_fleet_group_boxes[group] as VBoxContainer).add_child(b)
		else:
			(grids[group] as GridContainer).add_child(b)
		_fleet_buttons[action] = b
	_fleet_hint = UiTheme.paragraph("Clic droit sur un système : y envoyer la flotte (Maj : patrouiller). Clic molette : choisir l'ordre.  F : flotte suivante.  I : flotte inactive suivante.  T : tactique.", CARD_WIDTH - 26.0, 12)
	_fleet_hint.theme_type_variation = &"Dim"
	inner.add_child(_fleet_hint)


## Groupe d'un ordre de flotte (voir FLEET_GROUPS) ; « more » pour ceux qui n'y sont pas nommés.
static func fleet_group_of(action: String) -> String:
	for gdef: Array in FLEET_GROUPS:
		if (gdef[2] as Array).has(action):
			return String(gdef[0])
	return "more"


## Un titre de groupe ne s'affiche que si un de ses ordres est offert ; « Autres ordres » dit combien
## il en cache.
func _refresh_fleet_groups() -> void:
	for gdef: Array in FLEET_GROUPS:
		var gid := String(gdef[0])
		var n := 0
		for action: String in _fleet_buttons:
			if fleet_group_of(action) == gid and (_fleet_buttons[action] as Button).visible:
				n += 1
		var box: VBoxContainer = _fleet_group_boxes[gid]
		if gid == "more":
			_fleet_more_button.visible = n > 0
			_fleet_more_button.text = "AUTRES ORDRES (%d)  %s" % [n, "▴" if _fleet_more_open else "▾"]
			_fleet_more_button.set_pressed_no_signal(_fleet_more_open)
			box.visible = n > 0 and _fleet_more_open
			# La fiche ne doit pas sortir de l'écran : le détail s'efface le temps de choisir un ordre rare.
			_fleet_comp.visible = not box.visible
			_fleet_stats.visible = not box.visible
			_fleet_hint.visible = _fleet_hint.visible and not box.visible
		else:
			(_fleet_group_heads[gid] as Control).visible = n > 0
			box.visible = n > 0


## Composition d'une flotte, classe par classe : [{ship, label, n, hp, max}], la plus solide d'abord.
## Les marques successives d'une même classe (Frégate Mk 2, Mk 3) comptent ensemble.
static func fleet_rows(f: Fleet) -> Array[Dictionary]:
	var by := {}
	var mark := RegEx.create_from_string("\\s+Mk\\s*\\d+$")
	for i in f.ships.size():
		var id := String(f.ships[i])
		var label := mark.sub(String(GameData.ship(id).get("label", id)), "")
		if not by.has(label):
			by[label] = {"ship": id, "label": label, "n": 0, "hp": 0, "max": 0}
		var m := Fleet.max_hp_of(id)
		by[label]["n"] += 1
		by[label]["max"] += m
		by[label]["hp"] += clampi(f.hp[i], 0, m) if i < f.hp.size() and f.hp[i] >= 0 else m
	var out: Array[Dictionary] = []
	for label: String in by:
		out.append(by[label])
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ma := Fleet.max_hp_of(String(a["ship"]))
		var mb := Fleet.max_hp_of(String(b["ship"]))
		return ma > mb or (ma == mb and String(a["ship"]) < String(b["ship"])))
	return out


func _refresh_fleet_comp(f: Fleet, owner: Empire) -> void:
	var rows := fleet_rows(f)
	var sig := "%d|%s" % [f.owner, str(rows)]
	if sig == _fleet_comp_sig:
		return
	_fleet_comp_sig = sig
	for c in _fleet_comp.get_children():
		_fleet_comp.remove_child(c)
		c.queue_free()
	var style := SpeciesLook.hull_style(owner.faction_id) if owner != null else ""
	var catalog := GameData.ship_ids()
	for k in rows.size():
		var r: Dictionary = rows[k]
		if k >= FLEET_ROWS_MAX and rows.size() > FLEET_ROWS_MAX + 1:
			var rest := 0
			for j in range(k, rows.size()):
				rest += int(rows[j]["n"])
			_fleet_comp.add_child(UiTheme.dim("et %d autres vaisseaux de %d classes" % [rest, rows.size() - k], 13))
			break
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var slot := Control.new()
		slot.custom_minimum_size = Vector2(26, 22)
		row.add_child(slot)
		if catalog.has(r["ship"]) and owner != null:
			var pic := TextureRect.new()
			pic.texture = HullArt.icon(style, String(r["ship"]), owner.color())
			pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			pic.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
			slot.add_child(pic)
		var name_label := Label.new()
		name_label.text = "%s × %d" % [r["label"], int(r["n"])] if int(r["n"]) > 1 else String(r["label"])
		name_label.add_theme_font_size_override("font_size", 14)
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		row.add_child(name_label)
		var pct := int(r["hp"]) * 100 / maxi(1, int(r["max"]))
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(90, 8)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = 100
		bar.value = pct
		bar.tooltip_text = "Coque : %d sur %d" % [int(r["hp"]), int(r["max"])]
		bar.modulate = Color(0.45, 0.85, 0.55) if pct >= 67 else (Color(0.95, 0.75, 0.35) if pct >= 34 else Color(0.93, 0.42, 0.38))
		row.add_child(bar)
		_fleet_comp.add_child(row)


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
	# Les rangées de composition disent la même chose, en mieux : la ligne ne reste que pour nommer l'empire.
	_fleet_kind.visible = not mine
	if not mine:
		_fleet_kind.text = owner.short_name()
	_refresh_fleet_comp(f, owner)
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
	if not f.queue.is_empty():
		var steps := PackedStringArray()
		for q in f.queue:
			steps.append(_system_label(q))
		_fleet_status.text += "\nPuis : %s." % ", ".join(steps)
	if f.is_moving() and f.progress == 0:
		var wait := Fleets.spool_days(_state, f, f.system_id, f.path[0]) - f.spool
		if wait > 0:
			_fleet_status.text += "\nMise en route : départ dans %d jour%s." % [wait, "s" if wait > 1 else ""]
	_fleet_status.text += combat_status(_state, f)
	var adm := Heroes.assigned_to(_state, "fleet", f.id, f.owner)
	if not adm.is_empty():
		_fleet_status.text += "\nAmiral ✦ %s, niveau %d%s." % [adm["name"], int(adm["lvl"]),
				(" (en route, %d j)" % (int(adm["arrive"]) - _state.tick)) if int(adm["arrive"]) > _state.tick else ""]
	var v := Fleets.vision(f, _state)
	_fleet_stats.text = "%d vaisseau%s  ·  vitesse %d  ·  vision %d saut%s" % [f.ships.size(), "x" if f.ships.size() > 1 else "",
			Fleets.speed(f, _state), v, "s" if v > 1 else ""]
	var herd := Fauna.herd_of(_state, f)
	if not herd.is_empty():
		# Créatures : jamais la force exacte, une fourchette (plus étroite une fois l'espèce étudiée).
		var pr := Fauna.power_range(_state, _player, f)
		var sp := String(herd["sp"])
		_fleet_stats.text += "\nPuissance %d à %d  ·  %s  ·  %s" % [pr[0], pr[1], Fauna.temper_label(sp),
				"hostile" if Fauna.hostile(_state, f, _player) else "vous laisse passer"]
	elif f.owner == GameState.FAUNA_ID:
		# Gardiens et machines des tombeaux : un crâne et une fourchette, jamais la force exacte.
		var pr := Fauna.power_range(_state, _player, f)
		var gid := Guardians.of_fleet(_state, f)
		var pid := Plagues.of_fleet(_state, f)
		_fleet_stats.text += "\n☠ %s  ·  puissance %d à %d  ·  %s" % ["Fléau errant" if pid >= 0 else "Gardien", pr[0], pr[1],
				"hostile" if Fauna.hostile(_state, f, _player) else "pacifique, vous laisse passer"]
		if gid != "":
			_fleet_stats.text += "\n%s" % String(Guardians.def(gid).get("trait", ""))
		elif pid >= 0:
			var pd: Dictionary = Plagues.list(_state)[pid]
			_fleet_stats.text += "\n%s" % String(Plagues.kind_def(String(pd["kind"])).get("trait", ""))
			if String(pd["star"]) != "":
				_fleet_stats.text += " Sa couleur : %s." % GalaxyGenerator.star_label(String(pd["star"])).to_lower()
	elif f.owner == GameState.CRISIS_ID:
		# Crise de fin de partie : son rôle (cœur, point faible, flotte de guerre) et sa force.
		var role := Crisis.role_of(_state, f.id)
		var what := "cœur de la crise : le détruire la vainc" if role == Crisis.ROLE_HEART else ("point faible : le détruire l'affaiblit" if role == Crisis.ROLE_STATION else "flotte de guerre")
		@warning_ignore("integer_division")
		_fleet_stats.text += "
☄ %s  ·  puissance %d  ·  coque %d %%\n%s" % [Crisis.name_of(Crisis.kind(_state)), Combat.fleet_power(f),
				f.total_hp() * 100 / maxi(1, f.total_max_hp()), what]
	elif GameState.is_minor(f.owner):
		# Peuple mineur : votre faveur et votre palier (prop. 34).
		var mid := f.owner
		_fleet_stats.text += "\n◆ %s  ·  %s  ·  %s" % [Minors.name_of(_state, mid), "en guerre avec vous" if Combat.at_war(_state, mid, _player) else "faveur %d" % Minors.fav(_state, mid, _player),
				String(Minors.TIER_LABELS.get(Minors.tier(_state, mid, _player), ""))]
	elif GameState.is_ancient(f.owner):
		# Puissance ancienne : son humeur envers vous et le rapport de force en mots (prop. 6).
		var aid := f.owner
		var mood := "sans opinion" if Ancients.no_opinion(_state, aid) else String(Ancients.attitude(_state, aid, _player).get("label", "?")).to_lower()
		_fleet_stats.text += "\n✧ %s  ·  %s  ·  %s\n%s" % [Ancients.name_of(_state, aid), String(AncientsUi.STAGE_LABELS.get(Ancients.stage(_state, aid), "")).to_lower(),
				"en guerre avec vous" if Combat.at_war(_state, aid, _player) else mood, Ancients.force_text(_state, aid, _player)]
	elif Combat.is_armed(f) or f.total_hp() < f.total_max_hp():
		@warning_ignore("integer_division")
		if Ground.full(_state):
			_fleet_stats.text += "\nPuissance %d  ·  coque %d %%  ·  %s" % [Combat.fleet_power(f),
					f.total_hp() * 100 / maxi(1, f.total_max_hp()), Combat.tactic_label(Combat.fleet_tactic(f))]
		else:
			_fleet_stats.text += "\nPuissance %d  ·  coque %d %%  ·  troupes %d/%d  ·  %s" % [Combat.fleet_power(f),
					f.total_hp() * 100 / maxi(1, f.total_max_hp()), f.troops, Combat.max_troops(f, _state), Combat.tactic_label(Combat.fleet_tactic(f))]
	if Ground.full(_state) and Ground.capacity(_state, f) > 0 and (mine or Fleets.is_explored(_state, _player, f.system_id)):
		_fleet_stats.text += "\n" + ground_line(_state, f)
	# Furtivité : camouflage, détection et posture ; pour une flotte étrangère, ce qu'on en sait.
	if Stealth.enabled(_state):
		if mine:
			for line in Stealth.fleet_lines(_state, f):
				_fleet_stats.text += "\n" + line
		elif Stealth.full(_state) and _player >= 0:
			var deg := Stealth.degree(_state, _player, f)
			if deg > 0 and deg < 3:
				_fleet_stats.text += "\nRenseignement : %s%s" % [Stealth.degree_label(deg).to_lower(), " (pavillon inconnu)" if deg == 1 else ""]
	# Logistique : état de ravitaillement et réserves (prop. 28).
	if mine and Logistics.applies(_state, f):
		_fleet_stats.text += "\n" + Logistics.status_line(_state, f)
		_fleet_stats.tooltip_text = Logistics.status_tooltip(_state, f)
		_fleet_stats.mouse_filter = Control.MOUSE_FILTER_PASS
	else:
		_fleet_stats.tooltip_text = ""
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
	_fleet_buttons["patrol"].set_pressed_no_signal(f.is_patrolling())
	_fleet_buttons["explore"].text = "EXPLORATION : ACTIVE" if f.is_exploring() else "EXPLORATION AUTO"
	_fleet_buttons["explore"].disabled = mine and not f.is_exploring() and Fleets.explore_target(_state, f) == -1
	_fleet_buttons["patrol"].visible = mine
	_fleet_buttons["patrol"].text = "PATROUILLE : ACTIVE" if f.is_patrolling() else "PATROUILLE"
	if f.is_patrolling():
		_fleet_buttons["patrol"].tooltip_text = "Patrouille entre %s et %s. Clic : l'arrêter." % [g.systems[f.patrol[0]].system_name, g.systems[f.patrol[1]].system_name]
	_fleet_buttons["guard"].visible = mine and Combat.is_armed(f) and Defenses.full(_state)
	_fleet_buttons["stance"].visible = mine
	_fleet_buttons["stance"].text = "CONSIGNE : %s" % Fleets.stance_label(f.stance).to_upper()
	var me := _state.get_empire(_player)
	_fleet_buttons["rally"].visible = mine and not f.is_moving() and Combat.is_armed(f)
	_fleet_buttons["rally"].text = "RALLIEMENT : ICI" if me != null and me.rally_system == f.system_id else "RALLIEMENT ICI"
	_fleet_buttons["posture"].visible = mine and Stealth.enabled(_state)
	if mine and Stealth.enabled(_state):
		var pz := Stealth.posture(_state, f)
		_fleet_buttons["posture"].text = "POSTURE : %s" % Stealth.posture_label(pz).to_upper()
	_fleet_buttons["board"].visible = mine and Capture.full(_state) and Capture.posture_open(_state, f)
	if _fleet_buttons["board"].visible:
		var on := Capture.posture(_state, f)
		_fleet_buttons["board"].set_pressed_no_signal(on)
		_fleet_buttons["board"].text = "ABORDAGE : ACTIF" if on else "ABORDAGE"
		_fleet_buttons["board"].tooltip_text = CaptureUi.posture_tip(_state, f)
	var n_prizes := 0
	for s in f.ships:
		if Capture.is_prize(s):
			n_prizes += 1
	_fleet_buttons["prizes"].visible = mine and Capture.full(_state) and n_prizes > 0
	_fleet_buttons["prizes"].text = "PRISES (%d)" % n_prizes
	_fleet_buttons["insolite"].visible = mine and InsolitesUi.fleet_has_actions(_state, _player, f)
	if _fleet_buttons["insolite"].visible:
		_fleet_buttons["insolite"].text = InsolitesUi.fleet_button_text(_state, _player)
	_fleet_buttons["beacon"].visible = mine and Stealth.full(_state) and not Combat.is_armed(f)
	if _fleet_buttons["beacon"].visible:
		var bwhy := Stealth.check_beacon(_state, _player, f)
		_fleet_buttons["beacon"].disabled = bwhy != ""
		_fleet_buttons["beacon"].tooltip_text = "Poser une balise d'écoute camouflée qui voit à un saut." if bwhy == "" else "Impossible : %s." % bwhy
	_fleet_buttons["guard"].set_pressed_no_signal(f.is_guarding())
	_fleet_buttons["guard"].text = ("GARDE : %s" % g.systems[f.patrol[0]].system_name.to_upper()) if f.is_guarding() else "GARDER"
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
	var late := Fleets.outdated_count(_state, f)
	if armed and (late > 0 or f.refit_left > 0):
		_fleet_stats.text += "\n" + (("Au chantier : encore %d jour%s." % [f.refit_left, "s" if f.refit_left > 1 else ""]) if f.refit_left > 0 \
				else "%d vaisseau%s avec des marques d'armes dépassées." % [late, "x" if late > 1 else ""])
	_fleet_buttons["refit"].visible = mine and armed and (late > 0 or f.refit_left > 0)
	var refit_why := Fleets.check_refit(_state, _player, f.id) if mine else "x"
	_fleet_buttons["refit"].disabled = refit_why != ""
	_fleet_buttons["refit"].text = "AU CHANTIER : %d J" % f.refit_left if f.refit_left > 0 \
			else "REMISE À NIVEAU : %s, %d J" % [GameData.format_amounts(Fleets.refit_cost(_state, f)).to_upper(), Fleets.refit_days()]
	_fleet_buttons["refit"].tooltip_text = "Les vaisseaux gardent les marques de leur construction. Au chantier d'une de vos colonies, ils prennent les dernières (10 %% de leur prix, %d jours à quai ; partir interrompt les travaux).%s" % [
			Fleets.refit_days(), ("\n" + refit_why.substr(0, 1).to_upper() + refit_why.substr(1) + ".") if refit_why != "" and f.refit_left == 0 else ""]
	var enemy_owner := _state.system_owner(f.system_id)
	var invade_why := Combat.check_invade(_state, _player, f.id) if mine else "x"
	_fleet_buttons["invade"].visible = mine and not f.is_moving() and enemy_owner >= 0 and Combat.at_war(_state, _player, enemy_owner)
	_fleet_buttons["invade"].disabled = invade_why != ""
	var full := Ground.full(_state)
	if full:
		var mine_str := Ground.strength(Ground.aboard(_state, f.id))
		var def_str := Ground.militia_strength(_state, f.system_id) + Ground.strength(Ground.on_ground(_state, f.system_id, enemy_owner))
		_fleet_buttons["invade"].tooltip_text = "Débarquer les régiments : une bataille au sol de plusieurs jours s'engage contre la milice et les troupes du défenseur.\n%s" % (
				invade_why if invade_why != "" else "Force de vos régiments %d contre une défense estimée à %d." % [mine_str, def_str])
	else:
		_fleet_buttons["invade"].tooltip_text = "Débarquer les troupes : le système change de mains.\n%s" % (invade_why if invade_why != "" else "%d troupes contre une garnison de %d : la place est à vous." % [f.troops, Combat.garrison(_state, f.system_id)])
	var waiting := Ground.on_ground(_state, f.system_id, _player).size() if full and mine else 0
	var aboard := Ground.aboard(_state, f.id).size() if full and mine else 0
	var cap := Ground.capacity(_state, f) if full else 0
	_fleet_buttons["embark"].visible = mine and full and cap > 0 and not f.is_moving() and waiting > 0
	var emb_why := Ground.check_embark(_state, _player, f.id) if _fleet_buttons["embark"].visible else "x"
	_fleet_buttons["embark"].disabled = emb_why != ""
	_fleet_buttons["embark"].text = "EMBARQUER (%d)" % waiting
	_fleet_buttons["embark"].tooltip_text = "Faire monter à bord les régiments qui attendent dans ce système (%d place%s libre%s)." % [
			Ground.free_places(_state, f), "s" if Ground.free_places(_state, f) > 1 else "", "s" if Ground.free_places(_state, f) > 1 else ""] + (("\n" + emb_why) if emb_why != "" and emb_why != "x" else "")
	_fleet_buttons["bomb"].visible = mine and full and armed
	var bp := GroundSiege.posture(_state, f.id) if full else ""
	_fleet_buttons["bomb"].text = "BOMBARDEMENT : %s" % GroundSiege.posture_label(bp).to_upper()
	var nxt := GroundSiege.next_posture(_state, _player, bp) if full else ""
	_fleet_buttons["bomb"].tooltip_text = "%s\n\nClic : %s." % [
			String(GroundSiege.posture_def(bp).get("text", "Pas de bombardement : le siège use seulement fortifications et milice.")),
			GroundSiege.posture_label(nxt).to_lower() if nxt != "" else "aucun"]
	_fleet_buttons["disembark"].visible = mine and full and not f.is_moving() and aboard > 0
	var dis_why := Ground.check_disembark(_state, _player, f.id) if _fleet_buttons["disembark"].visible else "x"
	_fleet_buttons["disembark"].disabled = dis_why != ""
	_fleet_buttons["disembark"].tooltip_text = "Déposer les régiments à bord dans ce système (un des vôtres) ; ils y défendent et y récupèrent plus vite." + (("\n" + dis_why) if dis_why != "" and dis_why != "x" else "")
	var rq_vis := mine and armed and Logistics.full(_state) and Logistics._besieging(_state, f)
	_fleet_buttons["requisition"].visible = rq_vis
	var rq_why := Logistics.check_requisition(_state, _player, f.id) if rq_vis else "x"
	_fleet_buttons["requisition"].disabled = rq_why != ""
	if rq_vis:
		_fleet_buttons["requisition"].tooltip_text = "Refaire le plein sur le système assiégé : dévastation, stabilité -10, rancune du propriétaire, crime de guerre sous les Mondes protégés." + (("\n" + rq_why) if rq_why != "" else "")
	_fleet_buttons["report"].visible = mine and armed
	_fleet_buttons["report"].disabled = last_report(_state, _player).is_empty()
	_fleet_hint.visible = mine
	fleet_place_link.visible = not f.is_moving() and Fleets.is_explored(_state, _player, f.system_id)
	fleet_place_link.text = "Système : %s" % _system_label(f.system_id)
	_refresh_fleet_groups()


## Régiments à bord d'une flotte (combat au sol complet) : nombre, places, force.
static func ground_line(state: GameState, f: Fleet) -> String:
	var regs := Ground.aboard(state, f.id)
	if regs.is_empty():
		return "Transports : %d places libres, aucun régiment à bord." % Ground.capacity(state, f)
	return "%d régiment%s à bord  ·  places %d/%d  ·  force %d" % [regs.size(), "s" if regs.size() > 1 else "",
			Ground.used_places(state, f.id), Ground.capacity(state, f), Ground.strength(regs)]


## Ligne de combat d'une flotte à l'arrêt : bataille en cours, siège mené.
static func combat_status(state: GameState, f: Fleet) -> String:
	if f.is_moving():
		return ""
	var gb := Ground.battle(state, f.system_id) if Ground.full(state) else {}
	if not gb.is_empty():
		return "\nBATAILLE AU SOL : " + Ground.battle_text(state, gb) + "."
	var b := Combat.battle_at(state, f.system_id)
	if not b.is_empty():
		var day := int(b["day"])
		return "\nEN BATAILLE : jour %d sur %d, %s." % [day, Combat.battle_days(), Combat.phase_label(Combat.phase_index(day)).to_lower()]
	var owner := state.system_owner(f.system_id)
	if owner >= 0 and Combat.at_war(state, f.owner, owner) and Combat.is_besieged(state, f.system_id) and Combat.is_armed(f):
		if Ground.full(state):
			var line := "\nSIÈGE : fortifications %d / %d, milice %d / %d" % [GroundSiege.fort(state, f.system_id), GroundSiege.fort_max(state, f.system_id),
					Combat.garrison(state, f.system_id), Combat.garrison_max(state, f.system_id)]
			var left := GroundSiege.surrender_left(state, f.system_id)
			if left > 0:
				line += ", reddition dans %d j" % left
			return line + "."
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


func _build_quest_tracker() -> void:
	quest_tracker = QuestTracker.new()
	quest_tracker.anchor_left = 1.0
	quest_tracker.anchor_right = 1.0
	quest_tracker.offset_left = -CHRONICLE_WIDTH - MARGIN
	quest_tracker.offset_right = -MARGIN
	add_child(quest_tracker)
	quest_tracker.open_requested.connect(func() -> void: quests_requested.emit())
	quest_tracker.resized.connect(_place_fleet_list)
	quest_tracker.visibility_changed.connect(_place_fleet_list)


func _build_fleet_list() -> void:
	fleet_list = FleetListPanel.new()
	fleet_list.anchor_left = 1.0
	fleet_list.anchor_right = 1.0
	fleet_list.offset_left = -CHRONICLE_WIDTH - MARGIN
	fleet_list.offset_right = -MARGIN
	add_child(fleet_list)
	fleet_list.fleet_requested.connect(func(fid: int) -> void: fleet_requested.emit(fid))
	fleet_list.fleet_system_requested.connect(func(fid: int) -> void: fleet_system_requested.emit(fid))
	fleet_list.system_requested.connect(func(sid: int, open: bool) -> void: nav_system_requested.emit(sid, open))
	fleet_list.todo_requested.connect(func(item: Dictionary) -> void: todo_requested.emit(item))
	# La liste se range juste sous la chronique, dont la hauteur suit la longueur du texte.
	_chronicle.resized.connect(_place_fleet_list)
	_place_fleet_list()


func _place_fleet_list() -> void:
	var below := _chronicle.offset_top + _chronicle.size.y + 6.0
	if quest_tracker:
		quest_tracker.offset_top = below
		if quest_tracker.visible:
			below += quest_tracker.size.y + 6.0
	if fleet_list == null:
		return
	fleet_list.offset_top = below
	if spectator_panel:
		spectator_panel.offset_top = fleet_list.offset_top
		# Le tableau s'arrête au-dessus du cadran du temps ; ses lignes défilent au-delà.
		spectator_panel.set_max_height(get_viewport().get_visible_rect().size.y - spectator_panel.offset_top - TimeDial.SIDE - MARGIN - 8.0)


func _build_spectator_panel() -> void:
	spectator_panel = SpectatorPanel.new()
	spectator_panel.anchor_left = 1.0
	spectator_panel.anchor_right = 1.0
	spectator_panel.offset_left = -CHRONICLE_WIDTH - MARGIN
	spectator_panel.offset_right = -MARGIN
	spectator_panel.visible = false
	add_child(spectator_panel)
	get_viewport().size_changed.connect(_place_fleet_list)
	_place_fleet_list()


func _refresh_side_visibility() -> void:
	var on_map := not _system_mode and not _empire_screen and not spectator
	if _chronicle:
		_chronicle.visible = not _empire_screen and not (side_reduced and on_map)
	if fleet_list:
		fleet_list.visible = on_map and not side_reduced
	if quest_tracker:
		quest_tracker.set_allowed(on_map and not side_reduced)
	if alert_bar:
		alert_bar.visible = on_map and side_reduced
		side_toggle.visible = on_map
		side_toggle.text = "«" if side_reduced else "»"
		side_toggle.tooltip_text = ("Rouvrir le panneau : chronique, quêtes, flottes" if side_reduced else "Réduire le panneau à ses alertes, pour dégager la carte") + "  (touche ²)"
		side_toggle.offset_right = -MARGIN - (AlertBar.WIDTH if side_reduced else CHRONICLE_WIDTH) - 4.0
		side_toggle.offset_left = side_toggle.offset_right - 24.0
		if alert_bar.visible:
			alert_bar.refresh()
	if spectator_panel:
		spectator_panel.visible = spectator and not _system_mode and not _empire_screen
	if _tier_box:
		_tier_box.visible = not _system_mode and not _empire_screen
	_refresh_legend()
	_refresh_idle_button()


## Languette et barre d'alertes du panneau de droite (refonte, A4).
func _build_side_toggle() -> void:
	side_reduced = UiSettings.side_reduced
	alert_bar = AlertBar.new()
	alert_bar.anchor_left = 1.0
	alert_bar.anchor_right = 1.0
	alert_bar.offset_left = -MARGIN - AlertBar.WIDTH
	alert_bar.offset_right = -MARGIN
	alert_bar.offset_top = MARGIN
	alert_bar.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	alert_bar.visible = false
	add_child(alert_bar)
	alert_bar.alert_requested.connect(func(kind: String, arg: int) -> void: alert_requested.emit(kind, arg))
	side_toggle = Button.new()
	side_toggle.focus_mode = Control.FOCUS_NONE
	side_toggle.anchor_left = 1.0
	side_toggle.anchor_right = 1.0
	side_toggle.offset_top = MARGIN
	side_toggle.offset_bottom = MARGIN + 28.0
	side_toggle.pressed.connect(func() -> void: set_side_reduced(not side_reduced))
	add_child(side_toggle)


## Réduit le panneau de droite (chronique, quêtes, flottes) à sa barre d'alertes, ou le rouvre.
func set_side_reduced(on: bool) -> void:
	side_reduced = on
	if UiSettings.side_reduced != on:
		UiSettings.side_reduced = on
		UiSettings.save_settings()
	_refresh_side_visibility()


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
	# Réseau au tour par tour : qui a terminé son tour, à gauche du cadran.
	turn_players = TurnPlayersPanel.new()
	turn_players.anchor_left = 1.0
	turn_players.anchor_right = 1.0
	turn_players.anchor_top = 1.0
	turn_players.anchor_bottom = 1.0
	turn_players.offset_right = -TimeDial.SIDE - MARGIN - 8.0
	turn_players.offset_left = turn_players.offset_right - 230.0
	turn_players.offset_bottom = -MARGIN
	turn_players.offset_top = -MARGIN - 40.0
	turn_players.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	turn_players.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(turn_players)
	_build_tier_buttons()
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
	# Une seule fiche à la fois (refonte, A5) : une flotte choisie garde la sienne ; celle d'un système
	# ne revient que le temps d'un survol, pour voir où l'on envoie la flotte.
	var fleet_shown := _fleet_panel != null and _fleet_panel.visible and _hover_id < 0
	if _state == null or id < 0 or _system_mode or _empire_screen or fleet_shown:
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
	var owner := _state.get_empire(Intel.shown_owner(_state, s.id))
	var live := Intel.shown_live(_state, s.id)
	_portrait.set_star(s.star_type, fmod(float(s.id) * 0.731, 7.0))
	_card_title.text = s.system_name
	_card_title.add_theme_color_override("font_color", owner.color().lightened(0.35) if owner else UiTheme.TEXT)
	_card_kind.text = "Système stellaire (%s)" % GalaxyGenerator.star_label(s.star_type)
	_card_owner.text = "%s  ·  %s" % [
		("Monde libre" if owner.is_npc() else "Système de %s" % owner.short_name()) if owner else "Système libre",
		"à portée" if Economy.in_range(_state, _player, s.id) else "hors de portée",
	]
	if owner and owner.eliminated:
		_card_owner.text += "  ·  empire disparu"
	if owner and live:
		var war := owner.id != _player and Combat.at_war(_state, _player, owner.id)
		_card_owner.text += "%s\nGarnison %d / %d%s" % ["  ·  EN GUERRE" if war else "", Combat.garrison(_state, s.id), Combat.garrison_max(_state, s.id),
				"  ·  ASSIÉGÉ" if Combat.is_besieged(_state, s.id) else ""]
	elif owner and Intel.siege_of(_state, Intel.lens, s.id) >= 0:
		_card_owner.text += "\nAssiégé"
	if owner and owner.id == _player and Stability.applies(_state, _player):
		_card_owner.text += "\nStabilité %d (%s)" % [Stability.value(_state, s.id), Stability.tier_label(_state, s.id)]
	elif owner and owner.is_npc():
		_card_owner.text += "\nMonde libre : il a fait sécession"
	if Pirates.knows(_state, _player, s.id):
		_card_owner.text += "\nRepaire pirate"
	elif Pirates.is_port(_state, s.id) and _state.get_empire(_player) != null and _state.get_empire(_player).explored.has(s.id):
		_card_owner.text += "\nPort franc"
	if live and not Combat.battle_at(_state, s.id).is_empty():
		_card_owner.text += "\nBataille en cours"
	elif not live and Intel.battle_known(_state, Intel.lens, s.id):
		_card_owner.text += "\nBataille en cours"
	if not live:
		_card_owner.text += "\nHors de vue : %s (%s)" % [Intel.age_label(_state, Intel.lens, s.id),
				GameCalendar.date_string(Intel.last_seen(_state, Intel.lens, s.id))]
	for line in Intel.ghost_lines(_state, Intel.lens, s.id):
		_card_owner.text += "\nFlotte aperçue · " + line
	# Terrain (voir Terrain) : une ligne par terrain, inconvénient · avantage.
	var reg := Terrain.region_name(_state, s.id)
	if reg != "":
		_card_kind.text += "  ·  " + reg
	var tlines := Terrain.lines(_state, s.id)
	for line in tlines:
		_card_owner.text += "\n" + line
	_card_owner.tooltip_text = "\n\n".join(PackedStringArray(Terrain.lore_lines(_state, s.id)))
	_card_owner.mouse_filter = Control.MOUSE_FILTER_PASS if _card_owner.tooltip_text != "" else Control.MOUSE_FILTER_IGNORE
	var wl := CaptureLore.field_text(_state, s.id)  # champ d'épaves (prises de guerre)
	if wl != "":
		_card_owner.text += "\n" + wl
	if CaptureTomb.system(_state) == s.id:
		_card_owner.text += "\nLe Vaisseau-tombe dérive ici : l'aborder demande %d troupes (bouton PRISES d'une flotte)." % Capture.rule("tomb_troops", 60)
	if not tlines.is_empty():
		var tal: Array = []
		for t in Terrain.talent_labels(_state, Intel.lens):
			tal.append(String(t[0]))
		if not tal.is_empty():
			_card_owner.text += "\nTalent de terrain : " + ", ".join(tal)
	# Défenses spatiales (voir Defenses) : station, bouclier, mines, où en est l'assaut ; seulement en vue.
	if live:
		for line in Defenses.system_lines(_state, s.id):
			_card_owner.text += "\n" + line
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
		var c: Colony = Intel.shown_colony(_state, p.id)
		dot.ring = _state.get_empire(c.owner).color() if c else Color(0, 0, 0, 0)
		dot.tooltip_text = "%s  ·  %s  ·  taille %d\n%s" % [p.display_name(galaxy), p.type_label(), p.size, PlanetInfo.status_line(_state, p)]
		dot.queue_redraw()
	# Le bouton n'a de sens que pour le système sélectionné (pas pour un simple survol).
	_enter_button.visible = id == _system_id
	_enter_button.text = "CONTEMPLER LE VIDE" if s.planet_count == 0 else "ENTRER DANS LE SYSTÈME"
