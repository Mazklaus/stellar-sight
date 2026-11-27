class_name EmpireScreens
extends CanvasLayer
## Écrans d'empire, en plein écran comme dans les 4X « épurés » : la carte s'efface, le panneau
## d'empire et le cadran du temps restent en place, un onglet en haut au centre nomme l'écran (et le
## ferme), une colonne à gauche résume, et le contenu se range en blocs titrés.
## Économie, Colonies, Recherche, Diplomatie, Chantier (éditeur de vaisseaux, voir ShipyardScreen),
## Victoire et Renseignement (voir IntelScreen).
## Les chiffres viennent d'EmpireReport, qui applique les règles de la simulation sans rien modifier.
## Les emplacements d'illustration (Widgets.ArtSlot) prendront les images de assets/art/ quand elles existeront.

signal planet_requested(planet_id: int)
signal close_requested
signal screen_changed(screen_id: String)
## Le joueur déclare la guerre à un empire (écran Diplomatie, après confirmation).
signal war_requested(empire_id: int)
## Un ordre de l'écran Diplomatie (proposer, répondre, rompre, soudoyer, banquet, arbitrer).
signal command_requested(cmd: Dictionary)
## Montrer une flotte sur la carte (l'écran se ferme).
signal fleet_requested(fleet_id: int)
## Rouvrir un rapport de bataille spatiale (rang dans state.battle_reports).
signal battle_report_requested(index: int)
## Rouvrir une carte d'événement de la boîte (écran Chroniques).
signal event_requested(event_id: int)
## Ouvrir le choix de récompense d'un haut fait (voir DeedPanel).
signal deed_requested(item_id: int)
## Chroniques, onglet Annonces : rouvrir une annonce, montrer son lieu.
signal announce_requested(aid: int)
signal announce_locate_requested(system_id: int)
## Revoir une bataille au sol (écran Armées).
signal ground_replay_requested(report_id: int)
## Page du Codex d'une technologie (prop. 112 de l'étude de l'arbre).
signal codex_requested(article_id: String)

const MARGIN := 10.0
const SIDE_WIDTH := EmpireBar.WIDTH
const ROMAN := ["I", "II", "III", "IV", "V"]
const SIDE_TOP := EmpireBar.MARGIN + EmpireBar.HEIGHT + 8.0
const CONTENT_LEFT := SIDE_WIDTH + 2.0 * MARGIN + 18.0
## Le contenu s'arrête avant le cadran du temps, en bas à droite.
const CONTENT_RIGHT := TimeDial.SIDE + 30.0
const COLUMN_WIDTHS := [200.0, 200.0, 120.0, 210.0, 230.0]
## Colonnes du tableau des colonies : clé de tri, titre.
const COLONY_COLUMNS := [["name", "Planète"], ["type", "Type"], ["pop", "Population"], ["build", "Chantier"], ["net", "Bilan par mois"]]
const COLONY_FILTERS := [["all", "Toutes"], ["colony", "Colonies"], ["outpost", "Avant-postes"], ["founding", "Fondations"]]
const TYPE_COLORS := {
	"continental": Color(0.35, 0.7, 0.4), "ocean": Color(0.25, 0.5, 0.9), "desert": Color(0.9, 0.65, 0.35),
	"arctic": Color(0.75, 0.88, 1.0), "toxic": Color(0.65, 0.78, 0.2), "gas_giant": Color(0.88, 0.7, 0.45),
	"barren": Color(0.6, 0.58, 0.55), "asteroids": Color(0.62, 0.56, 0.48),
	"gaia": Color(0.3, 0.8, 0.45), "ecumenopole": Color(0.9, 0.76, 0.42),
	"noyau": Color(0.9, 0.5, 0.28), "habitat": Color(0.75, 0.8, 0.86), "coquille": Color(0.55, 0.85, 0.95),
	"creux": Color(0.45, 0.72, 0.88), "reliquaire": Color(0.72, 0.6, 0.95), "abri": Color(0.8, 0.72, 1.0),
}

var current := ""
## Planète choisie dans l'écran Colonies (-1 = aucune).
var selected_planet := -1
var colony_filter := "all"
## Tri du tableau des colonies (refonte, C2) : colonne ("" = ordre de l'empire) et sens.
var colony_sort := ""
var colony_sort_desc := false
var _col_heads: Array[Button] = []
var _state: GameState
var _player := 0
var _root: Control
var _tab: Button
## Onglets du domaine ouvert (refonte, A1 et A2) : une rangée sous l'onglet de l'écran.
var _domain_row: HBoxContainer
## Boutons de cette rangée, par libellé d'onglet (pour les tests).
var domain_buttons := {}
## Dernière adresse visitée dans chaque domaine (voir UiDomains).
var domain_last := {}
var _side: PanelContainer
var _side_box: VBoxContainer
## Défilement de la colonne de gauche quand elle dépasse l'écran (beaucoup de peuples, par exemple).
var _side_scroll: ScrollContainer
var _content: MarginContainer
# Économie
var _res_rows := {}
var _totals := {}
var _donut: Widgets.Donut
var _donut_legend: VBoxContainer
var _sys_list: VBoxContainer
var _sys_sig := ""
var _alerts: VBoxContainer
var _alerts_sig := "-"
## Courbes du bilan, par ressource, et liens des alertes (pour les tests).
var res_curves := {}
var alert_links: Array[Button] = []
var _faction_art: Widgets.ArtSlot
var _trait: Label
# Colonies
var _col_list: VBoxContainer
var _col_sig := ""
var _col_rows: Array[Dictionary] = []
var _col_empty: Label
var _col_donut: Widgets.Donut
var _col_counts := {}
var _filter_tabs := {}
## Écologie : boutons de doctrine environnementale (écran Colonies).
var _eco_buttons := {}
var _eco_label: Label
var _free_yards: Array[int] = []
var _pick_art: Widgets.ArtSlot
var _pick_title: Label
var _pick_lines: Label
var _pick_net: HBoxContainer
var _pick_open: Widgets.RoundButton
# Diplomatie
var _diplo_sig := ""
## Boutons « Déclarer la guerre » par empire (pour les tests).
var war_buttons := {}
## Empire choisi dans l'écran Diplomatie, et les boutons de sa relation (pour les tests).
var diplo_selected := -1
## Onglet de la diplomatie (empires, league, neighbors) et volet de la fiche d'un empire (relation, deal, war).
var diplo_tab := "empires"
var diplo_pane := "relation"
var diplo_pane_buttons := {}
var diplo_panes := {}
## Volets internes d'un écran (Assemblée, opérations du Renseignement) : groupe -> {"boxes", "buttons"},
## et le volet montré de chaque groupe, gardé d'une reconstruction à l'autre.
var panes := {}
var pane_current := {}
var diplo_table: DiplomacyTable
var treaty_buttons := {}
var cancel_buttons := {}
## Boutons Embargo / Lever l'embargo, par empire (pour les tests).
var embargo_buttons := {}
var proposal_buttons := {}
var ability_buttons := {}
## Sujets et paix à conditions (VassalUi) : boutons par rôle, brouillons de conditions et de clauses.
var vassal_buttons: Dictionary = {}
var vassal_draft: Dictionary = {}
## Koinon (KoinonUi) : boutons par rôle, brouillons de forme.
var koinon_buttons: Dictionary = {}
var koinon_draft: Dictionary = {}
## Buts de guerre (WarsUi) : boutons par rôle, motif choisi par empire.
var war_goal_buttons: Dictionary = {}
var war_draft: Dictionary = {}
## Frontières (BordersUi) : boutons par rôle.
var border_buttons: Dictionary = {}
## Écran Recherche : arbre, technologie choisie, boutons de la technologie choisie ("front", "queue", "remove").
var research_tree: ResearchTree
var research_selected := ""
var research_buttons := {}
var _research_sig := ""
var _tech_panel: PanelContainer
## Écran Chantier (éditeur de vaisseaux) ; garde le modèle affiché d'une ouverture à l'autre.
var shipyard: ShipyardScreen
## Écran Victoire : tout voir (mode spectateur), lignes de progression par victoire (pour les tests).
var see_all := false
var victory_rows := {}
## Bouton qui déplie le détail des victoires (écran Victoire).
var victory_detail: Button
var _vict_sig := ""
var _shipyard_selected := ""
## Écran Renseignement (IntelScreen) : empire dont on lit le dossier, boutons − / + des cellules par
## empire visé (pour les tests).
var intel_selected := -1
var intel_buttons := {}
## Boutons LANCER par opération (empire choisi), et EXPULSER / EXIGER RÉPARATION par dossier.
var intel_op_buttons := {}
var intel_case_buttons := {}
var _intel_sig := ""
var _peoples_sig := ""
## Onglet Flottes : tri, flotte choisie, boutons (pour les tests).
var _fleets_sig := ""
var _battles_sig := ""
var battles_buttons := {}
## Écran Armées : groupes de régiments dépliés (clé « f:flotte » ou « s:système »).
var armies_open := {}
var armies_buttons := {}
var fleets_sort := "power"
var fleets_sort_desc := true
var fleets_selected := -1
var fleets_buttons := {}
## Cartes des merveilles, par id (pour les tests).
var wonder_cards := {}
## Montant réglé au curseur d'emprunt, par prêteur (gardé d'un rafraîchissement à l'autre).
var borrow_amounts := {}
## Menus de statut de l'onglet Peuples, par espèce (pour les tests).
var peoples_buttons := {}
## Écran Panthéon (HeroScreen) : boutons par héros et par candidat (pour les tests).
var hero_buttons := {}
## Boutons de l'écran Ordre intérieur (« sid:décret », « free:sid »), pour les tests.
var order_buttons := {}
var _order_sig := ""
## Boutons de l'écran Commerce (réserve de routes intérieures), pour les tests.
var trade_buttons := {}
var _trade_sig := ""
## Onglet de l'écran Commerce : "routes", "resources" ou "market" ; brouillon d'échange (GoodsScreen).
var trade_tab := "routes"
var trade_deal := {}
## Boutons de soutien de l'écran Sénat, par courant (pour les tests).
var senate_buttons := {}
## Boutons Adopter/Abroger des lois (id de loi : bouton) et des actions électorales (id : bouton).
var law_buttons := {}
var action_buttons := {}
var _senate_sig := ""
## Boutons de l'écran Foi (« state:foi », « precept:foi:précepte », « choose:foi »), pour les tests.
var faith_buttons := {}
var _faith_sig := ""
## Boutons de l'écran Amphictyonie (« found », « join », « vote:1 », « propose:fam:dir »…), pour les tests.
var amph_buttons := {}
var _amph_sig := ""
## Cible choisie dans l'Ordre intérieur pour les contrats et les primes pirates.
var order_victim := -1
var _hero_sig := ""
## Écran Chroniques : boutons « event:id » et « curio:pid » (pour les tests).
var chronicle_buttons := {}
var _chron_sig := ""
var _armies_sig := ""
## Écran Rayonnement : boutons « osmose:1 », « savoir:tech », « ambassade:empire », « troupe:empire » (tests).
var culture_buttons := {}
var _culture_sig := ""
var genome_buttons := {}
var _genome_sig := ""
## Écran Songe : pouvoir choisi, dont on montre les cibles.
var psionics_power := ""
## Écran Génome : espèce affichée, traits cochés par espèce ({add, rem}), traits impossibles montrés ou non.
var genome_species := ""
var genome_picks := {}
var genome_show_all := false
## Écran Songe : boutons « path », « power:pouvoir:cible »… (tests).
var psionics_buttons := {}
var _psionics_sig := ""
## Écran Transcendance (onglet de l'écran Victoire) : boutons « path:voie », « oeuvre », « tab:… » (tests).
var transcendence_buttons := {}
var _transcendence_sig := ""
## Écran Contact (onglet de l'écran Victoire) : boutons « share:n », « transmit », « rate:n »… (tests).
var contact_buttons := {}
var _contact_sig := ""
## Écran Merveilles : boutons « start:merveille », « rush:merveille »… (tests).
var wonder_buttons := {}
var _wonders_sig := ""
## Écran Mégastructures (onglet de l'écran Merveilles) : boutons « plan:type », « advance:id », « tab:… » (tests).
var mega_buttons := {}
var _megas_sig := ""
var forge_buttons := {}
var _forge_sig := ""
## Écran L'Échelle (onglet de l'écran Victoires) : boutons « perk:id », « sober », « veil », « relight:s », « tab:… » (tests).
var kardashev_buttons := {}
var _kardashev_sig := ""
var throne_buttons := {}
var _throne_sig := ""
## Onglet ouvert de l'écran Chroniques : "quests", "events" ou "relics".
var chron_tab := "quests"
## Filtres de l'onglet Annonces des Chroniques : famille ("" : toutes), gravité minimale (0 à 3), me concerne.
var announce_filter := {"family": "", "gravity": 0, "mine": false}
var _shipyard_sig := ""


func _ready() -> void:
	layer = 2  # sous l'interface (panneau d'empire, cadran), au-dessus de la carte et de la vue système
	visible = false
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP  # la carte derrière ne réagit plus
	add_child(_root)
	var bg := ColorRect.new()
	bg.color = Color(0.008, 0.014, 0.028, 0.9)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bg)
	# Léger halo bleuté au centre, pour que le fond ne soit pas un aplat mort.
	var glow := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.16, 0.3, 0.42, 0.28))
	grad.set_color(1, Color(0.16, 0.3, 0.42, 0.0))
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.fill = GradientTexture2D.FILL_RADIAL
	gtex.fill_from = Vector2(0.5, 0.45)
	gtex.fill_to = Vector2(1.05, 0.45)
	glow.texture = gtex
	glow.stretch_mode = TextureRect.STRETCH_SCALE
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(glow)

	_tab = Button.new()
	_tab.theme_type_variation = &"TabButton"
	_tab.toggle_mode = true
	_tab.button_pressed = true
	_tab.focus_mode = Control.FOCUS_NONE
	_tab.tooltip_text = "Fermer  (Échap)"
	_tab.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_tab.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_tab.pressed.connect(func() -> void: close_requested.emit())
	_root.add_child(_tab)

	_domain_row = HBoxContainer.new()
	_domain_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_domain_row.add_theme_constant_override("separation", 22)
	_domain_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_domain_row.offset_left = CONTENT_LEFT
	_domain_row.offset_right = -CONTENT_RIGHT
	_domain_row.offset_top = 38.0
	_domain_row.offset_bottom = 66.0
	_root.add_child(_domain_row)

	_side = PanelContainer.new()
	_side.theme_type_variation = &"SidePanel"
	_side.position = Vector2(MARGIN, SIDE_TOP)
	_side.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
	_root.add_child(_side)
	_side_scroll = ScrollContainer.new()
	_side_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_side.add_child(_side_scroll)
	_side_box = VBoxContainer.new()
	_side_box.add_theme_constant_override("separation", 10)
	_side_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side_scroll.add_child(_side_box)

	_content = MarginContainer.new()
	_content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_content.offset_left = CONTENT_LEFT
	_content.offset_top = 78.0
	_content.offset_right = -CONTENT_RIGHT
	_content.offset_bottom = -24.0
	_root.add_child(_content)


func open(screen_id: String, state: GameState, player: int) -> void:
	_state = state
	_player = player
	var was_open := visible
	visible = true
	show_screen(screen_id)
	if not was_open:
		Son.cue("ui_ouvrir")
		_root.modulate.a = 0.0
		_root.create_tween().tween_property(_root, "modulate:a", 1.0, 0.18)


