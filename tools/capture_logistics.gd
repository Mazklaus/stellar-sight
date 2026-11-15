extends SceneTree
## Captures du pilier logistique et ravitaillement, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_logistics.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael (joueur), logistique complète. Une flotte de guerre loin de ses bases (Étirée, réserves
## entamées) : fiche de flotte et zone de ravitaillement en vert. Puis une flotte à quai à la capitale.


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
	main.game_options = {"logistics": "complete"}
	main.new_game(4242)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: int = main.view_empire
	sim.advance(900)
	for sys in st.galaxy.systems:
		st.get_empire(me).explored[sys.id] = true
	var home := FactionTraits.capital_system(st, me)
	# Une flotte à 3 ou 4 sauts de toute base, réserves à moitié.
	var far := -1
	var best := 99
	var dist := _dist(st, home)
	for sid in dist:
		var dz := 99
		var z := Logistics.zone(st, me)
		if z.has(sid):
			continue
		if int(dist[sid]) >= 3 and int(dist[sid]) < best:
			best = int(dist[sid])
			far = sid
	var f := st.spawn_ship(me, "frigate" if GameData.ships().has("frigate") else "corvette", far)
	f.add_ship("corvette")
	f.add_ship("corvette")
	f.fleet_name = "3e flotte"
	st.logistics["res"][str(f.id)] = 47
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._refresh_all()
	main.select_fleet(f.id)
	main._select(-1)
	main._camera.position = (st.galaxy.get_system(home).position + st.galaxy.get_system(far).position) / 2.0
	main._camera.zoom = Vector2(0.55, 0.55)
	main._view.queue_redraw()
	main._hud.refresh()
	await _frames(20)
	await _shot(out + "/logistique-flotte-etiree.png")
	# Survol de la ligne d'état : l'infobulle détaillée.
	# Flotte à quai à la capitale.
	var g := st.spawn_ship(me, "corvette", home)
	g.add_ship("corvette")
	g.fleet_name = "Garde de la capitale"
	main._refresh_all()
	main.select_fleet(g.id)
	main._select(-1)
	main._camera.position = st.galaxy.get_system(home).position
	main._camera.zoom = Vector2(0.8, 0.8)
	main._view.queue_redraw()
	main._hud.refresh()
	await _frames(20)
	await _shot(out + "/logistique-a-quai.png")
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
