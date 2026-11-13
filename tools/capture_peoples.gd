extends SceneTree
## Captures des populations mixtes (lot 1 de « Populations mixtes et migrations »), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_peoples.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : la Concorde de Vael a conquis des mondes kh'thari, ferrocornes et teyl ; écran Colonies
## (peuples de l'empire et collections), lentille des peuples, vue système d'une colonie mêlée.


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	main.start_with_menu = false
	root.add_child(main)
	await _frames(10)
	main.player_faction = "vael"
	main.game_options = {"peoples": "actifs"}
	main.new_game(4242)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var mixes := [{"khthari": 8}, {"ferrocornes": 5}, {"teyl": 10}, {"khthari": 4, "teyl": 3}, {"ferrocornes": 2}]
	var mixed_sid := -1
	for i in mixes.size():
		var sid := _plant(st, 0, 1 + i, 11, mixes[i])
		if i == 3:
			mixed_sid = sid
	sim.advance(40)
	Peoples.refresh(st)
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._refresh_all()
	await _frames(6)
	main.toggle_empire_screen("colonies")
	await _frames(10)
	await _shot(out + "/ecran-colonies-peuples.png")
	main.toggle_empire_screen("colonies")
	await _frames(4)
	main._hud.set_lens("peoples")
	await _frames(8)
	await _shot(out + "/lentille-peuples.png")
	main._hud.set_lens("")
	await _frames(4)
	if mixed_sid >= 0:
		main.open_system_view(mixed_sid)
		await _frames(10)
		await _shot(out + "/vue-systeme-mosaique.png")
	quit()


func _plant(st: GameState, empire_id: int, min_jumps: int, pop: int, species: Dictionary) -> int:
	var jumps := FactionTraits.jumps_from(st.galaxy, FactionTraits.capital_system(st, empire_id))
	for s in st.galaxy.systems:
		var j := int(jumps.get(s.id, 999))
		if j < min_jumps or j > min_jumps + 1 or st.system_owner(s.id) >= 0 or s.planet_ids.size() < 2:
			continue
		for pid in s.planet_ids:
			var p := st.galaxy.get_planet(pid)
			if Economy._pop_hab(st, empire_id, p.type) < 60:
				continue
			var c := Colony.new()
			c.planet_id = pid
			c.owner = empire_id
			c.kind = Colony.KIND_COLONY
			c.population = pop
			c.species = species.duplicate()
			st.add_colony(c)
			st.rebuild_ownership()
			for e in st.empires:
				if e.id == empire_id:
					e.explored[s.id] = true
			return s.id
	return -1


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
