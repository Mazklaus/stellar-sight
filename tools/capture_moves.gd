extends SceneTree
## Captures des mouvements de population (lot 3 de « Populations mixtes et migrations »), rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_moves.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : la Concorde de Vael abrite une diaspora ossarane (leur empire a disparu) qui réclame une
## terre ; deux convois de réfugiés errent près de la capitale ; écran Colonies (politique d'accueil,
## revendication, talents), carte avec les convois, écran Diplomatie (traité de migration).


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
	main.game_options = {"peoples": "actifs", "migrations": "actives"}
	main.new_game(4242)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var v := 0
	var o := -1
	var other := -1
	for e in st.empires:
		if e.faction_id == "ossarane":
			o = e.id
		elif e.id != v and other < 0 and e.faction_id != "khthari":
			other = e.id
	# L'empire ossarane a disparu ; sa diaspora vit chez les Vael.
	for pid in st.colonies.keys():
		if st.colonies[pid].owner == o:
			st.colonies.erase(pid)
	st.rebuild_ownership()
	st.get_empire(o).eliminated = true
	_plant(st, v, 1, 18, {"ossarane": 16})
	_plant(st, v, 2, 9, {"teyl": 4})
	sim.advance(40)
	Peoples.refresh(st)
	var added: Array[Dictionary] = []
	Movements._claims(st, st.get_empire(v), added)
	Movements.set_policy(st, v, "ouverte")
	# Deux convois près de la capitale.
	var cap := FactionTraits.capital_system(st, v)
	var nb: Array = st.galaxy.systems[cap].neighbors.duplicate()
	nb.sort()
	if nb.size() >= 1:
		st.moves["convoys"] = [{"id": 1, "fid": "khthari", "n": 4, "sid": int(nb[0]), "born": st.tick, "from": 2}]
	if nb.size() >= 2:
		st.moves["convoys"].append({"id": 2, "fid": "murmurants", "n": 2, "sid": int(nb[1]), "born": st.tick, "from": 3})
	st.moves["next_id"] = 3
	# Contact et paix avec un voisin, pour le traité de migration.
	if other >= 0:
		if not st.get_empire(v).contacts.has(other):
			st.get_empire(v).contacts.append(other)
			st.get_empire(other).contacts.append(v)
		Diplomacy.sign_treaty(st, v, other, Diplomacy.PEACE)
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._refresh_all()
	await _frames(6)
	main.toggle_empire_screen("colonies")
	await _frames(10)
	main._empire_screens._side_scroll.scroll_vertical = 100000
	await _frames(4)
	await _shot(out + "/ecran-colonies-accueil.png")
	main.toggle_empire_screen("colonies")
	await _frames(4)
	main._camera.position = st.galaxy.systems[cap].position
	main._camera.zoom = Vector2(1.6, 1.6)
	await _frames(8)
	await _shot(out + "/carte-convois.png")
	if other >= 0:
		main._empire_screens.diplo_selected = other
		main.toggle_empire_screen("diplomacy")
		await _frames(10)
		await _shot(out + "/diplomatie-migration.png")
	quit()


func _plant(st: GameState, empire_id: int, min_jumps: int, pop: int, species: Dictionary) -> int:
	var jumps := FactionTraits.jumps_from(st.galaxy, FactionTraits.capital_system(st, empire_id))
	for s in st.galaxy.systems:
		var j := int(jumps.get(s.id, 999))
		if j < min_jumps or j > min_jumps + 1 or st.system_owner(s.id) >= 0 or s.planet_ids.size() < 2:
			continue
		for pid in s.planet_ids:
			var p := st.galaxy.get_planet(pid)
			if Economy._pop_hab(st, empire_id, p.type) < 60:
				continue
			var c := Colony.new()
			c.planet_id = pid
			c.owner = empire_id
			c.kind = Colony.KIND_COLONY
			c.population = pop
			c.species = species.duplicate()
			st.add_colony(c)
			st.rebuild_ownership()
			for e in st.empires:
				if e.id == empire_id:
					e.explored[s.id] = true
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
