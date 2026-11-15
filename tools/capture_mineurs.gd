extends SceneTree
## Captures du pilier peuples mineurs, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_mineurs.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael (joueur), peuples mineurs « Beaucoup ». Premier contact (fenêtre), carte autour d'un
## peuple, section Peuples mineurs de l'écran Diplomatie avec un protégé ; puis la conquête d'un pré-spatial.


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
	main.game_options = {"minors": "beaucoup", "curios": "normales", "terrain": "normal"}
	main.new_game(4242)
	await _frames(5)
	main._main_menu.visible = false
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: int = main.view_empire
	main.set_process(false)
	sim.advance(200)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main.close_event_panel()
	var added: Array[Dictionary] = []
	for it: Dictionary in Events.inbox(st, me).duplicate():
		Events.choose(st, me, int(it["id"]), 0, added)
	for sys in st.galaxy.systems:
		st.get_empire(me).explored[sys.id] = true
	var ids := Minors.ids(st)
	print("peuples mineurs : ", ids.size())
	if ids.is_empty():
		quit(1)
		return
	# Premier contact avec un peuple encore inconnu (ou le premier).
	var first := ids[0]
	for id in ids:
		if not (Minors.get_m(st, id)["contact"] as Dictionary).has(me) and not Minors.is_pre(st, id):
			first = id
			break
	Minors.meet(st, first, me, added)
	main._events_told.clear()
	main._announce_events()
	await _frames(10)
	await _shot(out + "/mineurs-contact.png")
	main.close_event_panel()
	for id in ids:
		Minors.meet(st, id, me, added)
	for it: Dictionary in Events.inbox(st, me).duplicate():
		Events.choose(st, me, int(it["id"]), 0, added)
	# Un protégé : faveur au plus haut, suzerain.
	Minors.add_fav(st, first, me, 100)
	Minors.set_suzerain(st, first, me, added)
	for it: Dictionary in Events.inbox(st, me).duplicate():
		Events.choose(st, me, int(it["id"]), 0, added)
	# Le peuple sur la carte.
	main._refresh_all()
	main._select(-1)
	main._camera.position = st.galaxy.get_system(Minors.system_of(st, first)).position
	main._camera.zoom = Vector2(0.9, 0.9)
	main._view.queue_redraw()
	main._hud.refresh()
	await _frames(20)
	await _shot(out + "/mineurs-carte.png")
	# Section Peuples mineurs de l'écran Diplomatie, protégé sélectionné.
	st.get_empire(me).resources["influence"] = 400
	main.toggle_empire_screen("diplomacy")
	await _frames(10)
	await _scroll_end(main)
	await _shot(out + "/mineurs-diplomatie.png")
	main.toggle_empire_screen("diplomacy")
	# Conquête d'un pré-spatial : la cité tombe, garder ou raser.
	var pre := -1
	for id in ids:
		if Minors.is_pre(st, id) and id != first:
			pre = id
			break
	if pre >= 0:
		var m := Minors.get_m(st, pre)
		var c: Colony = st.colonies.get(int(m["planet"]))
		var sid := Minors.system_of(st, pre)
		if c != null:
			c.owner = me
		Minors.on_capture(st, sid, me, pre, added)
		main._refresh_all()
		main._events_told.clear()
		main._announce_events()
		await _frames(10)
		await _shot(out + "/mineurs-conquete.png")
		main.close_event_panel()
	quit()


func _scroll_end(main: Node) -> void:
	var sc: Node = _find_scroll(main._empire_screens)
	if sc is ScrollContainer:
		(sc as ScrollContainer).scroll_vertical = 100000
		await _frames(5)


func _find_scroll(n: Node) -> Node:
	var best: Node = null
	if n is ScrollContainer and (n as Control).is_visible_in_tree():
		best = n
	for ch in n.get_children():
		var r := _find_scroll(ch)
		if r != null:
			best = r
	return best


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