func close() -> void:
	if visible:
		Son.cue("ui_fermer")
	visible = false
	current = ""
	if _tech_panel and is_instance_valid(_tech_panel):
		_tech_panel.queue_free()
		_tech_panel = null


## La colonne de gauche prend la hauteur de son contenu, sans dépasser le bas de l'écran.
func _fit_side() -> void:
	if _side_scroll == null or not is_instance_valid(_side_scroll):
		return
	var avail := _root.get_viewport_rect().size.y - SIDE_TOP - 24.0
	# Recherche : la fiche de la technologie choisie occupe le bas de la colonne. La colonne s'arrête
	# au-dessus (et défile) au lieu de passer dessous, où ses lignes se lisaient à travers la fiche.
	if _tech_panel != null and is_instance_valid(_tech_panel) and _tech_panel.visible:
		var pad := _side.get_theme_stylebox("panel").get_minimum_size().y if _side.has_theme_stylebox("panel") else 0.0
		avail = minf(avail, _tech_panel.position.y - SIDE_TOP - 10.0 - pad)
	var need := _side_box.get_combined_minimum_size().y
	_side_scroll.custom_minimum_size.y = minf(need, maxf(120.0, avail))
	_side.reset_size()


func is_open() -> bool:
	return visible and current != ""


func show_screen(screen_id: String) -> void:
	current = screen_id
	if _tech_panel and is_instance_valid(_tech_panel):
		_tech_panel.queue_free()
		_tech_panel = null
	for c in _content.get_children() + _side_box.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	_res_rows.clear()
	_totals.clear()
	_col_rows.clear()
	_col_counts.clear()
	_filter_tabs.clear()
	_col_sig = ""
	_sys_sig = ""
	_fill_domain_row()
	match screen_id:
		"economy":
			_build_economy()
		"colonies":
			_build_colonies()
		"research":
			_build_research()
		"diplomacy":
			_build_diplomacy()
		"shipyard":
			_build_shipyard()
		"victory":
			_build_victory()
		"intel":
			IntelScreen.build(self)
		"peoples":
			PeoplesScreen.build(self)
		"fleets":
			FleetsScreen.build(self)
		"battles":
			BattlesScreen.build(self)
		"heroes":
			HeroScreen.build(self)
		"order":
			OrderScreen.build(self)
		"trade":
			TradeScreen.build(self)
		"senate":
			SenateScreen.build(self)
		"faith":
			FaithScreen.build(self)
		"amphictyony":
			AmphictyonyScreen.build(self)
		"chronicles":
			ChronicleScreen.build(self)
		"armies":
			ArmiesScreen.build(self)
		"culture":
			culture_buttons.clear()
			CultureScreen.build(self)
		"genome":
			genome_buttons.clear()
			GenomeScreen.build(self)
		"psionics":
			psionics_buttons.clear()
			PsionicsScreen.build(self)
		"transcendence":
			transcendence_buttons.clear()
			TranscendenceScreen.build(self)
		"contact":
			contact_buttons.clear()
			ContactScreen.build(self)
		"wonders":
			wonder_buttons.clear()
			mega_buttons.clear()
			WondersUi.build(self)
		"megas":
			mega_buttons.clear()
			MegasUi.build(self)
		"forge":
			mega_buttons.clear()
			forge_buttons.clear()
			ForgeUi.build(self)
		"kardashev":
			kardashev_buttons.clear()
			KardashevScreen.build(self)
		"throne":
			throne_buttons.clear()
			ThroneScreen.build(self)
	refresh()
	screen_changed.emit(screen_id)


## Ouvre une adresse de domaine (« trade:market », « order:admin », « economy » ; voir UiDomains).
func show_address(addr: String) -> void:
	UiDomains.apply_sub(self, addr)
	show_screen(UiDomains.screen_of(addr))


## Onglet du haut (nom du domaine) et rangée de ses onglets. Un écran hors domaine garde son nom.
func _fill_domain_row() -> void:
	for c in _domain_row.get_children():
		_domain_row.remove_child(c)
		c.queue_free()
	domain_buttons.clear()
	var addr := UiDomains.address(self)
	var at := UiDomains.locate(addr)
	var d := int(at[0])
	if d < 0:
		_tab.text = ("%s     ×" % EmpireBar.screen_info(current).get("label", current)).to_upper()
		return
	domain_last[d] = addr
	var dom: Dictionary = UiDomains.DOMAINS[d]
	_tab.text = ("%s     ×" % dom["label"]).to_upper()
	var tabs: Array = dom["tabs"]
	for t in tabs.size():
		var target := UiDomains.first_offered(_state, _player, d, t)
		if target == "":
			continue
		var tb := Button.new()
		tb.theme_type_variation = &"TabButton"
		tb.add_theme_font_size_override("font_size", 13)
		tb.toggle_mode = true
		tb.focus_mode = Control.FOCUS_NONE
		tb.text = String(tabs[t][0]).to_upper()
		tb.set_pressed_no_signal(t == int(at[1]))
		tb.pressed.connect(func() -> void: show_address(target))
		_domain_row.add_child(tb)
		domain_buttons[String(tabs[t][0])] = tb


## Met à jour les chiffres (à chaque tick et après chaque ordre).
func refresh() -> void:
	if not is_open() or _state == null:
		return
	_fit_side.call_deferred()
	match current:
		"economy":
			_refresh_economy()
		"colonies":
			_refresh_colonies()
		"diplomacy":
			if _diplomacy_sig() != _diplo_sig:
				show_screen("diplomacy")
		"victory":
			if _victory_sig() != _vict_sig:
				show_screen("victory")
		"intel":
			if IntelScreen.signature(self) != _intel_sig:
				show_screen("intel")
		"peoples":
			if PeoplesScreen.signature(self) != _peoples_sig:
				show_screen("peoples")
		"fleets":
			if FleetsScreen.signature(self) != _fleets_sig:
				show_screen("fleets")
		"battles":
			if BattlesScreen.signature(self) != _battles_sig:
				show_screen("battles")
		"heroes":
			if HeroScreen.signature(self) != _hero_sig:
				show_screen("heroes")
		"order":
			if OrderScreen.signature(self) != _order_sig:
				show_screen("order")
		"trade":
			if TradeScreen.signature(self) != _trade_sig:
				show_screen("trade")
		"senate":
			if SenateScreen.signature(self) != _senate_sig:
				show_screen("senate")
		"faith":
			if FaithScreen.signature(self) != _faith_sig:
				show_screen("faith")
		"amphictyony":
			if AmphictyonyScreen.signature(self) != _amph_sig:
				show_screen("amphictyony")
		"chronicles":
			if ChronicleScreen.signature(self) != _chron_sig:
				show_screen("chronicles")
		"armies":
			if ArmiesScreen.signature(self) != _armies_sig:
				show_screen("armies")
		"culture":
			if CultureScreen.signature(self) != _culture_sig:
				show_screen("culture")
		"genome":
			if GenomeScreen.signature(self) != _genome_sig:
				show_screen("genome")
		"psionics":
			if PsionicsScreen.signature(self) != _psionics_sig:
				show_screen("psionics")
		"transcendence":
			if TranscendenceScreen.signature(self) != _transcendence_sig:
				show_screen("transcendence")
		"contact":
			if ContactScreen.signature(self) != _contact_sig:
				show_screen("contact")
		"wonders":
			if WondersUi.signature(self) != _wonders_sig:
				show_screen("wonders")
		"megas":
			if MegasUi.signature(self) != _megas_sig:
				show_screen("megas")
		"forge":
			if ForgeUi.signature(self) != _forge_sig:
				show_screen("forge")
		"kardashev":
			if KardashevScreen.signature(self) != _kardashev_sig:
				show_screen("kardashev")
		"throne":
			if ThroneScreen.signature(self) != _throne_sig:
				show_screen("throne")
		"research":
			if _research_signature() != _research_sig:
				_fill_research_side()
				research_tree.refresh()
		"shipyard":
			# Une technologie découverte ouvre des coques et des modules : on rafraîchit les listes.
			if _shipyard_signature() != _shipyard_sig and shipyard != null:
				_shipyard_sig = _shipyard_signature()
				shipyard._refresh_all()


## Lignes de la liste des colonies (boutons), pour les tests.
func colony_buttons() -> Array[Button]:
	var out: Array[Button] = []
	for r in _col_rows:
		out.append(r["button"])
	return out


## Texte d'une ligne de ressource de l'économie (pour les tests) : "Matériaux|200|+20|-3|+17|…".
func economy_row_text(resource_id: String) -> String:
	if not _res_rows.has(resource_id):
		return ""
	var parts := PackedStringArray()
	for l: Label in _res_rows[resource_id]:
		parts.append(l.text)
	return "|".join(parts)


## Choisit une colonie dans l'écran Colonies (sa fiche s'affiche en bas).
func select_colony(pid: int) -> void:
	selected_planet = pid
	refresh()


## Ouvre la vue système de la colonie choisie.
func open_selected_colony() -> void:
	if selected_planet >= 0:
		planet_requested.emit(selected_planet)


## Trie le tableau des colonies par une colonne : premier clic croissant (décroissant pour les nombres),
## second clic inversé, troisième clic retour à l'ordre de l'empire.
func sort_colonies(key: String) -> void:
	var numeric := key == "pop" or key == "net"
	if colony_sort != key:
		colony_sort = key
		colony_sort_desc = numeric
	elif colony_sort_desc == numeric:
		colony_sort_desc = not numeric
	else:
		colony_sort = ""
	_col_sig = ""
	refresh()


## Valeur de tri d'une colonie pour une colonne. Chantier : les chantiers libres d'abord, puis les
## plus proches de la fin, les avant-postes en dernier.
static func colony_sort_key(c: Dictionary, key: String, free: Array) -> Variant:
	match key:
		"name":
			return String(c["name"]).to_lower()
		"type":
			return String(c["type_label"]).to_lower()
		"pop":
			return int(c["population"]) if c["established"] else -1
		"build":
			if free.has(int(c["planet_id"])):
				return -1
			return int(c["construction_days"]) if String(c["construction"]) != "" else 100000
		"net":
			var n := 0
			for k: String in (c["net"] as Dictionary):
				n += int(c["net"][k])
			return n
	return 0


func _refresh_colony_heads() -> void:
	for i in _col_heads.size():
		var key := String(COLONY_COLUMNS[i][0])
		var text := String(COLONY_COLUMNS[i][1])
		if key == "build" and colony_filter == "biosphere":
			text = "Biosphère  →  équilibre"
		if key == colony_sort and colony_filter != "biosphere":
			text += "  ▾" if colony_sort_desc else "  ▴"
		_col_heads[i].text = text.to_upper()
		_col_heads[i].add_theme_color_override("font_color", UiTheme.ACCENT if key == colony_sort and colony_filter != "biosphere" else UiTheme.TEXT_DIM)


func set_colony_filter(f: String) -> void:
	colony_filter = f
	for id in _filter_tabs:
		(_filter_tabs[id] as Button).set_pressed_no_signal(id == f)
	_col_sig = ""
	refresh()


# --- Pièces communes ------------------------------------------------------------------------

func _side_header(art_id: String, caption: String, tint: Color, motif: String) -> Widgets.ArtSlot:
	var art := Widgets.ArtSlot.new(art_id, Vector2(SIDE_WIDTH - 20.0, 150), tint, motif)
	art.set_caption(caption, 30)
	_side_box.add_child(art)
	return art


## Peuples mêlés (voir Peoples) : les espèces de l'empire, leur nombre, si elles peuvent fonder une
## colonie, et leur bonus de collection.
func _build_peoples_side() -> void:
	if not _state.peoples_on:
		return
	var cnt := Peoples.empire_counts(_state, _player)
	_side_box.add_child(HSeparator.new())
	_side_box.add_child(UiTheme.section("Peuples de l'empire"))
	_side_box.add_child(UiTheme.paragraph("%d espèce%s %s dans l'empire. Effectifs, statuts et accueil des réfugiés se règlent dans l'onglet Peuples." % [
			cnt.size(), "s" if cnt.size() > 1 else "", "vivent" if cnt.size() > 1 else "vit"], SIDE_WIDTH - 24.0, 13))
	var b := Button.new()
	b.theme_type_variation = &"BarButton"
	b.focus_mode = Control.FOCUS_NONE
	b.text = "VOIR LES PEUPLES"
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.pressed.connect(func() -> void: show_address("peoples"))
	_side_box.add_child(b)
	peoples_buttons["open"] = b


## Mouvements (lot 3) : politique d'accueil, revendication d'une diaspora, talents de peuples mêlés.
func _build_moves_side() -> void:
	_side_box.add_child(HSeparator.new())
	_side_box.add_child(UiTheme.section("Accueil et diasporas"))
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = "Réfugiés"
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.tooltip_text = "Politique d'accueil : chaque réfugié rapporte de l'influence et de l'opinion chez son peuple, coûte de la nourriture, et reste reconnaissant (stabilité) dix ans."
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	row.add_child(l)
	var ob := OptionButton.new()
	ob.custom_minimum_size = Vector2(170, 0)
	var cur := Movements.policy(_state, _player)
	for i in Movements.POLICIES.size():
		ob.add_item(String(Movements.POLICY_LABELS[Movements.POLICIES[i]]))
	ob.selected = Movements.POLICIES.find(cur)
	ob.item_selected.connect(func(i: int) -> void:
		if Movements.POLICIES[i] != cur:
			command_requested.emit(SimCommands.refugee_policy(_player, Movements.POLICIES[i])))
	row.add_child(ob)
	_side_box.add_child(row)
	var cl := Movements.claim(_state, _player)
	if not cl.is_empty():
		var fid := String(cl["fid"])
		_side_box.add_child(UiTheme.paragraph("La diaspora %s (%d habitants) réclame une terre avant le %s. Accepter : leur empire renaît, en paix avec vous, et ils vous en sont reconnaissants. Refuser : ils s'en souviendront." % [
				Peoples.label(fid), int(Peoples.foreign_pop(_state, _player).get(fid, 0)), GameCalendar.date_string(int(cl["end"]))], SIDE_WIDTH - 24.0, 12))
		var acts := HFlowContainer.new()
		acts.add_theme_constant_override("h_separation", 6)
		for choice in [["systeme", "CÉDER UN SYSTÈME"], ["neutre", "UN MONDE LIBRE"], ["refus", "REFUSER"]]:
			var b := Button.new()
			b.text = String(choice[1])
			b.focus_mode = Control.FOCUS_NONE
			var why := Movements.check_claim(_state, _player, String(choice[0]))
			b.disabled = why != ""
			if choice[0] == "systeme":
				var sid := Movements.claim_system(_state, _player, fid)
				b.tooltip_text = why if why != "" else "Céder %s, où vivent le plus de %s." % [_state.galaxy.systems[sid].system_name, Peoples.label(fid)]
			elif choice[0] == "neutre":
				var pid := Movements.claim_planet(_state, _player, fid)
				b.tooltip_text = why if why != "" else "Les laisser s'installer sur %s (%d colons partent)." % [_state.galaxy.get_planet(pid).display_name(_state.galaxy), int(Movements.data().get("claim_settlers", 5))]
			else:
				b.tooltip_text = "-5 de stabilité là où ils vivent pendant deux ans, et leur renaissance se rapproche."
			var ch := String(choice[0])
			b.pressed.connect(func() -> void: command_requested.emit(SimCommands.diaspora_answer(_player, ch)))
			acts.add_child(b)
		_side_box.add_child(acts)
	var tl := Movements.talent_labels(_state, _player)
	for t: Array in tl:
		var p := UiTheme.paragraph("%s. %s" % [t[0], t[1]], SIDE_WIDTH - 24.0, 12)
		p.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		_side_box.add_child(p)


