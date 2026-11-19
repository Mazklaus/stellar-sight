extends SceneTree
## Captures des peuples insolites, lot 2 (les peuples qui vivent chez les autres), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_insolites2.gd
## Écrit dans CAPTURE_DIR (par défaut user://captures) : la vue système d'une colonie étrangère vue par la
## Compagnie (Acheter 10 %), le menu des peuples (normes du Bureau, Accord d'hébergement du Signal) et la
## vue système d'un monde qui rêve, vue par les Ysmer.


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
	for who in ["ventrelune", "ossarane", "ysmer"]:
		var st := GameState.create(2026, 150, 1800.0, who, {"ai_level": "normal", "rivals": ["bureau", "signal", "ysmer", "vael", "choeur"] if who != "ysmer" else ["bureau", "signal", "vael", "choeur", "ossarane"]})
		var sim := Simulation.new(st)
		for _d in 400:
			sim.step()
		var target := -1
		for e in st.empires:
			if e.id == 0 or e.is_npc():
				continue
			for p in [[0, e.id], [e.id, 0]]:
				if not st.get_empire(p[0]).contacts.has(p[1]):
					st.get_empire(p[0]).contacts.append(p[1])
			if who == "ventrelune" and target < 0 and e.capital_planet >= 0:
				Diplomacy._rel_w(st, 0, e.id)["trade"] = 1
				target = e.capital_planet
		if who == "ventrelune":
			(Insolites.emp(st, 0)["shares"] as Dictionary)[str(target)] = 30
			Insolites._explore(st, 0)
			for _d in 2:
				sim.step()
		if who == "ysmer":
			var rv := InsYsmer.reveries(st, 0)
			target = rv[0] if not rv.is_empty() else -1
		main._start(st)
		main.game_in_progress = true
		main._refresh_all()
		await _frames(10)
		if who == "ossarane":
			main.toggle_empire_screen("insolites")
			await _frames(10)
			await _shot(out + "/insolites2-menu-des-peuples.png")
			for c in root.get_children():
				if c is PopupMenu:
					c.queue_free()
			await _frames(3)
			continue
		if target < 0:
			continue
		var sid := st.galaxy.get_planet(target).system_id
		main._select(sid)
		main.open_system_view(sid, target)
		await _frames(30)
		await _shot(out + "/insolites2-%s-systeme.png" % who)
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
