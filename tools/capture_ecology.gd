extends SceneTree
## Capture de l'onglet Biosphères de l'écran Colonies et de la vue système, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_ecology.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Lignées d'Ossarane, écologie complète. La capitale porte de l'industrie lourde et souffre,
## quelques colonies vivantes à des paliers différents, doctrine Extraction.


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
	var st := GameState.create(2026, 150, 1800.0, "ossarane", {"ai_level": "", "ecology": "complete"})
	main._start(st)
	main.game_in_progress = true
	var me := 0
	var e := st.get_empire(me)
	var cap: Colony = st.colonies[e.capital_planet]
	st.override_planet(cap.planet_id, {"type": "continental"})
	e.hab_cache.clear()
	for bid in ["complexe_minier", "complexe_minier", "centrale_fusion", "mine_profonde"]:
		cap.buildings.append(bid)
	cap.population = maxi(cap.population, 14)
	Ecology._set_health(st, cap.planet_id, 38)
	# Quelques colonies vivantes de plus dans les systèmes voisins, à des paliers différents.
	var sid := st.galaxy.get_planet(cap.planet_id).system_id
	var placed := 0
	var values := [86, 64, 47, 17]
	var types := ["ocean", "continental", "desert", "arctic"]
	var sids: Array = [sid]
	sids.append_array(st.galaxy.systems[sid].neighbors)
	for s in sids:
		for pid in st.galaxy.systems[s].planet_ids:
			if placed >= values.size() or st.colonies.has(pid):
				continue
			var c := Colony.new()
			c.planet_id = pid
			c.owner = me
			c.population = 4 + placed
			st.colonies[pid] = c
			st.override_planet(pid, {"type": types[placed]})
			if placed == 0:
				c.buildings.append("reserve_naturelle")
			if placed == 3:
				c.buildings.append_array(["mine_profonde", "complexe_minier"])
			Ecology._set_health(st, pid, values[placed])
			placed += 1
	e.hab_cache.clear()
	Ecology.apply(st, me, "doctrine", {"id": "extraction"})
	main._refresh_all()
	main.set_process(false)
	main.toggle_empire_screen("colonies")
	await _frames(5)
	main._empire_screens.set_colony_filter("biosphere")
	await _frames(30)
	await _shot(out + "/ecran-biospheres.png")
	main.toggle_empire_screen("colonies")
	await _frames(5)
	main.open_system_view(sid, cap.planet_id)
	await _frames(30)
	await _shot(out + "/vue-systeme-biosphere.png")
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