## Au-delà de ce nombre de caractères, la valeur d'une ligne de la colonne de gauche est coupée.
const KEY_VALUE_MAX := 20


func _key_value(grid: GridContainer, key: String, value := "") -> Label:
	var k := Label.new()
	k.text = key
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(k)
	var v := Label.new()
	v.theme_type_variation = &"Numbers"
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.text = value
	# Une valeur longue ne doit pas élargir la colonne de gauche par-dessus le contenu : elle est coupée,
	# le texte entier reste dans l'infobulle.
	if value.length() > KEY_VALUE_MAX:
		v.clip_text = true
		v.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.custom_minimum_size = Vector2(SIDE_WIDTH * 0.52, 0)
		v.tooltip_text = value
		v.mouse_filter = Control.MOUSE_FILTER_STOP
	grid.add_child(v)
	return v


func _grid(columns := 2) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 20)
	g.add_theme_constant_override("v_separation", 4)
	return g


## Icône et nombre pour chaque ressource non nulle d'un bilan.
func _fill_net(box: HBoxContainer, net: Dictionary, font_size := 16) -> void:
	for ch in box.get_children():
		box.remove_child(ch)
		ch.queue_free()
	for r in GameData.resource_ids():
		var v := int(net.get(r, 0))
		if v == 0:
			continue
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 3)
		pair.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pair.add_child(ResourceIcon.make(r, font_size - 2))
		var l := Label.new()
		l.text = "%+d" % v
		l.theme_type_variation = &"Numbers"
		l.add_theme_font_size_override("font_size", font_size)
		l.add_theme_color_override("font_color", UiTheme.delta_color(v))
		pair.add_child(l)
		box.add_child(pair)


func _row_button(height: float) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.toggle_mode = true
	b.custom_minimum_size = Vector2(0, height)
	b.add_theme_stylebox_override("normal", UiTheme.box(Color(1, 1, 1, 0.035), Color(0, 0, 0, 0), 8, 0))
	b.add_theme_stylebox_override("hover", UiTheme.box(Color(1, 1, 1, 0.08), Color(0, 0, 0, 0), 8, 0))
	var on := UiTheme.box(Color(UiTheme.ACCENT, 0.16), UiTheme.ACCENT, 8, 0)
	on.border_width_left = 3
	b.add_theme_stylebox_override("pressed", on)
	b.add_theme_stylebox_override("hover_pressed", on)
	return b


## Rangée de cases verrouillées (systèmes à venir).
func _locked_row(count: int, slot: Vector2, tip: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	for i in count:
		var l := Widgets.ArtSlot.new("", slot, Color(0.5, 0.6, 0.7), "lock")
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		l.tooltip_text = tip
		row.add_child(l)
	return row


# --- Économie -------------------------------------------------------------------------------

func _build_economy() -> void:
	var me := _state.get_empire(_player) if _state else null
	var col := me.color() if me else UiTheme.ACCENT
	var fid := me.faction_id if me else ""
	_faction_art = _side_header(GameData.portrait_art(fid), me.short_name() if me else "", col, "faction")
	_side_box.add_child(UiTheme.section("Effets"))
	_trait = UiTheme.paragraph("", SIDE_WIDTH - 24.0, 14)
	_side_box.add_child(_trait)
	_side_box.add_child(HSeparator.new())
	_side_box.add_child(UiTheme.section("Empire"))
	var tgrid := _grid()
	_side_box.add_child(tgrid)
	for key in ["population", "colonies", "outposts", "systems", "founding"]:
		var label: String = {"population": "Population", "colonies": "Colonies", "outposts": "Avant-postes",
				"systems": "Systèmes", "founding": "Fondations en cours"}[key]
		_totals[key] = _key_value(tgrid, label)

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 22)
	_content.add_child(rows)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 22)
	rows.add_child(top)
	var table := Widgets.Block.new("Bilan des ressources")
	table.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(table)
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 10)
	table.body.add_child(grid)
	for h in ["", "Stock", "Production", "Entretien", "Bilan / mois", "Tendance", "24 mois"]:
		var l := UiTheme.section(h)
		if h != "":
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		grid.add_child(l)
	for r in GameData.resource_ids():
		var name_box := HBoxContainer.new()
		name_box.add_theme_constant_override("separation", 8)
		name_box.custom_minimum_size = Vector2(150, 0)
		name_box.add_child(ResourceIcon.make(r, 20))
		var name_l := Label.new()
		name_l.text = GameData.resource_label(r)
		name_l.add_theme_font_size_override("font_size", 16)
		name_box.add_child(name_l)
		grid.add_child(name_box)
		var labels: Array[Label] = [name_l]
		for i in 5:
			var l := Label.new()
			l.theme_type_variation = &"Numbers"
			l.add_theme_font_size_override("font_size", 20 if i < 4 else 14)
			l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			l.custom_minimum_size = Vector2(68 if i < 4 else 124, 0)
			grid.add_child(l)
			labels.append(l)
		_res_rows[r] = labels
		var curve := Widgets.Sparkline.new(100, 26)
		curve.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		grid.add_child(curve)
		res_curves[r] = curve

	var share := Widgets.Block.new("Répartition de la production")
	share.custom_minimum_size = Vector2(380, 0)
	top.add_child(share)
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 16)
	share.body.add_child(srow)
	_donut = Widgets.Donut.new(176)
	_donut.center_title = "PAR MOIS"
	srow.add_child(_donut)
	_donut_legend = VBoxContainer.new()
	_donut_legend.alignment = BoxContainer.ALIGNMENT_CENTER
	_donut_legend.add_theme_constant_override("separation", 4)
	srow.add_child(_donut_legend)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 22)
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(bottom)
	var systems := Widgets.Block.new("Production par système")
	systems.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(systems)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	systems.body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	systems.body.add_child(scroll)
	_sys_list = VBoxContainer.new()
	_sys_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sys_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_sys_list)
	var alerts := Widgets.Block.new("Alertes")
	alerts.custom_minimum_size = Vector2(380, 0)
	bottom.add_child(alerts)
	_alerts = VBoxContainer.new()
	_alerts.add_theme_constant_override("separation", 12)
	alerts.body.add_child(_alerts)
	_alerts_sig = "-"


func _refresh_economy() -> void:
	var me := _state.get_empire(_player)
	if me == null:
		return
	var parts: Array = []
	var gross_total := 0
	for c in _donut_legend.get_children():
		_donut_legend.remove_child(c)
		c.queue_free()
	for r: Dictionary in EmpireReport.resources(_state, _player):
		var labels: Array[Label] = []
		labels.assign(_res_rows[r["id"]])
		labels[1].text = str(r["stock"])
		labels[2].text = "+%d" % r["gross"] if int(r["gross"]) > 0 else "0"
		labels[2].add_theme_color_override("font_color", UiTheme.GOOD if int(r["gross"]) > 0 else UiTheme.TEXT_DIM)
		labels[3].text = "-%d" % r["upkeep"] if int(r["upkeep"]) > 0 else "0"
		labels[3].add_theme_color_override("font_color", UiTheme.BAD if int(r["upkeep"]) > 0 else UiTheme.TEXT_DIM)
		labels[4].text = "%+d" % r["net"]
		labels[4].add_theme_color_override("font_color", UiTheme.delta_color(int(r["net"])))
		var trend := ""
		var col := UiTheme.TEXT_DIM
		if int(r["months_left"]) >= 0:
			trend = "épuisé dans %d mois" % r["months_left"] if int(r["stock"]) > 0 else "stock vide"
			col = UiTheme.WARN if int(r["months_left"]) > 2 else UiTheme.BAD
		elif int(r["net"]) > 0:
			trend = "en hausse"
			col = UiTheme.GOOD
		else:
			trend = "stable"
		if int(r["bonus_pct"]) != 0:
			labels[2].tooltip_text = "Bonus de faction : %+d %%" % r["bonus_pct"]
			labels[2].mouse_filter = Control.MOUSE_FILTER_STOP
		labels[5].text = trend
		labels[5].add_theme_color_override("font_color", col)
		(res_curves[r["id"]] as Widgets.Sparkline).set_values(me.ledger.get(r["id"], []), ResourceIcon.color_of(r["id"]))
		# Anneau : part de chaque ressource dans la production brute.
		var rc := ResourceIcon.color_of(r["id"])
		parts.append({"value": float(r["gross"]), "color": rc})
		gross_total += int(r["gross"])
		var leg := HBoxContainer.new()
		leg.add_theme_constant_override("separation", 6)
		var v := Label.new()
		v.theme_type_variation = &"Numbers"
		v.custom_minimum_size = Vector2(44, 0)
		v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		v.text = str(r["gross"])
		leg.add_child(v)
		leg.add_child(ResourceIcon.make(r["id"], 14))
		var n := Label.new()
		n.text = String(r["label"])
		n.add_theme_color_override("font_color", rc.lightened(0.2))
		leg.add_child(n)
		_donut_legend.add_child(leg)
	_donut.set_parts(parts, str(gross_total))

	_refresh_alerts()

	_faction_art.set_caption(me.short_name(), 30)
	_trait.text = EmpireBar.trait_summary(me.faction())
	var t := EmpireReport.totals(_state, _player)
	(_totals["population"] as Label).text = str(t["population"])
	(_totals["colonies"] as Label).text = str(t["colonies"])
	(_totals["outposts"] as Label).text = str(t["outposts"])
	(_totals["systems"] as Label).text = str(t["systems"])
	(_totals["founding"] as Label).text = "%d / %d" % [t["founding"], t["max_projects"]]
	_refresh_system_rows()


## Alertes du bilan : [{text, planet, bad}]. planet = colonie en cause (-1 si aucune), où mène le lien.
static func economy_alerts(state: GameState, player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var me := state.get_empire(player)
	if me == null:
		return out
	var cols := EmpireReport.colonies(state, player)
	if me.starving:
		var big := -1
		var pop := -1
		for c: Dictionary in cols:
			if bool(c["established"]) and int(c["population"]) > pop:
				pop = int(c["population"])
				big = int(c["planet_id"])
		out.append({"bad": true, "planet": big, "text": "Famine : les réserves de nourriture sont vides et la population décline. Construisez des fermes ou colonisez un monde fertile."})
	if me.blackout:
		out.append({"bad": true, "planet": _worst_colony(cols, "energy"), "text": "Pénurie d'énergie : tous les chantiers sont à l'arrêt tant que le stock reste vide."})
	for r: Dictionary in EmpireReport.resources(state, player):
		if int(r["months_left"]) >= 0 and int(r["months_left"]) <= 6 and int(r["stock"]) > 0:
			out.append({"bad": false, "planet": _worst_colony(cols, String(r["id"])),
					"text": "%s : épuisé dans %d mois à ce rythme." % [r["label"], r["months_left"]]})
	return out


## Colonie au plus mauvais bilan pour cette ressource (-1 si aucune n'est en déficit).
static func _worst_colony(cols: Array[Dictionary], res: String) -> int:
	var worst := -1
	var low := 0
	for c: Dictionary in cols:
		var n := int((c["net"] as Dictionary).get(res, 0))
		if n < low:
			low = n
			worst = int(c["planet_id"])
	return worst


func _refresh_alerts() -> void:
	var list := economy_alerts(_state, _player)
	var sig := str(list)
	if sig == _alerts_sig:
		return
	_alerts_sig = sig
	for c in _alerts.get_children():
		_alerts.remove_child(c)
		c.queue_free()
	alert_links.clear()
	if list.is_empty():
		_alerts.add_child(UiTheme.paragraph("Aucune crise en vue. Les comptables de l'empire s'ennuient, ce qui est bon signe.", 340, 15))
		return
	for a: Dictionary in list:
		var text := UiTheme.paragraph(String(a["text"]), 340, 15)
		text.add_theme_color_override("font_color", UiTheme.BAD if bool(a["bad"]) else UiTheme.WARN)
		_alerts.add_child(text)
		var pid := int(a["planet"])
		if pid < 0 or not _state.colonies.has(pid):
			continue
		var b := Button.new()
		b.theme_type_variation = &"BarButton"
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		b.text = "VOIR %s" % _state.galaxy.get_planet(pid).display_name(_state.galaxy).to_upper()
		b.tooltip_text = "Ouvrir la colonie en cause"
		b.pressed.connect(func() -> void: planet_requested.emit(pid))
		_alerts.add_child(b)
		alert_links.append(b)


## Une ligne par système de l'empire : nom, revendications, bilan. Un clic ouvre sa vue système.
func _refresh_system_rows() -> void:
	var systems := EmpireReport.owned_systems(_state, _player)
	var sig := str(systems)
	if sig != _sys_sig:
		_sys_sig = sig
		for c in _sys_list.get_children():
			_sys_list.remove_child(c)
			c.queue_free()
		for sid in systems:
			var b := _row_button(40)
			b.toggle_mode = false
			b.tooltip_text = "Ouvrir la vue système"
			var first := _first_claim(sid)
			b.pressed.connect(func() -> void: planet_requested.emit(first))
			var row := HBoxContainer.new()
			row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			row.offset_left = 10
			row.add_theme_constant_override("separation", 10)
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.add_child(row)
			var name_l := UiTheme.title(_state.galaxy.systems[sid].system_name, 19)
			name_l.custom_minimum_size = Vector2(200, 0)
			name_l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(name_l)
			var claims := UiTheme.dim("", 13)
			claims.custom_minimum_size = Vector2(150, 0)
			claims.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(claims)
			var net := HBoxContainer.new()
			net.add_theme_constant_override("separation", 12)
			net.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			net.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(net)
			b.set_meta("sid", sid)
			b.set_meta("claims", claims)
			b.set_meta("net", net)
			_sys_list.add_child(b)
	for b: Button in _sys_list.get_children():
		var sid: int = b.get_meta("sid")
		var n := 0
		for pid in _state.galaxy.systems[sid].planet_ids:
			var c: Colony = _state.colonies.get(pid)
			if c and c.owner == _player:
				n += 1
		(b.get_meta("claims") as Label).text = "%d revendication%s" % [n, "s" if n > 1 else ""]
		_fill_net(b.get_meta("net"), EmpireReport.system_net(_state, _player, sid), 15)


func _first_claim(sid: int) -> int:
	for pid in _state.galaxy.systems[sid].planet_ids:
		var c: Colony = _state.colonies.get(pid)
		if c and c.owner == _player:
			return pid
	return -1


# --- Colonies -------------------------------------------------------------------------------

func _build_colonies() -> void:
	_side_header("screen_colonies", "Colonies", UiTheme.ACCENT, "galaxy")
	var ring := HBoxContainer.new()
	ring.add_theme_constant_override("separation", 14)
	_side_box.add_child(ring)
	_col_donut = Widgets.Donut.new(130)
	_col_donut.center_title = "TOTAL"
	ring.add_child(_col_donut)
	var counts := _grid()
	counts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	counts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ring.add_child(counts)
	for key in ["colonies", "outposts", "founding"]:
		var label: String = {"colonies": "Colonies", "outposts": "Avant-postes", "founding": "Fondations"}[key]
		_col_counts[key] = _key_value(counts, label)
	_side_box.add_child(HSeparator.new())
	var g := _grid()
	_side_box.add_child(g)
	_col_counts["population"] = _key_value(g, "Population")
	_col_counts["systems"] = _key_value(g, "Systèmes")
	_col_counts["max_projects"] = _key_value(g, "Fondations simultanées")
	_build_peoples_side()
	_build_eco_side()

	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 22)
	_content.add_child(rows)
	var list_block := Widgets.Block.new("Liste des colonies")
	list_block.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_block.body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(list_block)
	var filters := HBoxContainer.new()
	filters.alignment = BoxContainer.ALIGNMENT_CENTER
	filters.add_theme_constant_override("separation", 30)
	list_block.body.add_child(filters)
	for f in colony_filters():
		var b := Button.new()
		b.theme_type_variation = &"TabButton"
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		b.text = String(f[1]).to_upper()
		var fid: String = f[0]
		b.pressed.connect(func() -> void: set_colony_filter(fid))
		b.set_pressed_no_signal(fid == colony_filter)
		filters.add_child(b)
		_filter_tabs[fid] = b
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 0)
	list_block.body.add_child(header)
	var indent := Control.new()
	indent.custom_minimum_size = Vector2(12, 0)  # même retrait que le texte des lignes
	header.add_child(indent)
	# En-têtes cliquables : un clic trie, un second inverse, un troisième rend l'ordre de l'empire.
	_col_heads.clear()
	for i in COLONY_COLUMNS.size():
		var l := Button.new()
		l.flat = true
		l.theme_type_variation = &"SortHead"
		l.alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.focus_mode = Control.FOCUS_NONE
		l.add_theme_font_override("font", UiTheme.section("").get_theme_font("font"))
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		l.custom_minimum_size = Vector2(COLUMN_WIDTHS[i], 0)
		l.tooltip_text = "Trier par cette colonne"
		var key := String(COLONY_COLUMNS[i][0])
		l.pressed.connect(func() -> void: sort_colonies(key))
		header.add_child(l)
		_col_heads.append(l)
	_refresh_colony_heads()
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_block.body.add_child(scroll)
	_col_list = VBoxContainer.new()
	_col_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_col_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_col_list)
	_col_empty = UiTheme.paragraph("Rien dans cette catégorie. L'empire tient tout entier dans un carnet d'adresses très mince.", 600)
	_col_empty.visible = false
	list_block.body.add_child(_col_empty)

	var pick := Widgets.Block.new("Colonie choisie", 0)
	pick.custom_minimum_size = Vector2(0, 236)
	rows.add_child(pick)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 0)
	pick.body.add_child(prow)
	_pick_art = Widgets.ArtSlot.new("", Vector2(380, 220), UiTheme.ACCENT, "planet")
	prow.add_child(_pick_art)
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 0)
	prow.add_child(info)
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiTheme.box(Color(1, 1, 1, 0.05), Color(0, 0, 0, 0), 10, 0))
	info.add_child(bar)
	_pick_title = UiTheme.title("", 26)
	_pick_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(_pick_title)
	var details := MarginContainer.new()
	details.add_theme_constant_override("margin_left", 20)
	details.add_theme_constant_override("margin_top", 10)
	details.add_theme_constant_override("margin_right", 20)
	details.size_flags_vertical = Control.SIZE_EXPAND_FILL
	info.add_child(details)
	var dbox := VBoxContainer.new()
	dbox.add_theme_constant_override("separation", 8)
	details.add_child(dbox)
	_pick_lines = UiTheme.paragraph("", 400, 15)
	dbox.add_child(_pick_lines)
	_pick_net = HBoxContainer.new()
	_pick_net.add_theme_constant_override("separation", 14)
	dbox.add_child(_pick_net)
	var foot := HBoxContainer.new()
	foot.alignment = BoxContainer.ALIGNMENT_END
	info.add_child(foot)
	_pick_open = Widgets.RoundButton.new("next", "Ouvrir la vue système", 16)
	_pick_open.pressed.connect(open_selected_colony)
	foot.add_child(_pick_open)
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(14, 0)
	foot.add_child(pad)


