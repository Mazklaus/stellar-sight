extends SceneTree
## Captures des victoires avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_victory.gd
## Écrit les images dans CAPTURE_DIR (par défaut user://captures) : l'écran Victoire du Chœur en
## milieu de partie, le panneau de fin de partie (victoire, puis vue du spectateur), le bouton
## « Unir nos lignées » d'Ossarane, et la page Nouvelle partie avec ses réglages de victoire.


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	main.start_with_menu = false
	root.add_child(main)
	await _frames(30)

	# Chœur (0) en milieu de partie, face à des IA : deux cathédrales debout, Vael qui fait signer sa Charte.
	var st := GameState.create(2026, 150, 1800.0, "choeur", {"ai_level": "veteran"})
	main._start(st)
	main.game_in_progress = true
	for a in 4:
		for b in 4:
			if a != b and not st.get_empire(a).contacts.has(b):
				st.get_empire(a).contacts.append(b)
				st.get_empire(a).contacts.sort()
	st.tick = 12600
	var me := st.get_empire(0)
	Research.grant(st, 0, ["dernier_couplet"])
	me.fervor = 72
	var built := 0
	for s in st.galaxy.systems:
		if built >= 2:
			break
		if st.system_owner(s.id) < 0 and s.planet_count > 0:
			var c := Colony.new()
			c.planet_id = s.planet_ids[0]
			c.owner = 0
			c.kind = Colony.KIND_COLONY
			c.population = 6
			c.buildings.append("cathedrale")
			st.add_colony(c)
			built += 1
	for e in st.empires:
		for sid in 40:
			e.explored[sid * 3 % 150] = true
	var vael := 2
	Diplomacy.sign_treaty(st, vael, 1, Diplomacy.PEACE)
	Diplomacy.sign_treaty(st, vael, 1, Diplomacy.TRADE)
	Research.grant(st, vael, ["charte"])
	st.get_empire(3).stats["digested"] = 9
	var junk: Array[Dictionary] = []
	VictorySystem._monthly(st, 30, junk)
	st.get_empire(vael).victory["charte"] = {"pct": 62, "held": 0, "warn": 1}
	st.get_empire(1).victory["elu"] = {"pct": 37, "held": 0, "warn": 0}
	main._refresh_all()
	main.toggle_empire_screen("victory")
	await _frames(40)
	await _shot(out + "/ecran-victoire-choeur.png")
	main.close_empire_screen()

	# Fin de partie : le Chœur achève l'hymne.
	st.winner = {"empire": 0, "victory": "couplet", "tick": st.tick, "allies": []}
	main._victory_told = false
	main.simulation.ticked.emit(st.tick)
	await _frames(30)
	await _shot(out + "/fin-de-partie-victoire.png")
	main.close_victory_panel()

	# Ossarane : unir ses lignées à un allié de longue date (Diplomatie).
	var so := GameState.create(2026, 150, 1800.0, "ossarane", {"ai_level": "normal"})
	main._start(so)
	for a in 4:
		for b in 4:
			if a != b and not so.get_empire(a).contacts.has(b):
				so.get_empire(a).contacts.append(b)
				so.get_empire(a).contacts.sort()
	so.tick = 9000
	Research.grant(so, 0, ["lignees_croisees"])
	Diplomacy.sign_treaty(so, 0, 2, Diplomacy.PEACE)
	Diplomacy.sign_treaty(so, 0, 2, Diplomacy.ALLIANCE)
	Diplomacy._rel_w(so, 0, 2)["since"] = so.tick - 400
	so.get_empire(0).resources["influence"] = 140
	so.get_empire(0).resources["crystals"] = 30
	main._refresh_all()
	main.toggle_empire_screen("diplomacy")
	main._empire_screens.diplo_selected = 2
	main._empire_screens.show_screen("diplomacy")
	await _frames(40)
	await _shot(out + "/diplomatie-unir-lignees.png")
	main.close_empire_screen()

	# Spectateur : une partie entre IA qui se termine à une date limite très courte.
	var sp := GameState.create(777, 150, 1800.0, "", {"spectator": true, "ai_level": "veteran", "deadline": 1800})
	main._start(sp)
	main.simulation.advance(1800)
	main.follow_empire(0)
	main._refresh_all()
	main.simulation.ticked.emit(sp.tick)
	await _frames(30)
	await _shot(out + "/fin-de-partie-spectateur.png")
	main.close_victory_panel()

	# Nouvelle partie : la date limite et les victoires de peuple.
	main.open_main_menu()
	main._main_menu.show_page("new")
	main._main_menu.select_faction("vael")
	await _frames(40)
	await _shot(out + "/nouvelle-partie-victoire.png")
	quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
