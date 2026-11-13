extends SceneTree
## Captures du commerce, lot 3A (accords de recherche, licences de technologie, diffusion) :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_savoir.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : l'empire Vael commerce avec deux voisins plus avancés, mène un accord de recherche,
## reçoit une demande de licence et peut en acheter.


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
	main.game_options = {"ai_level": "normal"}
	main.new_game(4242)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	for o in [1, 2]:
		_meet(st, 0, o)
		Diplomacy.sign_treaty(st, 0, o, Diplomacy.PEACE)
		Diplomacy.sign_treaty(st, 0, o, Diplomacy.TRADE)
	_meet(st, 0, 3)
	Diplomacy.sign_treaty(st, 0, 3, Diplomacy.PEACE)
	st.get_empire(0).resources["energy"] = 2000
	for o in [1, 2]:
		st.get_empire(o).resources["energy"] = 2000
		for t: String in GameData.technologies()["technologies"]:
			if int(Research.tech(t).get("era", 1)) == 1 and not Research.is_specific(t) and Research.is_available(st, o, t):
				Research.grant(st, o, [t])
	st.get_empire(0).research_queue = []
	sim.advance(400)
	main.set_process(false)
	if TechTrade.pact_between(st, 0, 1).is_empty() and TechTrade.check_pact(st, 0, 1) == "":
		TechTrade._sign_pact(st, 0, 1)
	var mine := ""
	for t in st.get_empire(0).sorted_techs():
		if TechTrade.sellable(st, 0, String(t)) and Research.is_available(st, 2, String(t)):
			mine = String(t)
			break
	if mine != "":
		st.goods["toff"].append({"id": 900, "kind": "licence", "from": 2, "to": 0, "tech": mine, "until": st.tick + 30})
	Trade.compute(st)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._refresh_all()
	main._empire_screens.trade_tab = "knowledge"
	main.toggle_empire_screen("trade")
	await _frames(10)
	await _shot(out + "/onglet-savoir.png")
	quit()


func _meet(st: GameState, a: int, b: int) -> void:
	for pr in [[a, b], [b, a]]:
		var e := st.get_empire(int(pr[0]))
		if not e.contacts.has(int(pr[1])):
			e.contacts.append(int(pr[1]))
			e.contacts.sort()


func _take(st: GameState, eid: int, good: String) -> void:
	var ids: Array = st.goods["dep"].keys()
	ids.sort()
	for pid in ids:
		if String(st.goods["dep"][pid]) == good and not st.colonies.has(int(pid)):
			var c := Colony.new()
			c.planet_id = int(pid)
			c.owner = eid
			c.kind = Colony.KIND_OUTPOST
			st.add_colony(c)
			return


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
