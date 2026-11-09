extends SceneTree
## Test de fumée du prototype, à lancer sans fenêtre :
##   godot --headless --path . -s res://tests/smoke_test.gd
## Code de sortie 0 si tout passe, 1 sinon.

const SEEDS := [0, 1, 42, 1337, 987654321, -5, 2147483647]

var _failures := 0
var _checks := 0


func _initialize() -> void:
	_test_generator()
	preload("res://tests/sim_tests.gd").new().run(_check)
	preload("res://tests/economy_tests.gd").new().run(_check)
	preload("res://tests/fleet_tests.gd").new().run(_check)
	preload("res://tests/faction_tests.gd").new().run(_check)
	_test_clock()
	_test_empire_report()
	await _test_main_scene()
	print("")
	if _failures == 0:
		print("OK : %d vérifications passées." % _checks)
	else:
		printerr("ÉCHEC : %d vérification(s) sur %d." % [_failures, _checks])
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		printerr("  ✗ ", what)


func _test_generator() -> void:
	print("Génération de galaxies…")
	for seed_value in SEEDS:
		var g := GalaxyGenerator.generate(seed_value, 150, 1800.0)
		_check(g.systems.size() == 150, "graine %d : 150 systèmes (obtenu %d)" % [seed_value, g.systems.size()])
		_check(_is_connected(g), "graine %d : galaxie entièrement connectée" % seed_value)
		_check(g.lanes.size() >= g.systems.size() - 1, "graine %d : au moins n-1 routes" % seed_value)
		var names := {}
		for s in g.systems:
			names[s.system_name] = true
			_check(s.neighbors.size() > 0, "graine %d : système %d isolé" % [seed_value, s.id])
		_check(names.size() == g.systems.size(), "graine %d : noms uniques" % seed_value)
		var lane_set := {}
		for l in g.lanes:
			_check(l.x < l.y, "graine %d : route %s ordonnée" % [seed_value, l])
			_check(not lane_set.has(l), "graine %d : route %s en double" % [seed_value, l])
			lane_set[l] = true
		# Même graine = même galaxie (indispensable pour le multijoueur et les sauvegardes).
		var g2 := GalaxyGenerator.generate(seed_value, 150, 1800.0)
		_check(_same_galaxy(g, g2), "graine %d : génération déterministe" % seed_value)
		print("  graine %d : %d systèmes, %d routes" % [seed_value, g.systems.size(), g.lanes.size()])


func _is_connected(g: Galaxy) -> bool:
	if g.systems.is_empty():
		return true
	var seen := {0: true}
	var stack: Array[int] = [0]
	while not stack.is_empty():
		var id: int = stack.pop_back()
		for n in g.systems[id].neighbors:
			if not seen.has(n):
				seen[n] = true
				stack.append(n)
	return seen.size() == g.systems.size()


func _same_galaxy(a: Galaxy, b: Galaxy) -> bool:
	if a.systems.size() != b.systems.size() or a.lanes != b.lanes:
		return false
	for i in a.systems.size():
		var sa := a.systems[i]
		var sb := b.systems[i]
		if sa.position != sb.position or sa.system_name != sb.system_name \
				or sa.star_type != sb.star_type or sa.planet_count != sb.planet_count:
			return false
	return true


func _test_clock() -> void:
	print("Horloge…")
	var clock: Node = root.get_node("GameClock")
	var sim := Simulation.new(GameState.create(11))
	clock.attach(sim)
	_check(clock.paused, "l'horloge démarre en pause")
	_check(clock.date_string() == "01/01/2400", "date initiale (obtenu %s)" % clock.date_string())
	clock._process(5.0)
	_check(clock.day == 0, "aucun jour ne passe en pause")
	sim.submit(SimCommands.rename_system(0, 1, "Arrêt-sur-Image"))
	clock._process(0.016)
	_check(sim.state.galaxy.systems[1].system_name == "Arrêt-sur-Image", "un ordre donné en pause s'applique")
	_check(clock.day == 0, "toujours aucun jour écoulé")
	clock.set_paused(false)
	clock.set_speed(0)
	clock._process(1.0)
	_check(clock.day == 1 and sim.state.tick == 1, "vitesse 1 : 1 jour par seconde (obtenu %d)" % clock.day)
	clock.set_speed(4)
	clock._process(10.0)
	_check(clock.day == 1 + clock.MAX_DAYS_PER_FRAME, "plafond de jours par image respecté")
	clock.set_speed(99)
	_check(clock.speed_index == 4, "vitesse bornée")
	_check(GameCalendar.date_string(360 + 30 * 2 + 4) == "05/03/2401", "format de date (obtenu %s)" % GameCalendar.date_string(364))

	# Tour par tour : le temps ne passe qu'à la fin du tour, puis s'arrête au tour suivant.
	var turns := Simulation.new(GameState.create(11))
	clock.attach(turns)
	clock.set_mode(clock.MODE_TURNS, 10)
	_check(clock.is_turn_based() and clock.paused and clock.turn() == 1, "tour par tour : tour 1, arrêté")
	clock.set_paused(false)
	clock._process(5.0)
	_check(clock.paused and clock.day == 0, "tour par tour : reprendre ne lance pas de tour")
	turns.submit(SimCommands.rename_system(0, 2, "Tour-Un"))
	clock._process(0.016)
	_check(turns.state.galaxy.systems[2].system_name == "Tour-Un", "tour par tour : les ordres s'appliquent pendant le tour")
	clock.toggle_pause()
	_check(clock.is_resolving_turn() and not clock.paused, "Espace / centre du cadran : fin de tour")
	_check(not clock.end_turn(), "pas de deuxième fin de tour pendant la résolution")
	clock.set_paused(true)
	clock._process(5.0)
	_check(clock.is_resolving_turn() and clock.day == 0, "un menu peut suspendre la résolution du tour")
	clock.set_paused(false)
	var turn_seen := [0]
	clock.turn_started.connect(func(t: int) -> void: turn_seen[0] = t, CONNECT_ONE_SHOT)
	for _i in 20:
		clock._process(0.5)
	_check(clock.day == 10 and clock.paused and not clock.is_resolving_turn(), "le tour fait 10 jours puis s'arrête (jour %d)" % clock.day)
	_check(turn_seen[0] == 2 and clock.turn() == 2, "signal de début du tour 2")
	clock._process(5.0)
	_check(clock.day == 10, "rien ne bouge entre deux tours")
	_check(clock.settings() == {"mode": "turns", "turn_days": 10}, "réglages du mode pour la sauvegarde")
	clock.apply_settings({})
	_check(not clock.is_turn_based(), "sauvegarde sans réglage : temps réel")
	clock.apply_settings({"mode": "turns", "turn_days": 30})
	_check(clock.is_turn_based() and clock.turn_days == 30 and clock.turn() == 1, "réglages relus : 30 jours par tour")
	clock.set_mode(clock.MODE_REALTIME)
	clock.attach(null)
	_check(clock.day == 0, "horloge détachée")