func _refresh_colonies() -> void:
	var all := EmpireReport.colonies(_state, _player)
	var list: Array[Dictionary] = []
	for c in all:
		if _matches_filter(c):
			list.append(c)
	if colony_filter == "biosphere":
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var ha := Ecology.health(_state, int(a["planet_id"]))
			var hb := Ecology.health(_state, int(b["planet_id"]))
			return ha < hb or (ha == hb and int(a["planet_id"]) < int(b["planet_id"])))
	elif colony_sort != "":
		var free := TurnChecks.free_yards(_state, _player)
		list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var ka: Variant = colony_sort_key(a, colony_sort, free)
			var kb: Variant = colony_sort_key(b, colony_sort, free)
			if ka == kb:
				return int(a["planet_id"]) < int(b["planet_id"])
			return ka > kb if colony_sort_desc else ka < kb)
	_refresh_eco_side()
	_refresh_colony_heads()
	var ids := PackedStringArray()
	for c in list:
		ids.append(str(c["planet_id"]))
	var sig := colony_filter + ":" + ",".join(ids)
	_free_yards = TurnChecks.free_yards(_state, _player)
	if sig != _col_sig:
		_col_sig = sig
		_rebuild_colony_rows(list)
	_col_empty.visible = list.is_empty()
	var t := EmpireReport.totals(_state, _player)
	(_col_counts["colonies"] as Label).text = str(t["colonies"])
	(_col_counts["outposts"] as Label).text = str(t["outposts"])
	(_col_counts["founding"] as Label).text = str(t["founding"])
	(_col_counts["population"] as Label).text = str(t["population"])
	(_col_counts["systems"] as Label).text = str(t["systems"])
	(_col_counts["max_projects"] as Label).text = str(t["max_projects"])
	_col_donut.set_parts([
		{"value": float(t["colonies"]), "color": UiTheme.ACCENT},
		{"value": float(t["outposts"]), "color": Color(0.55, 0.62, 0.72)},
		{"value": float(t["founding"]), "color": UiTheme.WARN}], str(all.size()))
	if selected_planet < 0 or not _state.colonies.has(selected_planet) or (_state.colonies[selected_planet] as Colony).owner != _player:
		selected_planet = int(all[0]["planet_id"]) if not all.is_empty() else -1
	for i in list.size():
		_fill_colony_row(_col_rows[i], list[i])
	_refresh_pick(all)


## Onglets de la liste des colonies : Biosphères en plus quand l'écologie est en jeu (prop. 11).
func colony_filters() -> Array:
	var out := COLONY_FILTERS.duplicate()
	if Ecology.enabled(_state):
		out.append(["biosphere", "Biosphères"])
	return out


