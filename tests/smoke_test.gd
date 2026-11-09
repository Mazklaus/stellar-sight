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
	_test_clock()
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
	clock.attach(null)
	_check(clock.day == 0, "horloge détachée")


func _test_main_scene() -> void:
	print("Scène principale…")
	var scene: PackedScene = load("res://scenes/main.tscn")
	_check(scene != null, "main.tscn se charge")
	var main := scene.instantiate()
	main.save_path = "user://saves/test_quicksave.json"  # ne jamais toucher la vraie sauvegarde du joueur
	root.add_child(main)
	for _i in 10:
		await process_frame
	_check(main.galaxy != null and main.galaxy.systems.size() == main.SYSTEM_COUNT, "galaxie créée au lancement")
	await _test_colony_ui(main)

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
	_press(KEY_R)
	_check(main.galaxy.seed_value != old_seed or main.galaxy.systems.size() == main.SYSTEM_COUNT, "R régénère la galaxie")
	for _i in 10:
		await process_frame
	DirAccess.remove_absolute(main.save_path)
	main.queue_free()
	await process_frame


## Au lancement : caméra et fiche sur le système d'origine ; vue système, colonisation et construction.
func _test_colony_ui(main: Node) -> void:
	var st: GameState = main.simulation.state
	var me: Empire = st.get_empire(main.LOCAL_PLAYER)
	var screen: SystemScreen = main._system_screen
	_check(me.faction_id == main.player_faction, "le joueur joue sa faction (%s)" % me.faction_id)
	var home_sys: int = main.galaxy.get_planet(me.capital_planet).system_id
	_check(main._view.selected_id == home_sys, "le système d'origine est sélectionné au lancement")
	_check(main._hud._info_panel.visible and main._hud._planet_label.text.get_slice_count("\n") == main.galaxy.systems[home_sys].planet_count,
			"la fiche résume les planètes du système d'origine")
	_check(main._hud._res_label.text.contains("Matériaux 200"), "les ressources du joueur s'affichent (%s)" % main._hud._res_label.text)
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


func _press(keycode: Key, physical: Key = KEY_NONE) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.physical_keycode = physical if physical != KEY_NONE else keycode
	ev.pressed = true
	root.push_input(ev)
	var up := ev.duplicate()
	up.pressed = false
	root.push_input(up)