func _test_main_scene() -> void:
	print("Scène principale…")
	var scene: PackedScene = load("res://scenes/main.tscn")
	_check(scene != null, "main.tscn se charge")
	var main := scene.instantiate()
	main.save_path = "user://saves/test_quicksave.json"  # ne jamais toucher la vraie sauvegarde du joueur
	main.start_with_menu = false
	root.add_child(main)
	for _i in 10:
		await process_frame
	_check(main.galaxy != null and main.galaxy.systems.size() == main.SYSTEM_COUNT, "galaxie créée au lancement")
	_check(root.theme == UiTheme.theme() and main._hud.bar.theme == UiTheme.theme() and main._pause_menu.get_child(0).theme == UiTheme.theme(),
			"le thème de l'interface est appliqué à la fenêtre et aux calques")
	await _test_fleet_ui(main)
	# La suite parcourt toute la carte : on lève le brouillard pour le joueur.
	_reveal_map(main)
	await _test_colony_ui(main)
	await _test_navigation_ui(main)
	_reveal_map(main)  # le menu principal a lancé une nouvelle partie

	var clock: Node = root.get_node("GameClock")
	_press(KEY_SPACE)
	_check(not clock.paused, "Espace enlève la pause")
	_press(KEY_3, KEY_3)
	_check(clock.speed_index == 2, "touche 3 : vitesse 3")
	for _i in 30:
		await process_frame
	_press(KEY_SPACE)
	_check(clock.paused, "Espace remet la pause")

	# Clic sur un système : il doit être sélectionné.
	var target: StarSystem = main.galaxy.systems[0]
	main._camera.position = target.position
	await process_frame
	await process_frame
	# En mode sans fenêtre, l'écran fait 64x64 pixels : la barre d'empire le recouvrirait entièrement.
	main._hud.visible = false
	var screen_pos: Vector2 = main.get_viewport().get_visible_rect().size * 0.5
	var motion := InputEventMouseMotion.new()
	motion.position = screen_pos
	motion.global_position = screen_pos
	root.push_input(motion)
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.position = screen_pos
	click.global_position = screen_pos
	click.pressed = true
	root.push_input(click)
	await process_frame
	_check(main._view.selected_id == target.id, "clic gauche : le système sous le curseur est sélectionné (obtenu %d)" % main._view.selected_id)
	main._hud.visible = true
	_check(main._hud._info_panel.visible, "la fiche du système s'affiche")
	_press(KEY_ESCAPE)
	_check(main._view.selected_id == -1, "Échap désélectionne")

	# Renommage depuis la vue système : passe par un ordre de simulation.
	main.open_system_view(5)
	main._system_screen._toggle_rename()
	main._system_screen._rename_edit.text = "Port-Libre"
	main._system_screen.submit_rename()
	await process_frame
	await process_frame
	_check(main.galaxy.systems[5].system_name == "Port-Libre", "renommer depuis la vue système (obtenu %s)" % main.galaxy.systems[5].system_name)
	_check(main.simulation.command_log.back()["type"] == "rename_system", "le renommage est un ordre journalisé")
	_check(main._system_screen._title.text == "Port-Libre", "l'en-tête de la vue système suit le nouveau nom")
	main.close_system_view()

	# F5 sauvegarde, F9 recharge exactement la même partie.
	_press(KEY_F5)
	var saved_checksum: String = main.simulation.state.checksum()
	var saved_tick: int = main.simulation.state.tick
	_press(KEY_SPACE)
	for _i in 40:
		await process_frame
	_press(KEY_SPACE)
	main.simulation.submit(SimCommands.rename_system(0, 5, "Autre-Nom"))
	main.simulation.flush_commands()
	_press(KEY_F9)
	_check(main.simulation.state.tick == saved_tick, "F9 : retour au jour sauvegardé")
	_check(main.simulation.state.checksum() == saved_checksum, "F9 : partie rechargée à l'identique")
	_check(main.galaxy.systems[5].system_name == "Port-Libre", "F9 : le nom sauvegardé revient")
	_check(clock.paused and clock.simulation == main.simulation, "F9 : l'horloge suit la partie chargée, en pause")
	_check(main._view.galaxy == main.galaxy, "F9 : la vue affiche la partie chargée")

	var old_seed: int = main.galaxy.seed_value
	main.new_game(old_seed + 1)
	_check(main.galaxy.seed_value == old_seed + 1 and main.galaxy.systems.size() == main.SYSTEM_COUNT, "nouvelle galaxie")
	for _i in 10:
		await process_frame
	DirAccess.remove_absolute(main.save_path)
	main.queue_free()
	await process_frame


