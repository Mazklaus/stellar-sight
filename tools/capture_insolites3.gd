extends SceneTree
## Captures des peuples insolites, lot 3 (les peuples qui jouent avec la vie et la mort), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_insolites3.gd
## Écrit dans CAPTURE_DIR (par défaut user://captures) : le menu des peuples vu par Asphodèle (Anciens, Revenants)
## et par un voisin (Pacte funéraire, Silencieux), et la vue système d'un peuple pré-spatial vue par Quiétude
## (poser un poste voilé, élever en secret).

const RIVALS := ["asphodele", "cassivel", "silencieux", "quietude", "teyl", "choeur"]


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
	for who in ["asphodele", "ossarane", "quietude"]:
		var r: Array = RIVALS.filter(func(x): return x != who)
		if who == "ossarane":
			r = r.slice(0, 5)
		var st := GameState.create(2026, 150, 1800.0, who, {"ai_level": "normal", "minors": "normal", "rivals": r})
		var sim := Simulation.new(st)
		for _d in 400:
			sim.step()
		for e in st.empires:
			if e.id == 0 or e.is_npc():
				continue
			for p in [[0, e.id], [e.id, 0]]:
				if not st.get_empire(p[0]).contacts.has(p[1]):
					st.get_empire(p[0]).contacts.append(p[1])
		var target := -1
		if who == "asphodele":
			if InsAsphodele.fallen(st).is_empty():
				st.insolites["fallen"] = [{"name": "Amirale Kesh-Varo", "portrait": "", "cls": "stratege", "lvl": 4, "sp": "", "o": 1, "t": st.tick}]
			st.get_empire(0).resources["influence"] = 200
		if who == "quietude":
			var best := 999
			var cap := FactionTraits.capital_system(st, 0)
			var d: Dictionary = FactionTraits.jumps_from(st.galaxy, cap)
			for mid in Minors.ids(st):
				if Minors.is_pre(st, mid) and int(d.get(Minors.system_of(st, mid), 999)) < best:
					best = int(d.get(Minors.system_of(st, mid), 999))
					target = int(Minors.get_m(st, mid)["planet"])
			if target >= 0:
				st.get_empire(0).explored[st.galaxy.get_planet(target).system_id] = true
				st.get_empire(0).resources["influence"] = 200
		main._start(st)
		main.game_in_progress = true
		main._refresh_all()
		await _frames(10)
		if who != "quietude":
			main.toggle_empire_screen("insolites")
			await _frames(10)
			await _shot(out + "/insolites3-menu-%s.png" % who)
			for c in main.get_children():
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
		await _shot(out + "/insolites3-quietude-systeme.png")
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
