extends SceneTree
## Captures du pilier buts de guerre et traités de paix, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_wars.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael (joueur) revendique un système d'un voisin (écran Diplomatie : motifs, revendications),
## lui déclare la guerre pour une conquête, gagne batailles et système (panneau de guerre : score en %,
## buts, reddition exigée avec l'avis de l'adversaire).


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
	main.game_options = {"vassals": "actifs", "koinon": "actif", "wargoals": "actifs"}
	main.new_game(4242)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: int = main.view_empire
	sim.advance(240)
	Wars.data()["claims"]["max_jumps"] = 99  # galaxie de démonstration : voisins éloignés
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
		Diplomacy._rel_w(st, me, o)["truce"] = 0
		Diplomacy._rel_w(st, me, o)["pact"] = Diplomacy.COLD
	var foe := others[0]
	st.get_empire(me).resources["influence"] = 600
	var cap := FactionTraits.capital_system(st, foe)
	var cand: Array = Wars.claim_candidates(st, me, foe, 8).filter(func(x: Array) -> bool: return int(x[0]) != cap)
	if not cand.is_empty():
		Wars.claim(st, me, int(cand[0][0]))
	Diplomacy.remember(st, me, foe, "declared_war")
	st.proposals = []
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._refresh_all()
	await _frames(6)
	var screens: EmpireScreens = main._empire_screens
	screens.diplo_selected = foe
	main.toggle_empire_screen("diplomacy")
	await _frames(10)
	await _scroll_to(main, "Motifs de guerre")
	await _shot(out + "/ecran-motifs-de-guerre.png")
	# La guerre : conquête annoncée, batailles gagnées, revendication prise et tenue.
	Wars.set_pending(st, me, foe, "revendication", "conquete")
	Combat.start_war(st, me, foe)
	var rec := Wars.war(st, me, foe)
	rec["t"] = st.tick - 150
	Wars.on_battle(st, me, foe, 220)
	Wars.on_battle(st, foe, me, 60)
	if not cand.is_empty():
		Combat.capture_system(st, int(cand[0][0]), me)
	rec["hold"][0] = 4
	main._refresh_all()
	screens.diplo_selected = foe
	screens.show_screen("diplomacy")
	await _frames(10)
	await _scroll_to(main, "Score de guerre")
	await _shot(out + "/ecran-guerre-score.png")
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


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
