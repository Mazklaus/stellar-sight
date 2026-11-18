extends SceneTree
## Captures des coques de peuple (étude « Les chantiers des peuples », lot 3) avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_coques_peuple.gd
## Écrit dans CAPTURE_DIR (par défaut user://captures) : le Chantier des Noosphères de Teyl (section
## Coques du peuple, silhouette du Châssis relié), puis la carte avec les silhouettes de flotte.


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	main.start_with_menu = false
	root.add_child(main)
	await _frames(30)

	var st := GameState.create(2026, 150, 1800.0, "teyl", {"ai_level": "normal"})
	main._start(st)
	main.game_in_progress = true
	Research.grant(st, 0, ["coques_lourdes", "torpilles", "chantier_titanesque"])
	main._refresh_all()
	main.toggle_empire_screen("shipyard")
	var screens: EmpireScreens = main._empire_screens
	screens.shipyard.new_draft("chassis_relie")
	screens.shipyard.auto_design_draft("ligne")
	screens.shipyard.draft["name"] = "Pensée commune"
	screens.shipyard._refresh_all()
	await _frames(20)
	await _shot(out + "/coques-chantier-teyl.png")
	main.toggle_empire_screen("shipyard")
	await _frames(10)

	UiSettings.fleet_silhouettes = true
	for f in st.fleets.values():
		if f.owner == 0:
			for cls in ["chassis_relie", "noeud_calcul"]:
				f.add_ship(cls)
	main._view.queue_redraw()
	await _frames(20)
	await _shot(out + "/coques-carte-silhouettes.png")
	UiSettings.fleet_silhouettes = false
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
