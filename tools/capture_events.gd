extends SceneTree
## Captures des curiosités et des événements (lot 1 de « Événements, quêtes et reliques »), rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_events.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : réglages Événements et Curiosités dans Nouvelle partie ; un empire du Chœur après deux
## ans, une carte avec un choix réservé à la Foi, une autre avec un pari ; l'écran Chroniques ; une
## curiosité en vue système avec un éclaireur qui la sonde.


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	root.add_child(main)
	await _frames(30)
	var menu: MainMenu = main._main_menu
	menu.show_page("new")
	menu.select_faction("choeur")
	await _frames(5)
	await _shot(out + "/nouvelle-partie-evenements.png")

	main.player_faction = "choeur"
	main.game_options = {"curios": "normales", "events": "normaux"}
	main.new_game(4242)
	await _frames(5)
	main._main_menu.visible = false
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	sim.advance(360)
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main.close_event_panel()
	var me := 0
	var e := st.get_empire(me)
	e.resources["energy"] = 600
	e.resources["food"] = 400
	e.resources["influence"] = 150
	# Une carte avec un choix réservé à la Foi (le Chœur est théocrate et croyant).
	var added: Array[Dictionary] = []
	for it: Dictionary in Events.inbox(st, me).duplicate():
		Events.choose(st, me, int(it["id"]), 0, added)
	Events.push(st, me, "comete", {"system": FactionTraits.capital_system(st, me)}, added)
	main._events_told.clear()
	main._announce_events()
	await _frames(10)
	await _shot(out + "/evenement-comete.png")
	if OS.get_environment("DUMP") != "":
		_dump(main._event_panel)
	main.close_event_panel()
	Events.push(st, me, "prophete_docks", {"system": FactionTraits.capital_system(st, me)}, added)
	main._announce_events()
	await _frames(10)
	await _shot(out + "/evenement-prophete.png")
	main.close_event_panel()

	# Une curiosité repérée, un éclaireur dessus.
	var pick := -1
	var ids := st.curios.keys()
	ids.sort()
	var jumps := FactionTraits.jumps_from(st.galaxy, FactionTraits.capital_system(st, me))
	for pid in ids:
		var sid := st.galaxy.get_planet(int(pid)).system_id
		if Curios.is_open(st, int(pid)) and int(st.curios[pid]["lvl"]) <= Curios.detect(st, me) and int(jumps.get(sid, 99)) <= 4 and st.system_owner(sid) < 0:
			pick = int(pid)
			break
	if pick >= 0:
		var sid := st.galaxy.get_planet(pick).system_id
		e.explored[sid] = true
		var sc := st.spawn_ship(me, "scout", sid)
		sc.fleet_name = "Sonde Aube"
		sim.advance(4)
	main._refresh_all()
	main.toggle_empire_screen("chronicles")
	await _frames(10)
	await _shot(out + "/chroniques.png")
	if OS.get_environment("DUMP") != "":
		_dump(main._empire_screens)
	main.toggle_empire_screen("chronicles")
	await _frames(4)
	if pick >= 0:
		main.open_system_view(st.galaxy.get_planet(pick).system_id, pick)
		await _frames(10)
		await _shot(out + "/systeme-curiosite.png")
		main.close_system_view()

	# Lot 2 : un site de fouilles chez nous, deux reliques, un Triomphe en cours.
	if not st.digs.is_empty():
		var keys := st.digs.keys()
		keys.sort()
		var sid := int(keys[0])
		var c := Colony.new()
		c.planet_id = st.galaxy.systems[sid].planet_ids[0]
		c.owner = me
		c.kind = Colony.KIND_OUTPOST
		st.add_colony(c)
		e.explored[sid] = true
		e.resources["energy"] = 600
		e.resources["materials"] = 600
		sim.submit(SimCommands.dig_start(me, sid))
		sim.flush_commands()
		st.digs[sid]["ch"] = 1
		st.digs[sid]["clues"] = 1
	Relics.gain(st, me, "graal_vide")
	Relics.gain(st, me, "lanterne_morts")
	Relics.add_fragments(st, me, 64)
	e.resources["influence"] = 200
	var tadded: Array[Dictionary] = []
	Relics.triumph(st, me, "lanterne_morts", tadded)
	main._refresh_all()
	main.toggle_empire_screen("chronicles")
	await _frames(8)
	var head := _find_text(main._empire_screens, "Reliquaire")
	if head != null:
		var scroll := head.get_parent()
		while scroll != null and not scroll is ScrollContainer:
			scroll = scroll.get_parent()
		if scroll != null:
			(scroll as ScrollContainer).scroll_vertical = int(head.position.y + (head.get_parent() as Control).position.y) - 10
	await _frames(8)
	await _shot(out + "/reliquaire.png")
	if OS.get_environment("DUMP") != "":
		_dump(main._empire_screens)
	main.toggle_empire_screen("chronicles")
	await _frames(4)
	if not st.digs.is_empty():
		var keys2 := st.digs.keys()
		keys2.sort()
		main.open_system_view(int(keys2[0]), st.galaxy.systems[int(keys2[0])].planet_ids[0])
		await _frames(10)
		await _shot(out + "/systeme-fouilles.png")
		main.close_system_view()
	quit()


func _find_text(n: Node, text: String) -> Control:
	if n is Label and (n as Label).text == text:
		return n
	for c in n.get_children():
		var f := _find_text(c, text)
		if f != null:
			return f
	return null


## Textes visibles d'un écran (vérification sans regarder l'image).
func _dump(n: Node) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Button and (n as Button).text != "":
		print("  [", (n as Button).text, "]", " (inactif)" if (n as Button).disabled else "", " @", (n as Control).global_position.round())
	elif n is Label and (n as Label).text != "":
		print("  ", (n as Label).text.left(110), " @", (n as Control).global_position.round())
	for c in n.get_children():
		_dump(c)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
