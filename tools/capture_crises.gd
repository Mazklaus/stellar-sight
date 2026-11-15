extends SceneTree
## Captures du pilier crises de fin de partie, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_crises.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael (joueur). Le Récif chantant arrive : fenêtre d'arrivée, carte autour de son cœur
## (losanges, anneaux magenta), onglet Crise des Chroniques ; puis la Nuit lente et son Phare ; puis un
## empire devenu Fléau des étoiles.


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
	main.game_options = {"crises": "toutes", "crisis_nemesis": true, "terrain": "normal"}
	main.new_game(4242)
	await _frames(5)
	main._main_menu.visible = false
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: int = main.view_empire
	main.set_process(false)
	sim.advance(400)
	for sys in st.galaxy.systems:
		st.get_empire(me).explored[sys.id] = true
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main.close_event_panel()
	var added: Array[Dictionary] = []
	for it: Dictionary in Events.inbox(st, me).duplicate():
		Events.choose(st, me, int(it["id"]), 0, added)
	# Le Récif chantant : présages puis arrivée.
	st.tick = 10800
	Crisis.begin(st, "recif", added)
	main._events_told.clear()
	main._announce_events()
	await _frames(10)
	await _shot(out + "/crise-presage.png")
	main.close_event_panel()
	var c := Crisis.cur(st)
	while String(c.get("stage", "")) == "notice":
		st.tick = int(c["steps"][int(c["step"])])
		Crisis._notice(st, added)
	for it: Dictionary in Events.inbox(st, me).duplicate():
		if String(it["card"]) != "crise_front":
			Events.choose(st, me, int(it["id"]), 0, added)
	main._events_told.clear()
	main._announce_events()
	await _frames(10)
	await _shot(out + "/crise-front-commun.png")
	main.close_event_panel()
	for it: Dictionary in Events.inbox(st, me).duplicate():
		Events.choose(st, me, int(it["id"]), 0, added)
	sim.advance(400)
	main.close_event_panel()
	for it: Dictionary in Events.inbox(st, me).duplicate():
		Events.choose(st, me, int(it["id"]), 0, added)
	var heart := -1
	for f in Crisis.stations(st):
		if Crisis.role_of(st, f.id) == Crisis.ROLE_HEART:
			heart = f.system_id
	if heart < 0 and not Crisis.stations(st).is_empty():
		heart = Crisis.stations(st)[0].system_id
	main._refresh_all()
	main._select(-1)
	if heart >= 0:
		main._camera.position = st.galaxy.get_system(heart).position
	main._camera.zoom = Vector2(0.45, 0.45)
	main._view.queue_redraw()
	main._hud.refresh()
	await _frames(20)
	await _shot(out + "/crise-carte.png")
	main._empire_screens.chron_tab = "crisis"
	main.toggle_empire_screen("chronicles")
	await _frames(10)
	await _shot(out + "/crise-onglet.png")
	main.toggle_empire_screen("chronicles")
	# La Nuit lente et son Phare.
	Crisis._finish(st, "victoire", me, added)
	st.crisis["gap"] = 0
	st.tick += 3600
	Crisis.begin(st, "nuit", added)
	c = Crisis.cur(st)
	while String(c.get("stage", "")) == "notice":
		st.tick = int(c["steps"][int(c["step"])])
		Crisis._notice(st, added)
	st.get_empire(me).resources["energy"] = 900
	for i in 4:
		CrisisKinds.fund(st, (me + i) % st.empires.size(), "energy", added) if CrisisKinds.check_fund(st, (me + i) % st.empires.size(), "energy") == "" else null
	main.close_event_panel()
	main._empire_screens.chron_tab = "crisis"
	main.toggle_empire_screen("chronicles")
	await _frames(10)
	await _shot(out + "/crise-nuit-phare.png")
	main.toggle_empire_screen("chronicles")
	# Le Fléau des étoiles (le joueur prend la voie), la Nuit passée.
	Crisis._finish(st, "victoire", me, added)
	CrisisNemesis.take(st, me, added)
	Research.count_stat(st, me, "conquests", 60)
	st.get_empire(me).resources["energy"] = 2000
	CrisisNemesis.fund(st, me, "energy", added)
	main.close_event_panel()
	main._empire_screens.chron_tab = "crisis"
	main.toggle_empire_screen("chronicles")
	await _frames(10)
	var sc: Node = _find_scroll(main._empire_screens)
	if sc is ScrollContainer:
		(sc as ScrollContainer).scroll_vertical = 100000
		await _frames(5)
	await _shot(out + "/crise-fleau.png")
	quit()


func _find_scroll(n: Node) -> Node:
	if n is ScrollContainer and (n as Control).is_visible_in_tree():
		return n
	for ch in n.get_children():
		var r := _find_scroll(ch)
		if r != null:
			return r
	return null


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
