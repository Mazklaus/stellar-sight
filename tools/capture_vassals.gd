extends SceneTree
## Captures du pilier fédérations et vassaux, lot 1 (paix à conditions et sujets), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_vassals.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael (joueur) mène une guerre (score élevé) et coche ses conditions de paix ; un autre
## empire est son vassal depuis deux ans, avec un deuxième sujet (patronage divisé). Écran Diplomatie :
## les conditions de paix, puis le panneau du sujet.


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
	main.game_options = {"vassals": "actifs"}
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
		if e.id != me and not Diplomacy.no_treaties(st, e.id):
			others.append(e.id)
	for o in others:
		if Combat.at_war(st, me, o):
			Diplomacy.sign_treaty(st, me, o, Diplomacy.PEACE)
	var foe := others[0]
	var sub := others[1]
	var sub2 := others[2]
	# Un vassal depuis deux ans, et un tributaire.
	Vassals.bind(st, me, sub, "vassal", Vassals.preset_clauses("vassal"), 300)
	Vassals.link(st, sub)["since"] = st.tick - 200
	Vassals.bind(st, me, sub2, "tributaire", Vassals.preset_clauses("tributaire"), 200)
	# Une guerre qui tourne bien.
	Diplomacy._rel_w(st, me, foe)["truce"] = 0
	Diplomacy._rel_w(st, me, foe)["pact"] = Diplomacy.COLD
	Combat.start_war(st, me, foe)
	Diplomacy._rel_w(st, me, foe)["since"] = st.tick - 240
	Diplomacy.add_war_score(st, me, foe, 95)
	st.proposals = []
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._refresh_all()
	await _frames(6)
	var screens: EmpireScreens = main._empire_screens
	screens.diplo_selected = foe
	screens.vassal_draft[str(foe)] = {"trib": true, "repar": true, "cede": Vassals.cedable(st, foe).slice(0, 1)}
	main.toggle_empire_screen("diplomacy")
	await _frames(10)
	await _scroll_to(main, "Conditions de paix")
	await _shot(out + "/ecran-paix-conditions.png")
	screens.diplo_selected = sub
	screens.show_screen("diplomacy")
	await _frames(10)
	await _scroll_to(main, "Votre sujet")
	await _shot(out + "/ecran-sujet.png")
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
	for c in n.find_children("*", "Label", true, false):
		var l := c as Label
		if l.is_visible_in_tree() and l.text.contains(text):
			return l
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
