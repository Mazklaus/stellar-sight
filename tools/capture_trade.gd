extends SceneTree
## Captures du commerce (lot 1 : routes et traités), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_trade.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : un empire Vael en accord commercial avec un voisin et en comptoirs ouverts avec un autre,
## un comptoir, deux jeunes colonies dont une desservie, un système de route laissé aux pirates ;
## écran Commerce, table diplomatique, lentille du commerce, puis la même lentille avec un blocus.


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
	main.game_options = {"ai_level": "", "pirates": "normaux"}
	main.new_game(4242)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var home := FactionTraits.capital_system(st, 0)
	_plant(st, 0, 2, 3)
	_plant(st, 0, 3, 2)
	(st.colonies[st.get_empire(0).capital_planet] as Colony).buildings.append("comptoir")
	for o in [1, 2]:
		_meet(st, 0, o)
		Diplomacy.sign_treaty(st, 0, o, Diplomacy.PEACE)
		Diplomacy.sign_treaty(st, 0, o, Diplomacy.TRADE)
	Diplomacy.sign_treaty(st, 0, 1, Diplomacy.TRADE)
	Trade.set_reserve(st, 0, 1)
	sim.advance(400)
	main.set_process(false)
	Trade.compute(st)
	# Un système de route sans présence, que les pirates guettent depuis longtemps.
	for r in Trade.sent_by(st, 0):
		var p: Array = r["path"]
		for i in range(1, p.size() - 1):
			if st.system_owner(int(p[i])) < 0:
				st.trade["risk"][int(p[i])] = 180
				break
	Trade.compute(st)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._refresh_all()
	main.toggle_empire_screen("trade")
	await _frames(10)
	await _shot(out + "/ecran-commerce.png")
	main.toggle_empire_screen("trade")
	await _frames(4)
	main.toggle_empire_screen("diplomacy")
	await _frames(10)
	await _shot(out + "/diplomatie-commerce.png")
	main.toggle_empire_screen("diplomacy")
	await _frames(4)
	main._hud.set_lens("trade")
	main._camera.position = st.galaxy.systems[home].position
	main._camera.zoom = Vector2(0.8, 0.8)
	await _frames(10)
	await _shot(out + "/lentille-commerce.png")
	# Blocus : une corvette d'un troisième empire en guerre sur la route.
	var ext: Array[Dictionary] = []
	for r in Trade.sent_by(st, 0):
		if String(r["kind"]) == "ext":
			ext.append(r)
	if not ext.is_empty():
		var p: Array = ext[0]["path"]
		var enemy := 3 if st.empires.size() > 3 else 2
		_meet(st, 0, enemy)
		st.get_empire(0).wars.append(enemy)
		st.get_empire(enemy).wars.append(0)
		st.spawn_ship(enemy, "corvette", int(p[p.size() / 2]))
		Trade.compute(st)
		main._refresh_all()
		await _frames(10)
		await _shot(out + "/lentille-blocus.png")
		main._hud.set_lens("")
		main.toggle_empire_screen("trade")
		await _frames(10)
		await _shot(out + "/ecran-commerce-blocus.png")
	quit()


func _meet(st: GameState, a: int, b: int) -> void:
	for pr in [[a, b], [b, a]]:
		var e := st.get_empire(int(pr[0]))
		if not e.contacts.has(int(pr[1])):
			e.contacts.append(int(pr[1]))
			e.contacts.sort()


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


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
