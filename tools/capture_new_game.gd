extends SceneTree
## Captures de l'écran Nouvelle partie en blocs (rivaux réglables un par un) avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_new_game.gd
## Écrit dans CAPTURE_DIR (par défaut user://captures) : l'écran par défaut, des rivaux réglés un par
## un (niveau, tempérament, couleur, au hasard), des peuples en double, et la partie lancée avec eux
## (tableau des empires du spectateur).


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
	await _frames(5)
	await _shot(out + "/nouvelle-partie-blocs.png")

	# Rivaux réglés un par un : un Kh'thari Légende belliqueux, un Chœur Recrue, deux inconnus.
	menu.set_slot(1, "level", "recrue")
	menu.set_slot(3, "level", "legende")
	menu.set_slot(3, "temper", "belliqueux")
	menu.set_slot(3, "color", Empire.PALETTE[7])
	menu.add_slot()
	menu.add_slot()
	menu.set_slot(5, "level", "expert")
	await _frames(5)
	await _shot(out + "/nouvelle-partie-rivaux-reglables.png")

	# Peuples en double : trois Kh'thari et un autre Vael en face de vous.
	menu.slots = MainMenu.default_slots()
	menu.set_duplicates(true)
	menu.add_slot("khthari")
	menu.add_slot("khthari")
	menu.set_slot(2, "level", "veteran")
	await _frames(5)
	await _shot(out + "/nouvelle-partie-doublons.png")

	menu.set_spectator(true)
	menu._seed_edit.text = "2026"
	menu.launch()
	await _frames(10)
	var sim: Simulation = main.simulation
	for _m in 6:
		sim.advance(30)
		main._refresh_all()
	main._camera.stop_glide()
	main._camera.position = Vector2(0, 0)
	main._camera.zoom = Vector2(0.26, 0.26)
	await _frames(60)
	await _shot(out + "/partie-doublons-spectateur.png")
	quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("capture : ", path)
