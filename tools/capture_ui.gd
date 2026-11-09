extends SceneTree
## Captures d'écran de l'interface (menus, barre d'empire, menus d'empire) avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_ui.gd
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
	await _shot(out + "/menu-principal.png")
	main._main_menu.show_page("new")
	main._main_menu.select_faction("vael")
	await _frames(5)
	await _shot(out + "/menu-nouvelle-partie.png")
	main._main_menu.select_faction("ossarane")
	main._main_menu._seed_edit.text = "4242"
	main._main_menu.launch()
	await _frames(10)

	# Quelques années de jeu avec des colonies, pour des menus d'empire bien remplis.
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	for month in 48:
		for p in st.galaxy.planets:
			if Economy.check_colonize(st, 0, p.id, Colony.KIND_COLONY) == "":
				sim.submit(SimCommands.colonize(0, p.id, Colony.KIND_COLONY))
			elif Economy.check_colonize(st, 0, p.id, Colony.KIND_OUTPOST) == "" and month % 3 == 0:
				sim.submit(SimCommands.colonize(0, p.id, Colony.KIND_OUTPOST))
		for pid in st.colonies:
			for b in ["ferme_hydroponique", "centrale_fusion", "complexe_minier"]:
				if Economy.check_build(st, 0, pid, b) == "":
					sim.submit(SimCommands.build(0, pid, b))
		for _d in 30:
			sim.step()
	main._refresh_all()
	var me: Empire = st.get_empire(0)
	var home: int = st.galaxy.get_planet(me.capital_planet).system_id
	main._select(home)
	main._camera.position = st.galaxy.get_system(home).position + Vector2(-120, 40)
	main._camera.zoom = Vector2(0.5, 0.5)
	await _frames(10)
	# Survol d'un système voisin.
	var n: int = st.galaxy.systems[home].neighbors[0]
	var screen_pos: Vector2 = main.get_viewport().get_canvas_transform() * st.galaxy.get_system(n).position
	main._view.hovered_id = n
	main._view.queue_redraw()
	main.set_process(false)
	main._hud.show_hover(st.galaxy.get_system(n), screen_pos)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._hud.notify("Partie sauvegardée (%s)" % GameCalendar.date_string(st.tick), "good")
	await _frames(5)
	await _shot(out + "/galaxie-interface.png")
	main.set_process(true)
	main.toggle_empire_screen("economy")
	await _frames(20)
	await _shot(out + "/menu-economie.png")
	main.toggle_empire_screen("colonies")
	await _frames(20)
	await _shot(out + "/menu-colonies.png")
	main.close_empire_screen()
	main.open_system_view(home)
	await _frames(90)
	await _shot(out + "/vue-systeme-interface.png")
	main.close_system_view()
	main._select(-1)
	main.open_pause_menu()
	await _frames(10)
	await _shot(out + "/menu-pause.png")
	main._pause_menu.show_page("shortcuts")
	await _frames(5)
	await _shot(out + "/menu-raccourcis.png")
	quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
