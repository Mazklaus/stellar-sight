extends SceneTree
## Captures du pilier merveilles galactiques, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_merveilles.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael (joueur), merveilles toutes. Un an et demi de partie, puis un chantier lancé sur la
## capitale, un rival dans la même course, des merveilles achevées dans la galaxie ; l'écran
## Merveilles, la fiche de la capitale, la carte avec ses pyramides, et le bloc Règles.


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
	main.game_options = {"wonders": "toutes", "culture": "actif"}
	main.new_game(4242)
	await _frames(5)
	main._main_menu.visible = false
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: int = main.view_empire
	main.set_process(false)
	print("avance…")
	sim.advance(400)
	print("colonies du joueur : ", Stability.systems_of(st, me).size(), " capitale ", st.get_empire(me).capital_planet, " éliminé ", st.get_empire(me).eliminated)
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
	for r in ["materials", "energy", "influence", "crystals"]:
		emp.resources[r] = 6000
	Research.grant(st, me, ["administration", "arts_holographiques", "chancelleries", "capteurs", "cales_rapides", "logistique", "conscription_planetaire"])
	var home := emp.capital_planet
	# Notre chantier, et un rival dans la même course.
	var w := "bibliotheque_mondes"
	if SimCommands.validate(st, SimCommands.won_act(me, "start", w, home)) != "":
		w = "arche_semenciere"
	sim.submit(SimCommands.won_act(me, "start", w, home))
	sim.flush_commands()
	var rival := -1
	for e in st.empires:
		if e.id != me and not e.is_npc() and not e.eliminated:
			rival = e.id
			break
	if rival >= 0:
		for r in ["materials", "energy", "influence", "crystals"]:
			st.get_empire(rival).resources[r] = 6000
		Research.grant(st, rival, ["administration", "arts_holographiques"])
		var rc := st.get_empire(rival).capital_planet
		st.colonies[rc].population = maxi(st.colonies[rc].population, 9)
		sim.submit(SimCommands.won_act(rival, "start", w, rc))
		sim.flush_commands()
		var re := Wonders.build_of(st, rival, w)
		if not re.is_empty():
			re["pts"] = int(re["need"]) * 52 / 100
		if not emp.contacts.has(rival):
			emp.contacts.append(rival)
	var mine := Wonders.build_of(st, me, w)
	if not mine.is_empty():
		mine["pts"] = int(mine["need"]) * 38 / 100
	# Des merveilles déjà bâties ailleurs dans la galaxie.
	var others: Array[int] = []
	for e in st.empires:
		if e.id != me and not e.is_npc() and not e.eliminated:
			others.append(e.id)
	var done := ["champ_mars", "phare_premiere_route"]
	for i in mini(done.size(), others.size()):
		var pid := st.get_empire(others[i]).capital_planet
		var b: Dictionary = Wonders._m(st, "build")
		if not b.has(done[i]):
			b[done[i]] = {}
		b[done[i]][str(others[i])] = {"p": pid, "pts": 0, "need": 100, "paid": {}, "total": {}, "ok": 1, "since": st.tick, "st": 0}
		Wonders.complete(st, done[i], others[i], added)
	main.close_event_panel()
	for it: Dictionary in Events.inbox(st, me).duplicate():
		Events.choose(st, me, int(it["id"]), 0, added)
	main._refresh_all()
	main.toggle_empire_screen("wonders")
	await _frames(10)
	await _shot(out + "/merveilles-ecran.png")
	main.toggle_empire_screen("wonders")
	await _frames(5)
	# La fiche de la capitale : chantier et merveilles possibles.
	main.open_system_view(st.galaxy.get_planet(home).system_id, home)
	await _frames(15)
	await _shot(out + "/merveilles-fiche.png")
	main.close_system_view()
	await _frames(5)
	# La carte : pyramides des merveilles et des ruines.
	main._select(-1)
	main._camera.position = st.galaxy.get_system(st.galaxy.get_planet(home).system_id).position
	main._view.fog = false
	main._view.queue_redraw()
	await _frames(10)
	main._camera.zoom = main._camera.zoom * 0.5
	main._view.queue_redraw()
	await _frames(30)
	await _shot(out + "/merveilles-carte.png")
	# La fenêtre d'achèvement.
	if not mine.is_empty():
		Wonders.complete(st, w, me, added)
		main._refresh_all()
		var inbox := Events.inbox(st, me)
		if not inbox.is_empty():
			main.open_event(int(inbox[-1]["id"]))
		await _frames(20)
		await _shot(out + "/merveilles-acheve.png")
		main.close_event_panel()
	# Le bloc Règles de la nouvelle partie.
	main.open_main_menu()
	await _frames(10)
	var menu: MainMenu = main._main_menu
	menu.show_page("new")
	menu.select_faction("vael")
	await _frames(5)
	menu._game_scroll.ensure_control_visible(menu._wonders_select)
	await _frames(5)
	await _shot(out + "/merveilles-reglages.png")
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
