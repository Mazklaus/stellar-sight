extends SceneTree
## Captures du pilier rayonnement culturel, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_rayonnement.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael (joueur), rayonnement actif, défections actives. Deux ans de partie, puis un musée,
## un rayonnement poussé chez chaque voisin, l'écran Rayonnement et la lentille Culture ; enfin le bloc
## Règles de la nouvelle partie.


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
	main.game_options = {"culture": "actif", "culture_defect": "active", "minors": "normal"}
	main.new_game(4242)
	await _frames(5)
	main._main_menu.visible = false
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: int = main.view_empire
	main.set_process(false)
	print("avance…")
	sim.advance(420)
	print("avancé")
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main.close_event_panel()
	var added: Array[Dictionary] = []
	for it: Dictionary in Events.inbox(st, me).duplicate():
		Events.choose(st, me, int(it["id"]), 0, added)
	var emp := st.get_empire(me)
	for sys in st.galaxy.systems:
		emp.explored[sys.id] = true
	# Un rayonnement avancé : chaque voisin reçoit un palier différent, et une culture étrangère chez nous.
	var others: Array[int] = []
	for e in st.empires:
		if e.id != me and not e.is_npc() and not e.eliminated:
			others.append(e.id)
	var pcts := [130, 75, 40, 215, 15]
	for i in others.size():
		var b: int = others[i]
		var pat := Culture.heritage(st, b)
		st.culture["cum"][Culture._k(me, b)] = pat * int(pcts[i % pcts.size()]) / 100
		st.culture["cum"][Culture._k(b, me)] = Culture.heritage(st, me) * 35 / 100
	sim.advance(31)
	main.close_event_panel()
	for it: Dictionary in Events.inbox(st, me).duplicate():
		Events.choose(st, me, int(it["id"]), 0, added)
	emp.resources["influence"] = 400
	emp.resources["energy"] = 2000
	main._refresh_all()
	main.toggle_empire_screen("culture")
	await _frames(10)
	await _shot(out + "/rayonnement-ecran.png")
	main.toggle_empire_screen("culture")
	# La lentille Culture.
	main._select(-1)
	main._camera.position = st.galaxy.get_system(st.galaxy.get_planet(emp.capital_planet).system_id).position
	main._view.fog = false
	main._hud.set_lens("culture")
	main._view.queue_redraw()
	main._hud.refresh()
	await _frames(10)
	main._camera.zoom = main._camera.zoom * 0.45
	main._view.queue_redraw()
	await _frames(30)
	await _shot(out + "/rayonnement-lentille.png")
	main._hud.set_lens("")
	# Le bloc Règles de la nouvelle partie.
	main.open_main_menu()
	await _frames(10)
	var menu: MainMenu = main._main_menu
	menu.show_page("new")
	menu.select_faction("vael")
	menu.set_culture("actif")
	await _frames(5)
	menu._game_scroll.ensure_control_visible(menu._culture_defect_select)
	await _frames(5)
	await _shot(out + "/rayonnement-reglages.png")
	quit()


func _scroll_of(n: Node) -> ScrollContainer:
	var p := n.get_parent()
	while p != null:
		if p is ScrollContainer:
			return p
		p = p.get_parent()
	return null


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
