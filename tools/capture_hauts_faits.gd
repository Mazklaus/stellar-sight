extends SceneTree
## Captures du pilier hauts faits galactiques, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_hauts_faits.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael (joueur), hauts faits « Tous ». Un an et demi de partie, puis quelques hauts faits
## accomplis (par le joueur et par des rivaux) ; la fenêtre de récompense, l'onglet Hauts faits, l'onglet
## Annales, la barre d'empire avec la Gloire, et le bloc Règles de la nouvelle partie.


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
	main.game_options = {"deeds": "tous", "golden_ages": true, "wonders": "toutes", "culture": "actif"}
	main.new_game(4242)
	await _frames(5)
	main._main_menu.visible = false
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: int = main.view_empire
	main.set_process(false)
	print("avance…")
	sim.advance(330)
	print("Gloire du joueur : ", Deeds.glory(st, me), " hauts faits : ", Deeds.held_by(st, me), " éliminé : ", st.get_empire(me).eliminated)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main.close_event_panel()
	main.close_deed_panel()
	var added: Array[Dictionary] = []
	for it: Dictionary in Events.inbox(st, me).duplicate():
		Events.choose(st, me, int(it["id"]), 0, added)
	for it: Dictionary in Deeds.inbox(st, me).duplicate():
		Deeds.choose(st, me, int(it["id"]), 0, added)
	var emp := st.get_empire(me)
	for e in st.empires:
		if e.id != me and not e.is_npc() and not e.eliminated and not emp.contacts.has(e.id):
			emp.contacts.append(e.id)
	# Quelques hauts faits de plus : un gardien abattu, des curiosités, un traité.
	Research.count_stat(st, me, "guardians")
	Research.count_stat(st, me, "curios", 6)
	Heroes.act(st, me, "treaty")
	var rival := -1
	for e in st.empires:
		if e.id != me and not e.is_npc() and not e.eliminated:
			rival = e.id
			break
	if rival >= 0:
		Research.count_stat(st, rival, "battles_won", 4)
		Deeds.add_glory(st, rival, 120)
	DeedsBridges.on_wonder(st, me, "")
	while posmod(st.tick, Deeds.r_int("check_days")) != Deeds.r_int("offset") - 1:
		sim.advance(1)
	sim.advance(1)
	main.close_event_panel()
	for it: Dictionary in Events.inbox(st, me).duplicate():
		Events.choose(st, me, int(it["id"]), 0, added)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._refresh_all()
	await _frames(5)
	# La fenêtre de récompense.
	var box := Deeds.inbox(st, me)
	if not box.is_empty():
		main.open_deed(int(box[0]["id"]))
		await _frames(20)
		await _shot(out + "/hauts-faits-fenetre.png")
		main.close_deed_panel()
		for it: Dictionary in Deeds.inbox(st, me).duplicate():
			if int(it["id"]) != int(box[0]["id"]):
				Deeds.choose(st, me, int(it["id"]), 0, added)
	main._refresh_all()
	await _frames(5)
	# L'onglet Hauts faits des Chroniques.
	main._empire_screens.chron_tab = "deeds"
	main.toggle_empire_screen("chronicles")
	await _frames(15)
	await _shot(out + "/hauts-faits-onglet.png")
	# L'onglet Annales.
	main._empire_screens.chron_tab = "annals"
	main._empire_screens.show_screen("chronicles")
	await _frames(15)
	await _shot(out + "/hauts-faits-annales.png")
	main.toggle_empire_screen("chronicles")
	await _frames(5)
	# La carte, avec la Gloire dans la barre d'empire.
	main._refresh_all()
	await _frames(20)
	await _shot(out + "/hauts-faits-barre.png")
	# Le bloc Règles de la nouvelle partie.
	main.open_main_menu()
	await _frames(10)
	var menu: MainMenu = main._main_menu
	menu.show_page("new")
	menu.select_faction("vael")
	await _frames(5)
	menu._game_scroll.ensure_control_visible(menu._golden_check)
	await _frames(5)
	await _shot(out + "/hauts-faits-reglages.png")
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
