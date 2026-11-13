extends SceneTree
## Captures du commerce, lot 2B (Bourse galactique, prix vivants, vaisseaux d'occasion, marché noir) :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_bourse.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : l'empire Vael bâtit la Bourse galactique (marché commun), deux rivaux se font la guerre
## (stratégiques en hausse), un krach frappe la nourriture et un port franc pirate est connu.


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
	main.game_options = {"ai_level": "normal", "goods": "normaux", "market": "actif", "pirates": "normaux"}
	main.new_game(4242)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	for g in ["soie_vide", "plasmine"]:
		_take(st, 0, g)
	for o in [1, 2]:
		_meet(st, 0, o)
		Diplomacy.sign_treaty(st, 0, o, Diplomacy.PEACE)
		Diplomacy.sign_treaty(st, 0, o, Diplomacy.TRADE)
	_meet(st, 1, 2)
	st.get_empire(0).resources["energy"] = 1500
	sim.advance(40)
	main.set_process(false)
	var cap := st.get_empire(0).capital_planet
	(st.colonies[cap] as Colony).buildings.append("bourse_galactique")
	Economy.clear_wonders()
	Combat.start_war(st, 1, 2)
	if not Pirates.lair_ids(st).is_empty():
		var sid: int = Pirates.lair_ids(st)[0]
		Pirates.make_port(st, sid, [])
		st.get_empire(0).explored[sid] = true
	Goods.monthly(st)
	st.goods["shock"] = {"res": "food", "pct": -40, "start": st.tick, "until": st.tick + 180}
	Goods.trade_market(st, 1, "crystals", 100)
	Goods.monthly(st)
	Trade.compute(st)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._refresh_all()
	main._empire_screens.trade_tab = "market"
	main.toggle_empire_screen("trade")
	await _frames(10)
	await _shot(out + "/onglet-marche-bourse.png")
	for sc in _scrolls(main._empire_screens):
		sc.scroll_vertical = 100000
	await _frames(10)
	await _shot(out + "/onglet-marche-bourse-bas.png")
	quit()


func _scrolls(n: Node) -> Array:
	var out := []
	if n is ScrollContainer and (n as Control).is_visible_in_tree():
		out.append(n)
	for c in n.get_children():
		out.append_array(_scrolls(c))
	return out


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