## Doctrine environnementale (écologie, prop. 10) : trois boutons dans la colonne de l'écran Colonies.
func _build_eco_side() -> void:
	_eco_buttons.clear()
	_eco_label = null
	if not Ecology.enabled(_state):
		return
	_side_box.add_child(HSeparator.new())
	_side_box.add_child(UiTheme.section("Doctrine environnementale"))
	_eco_label = UiTheme.paragraph("", SIDE_WIDTH - 30, 14)
	_side_box.add_child(_eco_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	_side_box.add_child(row)
	for d: Dictionary in Ecology.doctrine_defs():
		var b := Button.new()
		b.text = String(d["label"])
		b.toggle_mode = true
		b.focus_mode = Control.FOCUS_NONE
		var cmd := SimCommands.eco_act(_player, "doctrine", {"id": String(d["id"])})
		b.pressed.connect(func() -> void: command_requested.emit(cmd))
		row.add_child(b)
		_eco_buttons[String(d["id"])] = b


func _refresh_eco_side() -> void:
	if _eco_label == null or not Ecology.enabled(_state):
		return
	var cur := Ecology.doctrine(_state, _player)
	var wait := Ecology.doctrine_wait(_state, _player)
	_eco_label.text = "%s : %s%s" % [String(Ecology.doctrine_def(cur).get("label", cur)), String(Ecology.doctrine_def(cur).get("text", "")),
			("\nChangement possible dans %d jours." % wait) if wait > 0 else ""]
	for id in _eco_buttons:
		var b: Button = _eco_buttons[id]
		b.set_pressed_no_signal(id == cur)
		var why := SimCommands.validate(_state, SimCommands.eco_act(_player, "doctrine", {"id": id}))
		b.disabled = why != ""
		b.tooltip_text = String(Ecology.doctrine_def(id).get("text", "")) + ("" if why == "" else "\n(%s)" % why)


func _matches_filter(c: Dictionary) -> bool:
	match colony_filter:
		"biosphere":
			return c["established"] and Ecology.has_biosphere(_state, int(c["planet_id"]))
		"colony":
			return c["established"] and c["kind"] == Colony.KIND_COLONY
		"outpost":
			return c["established"] and c["kind"] != Colony.KIND_COLONY
		"founding":
			return not c["established"]
	return true


func _rebuild_colony_rows(list: Array[Dictionary]) -> void:
	for c in _col_list.get_children():
		_col_list.remove_child(c)
		c.queue_free()
	_col_rows.clear()
	for c in list:
		var b := _row_button(42)
		var pid: int = c["planet_id"]
		b.pressed.connect(func() -> void: select_colony(pid))
		b.gui_input.connect(func(ev: InputEvent) -> void:
			var mb := ev as InputEventMouseButton
			if mb and mb.double_click and mb.button_index == MOUSE_BUTTON_LEFT:
				planet_requested.emit(pid))
		b.tooltip_text = "Clic : choisir    Double-clic : ouvrir la vue système"
		var row := HBoxContainer.new()
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.offset_left = 12
		row.add_theme_constant_override("separation", 0)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(row)
		var cells: Array[Control] = []
		for i in COLUMN_WIDTHS.size():
			var cell: Control
			if i == 4:
				cell = HBoxContainer.new()
				(cell as HBoxContainer).add_theme_constant_override("separation", 10)
			else:
				cell = Label.new()
			cell.custom_minimum_size = Vector2(COLUMN_WIDTHS[i], 0)
			cell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(cell)
			cells.append(cell)
		(cells[0] as Label).theme_type_variation = &"Title"
		(cells[0] as Label).add_theme_font_size_override("font_size", 20)
		_col_list.add_child(b)
		_col_rows.append({"button": b, "cells": cells, "net_sig": "", "pid": pid})


func _pop_text(c: Dictionary) -> String:
	if not c["established"]:
		return "fondation : %d j" % c["days_left"]
	if c["kind"] == Colony.KIND_COLONY:
		return "%d / %d" % [c["population"], c["max_pop"]]
	return "avant-poste"


func _fill_colony_row(row: Dictionary, c: Dictionary) -> void:
	var cells: Array = row["cells"]
	(row["button"] as Button).set_pressed_no_signal(int(row["pid"]) == selected_planet)
	(cells[0] as Label).text = String(c["name"])
	(cells[0] as Label).add_theme_color_override("font_color", UiTheme.TEXT)
	(cells[1] as Label).text = String(c["type_label"]) + ("  (capitale)" if c["capital"] else "")
	(cells[2] as Label).text = _pop_text(c)
	(cells[2] as Label).add_theme_color_override("font_color", UiTheme.WARN if not c["established"] else UiTheme.TEXT)
	(cells[3] as Label).text = "%s (%d j)" % [c["construction"], c["construction_days"]] if c["construction"] != "" else "—"
	(cells[3] as Label).add_theme_color_override("font_color", UiTheme.TEXT if c["construction"] != "" else UiTheme.TEXT_DIM)
	if c["construction"] == "" and _free_yards.has(int(c["planet_id"])):
		# Chantier vide alors qu'on peut y bâtir : la colonne le dit (C2).
		(cells[3] as Label).text = "LIBRE"
		(cells[3] as Label).add_theme_color_override("font_color", UiTheme.WARN)
	if colony_filter == "biosphere":
		# Onglet Biosphères : la colonne Chantier montre la jauge, sa tendance et son palier.
		var pid := int(c["planet_id"])
		(cells[3] as Label).text = "%d %s %d  %s" % [Ecology.health(_state, pid), Ecology.arrow(_state, pid), Ecology.equilibrium(_state, pid), String(Ecology.tier(_state, pid).get("label", ""))]
		(cells[3] as Label).add_theme_color_override("font_color", Ecology.tier_color(Ecology.tier(_state, pid)))
		(row["button"] as Button).tooltip_text = Ecology.tooltip(_state, pid) + "\n\nClic : choisir    Double-clic : ouvrir la vue système"
	var sig := str(c["net"])
	if sig != row["net_sig"]:
		row["net_sig"] = sig
		_fill_net(cells[4], c["net"])


func _refresh_pick(all: Array[Dictionary]) -> void:
	var c: Dictionary = {}
	for x in all:
		if int(x["planet_id"]) == selected_planet:
			c = x
	_pick_open.disabled = c.is_empty()
	if c.is_empty():
		_pick_title.text = "Aucune colonie"
		_pick_lines.text = "Fondez une colonie ou un avant-poste depuis la vue d'un système."
		_fill_net(_pick_net, {})
		return
	var p := _state.galaxy.get_planet(selected_planet)
	var type_id := String(p.type)
	_pick_art.set_art("planet_" + type_id, TYPE_COLORS.get(type_id, UiTheme.ACCENT), "planet")
	_pick_title.text = String(c["name"]).to_upper()
	var lines := PackedStringArray()
	lines.append("%s, taille %d  ·  système %s%s" % [c["type_label"], p.size, c["system_name"], "  ·  capitale" if c["capital"] else ""])
	if not c["established"]:
		lines.append("Fondation en cours : encore %d jours." % c["days_left"])
	elif c["kind"] == Colony.KIND_COLONY:
		lines.append("Colonie : %d / %d population." % [c["population"], c["max_pop"]])
	else:
		lines.append("Avant-poste : pas de population, mais la planète est à nous.")
	lines.append("Chantier : %s (%d j)" % [c["construction"], c["construction_days"]] if c["construction"] != "" else "Aucun chantier en cours.")
	lines.append("Bilan par mois :")
	_pick_lines.text = "\n".join(lines)
	_fill_net(_pick_net, c["net"], 18)


# --- Recherche ------------------------------------------------------------------------------

func _build_research() -> void:
	research_buttons.clear()
	var me := _state.get_empire(_player)
	if research_selected == "" or not Research.is_visible(me.faction(), research_selected, _state, _player):
		research_selected = me.research_queue[0] if not me.research_queue.is_empty() else ""
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	_content.add_child(col)
	research_queue_bar = null
	if not Insolites.no_research(_state, _player):
		research_queue_bar = ResearchQueueBar.new()
		col.add_child(research_queue_bar)
		research_queue_bar.tech_picked.connect(func(tid: String) -> void: research_tree.select(tid))
		research_queue_bar.remove_requested.connect(func(tid: String) -> void: command_requested.emit(SimCommands.research_remove(_player, tid)))
		research_queue_bar.move_requested.connect(func(tid: String, to: int) -> void:
			if Research.check_move(_state, _player, tid, to) == "":
				command_requested.emit(SimCommands.research_move(_player, tid, to)))
	col.add_child(_research_toolbar())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	col.add_child(scroll)
	research_tree = ResearchTree.new()
	research_tree.selected = research_selected
	research_tree.filter = research_filter.duplicate()
	research_tree.zoom = research_zoom
	scroll.add_child(research_tree)
	research_tree.setup(_state, _player)
	research_tree.tech_selected.connect(func(tid: String) -> void:
		research_selected = tid
		_fill_research_side())
	research_tree.tech_activated.connect(func(tid: String) -> void:
		if Research.check_queue(_state, _player, tid, true) == "":
			Son.research_cue(tid)
			command_requested.emit(SimCommands.research(_player, tid, true)))
	research_tree.tech_planned.connect(plan_research_path)
	research_tree.zoom_changed.connect(func(z: float) -> void: research_zoom = z)
	_fill_research_side()


## Filtres de l'arbre gardés d'une ouverture à l'autre (prop. 105) et zoom.
var research_filter := {"field": "", "kind": "", "text": "", "mine": false}
var research_zoom := 1.0
var research_path: Array[String] = []
## File de recherche en bandeau, au-dessus de l'arbre (null pour un peuple qui n'invente rien).
var research_queue_bar: ResearchQueueBar


## Barre au-dessus de l'arbre : recherche par nom, champ, « ce que ça débloque », Mon peuple, zoom.
func _research_toolbar() -> Control:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	# Rangée calée à droite : le coin gauche de l'écran est pris par la barre de ressources.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var search := LineEdit.new()
	search.tooltip_text = "Par nom ou par texte. Clic droit sur une carte : planifier le chemin jusqu'à elle. Ctrl + molette : zoom."
	search.placeholder_text = "Chercher une technologie…"
	search.custom_minimum_size = Vector2(220, 0)
	search.text = String(research_filter["text"])
	search.text_changed.connect(func(t: String) -> void: _set_research_filter("text", t))
	bar.add_child(search)
	research_buttons["search"] = search
	var fields := OptionButton.new()
	fields.add_item("Tous les champs")
	fields.set_item_metadata(0, "")
	for d in Research.domain_ids():
		for fd: Dictionary in Research.domain(d).get("fields", []):
			fields.add_item("%s · %s" % [String(Research.domain(d).get("short", d)), String(fd["label"])])
			fields.set_item_metadata(fields.item_count - 1, String(fd["id"]))
			if String(fd["id"]) == String(research_filter["field"]):
				fields.select(fields.item_count - 1)
	fields.item_selected.connect(func(i: int) -> void: _set_research_filter("field", String(fields.get_item_metadata(i))))
	bar.add_child(fields)
	research_buttons["field"] = fields
	var kinds := OptionButton.new()
	kinds.add_item("Tout ce qui se débloque")
	kinds.set_item_metadata(0, "")
	for k in Research.UNLOCK_KINDS:
		kinds.add_item(String(Research.UNLOCK_KINDS[k]))
		kinds.set_item_metadata(kinds.item_count - 1, String(k))
		if String(k) == String(research_filter["kind"]):
			kinds.select(kinds.item_count - 1)
	kinds.item_selected.connect(func(i: int) -> void: _set_research_filter("kind", String(kinds.get_item_metadata(i))))
	bar.add_child(kinds)
	research_buttons["kind"] = kinds
	var mine := CheckButton.new()
	mine.text = "Mon peuple"
	mine.tooltip_text = "Allume les technologies propres à votre peuple et leurs chemins ; estompe le reste."
	mine.button_pressed = bool(research_filter["mine"])
	mine.toggled.connect(func(on: bool) -> void: _set_research_filter("mine", on))
	bar.add_child(mine)
	research_buttons["mine"] = mine
	for z in [["−", 1.0 / 1.15], ["+", 1.15]]:
		var b := Button.new()
		b.text = String(z[0])
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(28, 0)
		var mult: float = z[1]
		b.pressed.connect(func() -> void:
			if research_tree != null:
				research_tree.set_zoom(research_tree.zoom * mult))
		bar.add_child(b)
	return bar


func _set_research_filter(key: String, value: Variant) -> void:
	research_filter[key] = value
	if research_tree != null and is_instance_valid(research_tree):
		research_tree.set_filter(key, value)


## Clic droit sur une technologie lointaine (prop. 107) : la file se remplit avec ses prérequis dans
## l'ordre (et de quoi ouvrir les ères), et les liens du chemin s'allument.
func plan_research_path(tid: String) -> void:
	var e := _state.get_empire(_player)
	var steps := Research.plan_path(_state, _player, tid)
	research_path = steps
	if research_tree != null:
		research_tree.set_path(steps)
	if Insolites.no_research(_state, _player):
		return
	for q in steps:
		if e.research_queue.size() >= Research.MAX_QUEUE:
			break
		if Research.check_queue(_state, _player, q) == "":
			command_requested.emit(SimCommands.research(_player, q, false))


func _build_shipyard() -> void:
	if shipyard != null and is_instance_valid(shipyard):
		_shipyard_selected = shipyard.selected
	shipyard = ShipyardScreen.new()
	shipyard.selected = _shipyard_selected
	_content.add_child(shipyard)
	shipyard.command_requested.connect(func(cmd: Dictionary) -> void: command_requested.emit(cmd))
	var vp := get_viewport().get_visible_rect().size
	shipyard.setup(_state, _player, _side_box, SIDE_WIDTH - 24.0, vp.y - SIDE_TOP - 60.0)
	_shipyard_sig = _shipyard_signature()


func _shipyard_signature() -> String:
	var e := _state.get_empire(_player)
	return "%d|%d|%s" % [e.techs.size(), _state.designs.size(), CaptureUi.signature(_state, _player)]


func _research_signature() -> String:
	var e := _state.get_empire(_player)
	return "%d|%s|%d|%d|%s" % [e.techs.size(), ",".join(e.research_queue), e.research_progress,
			int(e.resources.get("knowledge", 0)), research_selected]


## Colonne de gauche de l'écran Recherche : recherche en cours, Savoir, talent du peuple, file,
## et la technologie choisie dans l'arbre avec ses boutons.
func _fill_research_side() -> void:
	_research_sig = _research_signature()
	for c in _side_box.get_children():
		_side_box.remove_child(c)
		c.queue_free()
	research_buttons.clear()
	var e := _state.get_empire(_player)
	var f := e.faction()
	var income := int(Economy.empire_income(_state, _player)["net"].get("knowledge", 0))

	if Insolites.no_research(_state, _player):
		_fill_research_catalogue(e)
		return
	_side_box.add_child(UiTheme.section("Recherche en cours"))
	if e.research_queue.is_empty():
		_side_box.add_child(UiTheme.paragraph("Aucune. Choisissez une technologie dans l'arbre : un double-clic la lance tout de suite.", SIDE_WIDTH - 24.0, 14))
	else:
		var cur := e.research_queue[0]
		var cost := Research.cost(_state, _player, cur)
		var name := UiTheme.title(String(Research.tech(cur).get("label", cur)), 20)
		_side_box.add_child(name)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(SIDE_WIDTH - 24.0, 8)
		bar.max_value = cost
		bar.value = e.research_progress
		_side_box.add_child(bar)
		var months := Research.months_left(_state, _player, cur, income)
		_side_box.add_child(UiTheme.dim("%d / %d Savoir  ·  %s" % [e.research_progress, cost,
				"encore %d mois environ" % months if months > 0 else ("achevée au prochain bilan" if months == 0 else "le Savoir manque")], 13))
	var g := _grid()
	_side_box.add_child(g)
	_key_value(g, "Savoir par mois", "%+d" % income)
	_key_value(g, "Savoir en réserve", str(int(e.resources.get("knowledge", 0))))
	_key_value(g, "Technologies", "%d / %d" % [e.techs.size(), Research.visible_for(_state, _player).size()])
	_key_value(g, "Ère la plus avancée", str(Research.current_era(_state, _player)))
	var rs: Dictionary = f.get("research", {})
	if not rs.is_empty():
		var talent := _key_value(g, "Talent du peuple", String(rs.get("name", "")))
		talent.mouse_filter = Control.MOUSE_FILTER_STOP
		talent.tooltip_text = String(rs.get("text", ""))
		talent.add_theme_color_override("font_color", e.color().lightened(0.3))
	var lack := Research.lacking_labels(f, _state, _player)
	if not lack.is_empty():
		var ll := UiTheme.paragraph("Votre peuple est %s : ce qui ne lui servirait à rien n'apparaît pas dans son arbre." % ", ".join(lack), SIDE_WIDTH - 24.0, 12)
		ll.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		_side_box.add_child(ll)

	if research_queue_bar != null and is_instance_valid(research_queue_bar):
		research_queue_bar.fill(_state, _player)
	_fill_tech_panel()


## Catalogue des acquisitions (prop. 26) : un peuple qui n'invente rien (les Silencieux) prend ses
## technologies aux épaves, aux prises et aux ruines ; pas de file, mais ce qui reste à prendre.
func _fill_research_catalogue(e: Empire) -> void:
	_side_box.add_child(UiTheme.section("Catalogue des acquisitions"))
	_side_box.add_child(UiTheme.paragraph("Votre peuple n'invente rien : il prend. Les technologies viennent des épaves des batailles gagnées, des vaisseaux pris (rétro-ingénierie) et des ruines. Pas de file de recherche.", SIDE_WIDTH - 24.0, 13))
	var ids := Research.visible_for(_state, _player)
	var g := _grid()
	_side_box.add_child(g)
	_key_value(g, "Acquises", "%d / %d" % [e.techs.size(), ids.size()])
	var by_dom := {}
	for tid in ids:
		if not e.techs.has(tid):
			var d := String(Research.tech(tid)["domain"])
			by_dom[d] = int(by_dom.get(d, 0)) + 1
	for d in Research.domain_ids():
		_key_value(g, "À prendre : %s" % String(Research.domain(d).get("label", d)), str(int(by_dom.get(d, 0))))
	var hint := UiTheme.paragraph("Où les trouver : les marques d'armes et les doctrines sur les épaves des flottes vaincues ; les coques et modules sur les vaisseaux pris ; le reste dans les ruines et les Strates. Ce qui a déjà été entamé porte un trait doré sous sa carte.", SIDE_WIDTH - 24.0, 12)
	hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_side_box.add_child(hint)
	_fill_tech_panel()


## Fiche de la technologie choisie, en bas à gauche par-dessus la colonne (comme dans Endless Space 2).
func _fill_tech_panel() -> void:
	if _tech_panel == null or not is_instance_valid(_tech_panel):
		_tech_panel = PanelContainer.new()
		_tech_panel.theme_type_variation = &"SidePanel"
		_tech_panel.custom_minimum_size = Vector2(SIDE_WIDTH, 0)
		_root.add_child(_tech_panel)
	for c in _tech_panel.get_children():
		_tech_panel.remove_child(c)
		c.queue_free()
	_tech_panel.visible = research_selected != "" and current == "research"
	if not _tech_panel.visible:
		_fit_side.call_deferred()
		return
	_tech_panel.add_child(_tech_detail(research_selected))
	_place_tech_panel()
	# Les paragraphes s'enroulent à la mise en page : la vraie hauteur n'est connue qu'ensuite.
	_place_tech_panel.call_deferred()


## Fiche collée en bas à gauche, à sa hauteur réelle ; la colonne s'arrête au-dessus (_fit_side).
func _place_tech_panel() -> void:
	if _tech_panel == null or not is_instance_valid(_tech_panel) or not _tech_panel.visible:
		return
	_tech_panel.reset_size()
	var vp := get_viewport().get_visible_rect().size
	_tech_panel.position = Vector2(MARGIN, vp.y - MARGIN - _tech_panel.get_combined_minimum_size().y)
	_fit_side()


func _tech_detail(tid: String) -> Control:
	var e := _state.get_empire(_player)
	var f := e.faction()
	var t := Research.tech(tid)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 5)
	var dom := Research.domain(String(t["domain"]))
	var head := UiTheme.title(String(t.get("label", tid)), 20)
	box.add_child(head)
	var fld := Research.field_label(String(t["domain"]), Research.field_of(tid))
	var sub := UiTheme.dim("%s%s  ·  ère %d  ·  %d Savoir" % [dom.get("label", ""), (" · " + fld) if fld != "" else "", int(t["era"]), Research.cost(_state, _player, tid)], 13)
	sub.add_theme_color_override("font_color", Color.html(String(dom.get("color", "#ffffff"))).lightened(0.2))
	box.add_child(sub)
	# Refonte E2 : la chose telle qu'elle existe dans l'univers d'abord, puis, à part, ce qu'elle fait en jeu.
	if String(t.get("lore", "")) != "":
		var lore := UiTheme.paragraph(String(t["lore"]), SIDE_WIDTH - 24.0, 14)
		lore.add_theme_color_override("font_color", Color(UiTheme.TEXT, 0.82))
		lore.name = "Lore"
		box.add_child(lore)
		box.add_child(Widgets.NotchHeader.new("En jeu", 12))
	box.add_child(UiTheme.paragraph(String(t.get("text", "")), SIDE_WIDTH - 24.0, 14))
	var unlocks := Research.unlocks(f, tid)
	if not unlocks.is_empty():
		box.add_child(UiTheme.paragraph("Débloque : %s" % ", ".join(unlocks), SIDE_WIDTH - 24.0, 13))
	if Research.is_mastery(tid):
		var ml0 := UiTheme.paragraph("Maîtrise de « %s » : facultative, jamais prérequise ; elle ne compte pas pour ouvrir l'ère suivante." % String(Research.tech(String(t["mastery"])).get("label", t["mastery"])), SIDE_WIDTH - 24.0, 13)
		ml0.add_theme_color_override("font_color", Color("d9b85c"))
		box.add_child(ml0)
	if Research.is_find(tid):
		var fi := UiTheme.paragraph("Trouvaille : elle ne se recherche pas. Curiosités, ruines, Strates, quêtes, prises ou hauts faits peuvent la livrer.", SIDE_WIDTH - 24.0, 13)
		fi.add_theme_color_override("font_color", Color("d9b85c"))
		box.add_child(fi)
	if Research.is_dangerous(tid):
		var dg := UiTheme.paragraph("Dangereuse : %s" % Research.danger_text(tid), SIDE_WIDTH - 24.0, 13)
		dg.add_theme_color_override("font_color", UiTheme.BAD)
		box.add_child(dg)
	if _state.politics_on and String(t.get("current", "")) != "" and Politics.index_of(String(t["current"])) >= 0:
		var cl := UiTheme.dim("Courant : %s y gagne un peu de soutien." % Politics.label(_state, _player, Politics.index_of(String(t["current"]))), 12)
		box.add_child(cl)
	var pre := PackedStringArray()
	for p in t.get("pre", []):
		var shown := Research.replaced_by(f, String(p))
		pre.append(String(Research.tech(shown if shown != "" else String(p)).get("label", p)))
	if not pre.is_empty():
		var pl := UiTheme.paragraph("Prérequis : %s" % ", ".join(pre), SIDE_WIDTH - 24.0, 13)
		pl.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		box.add_child(pl)
	if t.has("replaces"):
		var rl := UiTheme.paragraph("Propre à votre peuple, à la place de : %s" % Research.tech(String(t["replaces"])).get("label", t["replaces"]), SIDE_WIDTH - 24.0, 13)
		rl.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		box.add_child(rl)
	elif Research.is_specific(tid):
		box.add_child(UiTheme.dim("Propre à votre peuple.", 13))
	# Marques : où en est chaque famille touchée.
	var mk: Dictionary = t.get("effects", {}).get("marks", {})
	if not mk.is_empty():
		var now := Research.marks(_state, _player)
		var parts := PackedStringArray()
		for fam in Research.mark_families():
			if mk.has(fam):
				var m := int(now.get(fam, 1))
				parts.append("%s %s" % [Research.mark_label(String(fam)), ROMAN[m - 1] if e.techs.has(tid) else "%s → %s" % [ROMAN[m - 1], ROMAN[mini(4, m)]]])
		var ml := UiTheme.paragraph("Marques : %s. Les vaisseaux déjà construits les reçoivent au chantier (remise à niveau)." % ", ".join(parts), SIDE_WIDTH - 24.0, 13)
		ml.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		box.add_child(ml)
	if Research.spec_group(tid) != "" and not e.techs.has(tid):
		var others := PackedStringArray()
		for o in Research.spec_members(Research.spec_group(tid)):
			if o != tid:
				others.append("« %s »" % String(Research.tech(o).get("label", o)))
		var taken := Research.spec_taken(e.techs, tid)
		var dl := UiTheme.paragraph(("Spécialisation fermée : vous avez choisi « %s ». Celle-ci ne s'obtient plus que par échange, vol, épaves ou trouvaille." % String(Research.tech(taken).get("label", taken))) if taken != "" else \
				("Spécialisation définitive : la choisir ferme %s (que seuls l'échange, le vol, les épaves ou une trouvaille peuvent encore livrer)." % ", ".join(others)), SIDE_WIDTH - 24.0, 13)
		dl.add_theme_color_override("font_color", UiTheme.BAD if taken != "" else UiTheme.ACCENT)
		box.add_child(dl)
	if t.has("eureka") and not e.techs.has(tid):
		var st := Research.eureka_status(_state, _player, tid)
		var eu_txt := "Eurêka obtenu : 40 %% du coût déjà payé." if e.eurekas.has(tid) else \
				"Eurêka : %s (%d / %d) paiera 40 %% du coût." % [Research.eureka_text(tid), mini(int(st[0]), int(st[1])), int(st[1])]
		var el := UiTheme.paragraph(eu_txt, SIDE_WIDTH - 24.0, 13)
		el.add_theme_color_override("font_color", UiTheme.GOOD if e.eurekas.has(tid) else Color("d9b85c"))
		box.add_child(el)
	var got := int(e.research_shelf.get(tid, 0))
	if got > 0 and not e.techs.has(tid):
		var gl := UiTheme.paragraph("Déjà acquis : %d / %d Savoir (épaves, eurêka ou recherche interrompue)." % [got, Research.cost(_state, _player, tid)], SIDE_WIDTH - 24.0, 13)
		gl.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		box.add_child(gl)
	if Research.is_heretic(f, tid):
		var h := UiTheme.paragraph(String(t["heretic"].get("text", "Hérétique pour votre peuple.")), SIDE_WIDTH - 24.0, 13)
		h.add_theme_color_override("font_color", UiTheme.BAD)
		box.add_child(h)
	# Une technologie décrite ne garde son bon mot que si elle est marquée « quote » (une sur dix au plus).
	if Research.shows_flavor(t):
		var fl := UiTheme.paragraph("« %s »" % t["flavor"], SIDE_WIDTH - 24.0, 13)
		fl.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		box.add_child(fl)
	var cdx := Button.new()
	cdx.flat = true
	cdx.text = "Page du Codex ›"
	cdx.alignment = HORIZONTAL_ALIGNMENT_LEFT
	cdx.add_theme_font_size_override("font_size", 13)
	cdx.add_theme_color_override("font_color", Color.html(Glossary.LINK_COLOR))
	cdx.pressed.connect(func() -> void: codex_requested.emit("cat:technologies:" + tid))
	box.add_child(cdx)
	research_buttons["codex"] = cdx
	if e.techs.has(tid):
		var ok := UiTheme.dim("Découverte.", 14)
		ok.add_theme_color_override("font_color", UiTheme.GOOD)
		box.add_child(ok)
		return box
	var why := Research.check_queue(_state, _player, tid)
	if e.research_queue.has(tid):
		var rm := Widgets.RoundButton.new("close", "Retirer de la file", 13)
		rm.pressed.connect(func() -> void: command_requested.emit(SimCommands.research_remove(_player, tid)))
		box.add_child(rm)
		research_buttons["remove"] = rm
		if e.research_queue[0] != tid:
			var now := Widgets.RoundButton.new("next", "Lancer maintenant", 13)
			now.pressed.connect(func() -> void: command_requested.emit(SimCommands.research(_player, tid, true)))
			box.add_child(now)
			research_buttons["front"] = now
		return box
	if why != "":
		var w := UiTheme.paragraph(why.substr(0, 1).to_upper() + why.substr(1) + ".", SIDE_WIDTH - 24.0, 13)
		w.add_theme_color_override("font_color", UiTheme.WARN)
		box.add_child(w)
	var now := Widgets.RoundButton.new("next", "Lancer maintenant", 13)
	now.disabled = why != ""
	now.pressed.connect(func() -> void: command_requested.emit(SimCommands.research(_player, tid, true)))
	# (boutons l'un sous l'autre : la fiche garde la largeur de la colonne, sans déborder sur l'arbre)
	var acts := VBoxContainer.new()
	acts.add_theme_constant_override("separation", 2)
	box.add_child(acts)
	acts.add_child(now)
	research_buttons["front"] = now
	var add := Widgets.RoundButton.new("plus", "Mettre en file", 13)
	add.disabled = why != ""
	add.pressed.connect(func() -> void: command_requested.emit(SimCommands.research(_player, tid, false)))
	acts.add_child(add)
	research_buttons["queue"] = add
	return box


