extends SceneTree
## Captures de la politique intérieure (lots 1 et 2 de « Politique des peuples »), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_politics.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : un empire Vael (République) avec six colonies aux opinions variées, une élection tenue ;
## écran Sénat, fenêtre d'élection (résultats et dépouillement), lentille politique ; puis le Chœur
## Éternel (Conclave) qui nomme un autre courant que celui du peuple.


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
	await _scene(main, "vael", out, "")
	await _scene(main, "choeur", out, "-choeur")
	quit()


func _scene(main: Node, faction: String, out: String, suffix: String) -> void:
	main.player_faction = faction
	main.game_options = {"politics": "active"}
	main.new_game(4242)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var home := FactionTraits.capital_system(st, 0)
	var planted: Array[int] = []
	for j in [1, 2, 2, 3, 4, 5]:
		var sid := _plant(st, 0, j, 3 + j)
		if sid >= 0:
			planted.append(sid)
	sim.advance(300)
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	# Des actes qui ont marqué les esprits : une guerre, des colonies, des technologies, une cathédrale.
	var pushes := [["glaive", 260], ["seve", 300], ["forge", 220], ["autel", 280], ["concorde", 200], ["academie", 150]]
	for i in planted.size():
		Politics.push(st, planted[i], Politics.index_of(String(pushes[i % pushes.size()][0])), int(pushes[i % pushes.size()][1]))
	Politics.push(st, home, Politics.index_of("autel" if faction == "choeur" else "academie"), 150)
	if faction == "choeur":
		st.get_empire(0).fervor = 70
		Politics.support(st, 0, Politics.index_of("forge"))
	else:
		Politics.support(st, 0, Politics.index_of("concorde"))
	Politics.run_election(st, 0)
	for sid in Stability.systems_of(st, 0):
		for _m in 6:
			StabilitySystem._monthly_system(st, st.get_empire(0), sid, 30, Stability.context(st, 0), [])
	main._refresh_all()
	main._election_told = -1
	main._announce_election()
	await _frames(10)
	await _shot(out + "/election-resultats%s.png" % suffix)
	main._election_panel.show_step(1)
	await _frames(6)
	await _shot(out + "/election-depouillement%s.png" % suffix)
	main.close_election_panel()
	await _frames(4)
	main.toggle_empire_screen("senate")
	await _frames(10)
	await _shot(out + "/senat%s.png" % suffix)
	main.toggle_empire_screen("senate")
	await _frames(4)
	if suffix == "":
		# Lot 2 : des lois adoptées, une campagne lancée, puis le bloc des lois.
		var e := st.get_empire(0)
		e.resources["influence"] = 400
		var en := Laws._w(st, 0)
		for i in Politics.ruling(st, 0):
			en["xp"][int(i)] = 2
		st.relic_rev += 1
		var r: Array = Politics.ruling(st, 0)
		sim.submit(SimCommands.law_adopt(0, String(Laws.current_laws(int(r[0]))[0]["id"])))
		sim.submit(SimCommands.law_adopt(0, String(Laws.current_laws(int(r[0]))[1]["id"])))
		if r.size() > 1:
			sim.submit(SimCommands.law_adopt(0, String(Laws.current_laws(int(r[1]))[0]["id"])))
		sim.submit(SimCommands.law_adopt(0, "libre_echange"))
		sim.submit(SimCommands.politics_support(0, int(r[0])))
		sim.flush_commands()
		sim.submit(SimCommands.politics_action(0, "campagne"))
		sim.flush_commands()
		main._refresh_all()
		main.toggle_empire_screen("senate")
		await _frames(10)
		var sc := _find_scroll(main._empire_screens._content)
		if sc != null:
			var col := sc.get_child(0)
			sc.scroll_vertical = int((col.get_child(1) as Control).position.y)
			await _frames(6)
		await _shot(out + "/lois.png")
		if sc != null:
			sc.scroll_vertical = int((sc.get_child(0).get_child(2) as Control).position.y)
			await _frames(6)
		await _shot(out + "/lois-suite.png")
		main.toggle_empire_screen("senate")
		await _frames(4)
		main._hud.set_lens("politics")
		main._camera.position = st.galaxy.systems[home].position
		main._camera.zoom = Vector2(0.9, 0.9)
		await _frames(10)
		await _shot(out + "/carte-politique.png")
		main._hud.set_lens("")
		await _frames(4)


func _plant(st: GameState, empire_id: int, min_jumps: int, pop: int) -> int:
	var jumps := FactionTraits.jumps_from(st.galaxy, FactionTraits.capital_system(st, empire_id))
	for s in st.galaxy.systems:
		var j := int(jumps.get(s.id, 999))
		if j < min_jumps or j > min_jumps + 1 or st.system_owner(s.id) >= 0 or s.planet_ids.is_empty():
			continue
		var c := Colony.new()
		c.planet_id = s.planet_ids[0]
		c.owner = empire_id
		c.kind = Colony.KIND_COLONY
		c.population = pop
		st.add_colony(c)
		return s.id
	return -1


func _find_scroll(n: Node) -> ScrollContainer:
	if n is ScrollContainer:
		return n
	for ch in n.get_children():
		var f := _find_scroll(ch)
		if f != null:
			return f
	return null


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
