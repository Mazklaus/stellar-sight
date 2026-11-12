extends SceneTree
## Captures de la stabilité (lot 1 de « Pirates et stabilité »), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_stability.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : un empire Vael avec des colonies proches et lointaines, un système en révolte, un en
## agitation sous Fêtes publiques, un monde libre à la frontière ; écran Ordre intérieur, filtre de
## stabilité sur la carte, ligne de stabilité de la vue système.


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
	main.new_game(4242)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var home := FactionTraits.capital_system(st, 0)
	var planted: Array[int] = []
	for j in [1, 2, 2, 3, 5, 6, 7]:
		var sid := _plant(st, 0, j, 4)
		if sid >= 0:
			planted.append(sid)
	sim.advance(360)
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	st.get_empire(0).resources["influence"] = 120
	st.get_empire(0).resources["energy"] = 400
	# Un système en révolte depuis 7 mois, un en agitation, un monde libre à la frontière.
	if planted.size() >= 4:
		st.stability[planted[-1]] = {"v": 6, "revolt": 210}
		st.stability[planted[-2]] = {"v": 22}
		st.stability[planted[1]] = {"v": 78}
		sim.submit(SimCommands.decree(0, planted[-2], "fetes"))
		sim.flush_commands()
		StabilitySystem.secede(st, planted[-3], 0, [])
	st.stability[home]["v"] = 88
	Stability.refresh_empire(st, 0)
	main._refresh_all()

	main.toggle_empire_screen("order")
	await _frames(10)
	await _shot(out + "/ordre-interieur.png")
	main.toggle_empire_screen("order")
	await _frames(4)

	main._hud.set_lens("stability")
	main._camera.position = st.galaxy.systems[home].position
	main._camera.zoom = Vector2(0.9, 0.9)
	await _frames(10)
	await _shot(out + "/carte-stabilite.png")
	main._hud.set_lens("")

	if planted.size() >= 4:
		main.open_system_view(planted[-1])
		await _frames(10)
		await _shot(out + "/systeme-revolte.png")
		main.close_system_view()
		await _frames(4)
		main.open_system_view(planted[-3])
		await _frames(10)
		await _shot(out + "/monde-libre.png")
	quit()


func _plant(st: GameState, empire_id: int, min_jumps: int, pop: int) -> int:
	var jumps := FactionTraits.jumps_from(st.galaxy, FactionTraits.capital_system(st, empire_id))
	for s in st.galaxy.systems:
		var j := int(jumps.get(s.id, 999))
		if j < min_jumps or j > min_jumps + 1 or st.system_owner(s.id) >= 0 or s.planet_ids.is_empty():
			continue
		var c := Colony.new()
		c.planet_id = s.planet_ids[0]
		c.owner = empire_id
		c.kind = Colony.KIND_COLONY
		c.population = pop
		st.add_colony(c)
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
