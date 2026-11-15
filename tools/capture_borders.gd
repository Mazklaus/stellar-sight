extends SceneTree
## Captures du pilier frontières et droit de passage, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_borders.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael (joueur), frontières souples. Un voisin ferme ses frontières, un autre les ouvre ;
## une flotte de guerre voisine entre sans droit (intrusion). Écran Diplomatie (bloc Frontières) et
## lentille des frontières.


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
	main.game_options = {"borders": "souples", "wargoals": "actifs", "curios": "nombreuses"}
	main.new_game(4242)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: int = main.view_empire
	sim.advance(300)
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
	for sys in st.galaxy.systems:
		st.get_empire(me).explored[sys.id] = true
	var foe := others[0]
	# Le voisin ferme ses frontières, un autre les ouvre ; le joueur signe un libre-passage avec un troisième.
	Borders.set_policy(st, foe, me, Borders.CLOSED)
	if others.size() >= 2:
		Borders.set_policy(st, others[1], me, Borders.OPEN)
	if others.size() >= 3:
		Diplomacy.sign_treaty(st, me, others[2], Diplomacy.PASSAGE)
	# Une flotte de guerre du voisin entre chez le joueur sans droit.
	var home := FactionTraits.capital_system(st, me)
	var intruder := st.spawn_ship(foe, "corvette", home)
	intruder.add_ship("corvette")
	st.borders["first"]["%d>%d" % [me, foe]] = 1
	sim.step()
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
	await _scroll_to(main, "Frontières")
	await _shot(out + "/ecran-frontieres.png")
	main.toggle_empire_screen("diplomacy")
	await _frames(4)
	main._hud.set_lens("borders")
	main._view.queue_redraw()
	main._go_to_system(home)
	await _frames(20)
	main._camera.zoom = main._camera.zoom * 0.6
	main._view.queue_redraw()
	await _frames(40)
	await _shot(out + "/lentille-frontieres.png")
	main._hud.set_lens("")
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