## Au lancement : caméra et fiche sur le système d'origine ; vue système, colonisation et construction.
## Flottes à l'écran : brouillard, sélection, ordres au clic droit, fiche de flotte, chantier spatial.
func _test_fleet_ui(main: Node) -> void:
	var st: GameState = main.simulation.state
	var me := st.get_empire(0)
	var home := st.galaxy.get_planet(me.capital_planet).system_id
	var scout: Fleet = null
	var colonist: Fleet = null
	for f in Fleets.empire_fleets(st, 0):
		if f.count("scout") > 0:
			scout = f
		elif f.count("colony_ship") > 0:
			colonist = f
	_check(scout != null and colonist != null, "flottes de départ présentes à l'écran")
	var frontier := -1
	var unknown := -1
	for sys in st.galaxy.systems:
		if frontier == -1 and not Fleets.is_explored(st, 0, sys.id) and Fleets.is_known(st, 0, sys.id):
			frontier = sys.id
		if unknown == -1 and not Fleets.is_known(st, 0, sys.id):
			unknown = sys.id
	_check(main._view.pick_system(st.galaxy.systems[unknown].position, 5.0) == -1, "un système hors des cartes ne se sélectionne pas")
	_check(main._view.pick_system(st.galaxy.systems[frontier].position, 5.0) == frontier, "un système repéré se sélectionne")
	main.open_system_view(frontier)
	_check(not main.is_system_view_open() and Array(main._hud.toast_texts()).any(func(t: String) -> bool: return t.contains("inexploré")),
			"pas de vue système pour un système inexploré")
	main._select(frontier)
	_check(main._hud._card_title.text == "Système inexploré" and not main._hud._enter_button.visible, "fiche d'un système inexploré")
	main._select(-1)

	# Sélection et fiche de flotte.
	var at: Vector2 = main._view.fleet_world_position(scout.id)
	_check(main._view.pick_fleet(at, 4.0) == scout.id, "la flotte se sélectionne à sa position à l'écran")
	_check(main._view.fleet_world_position(colonist.id) != at, "deux flottes au même système ne se recouvrent pas")
	main.select_fleet(scout.id)
	_check(main._hud.fleet_card_visible() and main._hud._fleet_title.text == scout.fleet_name, "fiche de la flotte affichée")
	_check(main._hud.fleet_button("stop").disabled and main._hud.fleet_button("split").disabled and not main._hud.fleet_button("colonize").visible,
			"boutons de la fiche selon la flotte (éclaireur à l'arrêt)")
	main.order_fleet_to(frontier)
	await process_frame
	await process_frame
	_check(scout.is_moving() and scout.destination() == frontier, "ordre de déplacement donné depuis l'interface")
	_check(Array(main._hud.toast_texts()).any(func(t: String) -> bool: return t.contains("cap sur")), "la notification annonce le trajet")
	main._hud.refresh()
	_check(main._hud._fleet_status.text.begins_with("En route") and not main._hud.fleet_button("stop").disabled, "fiche : en route, bouton Arrêter actif")
	main._hud.fleet_button("stop").pressed.emit()
	await process_frame
	await process_frame
	_check(scout.path.size() == 1, "Arrêter : la flotte s'arrête au prochain système")

	# Clic droit sur un système voisin : la flotte y part. (Écran de 64x64 en mode sans fenêtre.)
	main.select_fleet(colonist.id)
	var dest: int = st.galaxy.systems[home].neighbors[0]
	main._camera.position = st.galaxy.systems[dest].position
	main._hud.visible = false
	await process_frame
	var center: Vector2 = main.get_viewport().get_visible_rect().size * 0.5
	for pressed in [true, false]:
		var rc := InputEventMouseButton.new()
		rc.button_index = MOUSE_BUTTON_RIGHT
		rc.position = center
		rc.global_position = center
		rc.pressed = pressed
		root.push_input(rc)
	await process_frame
	await process_frame
	main._hud.visible = true
	_check(colonist.is_moving() and colonist.destination() == dest, "clic droit : la flotte sélectionnée part vers le système visé")
	main.order_fleet_to(home)
	await process_frame
	await process_frame
	_check(colonist.system_id == home or colonist.destination() == home, "contre-ordre : retour au système d'origine")

	# F : flotte suivante ; Échap : désélection.
	main.select_fleet(-1)
	_press(KEY_F)
	await process_frame
	_check(main.selected_fleet == scout.id, "F sélectionne la première flotte")
	_press(KEY_F)
	await process_frame
	_check(main.selected_fleet == colonist.id, "F passe à la flotte suivante")
	_press(KEY_ESCAPE)
	await process_frame
	_check(main.selected_fleet == -1 and not main._hud.fleet_card_visible(), "Échap désélectionne la flotte")

	# Liste des flottes, flottes inactives, exploration auto (ergonomie à la Endless Space 2).
	var hud: Hud = main._hud
	hud.refresh()
	_check(hud.fleet_list.visible and hud.fleet_list.row_count() == Fleets.empire_fleets(st, 0).size(), "liste des flottes : une ligne par flotte")
	hud.fleet_list.row_button(colonist.id).pressed.emit()
	await process_frame
	_check(main.selected_fleet == colonist.id and hud.fleet_list.row_button(colonist.id).button_pressed, "clic sur une ligne : la flotte est sélectionnée")
	main.select_fleet(scout.id)
	_check(hud.fleet_button("explore").visible and not hud.fleet_button("explore").disabled, "bouton d'exploration auto sur la fiche")
	_press(KEY_E, KEY_E)
	await process_frame
	await process_frame
	_check(scout.is_exploring() and scout.is_moving(), "E : exploration automatique lancée")
	hud.refresh()
	_check(hud.fleet_list.row_status(scout.id) == "EXPLORATION AUTO" and hud.fleet_button("explore").button_pressed, "liste et fiche montrent l'exploration")
	_check(hud._fleet_status.text.begins_with("Exploration automatique"), "fiche : état de l'exploration")
	if colonist.is_moving():
		main.simulation.submit(SimCommands.stop_fleet(0, colonist.id))
		main.simulation.flush_commands()
		for _d in 60:
			if not colonist.is_moving():
				break
			main.simulation.step()
	hud.refresh()
	_check(hud.idle_button.visible and hud.idle_button.text.begins_with("1 FLOTTE"), "rappel des flottes inactives (obtenu %s)" % hud.idle_button.text)
	main.select_fleet(-1)
	_press(KEY_I, KEY_I)
	await process_frame
	_check(main.selected_fleet == colonist.id, "I : sélectionne la flotte qui attend des ordres")
	main.select_fleet(scout.id)
	hud.fleet_button("explore").pressed.emit()
	await process_frame
	await process_frame
	_check(not scout.is_exploring(), "le bouton coupe l'exploration auto")
	main.select_fleet(-1)

	# Chantier spatial depuis la vue système.
	main.open_system_view(home, me.capital_planet)
	var screen: SystemScreen = main._system_screen
	var b := screen.find_action("Chantier spatial : Éclaireur")
	_check(b != null and not b.disabled, "bouton du chantier spatial actif sur la capitale")
	if b:
		b.pressed.emit()
	await process_frame
	await process_frame
	_check(st.colonies[me.capital_planet].ship_build == "scout", "éclaireur mis en chantier depuis la vue système")
	_check(screen.find_action("Chantier spatial : Vaisseau colon").disabled, "un seul vaisseau à la fois par chantier")
	main.close_system_view()
	# On rend l'état de départ aux tests suivants (qui vérifient les stocks initiaux).
	st.colonies[me.capital_planet].ship_build = ""
	me.resources["materials"] += int(GameData.ship("scout")["cost"]["materials"])
	main._refresh_all()


