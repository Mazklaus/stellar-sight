extends SceneTree
## Captures du pilier puissances anciennes, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_anciennes.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael (joueur), anciennes « Beaucoup ». Premier contact (fenêtre), carte autour d'une poche,
## section Anciennes de l'écran Diplomatie ; puis l'éveil d'une parvenue, la Guerre au ciel et la fiche
## d'une ancienne éveillée.


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
	main.game_options = {"ancients": "beaucoup", "awakenings": true, "curios": "normales", "terrain": "normal"}
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
	var ids := Ancients.ids(st)
	print("anciennes : ", ids.size())
	if ids.is_empty():
		quit(1)
		return
	# Premier contact : la fiche de la première ancienne.
	Ancients.meet(st, ids[0], me, added)
	main._events_told.clear()
	main._announce_events()
	await _frames(10)
	await _shot(out + "/anciennes-contact.png")
	main.close_event_panel()
	for id in ids:
		Ancients.meet(st, id, me, added)
	for it: Dictionary in Events.inbox(st, me).duplicate():
		Events.choose(st, me, int(it["id"]), 0, added)
	# La poche sur la carte.
	main._refresh_all()
	main._select(-1)
	main._camera.position = st.galaxy.get_system(int(Ancients.get_a(st, ids[0])["home"])).position
	main._camera.zoom = Vector2(0.9, 0.9)
	main._view.queue_redraw()
	main._hud.refresh()
	await _frames(20)
	await _shot(out + "/anciennes-carte.png")
	# Section Anciennes de l'écran Diplomatie.
	st.get_empire(me).resources["energy"] = 2000
	Ancients.give(st, me, ids[0], "energy")
	Ancients.give(st, me, ids[0], "energy")
	main.toggle_empire_screen("diplomacy")
	await _frames(10)
	await _scroll_end(main)
	await _shot(out + "/anciennes-diplomatie.png")
	main.toggle_empire_screen("diplomacy")
	# Éveil d'une parvenue, puis Guerre au ciel si sa rivale est là.
	var parv := -1
	for id in ids:
		if AncientsWake.roles(st, id).has("parvenue") and Ancients.id_of_kind(st, String(Ancients.kind_def(Ancients.kind_of(st, id)).get("rival", ""))) >= 0:
			parv = id
	if parv < 0:
		for id in ids:
			if AncientsWake.roles(st, id).has("parvenue"):
				parv = id
	if parv >= 0:
		Ancients.get_a(st, parv)["why"] = "On dit que la puissance d'un empire voisin l'a tirée de son sommeil."
		AncientsWake.notice(st, parv, added)
		AncientsWake.awaken(st, parv, added)
		main._events_told.clear()
		main._announce_events()
		await _frames(10)
		var shown := false
		for i in 3:
			var top: Dictionary = Events.inbox(st, me)[0] if not Events.inbox(st, me).is_empty() else {}
			if not top.is_empty() and String(top["card"]) == "anc_eveil":
				break
			if not top.is_empty():
				Events.choose(st, me, int(top["id"]), 0, added)
			main._events_told.clear()
			main._announce_events()
			await _frames(5)
		await _shot(out + "/anciennes-eveil.png")
		main.close_event_panel()
		for it: Dictionary in Events.inbox(st, me).duplicate():
			Events.choose(st, me, int(it["id"]), 1 if String(it["card"]) == "anc_eveil" else 0, added)
		var rival := Ancients.id_of_kind(st, String(Ancients.kind_def(Ancients.kind_of(st, parv)).get("rival", "")))
		if rival >= 0:
			AncientsWake.start_heaven(st, parv, rival, added)
			main._events_told.clear()
			main._announce_events()
			await _frames(10)
			await _shot(out + "/anciennes-guerre-ciel.png")
			main.close_event_panel()
			for it: Dictionary in Events.inbox(st, me).duplicate():
				Events.choose(st, me, int(it["id"]), 2 if String(it["card"]) == "anc_guerre_ciel" else 0, added)
		sim.advance(60)
		main.close_event_panel()
		main.toggle_empire_screen("diplomacy")
		await _frames(10)
		await _scroll_end(main)
		await _shot(out + "/anciennes-eveillee.png")
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