func _build_diplomacy() -> void:
	_side_header("screen_diplomacy", "Diplomatie", Color(0.8, 0.6, 1.0), "faction")
	_diplo_sig = _diplomacy_sig()
	war_buttons.clear()
	treaty_buttons.clear()
	cancel_buttons.clear()
	embargo_buttons.clear()
	proposal_buttons.clear()
	ability_buttons.clear()
	vassal_buttons.clear()
	koinon_buttons.clear()
	var me := _state.get_empire(_player)
	if diplo_selected < 0 or _state.get_empire(diplo_selected) == null or diplo_selected == _player:
		diplo_selected = -1
		for e in _state.empires:
			if e.id != _player and me.contacts.has(e.id) and not e.eliminated:
				diplo_selected = e.id
				break
		if diplo_selected < 0:
			diplo_selected = 1 if _player == 0 else 0

	# Colonne de gauche : bilan, talents du peuple, héritier.
	var g := _grid()
	_side_box.add_child(g)
	var wars := 0
	var pacts := 0
	for o in me.contacts:
		if Combat.at_war(_state, _player, o):
			wars += 1
		elif Diplomacy.has_pact(_state, _player, o):
			pacts += 1
	_key_value(g, "Empires rencontrés", str(me.contacts.size()))
	_key_value(g, "Guerres", str(wars))
	_key_value(g, "Traités", str(pacts))
	if Kardashev.applies(_state, _player):
		_key_value(g, "Échelle de Kardashev", Kardashev.text(_state, _player))
	var income := Diplomacy.treaty_income(_state, _player)
	if not income.is_empty():
		_key_value(g, "Revenus des traités", GameData.format_amounts(income, true))
	_side_box.add_child(HSeparator.new())
	for ab in Diplomacy.faction_abilities(me.faction()):
		var t := UiTheme.paragraph("%s. %s" % [ab["label"], ab["text"]], SIDE_WIDTH - 24.0, 13)
		_side_box.add_child(t)
	if Diplomacy.has_heir(_state, _player):
		_side_box.add_child(_heir_box(me))
	if Diplomacy.faction_abilities(me.faction()).is_empty():
		_side_box.add_child(UiTheme.paragraph(String(EmpireBar.screen_info("diplomacy").get("why", "")), SIDE_WIDTH - 24.0, 14))
	_side_box.add_child(VassalUi.side(_state, _player, SIDE_WIDTH - 24.0))
	_side_box.add_child(WarsUi.side(_state, _player, SIDE_WIDTH - 24.0))
	_side_box.add_child(BordersUi.side(_state, _player, SIDE_WIDTH - 24.0, _vassal_emit, border_buttons))

	# Contenu : la table à gauche, la relation choisie et les propositions à droite.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 22)
	_content.add_child(row)
	var left := Widgets.Block.new("Galaxie diplomatique")
	left.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(left)
	if not UiDomains.offered(_state, _player, "diplomacy:" + diplo_tab):
		diplo_tab = "empires"
	left.visible = diplo_tab == "empires"
	diplo_table = DiplomacyTable.new(430.0)
	left.body.add_child(diplo_table)
	diplo_table.setup(_state, _player, diplo_selected)
	diplo_table.empire_selected.connect(func(id: int) -> void:
		diplo_selected = id
		var other := _state.get_empire(id)
		if other != null:
			# D4 : l'indicatif du peuple, lu selon le statut ; D5 : quelques mots dans sa langue.
			PeopleSound.hail(other.faction_id, diplo_table._status(id), diplo_table.status_line(id))
		show_screen("diplomacy"))
	var legend := HBoxContainer.new()
	legend.add_theme_constant_override("separation", 12)
	for st in ["war", "cold", "peace", "alliance"]:
		var pair := HBoxContainer.new()
		pair.add_theme_constant_override("separation", 4)
		pair.add_child(Widgets.Dot.new(DiplomacyTable.STATUS_COLORS[st], 10))
		pair.add_child(UiTheme.dim(Diplomacy.status_label(st), 13))
		legend.add_child(pair)
	left.body.add_child(legend)
	var leagues := diplo_table.league_legend()
	if not leagues.is_empty():
		var ll := HFlowContainer.new()
		ll.add_theme_constant_override("h_separation", 12)
		for lg: Array in leagues:
			var lp := HBoxContainer.new()
			lp.add_theme_constant_override("separation", 4)
			lp.add_child(Widgets.Dot.new(lg[1], 10))
			lp.add_child(UiTheme.dim(String(lg[0]), 13))
			ll.add_child(lp)
		left.body.add_child(ll)

	# Colonne de droite défilante : relation, sujets, Koinon peuvent dépasser l'écran.
	var right_scroll := ScrollContainer.new()
	right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(right_scroll)
	var right := VBoxContainer.new()
	right.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	right.add_theme_constant_override("separation", 18)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_scroll.add_child(right)
	var props := Diplomacy.proposals_for(_state, _player)
	if not props.is_empty():
		var pb := _proposals_block(props)
		pb.visible = diplo_tab == "empires"
		right.add_child(pb)
	var rel := _relation_block(diplo_selected)
	rel.visible = diplo_tab == "empires"
	right.add_child(rel)
	# Ligue et Voisins ont leur onglet (refonte, C18 et C19) : construits ici, montrés selon l'onglet.
	var kb := KoinonUi.league_block(_state, _player, _vassal_emit, koinon_buttons, koinon_draft)
	if kb != null:
		kb.visible = diplo_tab == "league"
		right.add_child(kb)
	var ab := AncientsUi.block(_state, _player, _vassal_emit, koinon_buttons, koinon_draft)
	if ab != null:
		ab.visible = diplo_tab == "neighbors"
		right.add_child(ab)
	var mb := MinorsUi.block(_state, _player, _vassal_emit, koinon_buttons, koinon_draft)
	if mb != null:
		mb.visible = diplo_tab == "neighbors"
		right.add_child(mb)


func _heir_box(me: Empire) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	var trend := Diplomacy.heir_trend(_state, _player)
	var delta := 0
	var lines := PackedStringArray()
	for p in trend:
		delta += int(p["value"])
		lines.append("%+d  %s" % [int(p["value"]), p["label"]])
	var g := _grid()
	box.add_child(g)
	var v := _key_value(g, "Loyauté de l'héritier", "%d / 100" % me.heir_loyalty)
	v.add_theme_color_override("font_color", UiTheme.GOOD if me.heir_loyalty >= 50 else (UiTheme.WARN if me.heir_loyalty >= 25 else UiTheme.BAD))
	v.tooltip_text = "Chaque mois : %+d\n%s" % [delta, "\n".join(lines)]
	v.mouse_filter = Control.MOUSE_FILTER_STOP
	var t := _key_value(g, "Tendance", "%+d / mois" % delta)
	t.add_theme_color_override("font_color", UiTheme.delta_color(delta))
	if me.heir_suitor >= 0 and _state.get_empire(me.heir_suitor) != null:
		box.add_child(UiTheme.dim("Courtisé par %s" % _state.get_empire(me.heir_suitor).short_name(), 13))
	var cost: Dictionary = Diplomacy.ability("heir")["banquet_cost"]
	var b := Button.new()
	b.text = "BANQUET DES LIGNÉES (%s)" % GameData.format_amounts(cost)
	b.focus_mode = Control.FOCUS_NONE
	var why := Diplomacy.check_banquet(_state, _player)
	b.disabled = why != ""
	b.tooltip_text = why if why != "" else "+%d loyauté." % int(Diplomacy.ability("heir")["banquet_gain"])
	b.pressed.connect(func() -> void: command_requested.emit(SimCommands.banquet(_player)))
	box.add_child(b)
	ability_buttons["banquet"] = b
	return box


func _proposals_block(props: Array[Dictionary]) -> Control:
	var blk := Widgets.Block.new("Propositions reçues")
	for p in props:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		blk.body.add_child(line)
		var from := _state.get_empire(int(p["from"]))
		var left := Diplomacy.proposal_limit(p) - (_state.tick - int(p["tick"]))
		var l := Label.new()
		l.text = "%s propose : %s  (encore %d j)" % [from.short_name(), Diplomacy.proposal_label(p), left]
		l.add_theme_color_override("font_color", from.color().lerp(Color.WHITE, 0.4))
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.tooltip_text = Vassals.kind_text(_state, p) if Vassals.is_kind(String(p["treaty"])) else (Wars.kind_text(_state, p) if Wars.is_kind(String(p["treaty"])) \
				else (Borders.kind_text(_state, p) if Borders.is_kind(String(p["treaty"])) else String(Diplomacy.treaty_info(String(p["treaty"])).get("desc", ""))))
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		line.add_child(l)
		var pid := int(p["id"])
		var ok := Button.new()
		ok.text = "ACCEPTER"
		ok.theme_type_variation = &"PrimaryButton"
		ok.focus_mode = Control.FOCUS_NONE
		var why := Diplomacy.check_answer(_state, _player, pid, true)
		ok.disabled = why != ""
		ok.tooltip_text = why
		ok.pressed.connect(func() -> void: command_requested.emit(SimCommands.answer_proposal(_player, pid, true)))
		line.add_child(ok)
		var no := Button.new()
		no.text = "REFUSER"
		no.focus_mode = Control.FOCUS_NONE
		no.pressed.connect(func() -> void: command_requested.emit(SimCommands.answer_proposal(_player, pid, false)))
		line.add_child(no)
		proposal_buttons[pid] = [ok, no]
	return blk


