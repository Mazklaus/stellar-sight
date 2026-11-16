extends SceneTree
## Captures du pilier La cour et les Grandes Maisons, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_cour.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael après deux ans ; maisons choisies, offices pourvus, un fief donné, une fête, un
## secret tenu. Onglet La Cour de l'écran Trône, en haut puis plus bas, et le réglage de Nouvelle partie.


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
	main.game_options = {"rulers": "mortels", "court": "actives", "faiths": "actives", "politics": "active", "goods": "actifs"}
	main.new_game(4344)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: int = main.view_empire
	var added: Array[Dictionary] = []
	for _i in 6:
		preload("res://tests/court_tests.gd").give_system(st, me)
	sim.advance(40)
	var en := Court.entry(st, me)
	for item: Dictionary in (Events.meta(st, me)["inbox"] as Array).duplicate():
		if String(item["card"]) == "court_houses":
			Events.choose(st, me, int(item["id"]), 3, added)
	sim.advance(680)
	var e := st.get_empire(me)
	e.resources["influence"] = 900
	e.resources["energy"] = 3000
	var hs := Court.houses(st, me)
	var offs := Court.office_ids(st, me)
	for i in mini(hs.size(), offs.size()):
		var h: Dictionary = hs[i]
		var best := -1
		var bv := -1
		for m: Dictionary in h["members"]:
			var v := int(Court.apts(m)[String(Court.office_def(offs[i])["apt"])])
			if v > bv:
				bv = v
				best = int(m["id"])
		Court.act(st, me, "appoint", best, 0, offs[i], added)
	var mm: Dictionary = (hs[0] as Dictionary)["members"][-1]
	Court.act(st, me, "minor", int(mm["id"]), -1, "medecin", added)
	Court.act(st, me, "train", 2, -1, "table", added)
	Court.act(st, me, "fete", -1, -1, "", added)
	(en["levers"] as Dictionary)[str(int((hs[hs.size() - 1] as Dictionary)["id"]))] = st.tick + 1800
	Court.refresh(st, me)
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._refresh_all()
	await _frames(6)
	ThroneScreen.tab = "cour"
	main.toggle_empire_screen("throne")
	await _frames(10)
	await _shot(out + "/ecran-cour.png")
	var sc := _find_scroll(main)
	if sc != null:
		sc.scroll_vertical = 650
		await _frames(6)
		await _shot(out + "/ecran-cour-maisons.png")
		sc.scroll_vertical = 100000
		await _frames(6)
		await _shot(out + "/ecran-cour-faste.png")
	main.toggle_empire_screen("throne")
	await _frames(4)
	quit()


func _find_scroll(n: Node) -> ScrollContainer:
	var best: ScrollContainer = null
	for c in n.find_children("*", "ScrollContainer", true, false):
		var s := c as ScrollContainer
		if s.is_visible_in_tree() and (best == null or s.size.x > best.size.x):
			best = s
	return best


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