func _test_colony_ui(main: Node) -> void:
	var st: GameState = main.simulation.state
	var me: Empire = st.get_empire(main.LOCAL_PLAYER)
	var screen: SystemScreen = main._system_screen
	_check(me.faction_id == main.player_faction, "le joueur joue sa faction (%s)" % me.faction_id)
	var home_sys: int = main.galaxy.get_planet(me.capital_planet).system_id
	_check(main._view.selected_id == home_sys, "le système d'origine est sélectionné au lancement")
	main._hud.show_hover(null, Vector2.ZERO)  # la souris peut tomber sur une étoile dans la petite fenêtre de test
	_check(main._hud._info_panel.visible and main._hud.planet_row_count() == main.galaxy.systems[home_sys].planet_count,
			"la fiche résume les planètes du système d'origine")
	_check(main._hud.bar.resource_text().contains("Matériaux 200"), "la barre d'empire affiche les ressources (%s)" % main._hud.bar.resource_text())
	_check(not screen.visible, "la vue système est fermée au lancement")

	# Entrée ouvre la vue système du système sélectionné, sur la capitale.
	_press(KEY_ENTER)
	await process_frame
	_check(main.is_system_view_open() and screen.system_id == home_sys, "Entrée ouvre la vue système")
	_check(not main._hud._info_panel.visible and not main._view.visible, "la carte et sa fiche s'effacent")
	_check(screen.planet_id == me.capital_planet, "la capitale est choisie d'office")
	_check(screen._cards.get_child_count() == main.galaxy.systems[home_sys].planet_count, "une carte par planète dans le bandeau")
	_check(screen.view._bodies.size() == main.galaxy.systems[home_sys].planet_count, "chaque planète est dessinée en orbite")

	# Construire depuis la fiche de la planète.
	var farm := screen.find_action("Construire : Fermes hydroponiques")
	_check(farm != null and not farm.disabled, "la ferme est proposée et disponible")
	if farm:
		farm.pressed.emit()
	for _i in 3:
		await process_frame
	var home: Colony = st.colonies[me.capital_planet]
	_check(home.construction == "ferme_hydroponique", "construire depuis la vue système lance un chantier")
	farm = screen.find_action("Construire : Fermes hydroponiques")
	_check(farm != null and farm.disabled and farm.tooltip_text.contains("chantier"), "un second chantier est refusé, avec la raison")

	# Clic sur une autre planète du bandeau : la fiche change.
	if main.galaxy.systems[home_sys].planet_count > 1:
		var other: int = screen._card_ids[0] if screen._card_ids[0] != me.capital_planet else screen._card_ids[1]
		(screen._cards.get_child(screen._card_ids.find(other)) as Button).pressed.emit()
		_check(screen.planet_id == other and screen.view.selected_planet == other, "choisir une planète dans le bandeau")
	# Tab bascule sur la vue de gestion (planètes alignées) et revient.
	_press(KEY_TAB)
	await process_frame
	_check(screen.manage_mode and screen.manage.visible and not screen.view.show_scene, "Tab : vue de gestion")
	_check(screen.manage._columns.size() == main.galaxy.systems[home_sys].planet_count, "une colonne par planète en gestion")
	var home_col: Dictionary = screen.manage._columns[me.capital_planet]
	_check((home_col["status"] as Label).text.begins_with("Colonisée"), "la capitale est « Colonisée » (obtenu %s)" % (home_col["status"] as Label).text)
	_check((home_col["yields"]["food"]["value"] as Label).visible, "rendements réels affichés pour sa propre planète")
	_check(main._hud._tab_manage.button_pressed and not main._hud._tab_orbit.button_pressed, "l'onglet Gestion suit la vue")
	main._hud._tab_orbit.pressed.emit()
	await process_frame
	_check(not screen.manage_mode and screen.view.show_scene, "onglet Vue orbitale : retour à la vue orbitale")
	_press(KEY_TAB)
	_press(KEY_TAB)
	await process_frame
	_check(not screen.manage_mode and screen.view.show_scene, "Tab : retour à la vue orbitale")
	_press(KEY_ESCAPE)
	await process_frame
	_check(not main.is_system_view_open() and main._view.visible and main._view.selected_id == home_sys,
			"Échap revient à la galaxie, système toujours sélectionné")

	# Coloniser depuis la vue d'un système voisin.
	var target := -1
	for n in main.galaxy.systems[home_sys].neighbors:
		for pid in main.galaxy.systems[n].planet_ids:
			if target == -1 and Economy.check_colonize(st, 0, pid, Colony.KIND_OUTPOST) == "":
				target = pid
	if target == -1:
		for pid in main.galaxy.systems[home_sys].planet_ids:
			if target == -1 and Economy.check_colonize(st, 0, pid, Colony.KIND_OUTPOST) == "":
				target = pid
	_check(target != -1, "une planète à revendiquer près du système d'origine")
	if target != -1:
		main.open_system_view(main.galaxy.get_planet(target).system_id)
		screen.view.planet_clicked.emit(target)
		var button := screen.find_action("Poser un avant-poste")
		_check(button != null and not button.disabled, "bouton Avant-poste actif")
		if button:
			button.pressed.emit()
		for _i in 3:
			await process_frame
		_check(st.colonies.has(target) and st.colonies[target].kind == Colony.KIND_OUTPOST, "avant-poste lancé depuis la vue système")
		_check(screen.find_action("Poser un avant-poste") == null, "la fiche se met à jour après l'ordre")
		main.close_system_view()
	var far := -1
	for p in st.galaxy.planets:
		if far == -1 and st.system_owner(p.system_id) == -1 and not Economy.in_range(st, 0, p.system_id):
			far = p.id
	main.open_system_view(main.galaxy.get_planet(far).system_id)
	screen.select_planet(far)
	var far_button := screen.find_action("Poser un avant-poste")
	_check(far_button != null and far_button.disabled and far_button.tooltip_text.contains("portée"), "hors de portée : bouton grisé avec la raison")
	main.close_system_view()
	main._select(-1)
	_test_system_view_picking(st)


