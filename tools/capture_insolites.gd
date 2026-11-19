extends SceneTree
## Captures des peuples insolites (lot 1, les peuples sans monde) avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_insolites.gd
## Écrit dans CAPTURE_DIR (par défaut user://captures) : le réglage « Peuples insolites » de Nouvelle
## partie, la fiche de flotte du Chapiteau (bouton Chantier embarqué), l'Orbe-Monde dans la vue système
## (Lune-sentinelle) et la harde des Kraal.


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
	menu.select_faction("zambalu")
	await _frames(5)
	await _shot(out + "/insolites-nouvelle-partie.png")
	main.queue_free()
	await _frames(5)
	main = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	main.start_with_menu = false
	root.add_child(main)
	await _frames(30)

	for who in ["zambalu", "halcyre", "kraal"]:
		var st := GameState.create(2026, 150, 1800.0, who, {"ai_level": "normal", "rivals": ["exode", "ossarane", "vael", "choeur"]})
		var sim := Simulation.new(st)
		for _d in 400:
			sim.step()
		main._start(st)
		main.game_in_progress = true
		main._refresh_all()
		var f: Fleet = FactionTraits.city_fleet(st, 0)
		if who == "halcyre":
			f = InsHalcyre.orbe(st, 0)
		elif who == "kraal":
			for x in Fleets.empire_fleets(st, 0):
				if InsKraal.kraal_count(x) > 0:
					f = x
		if f == null:
			continue
		main._select(f.system_id)
		main._camera.position = st.galaxy.get_system(f.system_id).position
		main._hud.show_fleet(f.id)
		await _frames(20)
		await _shot(out + "/insolites-%s-flotte.png" % who)
		if who == "halcyre":
			main._hud.show_fleet(-1)
			main.open_system_view(f.system_id)
			await _frames(20)
			await _shot(out + "/insolites-halcyre-systeme.png")
			main.close_system_view()
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
