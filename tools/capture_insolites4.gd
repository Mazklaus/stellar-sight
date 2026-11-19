extends SceneTree
## Captures des peuples insolites, lot 4 (les peuples du temps et de la vie autre), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_insolites4.gd
## Écrit dans CAPTURE_DIR (par défaut user://captures) : le menu des peuples vu par les Gardiens du Sablier
## (Registre, Boucle), les Lithes (Consensus, Patience), Myrr (comètes) et le Hallier (saisons), puis la vue
## système de la capitale des Lithes (Œuvres lentes) et celle du Hallier (planter un Cœur).

const RIVALS := ["sablier", "gravea", "myrr", "vergemonde", "teyl", "choeur"]


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
	for who in ["sablier", "gravea", "myrr", "vergemonde"]:
		var r: Array = RIVALS.filter(func(x): return x != who)
		var st := GameState.create(2026, 150, 1800.0, who, {"ai_level": "normal", "minors": "normal", "living": "rares", "rivals": r})
		var sim := Simulation.new(st)
		for _d in 400:
			sim.step()
		for e in st.empires:
			if e.id == 0 or e.is_npc():
				continue
			for p in [[0, e.id], [e.id, 0]]:
				if not st.get_empire(p[0]).contacts.has(p[1]):
					st.get_empire(p[0]).contacts.append(p[1])
		for res in ["energy", "materials", "knowledge", "influence"]:
			st.get_empire(0).resources[res] = 900
		var ed := Insolites.emp(st, 0)
		var cap := FactionTraits.capital_system(st, 0)
		var home := -1
		for pid in st.sorted_colony_ids():
			if (st.colonies[pid] as Colony).owner == 0 and st.galaxy.get_planet(int(pid)).system_id == cap:
				home = int(pid)
				break
		match who:
			"sablier":
				if InsSablier.ledger(st, 0).is_empty():
					var f := st.spawn_ship(0, "corvette", cap)
					InsSablier.on_ship_lost(st, f, 0)
					st.fleets.erase(f.id)
				ed["sand"] = 120
			"gravea":
				ed["time"] = 240
			"vergemonde":
				if home >= 0:
					st.override_planet(home, {"type": "gaia"})
		main._start(st)
		main.game_in_progress = true
		main._refresh_all()
		await _frames(10)
		main.toggle_empire_screen("insolites")
		await _frames(10)
		await _shot(out + "/insolites4-menu-%s.png" % who)
		for c in main.get_children():
			if c is PopupMenu:
				c.queue_free()
		await _frames(3)
		if (who == "gravea" or who == "vergemonde") and home >= 0:
			var target := home
			if who == "gravea":
				for pid in st.galaxy.systems[cap].planet_ids:
					if not st.colonies.has(pid):
						target = int(pid)
						st.override_planet(target, {"type": "barren"})
						break
			main._select(cap)
			main.open_system_view(cap, target)
			await _frames(30)
			await _shot(out + "/insolites4-%s-systeme.png" % who)
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
