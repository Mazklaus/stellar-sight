extends SceneTree
## Captures du lot 3 de Nouvelle partie avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_game_rules.gd
## Écrit dans CAPTURE_DIR (par défaut user://captures) : l'écran avec préréglages, victoires à cocher et
## difficulté progressive, le « + » d'un rival (départ, distance), le code de partie, l'enregistrement
## d'un préréglage, et l'accueil avec Partie rapide.


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
	menu.presets_path = "user://capture_new_game_presets.json"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(menu.presets_path))
	menu._rebuild_presets()
	menu.show_page("new")
	menu.select_faction("vael")
	menu.set_slot(0, "start", "avance")
	menu.set_slot(3, "distance", "proche")
	menu.set_slot(3, "level", "legende")
	menu.set_victory("domination", false)
	menu.set_ai_scaling(true)
	menu.save_preset("Duel serré")
	await _frames(5)
	await _shot(out + "/regles-ecran.png")
	menu.open_slot_advanced(3)
	await _frames(5)
	await _shot(out + "/regles-rival-depart-distance.png")
	menu._slot_adv.hide()
	menu._seed_edit.text = "2026"
	menu.open_code_popup()
	await _frames(5)
	await _shot(out + "/regles-code-de-partie.png")
	menu._code_popup.hide()
	menu.open_preset_popup()
	await _frames(5)
	await _shot(out + "/regles-prereglage.png")
	menu._preset_popup.hide()
	menu.launch()
	await _frames(10)
	main.open_main_menu()
	await _frames(10)
	await _shot(out + "/regles-accueil-partie-rapide.png")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(menu.presets_path))
	quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)
	print("capture : ", path)
