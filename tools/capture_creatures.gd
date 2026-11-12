extends SceneTree
## Captures de la faune (lot 1 de « Créatures spatiales et gardiens »), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_creatures.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : réglage Créatures dans Nouvelle partie ; un empire Vael qui a rencontré trois espèces,
## en a étudié une et en chasse une autre ; Bestiaire, carte d'un nid avec la fiche d'un troupeau.


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	root.add_child(main)
	await _frames(30)
	var menu: MainMenu = main._main_menu
	menu.show_page("new")
	menu.select_faction("vael")
	menu.set_creatures("grouillantes")
	await _frames(5)
	await _shot(out + "/nouvelle-partie-creatures.png")

	main.player_faction = "vael"
	main.game_options = {"creatures": "normales"}
	main.new_game(4242)
	await _frames(5)
	main._main_menu.visible = false
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var home := FactionTraits.capital_system(st, 0)
	var jumps := FactionTraits.jumps_from(st.galaxy, home)
	var nests := Fauna.nest_ids(st)
	nests.sort_custom(func(a: int, b: int) -> bool: return int(jumps.get(a, 99)) < int(jumps.get(b, 99)))
	var e := st.get_empire(0)
	for sid in nests.slice(0, 3):
		e.explored[sid] = true
		for n in st.galaxy.systems[sid].neighbors:
			e.explored[n] = true
	var added: Array[Dictionary] = []
	var met: Array[String] = []
	for sid in nests.slice(0, 3):
		var sp := String(Fauna.nests(st)[sid]["sp"])
		Fauna.see(st, 0, sp, sid, added)
		met.append(sp)
	e.resources["energy"] = 900
	e.resources["influence"] = 200
	Fauna.set_attitude(st, 0, met[0], "etude")
	st.fauna["meta"][0]["study"][met[0]] = st.tick + 2
	if met.size() > 1:
		Fauna.set_attitude(st, 0, met[1], "chasse")
	# Un éclaireur posté à côté du premier nid, pour voir ses troupeaux.
	var nb: Array = st.galaxy.systems[nests[0]].neighbors.duplicate()
	nb.sort()
	for n in nb:
		if st.system_owner(int(n)) < 0 and Fleets.fleets_at(st, int(n)).is_empty():
			st.spawn_ship(0, "scout", int(n)).fleet_name = "Naturalistes"
			break
	sim.advance(5)
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._empire_screens.chron_tab = "bestiary"
	main._refresh_all()
	main.toggle_empire_screen("chronicles")
	await _frames(10)
	await _shot(out + "/bestiaire.png")
	if OS.get_environment("DUMP") != "":
		_dump(main._empire_screens)
	main.toggle_empire_screen("chronicles")
	await _frames(4)

	var nest: int = nests[0]
	main._camera.position = st.galaxy.systems[nest].position
	main._camera.zoom = Vector2(1.1, 1.1)
	var herd := Fauna.nest_herds(st, nest)
	if herd.is_empty():
		herd = Fauna.herd_ids(st)
	main.select_fleet(herd[0])
	if OS.get_environment("DUMP") != "":
		print(main._hud._fleet_title.text, " | ", main._hud._fleet_kind.text, " | ", main._hud._fleet_stats.text)
	await _frames(10)
	await _shot(out + "/carte-nid-troupeau.png")
	quit()


## Textes visibles d'un écran (vérification sans regarder l'image).
func _dump(n: Node) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Button and (n as Button).text != "":
		print("  [", (n as Button).text, "]", " (inactif)" if (n as Button).disabled else "", " @", (n as Control).global_position.round())
	elif n is Label and (n as Label).text != "":
		print("  ", (n as Label).text.left(110), " @", (n as Control).global_position.round())
	for c in n.get_children():
		_dump(c)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