func _relation_block(id: int) -> Control:
	var e := _state.get_empire(id)
	var me := _state.get_empire(_player)
	var blk := Widgets.Block.new(e.display_name())
	var st := Diplomacy.status(_state, _player, id)
	if e.eliminated:
		st = "none"
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	blk.body.add_child(head)
	var art := Widgets.ArtSlot.new(GameData.portrait_art(e.faction_id), Vector2(150, 110), e.color(), "faction")
	head.add_child(art)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(info)
	info.add_child(UiTheme.dim(String(e.faction().get("registre", "")), 13))
	var sl := Label.new()
	sl.text = ("Disparu" if e.eliminated else Diplomacy.status_text(_state, _player, id)).to_upper()
	sl.add_theme_font_size_override("font_size", 20)
	sl.add_theme_color_override("font_color", DiplomacyTable.STATUS_COLORS[st])
	info.add_child(sl)
	var extra := PackedStringArray()
	if Diplomacy.in_truce(_state, _player, id):
		extra.append("Trêve : encore %d jours" % Diplomacy.truce_left(_state, _player, id))
	if st == "peace" or st == "alliance":
		extra.append("Signé il y a %d jours" % Diplomacy.pact_days(_state, _player, id))
	if Diplomacy.has_trade(_state, _player, id):
		extra.append("Commerce : %s (routes %+d énergie ce mois)" % [Trade.tier_label(Trade.tier(_state, _player, id)), Trade.value_between(_state, _player, id)])
	if Trade.embargo_by(_state, _player, id):
		extra.append("Vous lui imposez un embargo")
	if Trade.embargo_by(_state, id, _player):
		extra.append("Il vous impose un embargo")
	if st == "war":
		extra.append("Guerre depuis %d jours, score %+d%s" % [Diplomacy.pact_days(_state, _player, id), Diplomacy.war_score(_state, _player, id),
				" %" if _state.wars_on and not Wars.war(_state, _player, id).is_empty() else ""])
	if e.is_ai():
		extra.append("Tempérament : %s" % AiLevels.temperament_label(e))
		extra.append(AiLevels.bonus_text(_state, id))
	if not e.eliminated and _player >= 0 and st != "none":
		extra.append(ForceOdds.empire_line(_state, _player, id))  # bêta-test (3.2)
	if Kardashev.applies(_state, id) and not e.eliminated:
		extra.append("Échelle de Kardashev : %s" % Kardashev.text(_state, id))
	for x in extra:
		info.add_child(UiTheme.dim(x, 13))
	if st == "none":
		blk.body.add_child(UiTheme.paragraph("Aucun contact : vos éclaireurs n'ont pas encore croisé cet empire." if not e.eliminated else "Cet empire a disparu de la galaxie.", 520, 14))
		return blk

	# Trois volets (refonte, C16) : Relation, Traiter, Guerre. Tous construits, un seul montré.
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	blk.body.add_child(tabs)
	var p_rel := VBoxContainer.new()
	var p_deal := VBoxContainer.new()
	var p_war := VBoxContainer.new()
	diplo_panes = {"relation": p_rel, "deal": p_deal, "war": p_war}
	diplo_pane_buttons = {}
	for pn in [["relation", "Relation"], ["deal", "Traiter"], ["war", "Guerre"]]:
		var pid := String(pn[0])
		var pb := Button.new()
		pb.theme_type_variation = &"TabButton"
		pb.toggle_mode = true
		pb.focus_mode = Control.FOCUS_NONE
		pb.text = String(pn[1]).to_upper()
		pb.add_theme_font_size_override("font_size", 13)
		pb.set_pressed_no_signal(pid == diplo_pane)
		pb.pressed.connect(func() -> void: set_diplo_pane(pid))
		tabs.add_child(pb)
		diplo_pane_buttons[pid] = pb
		var pane: VBoxContainer = diplo_panes[pid]
		pane.add_theme_constant_override("separation", 8)
		pane.visible = pid == diplo_pane
		blk.body.add_child(pane)
	var acts_deal := HFlowContainer.new()
	var acts_war := HFlowContainer.new()
	for fl: HFlowContainer in [acts_deal, acts_war]:
		fl.add_theme_constant_override("h_separation", 10)
		fl.add_theme_constant_override("v_separation", 6)

	# Opinions, détaillées dans l'infobulle.
	var g := _grid(2)
	p_rel.add_child(g)
	_opinion_row(g, "Son opinion de vous", id, _player)
	_opinion_row(g, "Votre opinion de lui", _player, id)
	for ab in Diplomacy.faction_abilities(e.faction()):
		var t := UiTheme.paragraph("%s. %s" % [ab["label"], ab["text"]], 520, 13)
		t.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		p_rel.add_child(t)
	if InsSilencieux.is_silent(_state, id):  # la directive des Silencieux est affichée à tous (prop. 74)
		var dt := UiTheme.paragraph(InsSilencieux.directive_text(_state, id), 520, 13)
		dt.add_theme_color_override("font_color", UiTheme.WARN)
		p_rel.add_child(dt)
	if Diplomacy.has_heir(_state, id):
		p_rel.add_child(UiTheme.dim("Loyauté de son héritier : %d / 100" % e.heir_loyalty, 13))

	# Traités : un bouton par traité, avec ce que l'autre en pense (comme la barre d'Endless Space 2).
	p_deal.add_child(UiTheme.section("Proposer"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 6)
	p_deal.add_child(grid)
	for t in Diplomacy.TREATY_IDS:
		if t == Diplomacy.MIGRATION and not _state.peoples_on:
			continue
		if (t == Diplomacy.PASSAGE or t == Diplomacy.PROSP) and not Borders.active(_state):
			continue
		if t == Diplomacy.PROSP and _state.curios.is_empty():
			continue
		var b := Button.new()
		b.text = Diplomacy.offer_label(_state, _player, id, t).to_upper()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2(220, 0)
		var why := Diplomacy.check_propose(_state, _player, id, t)
		b.disabled = why != ""
		var desc := Diplomacy.offer_desc(_state, _player, id, t)
		b.tooltip_text = (why + "\n\n" + desc) if why != "" else desc
		var treaty := t
		b.pressed.connect(func() -> void: command_requested.emit(SimCommands.propose_treaty(_player, id, treaty)))
		grid.add_child(b)
		treaty_buttons[t] = b
		var verdict := Label.new()
		verdict.mouse_filter = Control.MOUSE_FILTER_STOP
		if why != "":
			verdict.text = why
			verdict.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		elif e.is_ai():
			var ev := AiDiplomacy.evaluate(_state, id, _player, t)
			var yes := int(ev["score"]) >= int(Diplomacy.data()["ai"]["accept_at"])
			verdict.text = "%s  (%+d)" % ["Accepterait" if yes else "Refuserait", int(ev["score"])]
			verdict.add_theme_color_override("font_color", UiTheme.GOOD if yes else UiTheme.BAD)
			var lines := PackedStringArray()
			for p in ev["parts"]:
				lines.append("%+d  %s" % [int(p["value"]), p["label"]])
			verdict.tooltip_text = "Ce que %s pense de l'offre :\n%s" % [e.short_name(), "\n".join(lines)]
		else:
			verdict.text = "Il devra répondre"
			verdict.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		verdict.add_theme_font_size_override("font_size", 13)
		verdict.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		verdict.custom_minimum_size = Vector2(240, 0)
		grid.add_child(verdict)
	# Frontières : accès dans les deux sens, politique, intrus (voir BordersUi).
	p_rel.add_child(BordersUi.relation(_state, _player, id, _vassal_emit, border_buttons))
	# Buts de guerre : motifs, revendications, score en %, reddition sur but (voir WarsUi).
	p_war.add_child(WarsUi.relation(_state, _player, id, _vassal_emit, war_goal_buttons, war_draft))
	# Paix à conditions, reddition, protection, sujets (voir VassalUi).
	p_deal.add_child(VassalUi.relation(_state, _player, id, _vassal_emit, vassal_buttons, vassal_draft))
	# Koinon : fonder, entrer, guerre commune, exclusion (voir KoinonUi).
	p_deal.add_child(KoinonUi.relation(_state, _player, id, _vassal_emit, koinon_buttons, koinon_draft))

	# Rompre, déclarer, intriguer, arbitrer.
	var acts := HFlowContainer.new()
	acts.add_theme_constant_override("h_separation", 10)
	acts.add_theme_constant_override("v_separation", 6)
	p_rel.add_child(acts)
	p_deal.add_child(acts_deal)
	p_war.add_child(acts_war)
	for t in [Diplomacy.ALLIANCE, Diplomacy.PEACE, Diplomacy.TRADE, Diplomacy.MIGRATION, Diplomacy.PASSAGE, Diplomacy.PROSP]:
		var label: String = {"alliance": "QUITTER L'ALLIANCE", "peace": "DÉNONCER LA PAIX", "trade": "ROMPRE LE COMMERCE", "migration": "FERMER LA MIGRATION",
				"passage": "DÉNONCER LE LIBRE-PASSAGE", "prosp": "FIN DE LA PROSPECTION"}[t]
		var shown: bool = (t == Diplomacy.ALLIANCE and Diplomacy.allied(_state, _player, id)) \
				or (t == Diplomacy.PEACE and Diplomacy.pact(_state, _player, id) == Diplomacy.PEACE) \
				or (t == Diplomacy.TRADE and Diplomacy.has_trade(_state, _player, id)) \
				or (t == Diplomacy.MIGRATION and Diplomacy.has_migration(_state, _player, id)) \
				or (t == Diplomacy.PASSAGE and Borders.has_treaty(_state, _player, id)) \
				or (t == Diplomacy.PROSP and Borders.has_prosp(_state, _player, id))
		if not shown:
			continue
		var b := Button.new()
		b.text = label
		b.focus_mode = Control.FOCUS_NONE
		var why := Diplomacy.check_cancel(_state, _player, id, t)
		b.disabled = why != ""
		b.tooltip_text = why
		var treaty: String = t
		b.pressed.connect(func() -> void: command_requested.emit(SimCommands.cancel_treaty(_player, id, treaty)))
		acts.add_child(b)
		cancel_buttons[t] = b
	# Embargo (voir Trade) : couper le commerce, ou le rouvrir.
	if not e.eliminated:
		var emb := Button.new()
		var lifting := Trade.embargo_by(_state, _player, id)
		emb.text = "LEVER L'EMBARGO" if lifting else "EMBARGO"
		emb.focus_mode = Control.FOCUS_NONE
		var ewhy := Trade.check_lift(_state, _player, id) if lifting else Trade.check_embargo(_state, _player, id)
		emb.disabled = ewhy != ""
		emb.tooltip_text = ewhy if ewhy != "" else ("Le commerce pourra reprendre (il faudra le signer de nouveau)." if lifting \
				else "Coupe tout commerce avec cet empire et interdit d'en signer. Vos alliés IA qui ne l'aiment pas suivront. Il s'en souviendra.")
		var etarget := id
		emb.pressed.connect(func() -> void:
			command_requested.emit(SimCommands.lift_embargo(_player, etarget) if lifting else SimCommands.embargo(_player, etarget)))
		acts.add_child(emb)
		embargo_buttons[id] = emb
	if not e.eliminated and not Combat.at_war(_state, _player, id):
		var war := Button.new()
		var goals := _state.wars_on
		var brk := goals and Diplomacy.in_truce(_state, _player, id)
		var label := "ROMPRE LA TRÊVE ET DÉCLARER LA GUERRE" if brk else ("ROMPRE ET DÉCLARER LA GUERRE" if Diplomacy.has_pact(_state, _player, id) else "DÉCLARER LA GUERRE")
		war.text = label
		war.focus_mode = Control.FOCUS_NONE
		var why := Combat.check_declare_war(_state, _player, id, brk)
		war.disabled = why != ""
		war.tooltip_text = why if why != "" else ("Deux clics. Rompre un traité fait de vous un parjure aux yeux de toute la galaxie." \
				if Diplomacy.has_pact(_state, _player, id) else "Deux clics : la guerre vaut dans les deux sens.")
		if goals and why == "":
			war.tooltip_text += "\n\n" + WarsUi.declare_tip(_state, _player, id, war_draft)
		var target := id
		war.pressed.connect(func() -> void:
			if war.text == label:
				war.text = "CONFIRMER ?"
				war.theme_type_variation = &"PrimaryButton"
			elif goals:
				var c := WarsUi.choice(_state, _player, target, war_draft)
				command_requested.emit(SimCommands.declare_war(_player, target, String(c[0]), String(c[1]), brk))
			else:
				war_requested.emit(target))
		acts_war.add_child(war)
		war_buttons[id] = war
	if Diplomacy.has_heir(_state, id):
		var b := Button.new()
		b.text = "SOUDOYER L'HÉRITIER (%s)" % GameData.format_amounts(Diplomacy.ability("heir")["bribe_cost"])
		b.focus_mode = Control.FOCUS_NONE
		var why := Diplomacy.check_bribe(_state, _player, id)
		b.disabled = why != ""
		b.tooltip_text = why if why != "" else "Sa loyauté baisse de %d. À 0, il vous livre son fief le plus lointain. Ils le sauront." % int(Diplomacy.ability("heir")["bribe_loss"])
		b.pressed.connect(func() -> void: command_requested.emit(SimCommands.bribe_heir(_player, id)))
		acts_deal.add_child(b)
		ability_buttons["bribe"] = b
	# Flottes à louer : le syndicat propose ses flottes, ou le client les engage.
	if Diplomacy.has_ability(_state, _player, "mercenary") and not e.eliminated:
		for w in e.wars:
			if w == _player or not me.contacts.has(w):
				continue
			var b := Button.new()
			b.text = "LOUER NOS FLOTTES CONTRE %s" % _state.get_empire(w).short_name().to_upper()
			b.focus_mode = Control.FOCUS_NONE
			var why := Diplomacy.check_propose_contract(_state, _player, _player, id, w)
			b.disabled = why != ""
			b.tooltip_text = why if why != "" else "Nous entrons en guerre contre %s ; %s nous paie %s par mois tant que dure sa guerre." % [
					_state.get_empire(w).short_name(), e.short_name(), GameData.format_amounts(Diplomacy.contract_fee(_state, _player))]
			var target := w
			b.pressed.connect(func() -> void: command_requested.emit(SimCommands.contract(_player, _player, id, target)))
			acts_deal.add_child(b)
			ability_buttons["hire_out_%d" % w] = b
	if Diplomacy.has_ability(_state, id, "mercenary") and not e.eliminated:
		for w in me.wars:
			if w == id or not e.contacts.has(w):
				continue
			var b := Button.new()
			b.text = "ENGAGER CONTRE %s" % _state.get_empire(w).short_name().to_upper()
			b.focus_mode = Control.FOCUS_NONE
			var why := Diplomacy.check_propose_contract(_state, _player, id, _player, w)
			b.disabled = why != ""
			b.tooltip_text = why if why != "" else "%s entre en guerre contre %s pour %s par mois, tant que dure votre guerre." % [
					e.short_name(), _state.get_empire(w).short_name(), GameData.format_amounts(Diplomacy.contract_fee(_state, id))]
			var target := w
			b.pressed.connect(func() -> void: command_requested.emit(SimCommands.contract(_player, id, _player, target)))
			acts_deal.add_child(b)
			ability_buttons["hire_%d" % w] = b
	if Victory.applies(_state, _player, "elu") and not Diplomacy.no_treaties(_state, id) and not e.eliminated:
		var b := Button.new()
		var united := Victory.united(_state, _player, id)
		b.text = "LIGNÉES UNIES" if united else "UNIR NOS LIGNÉES (%s)" % GameData.format_amounts(Victory.info("elu")["union_cost"])
		b.focus_mode = Control.FOCUS_NONE
		var why := Victory.check_union(_state, _player, id)
		b.disabled = why != ""
		b.tooltip_text = (why if why != "" else "Un pas vers l'Élu des routes : l'union tient tant que l'alliance tient.") if not united \
				else "Vos maisons sont unies. Si l'alliance tombe, l'union tombe avec elle."
		b.pressed.connect(func() -> void: command_requested.emit(SimCommands.unite_lineages(_player, id)))
		acts_deal.add_child(b)
		ability_buttons["union"] = b
	if Diplomacy.has_ability(_state, _player, "mediation"):
		for w in e.wars:
			if w == _player or not me.contacts.has(w) or Diplomacy.no_treaties(_state, w) or Diplomacy.no_treaties(_state, id):
				continue
			var b := Button.new()
			b.text = "ARBITRER : %s / %s" % [e.short_name().to_upper(), _state.get_empire(w).short_name().to_upper()]
			b.focus_mode = Control.FOCUS_NONE
			var why := Diplomacy.check_mediate(_state, _player, id, w)
			b.disabled = why != ""
			b.tooltip_text = why if why != "" else "Les Veilleurs du Seuil imposent la paix (%s)." % GameData.format_amounts(Diplomacy.ability("mediation")["cost"])
			var other := w
			b.pressed.connect(func() -> void: command_requested.emit(SimCommands.mediate(_player, id, other)))
			acts_deal.add_child(b)
			ability_buttons["mediate_%d" % w] = b
	return blk


## Rangée d'onglets d'un groupe de volets. `defs` : [[id, libellé], ...]. Tous les volets sont construits,
## un seul est visible : pane_box(groupe, id) rend la colonne à remplir, que l'appelant place lui-même.
func pane_row(group: String, defs: Array, fallback: String) -> HFlowContainer:
	var tabs := HFlowContainer.new()
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 4)
	var cur := String(pane_current.get(group, fallback))
	var known := false
	for d: Array in defs:
		known = known or String(d[0]) == cur
	if not known:
		cur = fallback
	pane_current[group] = cur
	var boxes := {}
	var buttons := {}
	for d: Array in defs:
		var pid := String(d[0])
		var pb := Button.new()
		pb.theme_type_variation = &"TabButton"
		pb.toggle_mode = true
		pb.focus_mode = Control.FOCUS_NONE
		pb.text = String(d[1]).to_upper()
		pb.add_theme_font_size_override("font_size", 13)
		pb.set_pressed_no_signal(pid == cur)
		pb.pressed.connect(func() -> void: set_pane(group, pid))
		tabs.add_child(pb)
		buttons[pid] = pb
		var box := VBoxContainer.new()
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		box.add_theme_constant_override("separation", 18)
		box.visible = pid == cur
		boxes[pid] = box
	panes[group] = {"boxes": boxes, "buttons": buttons}
	return tabs


