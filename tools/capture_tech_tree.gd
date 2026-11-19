extends SceneTree
## Captures de la refonte de l'arbre de recherche (lot 1), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_tech_tree.gd
## Écrit les images dans CAPTURE_DIR (par défaut user://captures) : l'arbre du Chœur avec un chemin
## planifié, le même avec « Mon peuple », sa bande Peuple, l'arbre de la Sporemère de Myrr (sans
## vaisseau), et la page du Codex d'une technologie.


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	CodexPrefs.persist = false
	CodexPrefs.reset()
	UiSettings.glossary_intro_done = true
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	main.start_with_menu = false
	root.add_child(main)
	await _frames(20)

	var st := GameState.create(2026, 150, 1800.0, "choeur", {"ai_level": "normal"})
	main._start(st)
	main.game_in_progress = true
	main.set_process(false)
	Research.grant(st, 0, ["canons_masse", "litanies", "extraction", "academies", "scriptorium"])
	main._refresh_all()
	main.toggle_empire_screen("research")
	await _frames(10)
	var scr = main._empire_screens
	scr.plan_research_path("arsenaux")
	scr.research_selected = "arsenaux"
	scr.show_screen("research")
	scr.research_tree.set_path(Research.plan_path(st, 0, "arsenaux"))
	await _frames(20)
	await _shot(out + "/arbre-chemin.png")
	scr._set_research_filter("mine", true)
	scr.show_screen("research")
	await _frames(20)
	await _shot(out + "/arbre-mon-peuple.png")
	scr._set_research_filter("mine", false)
	var tree: ResearchTree = scr.research_tree
	var sc := tree.get_parent() as ScrollContainer
	sc.scroll_vertical = int(tree.custom_minimum_size.y)
	await _frames(10)
	await _shot(out + "/arbre-bande-peuple.png")
	main.close_empire_screen()

	var st2 := GameState.create(2026, 150, 1800.0, "myrr", {"ai_level": "normal"})
	main._start(st2)
	main.game_in_progress = true
	main.set_process(false)
	main._refresh_all()
	main.toggle_empire_screen("research")
	await _frames(20)
	main._empire_screens.research_tree.set_zoom(0.7)
	await _frames(10)
	await _shot(out + "/arbre-myrr.png")
	main.close_empire_screen()

	main._sync_codex()
	main.open_codex("cat:technologies:essaim_dyson")
	await _frames(20)
	await _shot(out + "/codex-technologie.png")
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
