extends SceneTree
## Captures du pilier fédérations et vassaux, lot 2 (le Koinon), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_koinon.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael (joueur) a fondé une Ligue savante avec un allié, un troisième empire y est entré ;
## la ligue est au rang II, une loi est au vote, le trésor a de quoi secourir. Écran Diplomatie : le bloc
## de la ligue, puis la fondation proposée à un autre allié de longue date.


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
	main.game_options = {"vassals": "actifs", "koinon": "actif"}
	main.new_game(4242)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: int = main.view_empire
	sim.advance(240)
	var others: Array[int] = []
	for e in st.empires:
		if e.is_npc():
			continue
		for o in st.empires:
			if o.id != e.id and not o.is_npc() and not e.contacts.has(o.id):
				e.contacts.append(o.id)
		if e.id != me and not Diplomacy.no_treaties(st, e.id) and not e.eliminated:
			others.append(e.id)
	for o in others:
		if Combat.at_war(st, me, o):
			Diplomacy.sign_treaty(st, me, o, Diplomacy.PEACE)
	var a := others[0]
	var b := others[1]
	var c := others[2]
	for x in [a, c]:
		Diplomacy.sign_treaty(st, me, x, Diplomacy.ALLIANCE)
		Diplomacy._rel_w(st, me, x)["since"] = st.tick - 800
		Diplomacy._rel_w(st, me, x)["trust"] = 60
	for x in st.empires:
		x.resources["influence"] = maxi(400, int(x.resources.get("influence", 0)))
	if Koinon.league_of(st, a) >= 0 or Koinon.league_of(st, me) >= 0:
		push_warning("ligue déjà là")
	st.proposals = []
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._refresh_all()
	await _frames(6)
	var screens: EmpireScreens = main._empire_screens
	screens.diplo_selected = c
	main.toggle_empire_screen("diplomacy")
	await _frames(10)
	await _scroll_to(main, "FONDER")
	await _shot(out + "/ecran-koinon-fonder.png")
	var lid := Koinon.found(st, me, a, "savante")
	var l := Koinon.league(st, lid)
	if Combat.at_war(st, b, me):
		Diplomacy.sign_treaty(st, b, me, Diplomacy.PEACE)
	if Combat.at_war(st, b, a):
		Diplomacy.sign_treaty(st, b, a, Diplomacy.PEACE)
	(l["members"] as Array).append(b)
	l["joined"][str(b)] = st.tick
	l["xp"] = 150
	l["coh"] = 46
	l["treasury"] = 340
	l["laws"]["trade"] = 1
	l["laws"]["tax"] = 1
	l["founded"] = st.tick - 900
	# Une loi au vote, que les deux IA ont déjà tranchée à moitié.
	var v := {"id": int(l["vid"]), "kind": "law", "x": 1, "s": "central", "by": a, "until": st.tick + 20, "yes": [a], "no": [b], "ballots": {}}
	l["vid"] = int(l["vid"]) + 1
	(l["votes"] as Array).append(v)
	screens.diplo_selected = a
	screens.show_screen("diplomacy")
	await _frames(10)
	await _scroll_to(main, "Politique commerciale")
	await _shot(out + "/ecran-koinon.png")
	quit()


func _scroll_to(main: Node, text: String) -> void:
	var l := _find_label(main, text)
	if l == null:
		return
	var sc: Node = l.get_parent()
	while sc != null and not sc is ScrollContainer:
		sc = sc.get_parent()
	if sc == null:
		return
	var s := sc as ScrollContainer
	s.scroll_vertical = int(l.global_position.y - s.global_position.y) + s.scroll_vertical - 300
	await _frames(6)


func _find_label(n: Node, text: String) -> Control:
	for c in n.find_children("*", "", true, false):
		if c is Label and (c as Label).is_visible_in_tree() and (c as Label).text.contains(text):
			return c
		if c is Button and (c as Button).is_visible_in_tree() and (c as Button).text.contains(text):
			return c
	return null


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
