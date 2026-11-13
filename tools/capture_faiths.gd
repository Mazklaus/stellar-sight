extends SceneTree
## Captures de la religion (lot 1 de « Religion »), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_faiths.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : les Murmurants d'Abysse (joueur) après un an et demi ; le Murmure a gagné des colonies, Vael a eu sa
## Révélation, un dogme attend le choix du chef de foi. Écran Foi, lentille de la foi, vue système.


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
	main.player_faction = "murmurants"
	main.game_options = {"faiths": "actives", "peoples": "actifs"}
	main.new_game(4242)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: int = main.view_empire
	var fc := Faiths.founded_by(st, me)
	Faiths.add_dogma(st, fc, "doute_sacre")
	for e in st.empires:
		if e.faction_id == "vael" and Faiths.founded_by(st, e.id) == "":
			Faiths.reveal(st, e.id, "relique", -1, [] as Array[Dictionary])
	sim.advance(540)
	# Quelques colonies du joueur autour de la capitale, aux croyances mêlées.
	var cap0 := FactionTraits.capital_system(st, me)
	var other := ""
	for fid in Faiths.ids(st):
		if fid != fc:
			other = fid
			break
	var mixes := [{fc: 6}, {fc: 3, other: 4}, {other: 5}, {}]
	for i in mixes.size():
		_plant(st, me, cap0, 1 + i % 2, 7, mixes[i])
	for s in st.galaxy.systems:
		st.get_empire(me).explored[s.id] = true
	# Une place de dogme libre, pour montrer le choix du chef de foi.
	var f: Dictionary = st.faiths["list"][fc]
	f["slots"] = maxi(int(f["slots"]), (f["dogmas"] as Array).size() + 1)
	for e in st.empires:
		for s in st.galaxy.systems:
			if st.system_owner(s.id) == me:
				st.get_empire(me).explored[s.id] = true
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._refresh_all()
	await _frames(6)
	main.toggle_empire_screen("faith")
	await _frames(10)
	await _shot(out + "/ecran-foi.png")
	main.toggle_empire_screen("faith")
	await _frames(4)
	main._hud.set_lens("faith")
	await _frames(8)
	await _shot(out + "/lentille-foi.png")
	main._hud.set_lens("")
	await _frames(4)
	var cap := FactionTraits.capital_system(st, me)
	main.open_system_view(cap)
	await _frames(10)
	await _shot(out + "/vue-systeme-foi.png")
	quit()


func _plant(st: GameState, empire_id: int, from: int, min_jumps: int, pop: int, faith: Dictionary) -> void:
	var jumps := FactionTraits.jumps_from(st.galaxy, from)
	for s in st.galaxy.systems:
		var j := int(jumps.get(s.id, 999))
		if j < min_jumps or j > min_jumps + 1 or st.system_owner(s.id) >= 0 or s.planet_ids.is_empty():
			continue
		var c := Colony.new()
		c.planet_id = s.planet_ids[0]
		c.owner = empire_id
		c.kind = Colony.KIND_COLONY
		c.population = pop
		c.faith = faith.duplicate()
		c.faith.erase("")
		st.add_colony(c)
		st.rebuild_ownership()
		return


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
