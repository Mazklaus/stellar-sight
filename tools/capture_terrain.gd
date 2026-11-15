extends SceneTree
## Captures du pilier terrain galactique, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_terrain.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael (joueur), terrain dense, tempêtes actives. La carte autour de la nébuleuse la plus
## proche de la capitale, une tempête posée à côté (anneau et flèche de route), la fiche d'un système
## en nébuleuse ; puis un rapport de bataille livrée dans un terrain.


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
	main.game_options = {"terrain": "dense", "storms": "actives"}
	main.new_game(4242)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: int = main.view_empire
	main.set_process(false)
	sim.advance(300)
	for sys in st.galaxy.systems:
		st.get_empire(me).explored[sys.id] = true
	var home := FactionTraits.capital_system(st, me)
	var dist := _dist(st, home)
	# La nébuleuse nommée la plus proche de la capitale.
	var neb := -1
	for sid in dist:
		if Terrain.region_name(st, sid) != "" and (neb < 0 or int(dist[sid]) < int(dist[neb])):
			neb = sid
	# Une tempête ionique posée sur un voisin de la nébuleuse.
	var c: int = st.galaxy.systems[neb].neighbors[0]
	var storm := {"id": 1, "k": "tempete_ionique", "c": c, "nx": c, "left": 400, "step": 40, "prev": -1}
	storm["nx"] = Terrain._next_center(st, storm)
	st.terrain["st"] = [storm]
	st.terrain["nst"] = 2
	Terrain.refresh(st)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._refresh_all()
	main._select(-1)
	main._camera.position = st.galaxy.get_system(neb).position
	main._camera.zoom = Vector2(0.6, 0.6)
	main._view.queue_redraw()
	main._hud.refresh()
	main._hud.show_hover(st.galaxy.get_system(neb), Vector2.ZERO)
	await _frames(20)
	await _shot(out + "/terrain-carte.png")
	quit()


func _dist(st: GameState, from: int) -> Dictionary:
	var d := {from: 0}
	var q: Array[int] = [from]
	while not q.is_empty():
		var s: int = q.pop_front()
		for n in st.galaxy.systems[s].neighbors:
			if not d.has(n):
				d[n] = int(d[s]) + 1
				q.append(n)
	return d


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
