extends SceneTree
## Captures d'écran de la vue système (rendu réel, il faut un affichage) :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_system_view.gd
## Écrit les images dans le dossier donné par la variable d'environnement CAPTURE_DIR (par défaut user://captures).


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	root.add_child(main)
	await _frames(5)
	main.new_game(int(OS.get_environment("CAPTURE_SEED")) if OS.get_environment("CAPTURE_SEED") != "" else 4242)
	await _frames(20)
	await _shot(out + "/galaxie-fiche.png")
	var st: GameState = main.simulation.state
	var me: Empire = st.get_empire(0)
	var home: int = st.galaxy.get_planet(me.capital_planet).system_id
	main.open_system_view(home)
	await _frames(90)
	await _shot(out + "/vue-systeme-origine.png")
	# Un système bien rempli, avec si possible une géante gazeuse et une ceinture d'astéroïdes.
	var best: StarSystem = null
	var best_score := -1
	for s in st.galaxy.systems:
		var score := s.planet_count * 2
		for pid in s.planet_ids:
			var t := st.galaxy.get_planet(pid).type
			if t == "gas_giant" or t == "asteroids":
				score += 3
		if s.star_type == "blue_giant" or s.star_type == "red":
			score += 2
		if s.id != home and score > best_score:
			best_score = score
			best = s
	main.open_system_view(best.id)
	await _frames(120)
	await _shot(out + "/vue-systeme-riche.png")
	for s in st.galaxy.systems:
		if s.star_type == "black_hole" and s.planet_count >= 2:
			main.open_system_view(s.id)
			await _frames(60)
			await _shot(out + "/vue-systeme-trou-noir.png")
			break
	for s in st.galaxy.systems:
		if s.star_type == "neutron" and s.planet_count >= 2:
			main.open_system_view(s.id)
			await _frames(60)
			await _shot(out + "/vue-systeme-neutrons.png")
			break
	quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
