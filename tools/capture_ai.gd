extends SceneTree
## Captures des empires IA et du mode spectateur avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_ai.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures) : la page
## Nouvelle partie (niveau des IA, mode spectateur), une partie de spectateur après deux ans en vue
## d'ensemble puis à travers les yeux d'un empire, et une partie normale avec ses rivaux.


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
	menu.set_ai_level("veteran")
	menu.set_temperament("agressif")
	menu.set_spectator(true)
	menu._seed_edit.text = "2026"
	await _frames(5)
	await _shot(out + "/nouvelle-partie-spectateur.png")

	menu.launch()
	await _frames(10)
	var sim: Simulation = main.simulation
	for _m in 24:
		sim.advance(30)
		main._refresh_all()  # le tableau relève le score chaque mois
	main._camera.stop_glide()
	main._camera.position = Vector2(0, 0)
	main._camera.zoom = Vector2(0.26, 0.26)
	main.select_fleet(-1)
	main._select(-1)
	await _frames(60)
	await _shot(out + "/spectateur-vue-ensemble.png")

	main.follow_empire(2)
	main.set_spectator_fog(true)
	main.go_to_capital()
	await _frames(90)
	await _shot(out + "/spectateur-yeux-empire.png")

	# Partie normale : le joueur (Ossarane) au départ, ses rivaux IA ont un an d'avance.
	menu.set_spectator(false)
	main.open_main_menu()
	menu.show_page("new")
	menu.select_faction("ossarane")
	menu._seed_edit.text = "2026"
	menu.launch()
	await _frames(10)
	main.simulation.advance(360)
	FleetSystem.update_exploration(main.simulation.state)
	for s in main.simulation.state.galaxy.systems:
		main.simulation.state.get_empire(0).explored[s.id] = true
	main._refresh_all()
	main._camera.stop_glide()
	main._camera.position = Vector2(0, 0)
	main._camera.zoom = Vector2(0.26, 0.26)
	await _frames(60)
	await _shot(out + "/partie-rivaux-ia.png")
	quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
