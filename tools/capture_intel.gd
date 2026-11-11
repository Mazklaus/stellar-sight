extends SceneTree
## Captures de la dernière information connue, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_intel.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : un éclaireur aperçoit un système libre puis s'en va ; un rival s'y installe hors de vue.


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
	var me: Empire = st.get_empire(0)
	var home: int = st.galaxy.get_planet(me.capital_planet).system_id

	# Un système libre à quelques sauts, qu'on aperçoit avec un éclaireur posé là puis retiré.
	var target := _target(st, home)
	var scout := st.spawn_ship(0, "scout", target)
	sim.step()
	st.fleets.erase(scout.id)
	sim.advance(2)
	# Hors de vue, un rival y pose deux revendications.
	var rival := 1
	var n := 0
	for pid in st.galaxy.systems[target].planet_ids:
		if n < 2:
			var c := Colony.new()
			c.planet_id = pid
			c.owner = rival
			c.kind = Colony.KIND_COLONY if n == 0 else Colony.KIND_OUTPOST
			c.population = 3 if n == 0 else 0
			st.add_colony(c)
			n += 1
	sim.advance(75)
	main._refresh_all()

	var focus: Vector2 = st.galaxy.systems[target].position.lerp(st.galaxy.systems[home].position, 0.35)
	main._camera.position = focus
	main._camera.zoom = Vector2(0.7, 0.7)
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()

	# 1. Ce que sait le joueur : le système tel qu'il l'a vu, libre, il y a deux mois et demi.
	main._select(target)
	main._view.hovered_id = -1
	main._hud.show_hover(null, Vector2.ZERO)
	main._hud.refresh()
	await _frames(8)
	await _shot(out + "/memoire-hors-de-vue.png")

	# 2. La réalité au même instant (vue d'ensemble du spectateur) : le rival s'y est installé.
	main._view.fog = false
	Intel.lens = -1
	main._refresh_all()
	await _frames(8)
	await _shot(out + "/memoire-realite.png")
	main._view.fog = true
	Intel.lens = 0

	# 3. Un éclaireur repasse : la mémoire se met à jour, puis reste figée à cette date.
	var back := st.spawn_ship(0, "scout", target)
	sim.step()
	st.fleets.erase(back.id)
	sim.advance(20)
	main._refresh_all()
	main._select(target)
	main._hud.show_hover(null, Vector2.ZERO)
	await _frames(8)
	await _shot(out + "/memoire-mise-a-jour.png")

	# 4. Vue système du système mémorisé : les revendications telles qu'on les a vues.
	main.set_process(true)
	main.open_system_view(target)
	await _frames(15)
	await _shot(out + "/memoire-vue-systeme.png")
	main.close_system_view()
	quit()


## Système libre avec au moins deux planètes, à 3 sauts ou plus de la capitale, hors de vue.
func _target(st: GameState, home: int) -> int:
	var seen := Fleets.visible_systems(st, 0)
	var dist := {home: 0}
	var frontier: Array[int] = [home]
	while not frontier.is_empty():
		var next: Array[int] = []
		for s in frontier:
			for nb in st.galaxy.systems[s].neighbors:
				if not dist.has(nb):
					dist[nb] = int(dist[s]) + 1
					next.append(nb)
		frontier = next
	var best := -1
	for s in st.galaxy.systems:
		var d := int(dist.get(s.id, 99))
		if d >= 3 and d <= 4 and s.planet_count >= 2 and st.system_owner(s.id) == -1 and not seen.has(s.id):
			if best == -1 or s.planet_count > st.galaxy.systems[best].planet_count:
				best = s.id
	return best


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
