extends SceneTree
## Captures du mode tour par tour (choix dans « Nouvelle partie », cadran de fin de tour) :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_turns.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).


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
	menu.select_faction("ossarane")
	menu.set_time_choice(2)
	await _frames(5)
	await _shot(out + "/tour-par-tour-nouvelle-partie.png")
	menu._seed_edit.text = "4242"
	menu.launch()
	await _frames(15)
	await _shot(out + "/tour-par-tour-fin-de-tour.png")
	var clock: Node = root.get_node("GameClock")
	clock.end_turn()
	while clock.turn_progress() < 0.4:
		await process_frame
	await _shot(out + "/tour-par-tour-en-cours.png")
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("capture : ", path)
