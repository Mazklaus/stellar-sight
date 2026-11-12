extends SceneTree
## Captures des pirates (lot 2 de « Pirates et stabilité »), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_pirates.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : réglage Pirates dans Nouvelle partie ; un empire Vael qui connaît deux repaires, une
## colonie à portée, un raid en route ; écran Ordre intérieur, carte, vue système d'un repaire,
## fiche d'une flotte en patrouille.


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	root.add_child(main)
	await _frames(30)
	var menu: MainMenu = main._main_menu
	menu.show_page("new")
	menu.select_faction("vael")
	menu.set_pirates("infestes")
	await _frames(5)
	await _shot(out + "/nouvelle-partie-pirates.png")

	main.player_faction = "vael"
	main.game_options = {"pirates": "normaux"}
	main.new_game(4242)
	await _frames(5)
	main._main_menu.visible = false
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var home := FactionTraits.capital_system(st, 0)
	var jumps := FactionTraits.jumps_from(st.galaxy, home)
	var lairs := Pirates.lair_ids(st)
	lairs.sort_custom(func(a: int, b: int) -> bool: return int(jumps.get(a, 99)) < int(jumps.get(b, 99)))
	var lair: int = lairs[0]
	for sid in lairs.slice(0, 2):
		st.get_empire(0).explored[sid] = true
		for n in st.galaxy.systems[sid].neighbors:
			st.get_empire(0).explored[n] = true
	var target := _plant_near(st, lair)
	st.get_empire(0).contacts.append(1)
	st.get_empire(0).resources["energy"] = 900
	st.get_empire(0).resources["influence"] = 120
	sim.advance(400)
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	st.lairs[lair]["next"] = st.tick + 1
	sim.advance(3)
	sim.submit(SimCommands.pirate_tribute(0, lairs[1]))
	sim.flush_commands()
	# Une flotte en patrouille entre la capitale et la colonie exposée.
	var pat := st.spawn_ship(0, "fregate", home)
	pat.add_ship("fregate", -1, 1)
	pat.fleet_name = "Garde-côtes"
	if target >= 0:
		sim.submit(SimCommands.patrol_fleet(0, pat.id, target))
		sim.flush_commands()
	main._refresh_all()

	main.toggle_empire_screen("order")
	await _frames(10)
	await _shot(out + "/ordre-interieur-repaires.png")
	if OS.get_environment("DUMP") != "":
		_dump(main._empire_screens)
	main.toggle_empire_screen("order")
	await _frames(4)

	main._camera.position = st.galaxy.systems[lair].position
	main._camera.zoom = Vector2(1.1, 1.1)
	main.select_fleet(pat.id)
	await _frames(10)
	await _shot(out + "/carte-repaire-raid.png")

	main.open_system_view(lair)
	await _frames(10)
	await _shot(out + "/systeme-repaire.png")
	main.close_system_view()
	await _frames(4)

	# Lot 3 : le second repaire devenu port franc, un héros retenu contre rançon.
	var port: int = lairs[1]
	Pirates.make_port(st, port, [])
	var hid: int = Heroes.ids_of(st, 0)[0]
	st.heroes[hid]["post"] = ""
	st.heroes[hid]["jailer"] = GameState.PIRATE_ID
	st.heroes[hid]["ransom"] = st.tick + 700
	main._refresh_all()
	main.toggle_empire_screen("order")
	await _frames(10)
	await _shot(out + "/ordre-interieur-port-franc.png")
	if OS.get_environment("DUMP") != "":
		_dump(main._empire_screens)
	main.toggle_empire_screen("order")
	await _frames(4)
	main.toggle_empire_screen("heroes")
	await _frames(10)
	await _shot(out + "/pantheon-rancon.png")
	if OS.get_environment("DUMP") != "":
		_dump(main._empire_screens)
	main.toggle_empire_screen("heroes")
	await _frames(4)
	main._camera.position = st.galaxy.systems[port].position
	await _frames(10)
	await _shot(out + "/carte-port-franc.png")
	quit()


func _plant_near(st: GameState, lair: int) -> int:
	var jumps := FactionTraits.jumps_from(st.galaxy, lair)
	for j in [2, 3, 1]:
		for s in st.galaxy.systems:
			if int(jumps.get(s.id, 99)) == j and st.system_owner(s.id) < 0 and not s.planet_ids.is_empty() and not Pirates.is_lair(st, s.id):
				var c := Colony.new()
				c.planet_id = s.planet_ids[0]
				c.owner = 0
				c.kind = Colony.KIND_COLONY
				c.population = 4
				st.add_colony(c)
				st.get_empire(0).explored[s.id] = true
				return s.id
	return -1


## Textes visibles d'un écran (vérification sans regarder l'image).
func _dump(n: Node) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Button and (n as Button).text != "":
		print("  [", (n as Button).text, "]", " (inactif)" if (n as Button).disabled else "", " @", (n as Control).global_position.round())
	elif n is Label and (n as Label).text != "":
		print("  ", (n as Label).text.left(110), " @", (n as Control).global_position.round())
	for c in n.get_children():
		_dump(c)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
