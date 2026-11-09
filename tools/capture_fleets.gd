extends SceneTree
## Captures d'écran des flottes et du brouillard de guerre, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_fleets.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	main.start_with_menu = false
	root.add_child(main)
	await _frames(10)
	main.player_faction = "ossarane"
	main.new_game(4242)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: Empire = st.get_empire(0)
	var home: int = st.galaxy.get_planet(me.capital_planet).system_id
	var scout := _fleet(st, "scout")
	var colonist := _fleet(st, "colony_ship")

	# Quelques mois : l'éclaireur explore, un second éclaireur sort des chantiers,
	# le vaisseau colon fonde un avant-poste dans un système voisin.
	sim.submit(SimCommands.build_ship(0, me.capital_planet, "scout"))
	var dest := -1
	for n in st.galaxy.systems[home].neighbors:
		if dest == -1 and st.galaxy.systems[n].planet_count >= 2 and st.system_owner(n) == -1:
			dest = n
	if dest == -1:
		dest = st.galaxy.systems[home].neighbors[0]
	sim.submit(SimCommands.move_fleet(0, colonist.id, dest))
	for _trip in 4:
		var target := _frontier(st)
		sim.submit(SimCommands.move_fleet(0, scout.id, target))
		sim.flush_commands()
		while scout.is_moving():
			sim.step()
			if not colonist.is_moving() and st.fleets.has(colonist.id):
				for pid in st.galaxy.systems[dest].planet_ids:
					for kind in [Colony.KIND_COLONY, Colony.KIND_OUTPOST]:
						if st.fleets.has(colonist.id) and Economy.check_colonize(st, 0, pid, kind) == "":
							sim.submit(SimCommands.colonize(0, pid, kind))
							sim.flush_commands()
	sim.submit(SimCommands.build_ship(0, me.capital_planet, "colony_ship"))
	sim.submit(SimCommands.move_fleet(0, scout.id, _frontier(st)))
	var scout2: Fleet = Fleets.empire_fleets(st, 0)[-1]
	sim.submit(SimCommands.move_fleet(0, scout2.id, _frontier(st, 2)))
	sim.advance(6)
	main._refresh_all()

	# 1. Carte : brouillard, flottes, trajet de l'éclaireur sélectionné.
	main.select_fleet(scout.id)
	main._select(-1)
	main._camera.position = st.galaxy.get_system(home).position + Vector2(150, 0)
	main._camera.zoom = Vector2(0.42, 0.42)
	main.set_process(false)
	main._hud.show_hover(null, Vector2.ZERO)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._hud.notify("%s : cap sur un système inexploré (%d jours)." % [scout.fleet_name, Fleets.eta_days(st, scout)])
	main._hud.refresh()
	await _frames(8)
	await _shot(out + "/flottes-galaxie.png")

	# 2. Plus près : la fiche du système inexploré survolé à côté de celle de la flotte.
	main._camera.position = Fleets.position(st, scout) + Vector2(60, -20)
	main._camera.zoom = Vector2(0.85, 0.85)
	main._view.hovered_id = scout.destination()
	main._hud.show_hover(st.galaxy.get_system(scout.destination()), Vector2.ZERO)
	await _frames(8)
	await _shot(out + "/flottes-fiche.png")
	main._view.hovered_id = -1
	main._hud.show_hover(null, Vector2.ZERO)

	# 3. Vue système de la capitale : le chantier spatial.
	main.set_process(true)
	main.select_fleet(-1)
	main.open_system_view(home, me.capital_planet)
	await _frames(15)
	await _shot(out + "/vue-systeme-chantier-spatial.png")
	main.close_system_view()

	# 4. Un vaisseau colon arrivé dans un système libre : coloniser par le vaisseau.
	sim.advance(int(GameData.ship("colony_ship")["days"]))
	var ship2 := _fleet(st, "colony_ship")
	var free := -1
	for n in st.galaxy.systems[home].neighbors:
		if free == -1 and n != dest and st.system_owner(n) == -1 and st.galaxy.systems[n].planet_count > 0:
			free = n
	if ship2 and free != -1:
		sim.submit(SimCommands.move_fleet(0, ship2.id, free))
		sim.flush_commands()
		while ship2.is_moving():
			sim.step()
		main._refresh_all()
		main._select(free)
		main.select_fleet(ship2.id)
		main._on_fleet_action("colonize", ship2.id)
		await _frames(15)
		await _shot(out + "/vue-systeme-vaisseau-colon.png")
		main.close_system_view()
	quit()


func _fleet(st: GameState, ship_id: String) -> Fleet:
	for f in Fleets.empire_fleets(st, 0):
		if f.count(ship_id) > 0:
			return f
	return null


## n-ième système repéré mais inexploré (le plus proche de la capitale en premier).
func _frontier(st: GameState, nth := 1) -> int:
	var home := st.galaxy.get_planet(st.get_empire(0).capital_planet).system_id
	var found: Array = []
	for s in st.galaxy.systems:
		if not Fleets.is_explored(st, 0, s.id) and Fleets.is_known(st, 0, s.id):
			found.append([s.position.distance_to(st.galaxy.systems[home].position), s.id])
	found.sort()
	return found[mini(nth - 1, found.size() - 1)][1]


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
