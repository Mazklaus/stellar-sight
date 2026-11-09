extends SceneTree
## Captures du combat spatial avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_combat.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures) : une bataille
## en cours (fiche de flotte), le rapport de bataille, un siège avec le bouton d'invasion, l'écran
## Diplomatie avec la guerre, et une partie de spectateur en pleine guerre.


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	main.start_with_menu = false
	root.add_child(main)
	await _frames(30)

	# Une partie Ossarane sans IA : on place les flottes à la main.
	var st := GameState.create(2026, 150, 1800.0, "ossarane", {"ai_level": ""})
	main._start(st)
	main.game_in_progress = true
	for s in st.galaxy.systems:
		st.get_empire(0).explored[s.id] = true
	var home := st.galaxy.get_planet(st.get_empire(0).capital_planet).system_id
	var front: int = st.galaxy.systems[home].neighbors[0]
	for e in [st.get_empire(0), st.get_empire(1)]:
		e.contacts.append(1 - e.id)
	Combat.start_war(st, 0, 1)
	var mine := st.spawn_ship(0, "fregate", front)
	mine.fleet_name = "Ost de Saphène"
	for s in ["fregate", "croiseur", "corvette", "corvette"]:
		mine.add_ship(s)
	mine.troops = Combat.max_troops(mine)
	mine.tactic = "distance"
	var foe := st.spawn_ship(1, "corvette", front)
	for s in ["corvette", "corvette", "fregate", "fregate"]:
		foe.add_ship(s)
	var sim: Simulation = main.simulation
	sim.advance(3)
	main.select_fleet(mine.id)
	main._select(front)
	main._camera.stop_glide()
	main._camera.position = st.galaxy.systems[front].position + Vector2(60, 40)
	main._camera.zoom = Vector2(0.9, 0.9)
	main._refresh_all()
	await _frames(40)
	await _shot(out + "/bataille-en-cours.png")

	sim.advance(3)
	main._refresh_all()
	main.toggle_battle_report()
	await _frames(30)
	await _shot(out + "/rapport-de-bataille.png")
	main.toggle_battle_report()

	# Siège de la capitale ennemie.
	var target := st.galaxy.get_planet(st.get_empire(1).capital_planet).system_id
	for fid in st.sorted_fleet_ids():
		if st.fleets[fid].owner == 1:
			st.fleets.erase(fid)
	var siege := st.spawn_ship(0, "croiseur", target)
	siege.fleet_name = "Ban de Vaëlis"
	for s in ["croiseur", "croiseur", "fregate"]:
		siege.add_ship(s)
	siege.troops = Combat.max_troops(siege)
	var days := 0
	while Combat.garrison(st, target) >= siege.troops and days < 200:
		sim.step()
		days += 1
	main.select_fleet(siege.id)
	main._select(target)
	main._camera.stop_glide()
	main._camera.position = st.galaxy.systems[target].position + Vector2(60, 40)
	main._camera.zoom = Vector2(0.9, 0.9)
	main._refresh_all()
	await _frames(40)
	await _shot(out + "/siege-invasion.png")

	main.toggle_empire_screen("diplomacy")
	await _frames(30)
	await _shot(out + "/diplomatie-guerre.png")
	main.close_empire_screen()

	# Spectateur : quatre IA belliqueuses, trois ans de guerre.
	var sp := GameState.create(17, 150, 1800.0, "", {"spectator": true, "ai_level": "veteran", "temperament": "belliqueux"})
	main._start(sp)
	var ssim: Simulation = main.simulation
	var guard := 0
	while guard < 360 * 4 and (ssim.state.tick < 360 * 2 or ssim.state.battles.is_empty()):
		ssim.step()
		guard += 1
	main._camera.stop_glide()
	main._camera.position = Vector2(0, 0)
	main._camera.zoom = Vector2(0.26, 0.26)
	main._refresh_all()
	await _frames(60)
	await _shot(out + "/spectateur-guerre.png")
	quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