## Bilans d'empire (lecture seule) : mêmes chiffres que la simulation, navigation entre systèmes.
func _test_empire_report() -> void:
	print("Bilans d'empire…")
	var st := GameState.create(77, 150, 1800.0, "vael")
	var me := st.get_empire(0)
	var checksum := st.checksum()
	var res := EmpireReport.resources(st, 0)
	var income := Economy.empire_income(st, 0)
	_check(res.size() == GameData.resource_ids().size(), "une ligne par ressource")
	var ok := true
	for r in res:
		if r["stock"] != me.resources[r["id"]] or r["net"] != income["net"][r["id"]] or r["net"] != r["gross"] - r["upkeep"]:
			ok = false
	_check(ok, "stock, production, entretien et bilan cohérents avec la simulation")
	var influence: Dictionary = res[GameData.resource_ids().find("influence")]
	_check(influence["bonus_pct"] == 50, "bonus de faction de Vael sur l'influence (obtenu %d)" % influence["bonus_pct"])
	var home := st.galaxy.get_planet(me.capital_planet).system_id
	var cols := EmpireReport.colonies(st, 0)
	_check(cols.size() == 1 and cols[0]["capital"] and cols[0]["population"] > 0, "la capitale est la seule colonie au départ")
	var t := EmpireReport.totals(st, 0)
	_check(t["colonies"] == 1 and t["outposts"] == 0 and t["systems"] == 1, "chiffres clés de départ")
	_check(EmpireReport.owned_systems(st, 0) == [home], "un seul système possédé : celui d'origine")
	# Un avant-poste dans un système voisin ajoute un système à parcourir avec Tab.
	# (On y pose directement le vaisseau colon de départ, sans attendre le trajet.)
	var target := -1
	var ship := Fleets.colonizer_fleet(st, 0, home)
	for n in st.galaxy.systems[home].neighbors:
		if target == -1:
			ship.system_id = n
		for pid in st.galaxy.systems[n].planet_ids:
			if target == -1 and Economy.check_colonize(st, 0, pid, Colony.KIND_OUTPOST) == "":
				target = pid
	var other := st.galaxy.get_planet(target).system_id
	ship.system_id = other
	var sim := Simulation.new(st)
	sim.submit(SimCommands.colonize(0, target, Colony.KIND_OUTPOST))
	sim.flush_commands()
	_check(EmpireReport.owned_systems(st, 0) == [home, other], "le système de l'avant-poste suit celui d'origine")
	_check(EmpireReport.totals(st, 0)["founding"] == 1, "la fondation en cours est comptée")
	_check(EmpireReport.cycle_system(st, 0, home, 1) == other and EmpireReport.cycle_system(st, 0, other, 1) == home,
			"système suivant, en boucle")
	_check(EmpireReport.cycle_system(st, 0, home, -1) == other, "système précédent, en boucle")
	_check(EmpireReport.cycle_system(st, 0, -1, 1) == home, "sans sélection : on part du système d'origine")
	_check(EmpireReport.cycle_system(st, 3, -1, 1) != -1, "les autres empires ont aussi leur système")
	_check(EmpireReport.cycle_system(st, 9, -1, 1) == -1, "empire inconnu : aucun système")
	var checksum_after := st.checksum()
	EmpireReport.resources(st, 0)
	EmpireReport.colonies(st, 0)
	EmpireReport.totals(st, 0)
	_check(st.checksum() == checksum_after and checksum != "", "les bilans ne modifient pas la partie")


