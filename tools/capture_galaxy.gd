extends SceneTree
## Captures de la galaxie paramétrable avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_galaxy.gd
## Écrit dans CAPTURE_DIR (par défaut user://captures) : le bloc Galaxie de Nouvelle partie, la fenêtre
## des réglages avancés, puis une partie vue de loin pour chaque forme (spectateur, quelques mois joués).

const SHOTS := [
	{"name": "spirale-2", "galaxy": {"shape": "spirale_2", "size": "grande"}},
	{"name": "spirale-6", "galaxy": {"shape": "spirale_6", "size": "grande"}},
	{"name": "elliptique", "galaxy": {"shape": "elliptique", "size": "grande"}},
	{"name": "anneau", "galaxy": {"shape": "anneau", "size": "grande", "placement": "equilibre"}},
	{"name": "amas", "galaxy": {"shape": "amas", "size": "grande", "lanes": "rares"}},
	{"name": "colossale", "galaxy": {"shape": "spirale_4", "size": "colossale", "placement": "equilibre", "lanes": "denses"}},
]


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
	menu.set_galaxy("size", "grande")
	menu.set_galaxy("shape", "anneau")
	await _frames(5)
	await _shot(out + "/galaxie-bloc.png")
	menu.set_galaxy("placement", "equilibre")
	menu.set_galaxy("guaranteed", 2)
	menu.open_galaxy_advanced()
	await _frames(5)
	await _shot(out + "/galaxie-avances.png")
	menu._galaxy_adv.hide()
	# Trop d'empires pour la taille choisie : l'écran le signale.
	menu.set_galaxy("size", "petite")
	for _i in 4:
		menu.add_slot()
	await _frames(5)
	await _shot(out + "/galaxie-trop-d-empires.png")

	var rivals := ["choeur", "vael", "khthari", "ossarane", "choeur", "vael", "khthari", "ossarane", "choeur", "vael", "khthari"]
	for shot: Dictionary in SHOTS:
		var g: Dictionary = shot["galaxy"]
		menu.galaxy_settings = GalaxySettings.normalize(g)
		var n := GalaxySettings.recommended_empires(g)
		menu.slots = []
		for i in n - 1:
			menu.slots.append(MainMenu.new_slot(rivals[i]))
		menu.set_duplicates(true)
		menu.set_spectator(true)
		menu._seed_edit.text = "2026"
		menu.launch()
		await _frames(10)
		var sim: Simulation = main.simulation
		for _m in 4:
			sim.advance(30)
			main._refresh_all()
		main._camera.stop_glide()
		main._camera.position = Vector2.ZERO
		var z := 900.0 / (2.25 * sim.state.galaxy_radius)
		main._camera.zoom = Vector2(z, z)
		await _frames(60)
		await _shot(out + "/galaxie-%s.png" % shot["name"])
		main.open_main_menu()
		await _frames(5)
		menu.show_page("new")
	quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("capture : ", path)