func pane_box(group: String, id: String) -> VBoxContainer:
	return panes[group]["boxes"][id]


func set_pane(group: String, id: String) -> void:
	if not panes.has(group) or not (panes[group]["boxes"] as Dictionary).has(id):
		return
	pane_current[group] = id
	for k: String in panes[group]["boxes"]:
		if is_instance_valid(panes[group]["boxes"][k]):
			(panes[group]["boxes"][k] as Control).visible = k == id
			(panes[group]["buttons"][k] as Button).set_pressed_no_signal(k == id)


## Montre un volet de la fiche d'un empire : "relation", "deal" (Traiter) ou "war" (Guerre).
func set_diplo_pane(pane: String) -> void:
	diplo_pane = pane
	for k: String in diplo_panes:
		if is_instance_valid(diplo_panes[k]):
			(diplo_panes[k] as Control).visible = k == pane
			(diplo_pane_buttons[k] as Button).set_pressed_no_signal(k == pane)


func _opinion_row(g: GridContainer, caption: String, who: int, about: int) -> void:
	var v := Diplomacy.opinion(_state, who, about)
	var val := _key_value(g, caption, "%+d  %s" % [v, Diplomacy.opinion_label(v)])
	val.add_theme_color_override("font_color", UiTheme.delta_color(v) if absi(v) >= 20 else UiTheme.TEXT)
	var lines := PackedStringArray()
	for p in Diplomacy.opinion_parts(_state, who, about):
		lines.append("%+d  %s" % [int(p["value"]), p["label"]])
	val.tooltip_text = "\n".join(lines) if not lines.is_empty() else "Aucune raison particulière."
	val.mouse_filter = Control.MOUSE_FILTER_STOP


## Ce qui change l'écran Diplomatie : contacts, guerres, traités, propositions, mois, influence.
func _diplomacy_sig() -> String:
	var parts := PackedStringArray()
	for e in _state.empires:
		parts.append("%d:%s:%s:%s:%d" % [e.id, str(e.contacts), str(e.wars), e.eliminated, e.heir_loyalty])
	@warning_ignore("integer_division")
	parts.append(str(_state.tick / 30))
	parts.append(str(_state.relations))
	parts.append(str(_state.proposals.size()) + ":" + str(_state.next_proposal_id))
	parts.append(str(_state.get_empire(_player).resources.get("influence", 0)))
	parts.append(str(_state.vassals.get("subs", {})))
	if _state.koinon_on:
		parts.append(str(_state.koinon))
	if _state.wars_on:
		parts.append(str(_state.wars))
	if Borders.active(_state):
		parts.append(str(_state.borders))
	return "|".join(parts)


## Ordre venu de VassalUi ; un ordre vide redessine l'écran (brouillon changé).
func _vassal_emit(cmd: Dictionary) -> void:
	if cmd.is_empty():
		show_screen("diplomacy")
	else:
		command_requested.emit(cmd)


func _spacer(parent: Control) -> void:
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(gap)


# --- Victoire -------------------------------------------------------------------------------

func _build_victory() -> void:
	_vict_sig = _victory_sig()
	victory_rows.clear()
	var me := _state.get_empire(_player)
	_side_header("screen_victory", "Victoire", Color(1.0, 0.85, 0.45), "faction")
	transcendence_buttons.clear()
	contact_buttons.clear()
	TranscendenceScreen.tabs(self, "victory")
	var w := _state.winner
	if not w.is_empty():
		var we := _state.get_empire(int(w["empire"]))
		var winners := we.short_name()
		for a in w.get("allies", []):
			winners += " et " + _state.get_empire(int(a)).short_name()
		_side_box.add_child(UiTheme.title("%s l'emporte%s" % [winners, "nt" if not Array(w.get("allies", [])).is_empty() else ""], 20, we.color().lightened(0.3)))
		_side_box.add_child(UiTheme.dim("%s, le %s" % [Victory.label(String(w["victory"])), GameCalendar.date_string(int(w["tick"]))], 14))
		_side_box.add_child(HSeparator.new())
	var g := _grid()
	_side_box.add_child(g)
	var dl := Victory.deadline(_state)
	_key_value(g, "Date limite", GameCalendar.date_string(dl) if dl > 0 else "aucune")
	_key_value(g, "Victoires de peuple", "en jeu" if Victory.people_enabled(_state) else "désactivées")
	_key_value(g, "Votre score", str(Victory.score(_state, _player)))
	_side_box.add_child(HSeparator.new())
	var mine := Victory.people_ids_for(me.faction())
	if mine.is_empty():
		_side_box.add_child(UiTheme.paragraph("Votre peuple n'a pas de victoire propre : ses couches d'espèce n'en ouvrent aucune.", SIDE_WIDTH - 24.0, 13))
	for id in mine:
		_side_box.add_child(UiTheme.section(Victory.label(id)))
		_side_box.add_child(UiTheme.paragraph(Victory.rule_text(id), SIDE_WIDTH - 24.0, 13))
		var counter := UiTheme.paragraph("La contrer : %s" % String(Victory.info(id).get("counter", "")), SIDE_WIDTH - 24.0, 12)
		counter.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
		_side_box.add_child(counter)
	_side_box.add_child(UiTheme.paragraph(String(EmpireBar.screen_info("victory").get("why", "")), SIDE_WIDTH - 24.0, 13))

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(scroll)
	var page := VBoxContainer.new()
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.add_theme_constant_override("separation", 18)
	scroll.add_child(page)
	page.add_child(_victory_ranking())
	page.add_child(_victory_paths())
	var cols := HFlowContainer.new()
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_theme_constant_override("h_separation", 22)
	cols.add_theme_constant_override("v_separation", 18)
	var count := 0
	for id in Victory.ids():
		if not Victory.enabled(_state, id):
			continue
		if Victory.is_people(id) and not _victory_relevant(id):
			continue
		cols.add_child(_victory_block(id))
		count += 1
	var open := bool(pane_current.get("victory_detail", false))
	victory_detail = Button.new()
	victory_detail.toggle_mode = true
	victory_detail.focus_mode = Control.FOCUS_NONE
	victory_detail.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	victory_detail.text = "DÉTAIL DES %d VICTOIRES" % count
	victory_detail.tooltip_text = "Chaque victoire, sa règle, et l'avancée de tous les empires connus."
	victory_detail.set_pressed_no_signal(open)
	cols.visible = open
	victory_detail.toggled.connect(func(on: bool) -> void:
		pane_current["victory_detail"] = on
		cols.visible = on)
	page.add_child(victory_detail)
	page.add_child(cols)


## Pour chaque empire encore en lice, sa victoire la plus avancée parmi celles qu'on peut lire :
## [{empire, id, pct}], le plus avancé d'abord. id vide et pct -1 : rien de lisible chez lui.
static func victory_leaders(state: GameState, viewer: int, empires: Array[Empire]) -> Array:
	var out := []
	for e in empires:
		if e.eliminated:
			continue
		var best := {"empire": e.id, "id": "", "pct": -1}
		for id in Victory.ids():
			if id == Victory.SCORE or not Victory.applies(state, e.id, id):
				continue
			var pct := Victory.visible_pct(state, viewer, e.id, id)
			if pct > int(best["pct"]):
				best = {"empire": e.id, "id": id, "pct": pct}
		out.append(best)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["pct"]) > int(b["pct"]) or (int(a["pct"]) == int(b["pct"]) and int(a["empire"]) < int(b["empire"])))
	return out


func _victory_line(name: String, name_color: Color, what: String, pct: int, fill_color: Color, tip: String) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	line.mouse_filter = Control.MOUSE_FILTER_STOP
	line.tooltip_text = tip
	var nl := Label.new()
	nl.text = name
	nl.custom_minimum_size = Vector2(230, 0)
	nl.clip_text = true
	nl.add_theme_color_override("font_color", name_color)
	line.add_child(nl)
	if what != "":
		var wl := Label.new()
		wl.text = what
		wl.custom_minimum_size = Vector2(250, 0)
		wl.clip_text = true
		line.add_child(wl)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(260, 8)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = 100
	bar.value = maxi(0, pct)
	bar.add_theme_stylebox_override("fill", UiTheme.box(fill_color, Color(0, 0, 0, 0), 0, 0))
	line.add_child(bar)
	var val := Label.new()
	val.theme_type_variation = &"Numbers"
	val.custom_minimum_size = Vector2(56, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val.text = "%d %%" % pct if pct >= 0 else "?"
	if pct >= Victory.met_at():
		val.add_theme_color_override("font_color", UiTheme.WARN)
	line.add_child(val)
	return line


## En tête de l'écran : qui est le plus près de gagner, et par quelle voie.
func _victory_ranking() -> Control:
	var blk := Widgets.Block.new("La course")
	var viewer := -1 if see_all else _player
	for r: Dictionary in victory_leaders(_state, viewer, _victory_empires()):
		var e := _state.get_empire(int(r["empire"]))
		var id := String(r["id"])
		var tip := "Rien de lisible : une victoire ne se voit chez un rival qu'à partir de %d %%." % Victory.visible_at()
		if id != "":
			tip = "%s\n%s" % [Victory.rule_text(id), "\n".join(Victory.progress(_state, e.id, id)["lines"])]
		blk.body.add_child(_victory_line(e.short_name() + (" (vous)" if e.id == _player and not see_all else ""), e.color().lightened(0.25),
				Victory.label(id) if id != "" else "voie inconnue", int(r["pct"]), e.color(), tip))
	return blk


## Vos propres voies, de la plus avancée à la moins avancée.
func _victory_paths() -> Control:
	var blk := Widgets.Block.new("Vos voies")
	var rows := []
	for id in Victory.ids():
		if id == Victory.SCORE or not Victory.applies(_state, _player, id):
			continue
		rows.append([int(Victory.progress(_state, _player, id)["pct"]), id])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) > int(b[0]) or (int(a[0]) == int(b[0]) and String(a[1]) < String(b[1])))
	var me := _state.get_empire(_player)
	for r: Array in rows:
		var id := String(r[1])
		blk.body.add_child(_victory_line(Victory.label(id), UiTheme.GOLD if Victory.is_people(id) else UiTheme.TEXT, "", int(r[0]), me.color(),
				"%s\n%s" % [Victory.rule_text(id), "\n".join(Victory.progress(_state, _player, id)["lines"])]))
	if Victory.enabled(_state, Victory.SCORE):
		blk.body.add_child(UiTheme.dim("À la date limite, le meilleur score l'emporte : le vôtre est de %d, le plus haut connu de %d." % [Victory.score(_state, _player), _best_score()], 13))
	return blk


## Une victoire de peuple ne s'affiche que si un empire connu peut la viser.
func _victory_relevant(id: String) -> bool:
	for e in _victory_empires():
		if Victory.applies(_state, e.id, id):
			return true
	return false


## Empires affichés : soi d'abord, puis ceux rencontrés (tous en spectateur).
func _victory_empires() -> Array[Empire]:
	var me := _state.get_empire(_player)
	var out: Array[Empire] = [me]
	for e in _state.empires:
		if e.id != _player and (see_all or me.contacts.has(e.id)):
			out.append(e)
	return out


func _victory_block(id: String) -> Widgets.Block:
	var blk := Widgets.Block.new(Victory.label(id))
	blk.custom_minimum_size = Vector2(430, 0)
	blk.heading.add_theme_font_size_override("font_size", 22)
	var rule := UiTheme.paragraph(Victory.rule_text(id), 400, 13)
	rule.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	blk.body.add_child(rule)
	var rows := {}
	var viewer := -1 if see_all else _player
	for e in _victory_empires():
		if not Victory.applies(_state, e.id, id):
			continue
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 10)
		line.mouse_filter = Control.MOUSE_FILTER_STOP
		var name := Label.new()
		name.text = e.short_name() + (" (disparu)" if e.eliminated else "")
		name.custom_minimum_size = Vector2(130, 0)
		name.add_theme_color_override("font_color", e.color().lightened(0.25))
		line.add_child(name)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(200, 8)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.max_value = 100
		var fill := UiTheme.box(e.color(), Color(0, 0, 0, 0), 0, 0)
		bar.add_theme_stylebox_override("fill", fill)
		line.add_child(bar)
		var val := Label.new()
		val.theme_type_variation = &"Numbers"
		val.custom_minimum_size = Vector2(60, 0)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		line.add_child(val)
		if id == Victory.SCORE:
			bar.max_value = maxi(1, _best_score())
			bar.value = Victory.score(_state, e.id)
			val.text = str(Victory.score(_state, e.id))
			line.tooltip_text = "\n".join(Victory.progress(_state, e.id, id)["lines"])
		else:
			var pct := Victory.visible_pct(_state, viewer, e.id, id) if not e.eliminated else 0
			if pct < 0:
				bar.value = 0
				val.text = "?"
				line.tooltip_text = "Cachée : on ne la voit qu'à partir de %d %%." % Victory.visible_at()
			else:
				bar.value = pct
				val.text = "%d %%" % pct
				if pct >= Victory.met_at():
					val.add_theme_color_override("font_color", Color(1.0, 0.55, 0.4) if e.id != _player else UiTheme.ACCENT)
				# Le détail se lit pour soi, pour le spectateur, et pour les rivaux une fois la victoire visible.
				line.tooltip_text = "\n".join(Victory.progress(_state, e.id, id)["lines"])
		blk.body.add_child(line)
		rows[e.id] = val
	if rows.is_empty():
		blk.body.add_child(UiTheme.dim("Aucun empire connu ne peut la viser.", 13))
	victory_rows[id] = rows
	return blk


func _best_score() -> int:
	var best := 1
	for e in _victory_empires():
		best = maxi(best, Victory.score(_state, e.id))
	return best


## Ce qui change l'écran Victoire : le mois (avancées recalculées), les contacts, le vainqueur.
func _victory_sig() -> String:
	var parts := PackedStringArray()
	@warning_ignore("integer_division")
	parts.append(str(_state.tick / 30))
	parts.append(str(_state.winner))
	for e in _state.empires:
		parts.append("%d:%s:%s" % [e.id, str(e.contacts), e.eliminated])
	return "|".join(parts)

