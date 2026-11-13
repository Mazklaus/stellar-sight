extends SceneTree
## Captures du commerce, lot 3B (talents commerciaux, contrebande, délit d'initié), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_liens.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : le Syndicat Brisecomète (Profit, Syndicat) exploite deux luxes, en reçoit un en contrebande
## et connaît le prochain choc du marché ; onglets Ressources et Marché.


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
	main.player_faction = "brisecomete"
	main.game_options = {"ai_level": "normal", "goods": "normaux", "market": "actif"}
	main.new_game(4242)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	for g in ["soie_vide", "ambre_chantant", "ambre_chantant", "plasmine"]:
		_take(st, 0, g)
	for o in [1, 2]:
		_meet(st, 0, o)
		Diplomacy.sign_treaty(st, 0, o, Diplomacy.PEACE)
		Diplomacy.sign_treaty(st, 0, o, Diplomacy.TRADE)
	_take(st, 1, "encens_fossile")
	_take(st, 2, "corail_orage")
	st.get_empire(0).resources["energy"] = 900
	sim.advance(40)
	main.set_process(false)
	Goods.monthly(st)
	if Goods.check_licence(st, 0, 1, "encens_fossile") == "":
		Goods.buy_licence(st, 0, 1, "encens_fossile")
	if Goods.check_licence(st, 2, 0, "soie_vide") == "":
		Goods.buy_licence(st, 2, 0, "soie_vide")
	Goods.trade_market(st, 0, "materials", 200)
	Goods.set_order(st, 0, "food", -20)
	st.get_empire(0).resources["materials"] = 800
	Goods.offer(st, 0, 1, {"materials": 30}, {"energy": 12}, 60)
	Goods.monthly(st)
	var g := TradeLinks.smuggle_pick(st, 0, 2)
	if g != "":
		TradeLinks.smuggle(st, 0, 2)
	if TradeLinks.learn_insider(st, 0).is_empty():
		st.goods["insider"] = {0: {"tick": st.tick + 300, "res": "ferronoir", "pct": 60}}
	Trade.compute(st)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._refresh_all()
	main._empire_screens.trade_tab = "resources"
	main.toggle_empire_screen("trade")
	await _frames(10)
	await _shot(out + "/onglet-ressources-talents.png")
	main._empire_screens.trade_tab = "market"
	main._empire_screens.trade_deal = {"to": 2, "give_res": "food", "give": 60, "get_res": "energy", "get": 30, "months": 0}
	main._empire_screens.show_screen("trade")
	await _frames(10)
	await _shot(out + "/onglet-marche-initie.png")
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
