extends SceneTree
## Captures du catalogue de vaisseaux avec le rendu réel :
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_catalogue.gd
## Écrit dans CAPTURE_DIR (par défaut user://captures) : le chantier spatial de la capitale avec
## tout le catalogue d'Ossarane, une bataille entre flottes mixtes et son rapport.


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

	var st := GameState.create(2026, 150, 1800.0, "ossarane", {"ai_level": ""})
	main._start(st)
	main.game_in_progress = true
	var me := st.get_empire(0)
	for r in GameData.resource_ids():
		me.resources[r] = 3000
	var cap: Colony = st.colonies[me.capital_planet]
	cap.buildings.append("arsenal")
	var home := st.galaxy.get_planet(me.capital_planet).system_id
	main.open_system_view(home)
	await _frames(60)
	main._system_screen.set_manage_mode(true)
	main._system_screen.select_planet(me.capital_planet)
	await _frames(40)
	await _shot(out + "/chantier-catalogue.png")
	main._system_screen.set_manage_mode(false)
	main.close_system_view()
	await _frames(20)

	for s in st.galaxy.systems:
		me.explored[s.id] = true
	var front: int = st.galaxy.systems[home].neighbors[0]
	for e in [me, st.get_empire(1)]:
		e.contacts.append(1 - e.id)
	Combat.start_war(st, 0, 1)
	var mine := st.spawn_ship(0, "cuirasse", front)
	mine.fleet_name = "Ost de Saphène"
	for s in ["porte_vaisseaux", "fregate", "fregate", "escorteur", "escorteur", "coursier", "torpilleur"]:
		mine.add_ship(s)
	mine.troops = Combat.max_troops(mine)
	mine.tactic = "distance"
	var foe := st.spawn_ship(1, "croiseur", front)
	for s in ["croiseur", "corvette", "corvette", "corvette", "fregate", "transport"]:
		foe.add_ship(s)
	foe.troops = Combat.max_troops(foe)
	var sim: Simulation = main.simulation
	sim.advance(2)
	main.select_fleet(mine.id)
	main._select(front)
	main._camera.stop_glide()
	main._camera.position = st.galaxy.systems[front].position + Vector2(60, 40)
	main._camera.zoom = Vector2(0.9, 0.9)
	main._refresh_all()
	await _frames(40)
	await _shot(out + "/bataille-flottes-mixtes.png")
	sim.advance(4)
	main._refresh_all()
	main.toggle_battle_report()
	await _frames(30)
	await _shot(out + "/rapport-flottes-mixtes.png")
	quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
