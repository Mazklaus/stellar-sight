extends SceneTree
## Captures du pilier Furtivité et détection, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_stealth.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Ossarane, furtivité complète. Une de nos corvettes voilées en Silence radio près d'un
## rival (fiche de flotte : camouflage, détection, posture) ; deux flottes rivales voilées tout près de
## notre capitale : l'une identifiée par une vigie, l'autre simple contact gris, sans pavillon.


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
	var st := GameState.create(2026, 150, 1800.0, "ossarane", {"ai_level": "", "stealth": "complete"})
	main._start(st)
	main.game_in_progress = true
	var me := 0
	for s in st.galaxy.systems:
		st.get_empire(me).explored[s.id] = true
	var T := preload("res://tests/stealth_tests.gd")
	var ombre := T.design(st, me, "Ombre", "corvette", ["voile_1"], ["capteurs", "voiles_1"])
	var lame := T.design(st, 1, "Lame d'ombre", "corvette", ["voile_1"], ["capteurs", "voiles_1"])
	var vigie := T.design(st, me, "Vigie", "fregate", ["reseau_detecteurs_1", "capteurs"], ["detecteurs_1"])
	var home := T.home(st, me)
	var near := T.next_to(st, home)
	var mine := st.spawn_ship(me, ombre, near)
	mine.fleet_name = "Voile d'Aube"
	SimCommands.apply(st, SimCommands.stealth_act(me, "pose", mine.id, -1, "silence"))
	st.spawn_ship(me, vigie, home)
	# Deux intrus : l'un à portée de la vigie, l'autre au-delà (contact seulement).
	var far := -1
	for n in st.galaxy.systems[near].neighbors:
		if int(n) != home and not st.galaxy.systems[home].neighbors.has(n):
			far = int(n)
			break
	st.spawn_ship(1, lame, near)
	if far >= 0:
		st.spawn_ship(1, lame, far)
	main._refresh_all()
	main.set_process(false)
	main.simulation.advance(1)
	main._camera.stop_glide()
	main._camera.position = st.galaxy.systems[near].position + Vector2(40, 30)
	main._camera.zoom = Vector2(1.2, 1.2)
	main.select_fleet(mine.id)
	main._refresh_all()
	await _frames(30)
	await _shot(out + "/fiche-flotte-voilee.png")
	main.toggle_empire_screen("shipyard")
	await _frames(20)
	await _shot(out + "/chantier-voile.png")
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