## Barre d'empire, menus d'empire, menu pause, menu principal, raccourcis de navigation.
func _test_navigation_ui(main: Node) -> void:
	var st: GameState = main.simulation.state
	var me: Empire = st.get_empire(main.LOCAL_PLAYER)
	var clock: Node = root.get_node("GameClock")
	var hud: Hud = main._hud
	var screens: EmpireScreens = main._empire_screens
	var home_sys: int = main.galaxy.get_planet(me.capital_planet).system_id
	main._select(-1)

	# Menus d'empire.
	_press(KEY_F1)
	await process_frame
	_check(screens.is_open() and screens.current == "economy", "F1 ouvre l'économie")
	_check(hud.bar.screen_button("economy").button_pressed, "le bouton Économie de la barre est mis en évidence")
	var row := screens.economy_row_text("materials")
	_check(row.begins_with("Matériaux|%d|" % me.resources["materials"]), "ligne des matériaux (%s)" % row)
	_check(not main._camera.is_processing_unhandled_input(), "la carte ne réagit plus sous un menu d'empire")
	_press(KEY_F2)
	await process_frame
	_check(screens.current == "colonies", "F2 passe aux colonies")
	var rows := screens.colony_buttons()
	_check(rows.size() == EmpireReport.colonies(st, 0).size() and rows.size() >= 2, "une ligne par colonie ou avant-poste (%d)" % rows.size())
	_press(KEY_F2)
	_check(not screens.is_open() and not hud.bar.screen_button("colonies").button_pressed, "F2 referme les colonies")
	_check(main._camera.is_processing_unhandled_input(), "la carte reprend la main")
	main.toggle_empire_screen("colonies")
	await process_frame
	var second: int = screens._col_rows[1]["pid"]
	screens.colony_buttons()[1].pressed.emit()
	_check(screens.selected_planet == second and screens.colony_buttons()[1].button_pressed, "clic sur une colonie : elle est choisie")
	_check(screens._pick_title.text == main.galaxy.get_planet(second).display_name(main.galaxy).to_upper(), "la fiche de la colonie choisie suit")
	screens.set_colony_filter("outpost")
	var outposts := 0
	for c in EmpireReport.colonies(st, 0):
		if c["established"] and c["kind"] != Colony.KIND_COLONY:
			outposts += 1
	_check(screens.colony_buttons().size() == outposts, "filtre Avant-postes (%d)" % outposts)
	screens.set_colony_filter("all")
	screens.select_colony(me.capital_planet)
	screens._pick_open.pressed.emit()
	await process_frame
	_check(not screens.is_open() and main.is_system_view_open() and main._system_screen.planet_id == me.capital_planet,
			"Ouvrir la vue système depuis la colonie choisie")
	main.close_system_view()
	_press(KEY_F3)
	await process_frame
	_check(screens.is_open() and screens.current == "research" and screens._tab.text.begins_with("RECHERCHE"), "F3 : écran Recherche (en attente)")
	_press(KEY_F4)
	await process_frame
	_check(screens.current == "diplomacy" and screens._content.get_child(0) != null, "F4 : écran Diplomatie (en attente)")
	_check(not hud._tabs.visible and hud.bar.visible and hud.dial.visible, "écran d'empire : onglets de vue masqués, panneau et cadran restent")
	_press(KEY_F4)
	_check(not screens.is_open() and hud._tabs.visible, "F4 referme, les onglets reviennent")
	main.toggle_empire_screen("economy")
	await process_frame
	_check(screens._sys_list.get_child_count() == EmpireReport.owned_systems(st, 0).size(), "une ligne par système dans l'économie")
	_check(screens._donut.center_value != "" and screens._donut.parts.size() == GameData.resource_ids().size(), "anneau de répartition rempli")
	main.toggle_empire_screen("economy")
	_press(KEY_ESCAPE)
	_check(not screens.is_open(), "Échap ferme le menu d'empire")

	# Pause automatique (réglage local, jamais enregistré ici).
	UiSettings.auto_pause_menus = true
	clock.set_paused(false)
	main.toggle_empire_screen("economy")
	_check(clock.paused, "pause automatique à l'ouverture d'un menu d'empire")
	main.close_empire_screen()
	_check(not clock.paused, "le temps repart à la fermeture")
	UiSettings.auto_pause_menus = false
	clock.set_paused(true)

	# Navigation entre les systèmes de l'empire.
	var owned := EmpireReport.owned_systems(st, 0)
	main._select(-1)
	_press(KEY_TAB)
	_check(main._view.selected_id == owned[0], "Tab sans sélection : système d'origine")
	_press(KEY_TAB)
	_check(main._view.selected_id == owned[1 % owned.size()], "Tab : système suivant de l'empire")
	var ev := InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.physical_keycode = KEY_TAB
	ev.shift_pressed = true
	ev.pressed = true
	root.push_input(ev)
	_check(main._view.selected_id == owned[0], "Maj+Tab : système précédent")
	main._select(owned[owned.size() - 1])
	_press(KEY_H, KEY_H)
	_check(main._view.selected_id == home_sys, "H : retour à la capitale")
	main.open_system_view(home_sys)
	var screen: SystemScreen = main._system_screen
	var first: int = screen.planet_id
	_press(KEY_RIGHT)
	_check(screen.planet_id != first or main.galaxy.systems[home_sys].planet_count == 1, "flèche droite : planète suivante")
	_press(KEY_LEFT)
	_check(screen.planet_id == first, "flèche gauche : planète précédente")
	if owned.size() > 1:
		_press(KEY_PAGEDOWN)
		_check(main.is_system_view_open() and screen.system_id == owned[1], "Page suiv. dans la vue système : système suivant")
		screen.cycle_requested.emit(-1)
		_check(screen.system_id == home_sys, "bouton système précédent de la vue système")
	main.close_system_view()

	# Survol : la fiche montre le système survolé, puis revient à la sélection.
	main._select(-1)
	hud.show_hover(main.galaxy.systems[home_sys], Vector2(10, 10))
	_check(hud._info_panel.visible and hud.card_system() == home_sys and hud._card_title.text == main.galaxy.systems[home_sys].system_name,
			"la fiche montre le système survolé")
	_check(not hud._enter_button.visible, "pas de bouton d'entrée pour un simple survol")
	hud.show_hover(null, Vector2.ZERO)
	_check(not hud._info_panel.visible, "fin du survol sans sélection : la fiche se cache")

	# Lentille économique (touche L).
	_press(KEY_L, KEY_L)
	_check(hud.lens == "economy" and main._view.lens == "economy", "L active la lentille économique")
	var net := EmpireReport.system_net(st, 0, home_sys)
	_check(int(net["food"]) != 0 or int(net["materials"]) != 0, "la lentille a un bilan à montrer pour le système d'origine")
	_press(KEY_L, KEY_L)
	_check(hud.lens == "" and main._view.lens == "", "L la désactive")

	# Cadran du temps : le centre met en pause, les crans règlent la vitesse.
	var dial: TimeDial = hud.dial
	clock.set_paused(true)
	dial.pause_toggled.emit()
	_check(not clock.paused, "cadran : le centre relance le temps")
	dial.speed_requested.emit(3)
	_check(clock.speed_index == 3, "cadran : cran de vitesse 4")
	clock.set_paused(true)
	# Au tour par tour, le centre du cadran termine le tour.
	clock.set_mode(clock.MODE_TURNS, 5)
	var d0: int = clock.day
	dial.pause_toggled.emit()
	_check(clock.is_resolving_turn(), "cadran au tour par tour : fin de tour")
	dial.speed_requested.emit(0)
	for _i in 60:
		await process_frame
	_check(clock.day > d0, "le tour avance en jeu (jour %d → %d)" % [d0, clock.day])
	clock.set_mode(clock.MODE_REALTIME)

	# Onglet « Gestion du système » : le referme.
	main.open_system_view(home_sys)
	hud._tab_galaxy.pressed.emit()
	_check(not main.is_system_view_open(), "l'onglet de la vue système la referme")

	# Menu pause : Échap sans sélection, le temps s'arrête puis reprend comme avant.
	main._select(-1)
	clock.set_paused(false)
	_press(KEY_ESCAPE)
	_check(main._pause_menu.is_open() and clock.paused, "Échap sans sélection : menu pause, jeu en pause")
	_press(KEY_SPACE)
	_check(clock.paused, "Espace ne relance pas le temps sous le menu pause")
	main._pause_menu.show_page("confirm_quit")
	_check(main._pause_menu._confirm.visible and not main._pause_menu._home.visible, "Quitter demande confirmation")
	main._pause_menu.show_page("shortcuts")
	_press(KEY_ESCAPE)
	_check(main._pause_menu.is_open() and main._pause_menu.page == "home", "Échap revient à l'accueil du menu pause")
	_press(KEY_ESCAPE)
	_check(not main._pause_menu.is_open() and not clock.paused, "Échap referme le menu pause et le temps reprend")
	clock.set_paused(true)

	# Menu principal : reprendre, puis nouvelle partie avec une autre faction et une graine choisie.
	main.open_main_menu()
	await process_frame
	var menu: MainMenu = main._main_menu
	_check(menu.is_open() and not hud.visible and menu._resume.visible, "menu principal : la partie en cours peut reprendre")
	_check(not menu._continue.visible and menu._items.size() == 5, "accueil : Reprendre remplace Continuer")
	menu._layout_home()
	var geo: Array = menu._planet_geometry()
	var orbit_r: float = geo[1] + geo[2].y * 0.09
	var orbit_ok := true
	for it in menu._items:
		var pin: Vector2 = it.position + Vector2(it.DIAMETER * 0.5 + 2.0, it.size.y * 0.5)
		if it.visible and absf(pin.distance_to(geo[0]) - orbit_r) > 1.0:
			orbit_ok = false
	_check(orbit_ok, "les entrées sont posées sur l'orbite de la planète")
	menu.show_page("options")
	menu._options.show_tab("controls")
	_check(menu._options_page.visible and menu._options._pages["controls"].visible and not menu._options._pages["display"].visible, "options : onglet Commandes")
	var was_auto := UiSettings.auto_pause_menus
	menu._options._auto_pause.pressed.emit()
	_check(UiSettings.auto_pause_menus != was_auto and menu._options._auto_pause.text == ("Activé" if UiSettings.auto_pause_menus else "Désactivé"), "options : la case suit le réglage")
	menu._options._scale.pressed.emit()
	_check(is_equal_approx(root.content_scale_factor, 1.25) and menu._options._scale.text == "125 %", "options : échelle de l'interface")
	menu._options.reset_defaults()
	_check(not UiSettings.auto_pause_menus and is_equal_approx(root.content_scale_factor, 1.0), "options : valeurs par défaut")
	menu.show_page("home")
	_press(KEY_ESCAPE)
	_check(not menu.is_open() and hud.visible, "Échap reprend la partie")
	main.open_main_menu()
	menu.show_page("new")
	menu.select_faction(MainMenu.RANDOM_FACTION)
	_check(menu._faction_cards[MainMenu.RANDOM_FACTION].button_pressed and menu._lore_header.text == "AU HASARD", "case Au hasard")
	menu.select_faction("khthari")
	_check(menu._lore_header.text == "KH'THARI" and menu._faction_lore.text != "", "le choix de faction montre l'histoire du peuple")
	_check(menu.trait_text().contains("Essaimage") and menu.trait_text().contains("Biomasse"), "le choix de faction liste tous les traits du peuple")
	menu._seed_edit.text = "123"
	menu.set_time_choice(2)
	menu.launch()
	await process_frame
	_check(not menu.is_open() and main.simulation.state.seed_value == 123, "nouvelle partie avec la graine choisie")
	_check(clock.is_turn_based() and clock.turn_days == GameClock.TURN_LENGTHS[1], "nouvelle partie au tour par tour")
	main.save_game()
	clock.set_mode(clock.MODE_REALTIME)
	main.load_game()
	_check(clock.is_turn_based() and clock.turn_days == GameClock.TURN_LENGTHS[1], "le mode tour par tour est gardé dans la sauvegarde")
	menu.set_time_choice(0)
	clock.set_mode(clock.MODE_REALTIME)
	_check(main.simulation.state.get_empire(0).faction_id == "khthari", "le joueur joue la faction choisie")
	_check(hud.bar._name.text == "KH'THARI", "le panneau d'empire suit la nouvelle faction")
	hud.bar.refresh()
	_check(hud.bar.gauge_text().begins_with("BIOMASSE"), "le panneau d'empire montre la jauge de la faction (%s)" % hud.bar.gauge_text())
	main.player_faction = "ossarane"


