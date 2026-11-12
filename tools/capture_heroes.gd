extends SceneTree
## Captures des héros, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_heroes.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : quelques mois de jeu, une offre « 1 parmi 3 », des héros en poste, puis la galerie
## de portraits de chaque archétype.


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
	main.player_faction = "ossarane"
	main.new_game(4242)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var home: int = st.galaxy.get_planet(st.get_empire(0).capital_planet).system_id
	sim.advance(90)
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()

	# Deux héros de plus, en poste, et une offre qui attend.
	var first := Heroes.ids_of(st, 0)[0]
	var fpost := String(Heroes.class_def(String(st.heroes[first]["cls"]))["post"])
	if _target_for(st, fpost, home) >= 0:
		sim.submit(SimCommands.hero_assign(0, first, fpost, _target_for(st, fpost, home)))
	var o := Heroes.recruit(st, 0, Heroes.make_candidate(st, 0, "orateur", ["capture", 1]))
	sim.submit(SimCommands.hero_assign(0, o, "council", 0))
	var s := Heroes.recruit(st, 0, Heroes.make_candidate(st, 0, "stratege", ["capture", 2]))
	var war := st.spawn_ship(0, "corvette", (st.galaxy.systems[home].neighbors[0]))
	war.add_ship("fregate", -1, Research.mark_gen(st, 0))
	sim.submit(SimCommands.hero_assign(0, s, "fleet", war.id))
	sim.flush_commands()
	Heroes.gain_xp(st, st.heroes[o], 160)
	sim.advance(5)
	Heroes.act(st, 0, "conquests", 40)
	Heroes._maybe_offer(st, 0)
	Heroes.meta(st, 0)["renown"] = 180
	main._refresh_all()

	# 1. L'offre et les héros (une place libre : le choix est possible).
	if Heroes.ids_of(st, 0).size() >= Heroes.cap(st, 0):
		st.heroes.erase(Heroes.ids_of(st, 0)[-1])
		sim.submit(SimCommands.hero_assign(0, Heroes.ids_of(st, 0)[0], "", -1))
		sim.flush_commands()
	main.toggle_empire_screen("heroes")
	await _frames(10)
	await _shot(out + "/pantheon-offre.png")

	# 2. Après le choix : les héros en poste, dont un en route.
	sim.submit(SimCommands.hero_pick(0, 0))
	sim.flush_commands()
	var newest := Heroes.ids_of(st, 0)[-1]
	var post := String(Heroes.class_def(String(st.heroes[newest]["cls"]))["post"])
	var tgt := _target_for(st, post, -1)
	if tgt >= 0:
		sim.submit(SimCommands.hero_assign(0, newest, post, tgt))
		sim.flush_commands()
	main._empire_screens.show_screen("heroes")
	await _frames(10)
	await _shot(out + "/pantheon-heros.png")

	# 2 bis. Vie et mort : un prisonnier rival, un souvenir, un héros mécontent.
	var rival := 1
	var pr := Heroes.recruit(st, rival, Heroes.make_candidate(st, rival, "ombre", ["capture", 3]))
	st.heroes[pr]["jailer"] = 0
	st.heroes[pr]["lvl"] = 2
	Heroes.meta(st, 0)["memorials"].append({"name": "Aldric de Lunelle", "until": st.tick + 4 * Heroes.DAYS_PER_YEAR, "credo": "honneur"})
	st.heroes[Heroes.ids_of(st, 0)[0]]["loy"] = 17
	main._empire_screens.show_screen("heroes")
	await _frames(10)
	await _shot(out + "/pantheon-vie-et-mort.png")
	main.toggle_empire_screen("heroes")
	await _frames(4)

	# 2 ter. Le médaillon d'or sur la carte : une flotte commandée par un héros.
	var led: Fleet = war
	for fid in st.sorted_fleet_ids():
		if not Heroes.at_post(st, "fleet", fid, 0).is_empty():
			led = st.fleets[fid]
	main._camera.position = st.galaxy.systems[led.system_id].position
	main._camera.zoom = Vector2(2.2, 2.2)
	main.select_fleet(led.id)
	main._hud.show_hover(null, Vector2.ZERO)
	main._refresh_all()
	await _frames(8)
	await _shot(out + "/medaillon-flotte.png")

	# 3. La galerie de portraits des héros, un archétype par ligne.
	var layer := CanvasLayer.new()
	layer.layer = 50
	root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.08)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	layer.add_child(bg)
	var col := VBoxContainer.new()
	col.position = Vector2(30, 20)
	col.add_theme_constant_override("separation", 10)
	layer.add_child(col)
	var by_arch := {}
	for p: Dictionary in Heroes.data()["portraits"]:
		for a in p["archetypes"]:
			if not by_arch.has(a):
				by_arch[a] = []
			by_arch[a].append(p)
	var colors := ["#e0574a", "#d1aa4c", "#79bb84", "#8c7ad6"]
	for a in by_arch:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		col.add_child(row)
		var l := Label.new()
		l.text = String(a).capitalize()
		l.custom_minimum_size = Vector2(130, 0)
		row.add_child(l)
		var i := 0
		for p: Dictionary in by_arch[a]:
			var v := VBoxContainer.new()
			var art := Widgets.ArtSlot.new(String(p["id"]), Vector2(130, 120), Color(colors[i % colors.size()]), "faction")
			v.add_child(art)
			var cap := Label.new()
			cap.text = String(p["label"])
			cap.add_theme_font_size_override("font_size", 11)
			cap.custom_minimum_size = Vector2(130, 0)
			cap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			v.add_child(cap)
			row.add_child(v)
			i += 1
	await _frames(10)
	await _shot(out + "/galerie-portraits-heros.png")
	quit()


func _target_for(st: GameState, post: String, home: int) -> int:
	match post:
		"system":
			return home if home >= 0 else _first_system(st)
		"council":
			for seat in Heroes.seats(st, 0):
				if Heroes.assigned_to(st, "council", seat, 0).is_empty():
					return seat
		"fleet":
			for fid in st.sorted_fleet_ids():
				var f: Fleet = st.fleets[fid]
				if f.owner == 0 and Heroes.assigned_to(st, "fleet", fid, 0).is_empty():
					return fid
		"agent":
			for o in st.get_empire(0).contacts:
				if Espionage.cells_on(st, 0, o) > 0:
					return o
	return -1


func _first_system(st: GameState) -> int:
	for s in st.galaxy.systems:
		if st.system_owner(s.id) == 0 and Heroes.assigned_to(st, "system", s.id, 0).is_empty():
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