## La vue système à taille réelle : chaque planète se trouve sous sa position affichée.
func _test_system_view_picking(st: GameState) -> void:
	var busiest: StarSystem = st.galaxy.systems[0]
	for s in st.galaxy.systems:
		if s.planet_count > busiest.planet_count:
			busiest = s
	var v := SystemView.new()
	root.add_child(v)
	v.set_anchors_preset(Control.PRESET_TOP_LEFT)
	v.size = Vector2(1600, 900)
	v.margins = Vector4(0, 130, 420, 150)
	v.set_system(st, busiest, 0)
	var ok := true
	for pid in busiest.planet_ids:
		var pos := v.planet_position(pid)
		if not v.scene_rect().grow(40).has_point(pos):
			ok = false
		# Une planète devant une autre peut la masquer : on vérifie seulement que le clic tombe sur une planète.
		if v.planet_at(pos) == -1:
			ok = false
	_check(ok, "vue système : %d planètes dans la scène et cliquables" % busiest.planet_count)
	var r_last := v.orbit_radius(busiest.planet_count - 1)
	_check(v.orbit_radius(0) > v.star_radius() and r_last > v.orbit_radius(0), "orbites ordonnées, hors de l'étoile")
	v.queue_free()


func _find_button(node: Node, prefix: String) -> Button:
	for child in node.get_children():
		if child is Button and not child is MenuButton and (child as Button).text.begins_with(prefix):
			return child
		var found := _find_button(child, prefix)
		if found:
			return found
	return null


func _reveal_map(main: Node) -> void:
	for sys in main.galaxy.systems:
		main.simulation.state.get_empire(0).explored[sys.id] = true


func _press(keycode: Key, physical: Key = KEY_NONE) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = physical if physical != KEY_NONE else keycode
	ev.pressed = true
	root.push_input(ev)
	var up := ev.duplicate()
	up.pressed = false
	root.push_input(up)
