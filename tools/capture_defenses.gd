extends SceneTree
## Captures du pilier Défenses spatiales, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_defenses.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Ossarane, défenses complètes ; la capitale porte un Rempart stellaire, six modules, des
## plates-formes, un dôme planétaire et un champ de mines. Vue système (panneau Défenses), fiche du
## système sur la carte, puis une flotte ennemie qui attaque : rapport de bataille et vue de replay.


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
	var st := GameState.create(2026, 150, 1800.0, "ossarane", {"ai_level": "", "defenses": "complete"})
	main._start(st)
	main.game_in_progress = true
	var me := 0
	for s in st.galaxy.systems:
		st.get_empire(me).explored[s.id] = true
	preload("res://tests/defenses_tests.gd").learn_all(st, me)
	var c: Colony = st.colonies[st.get_empire(me).capital_planet]
	var home := st.galaxy.get_planet(c.planet_id).system_id
	c.population = 14
	c.buildings.append_array(["rempart_stellaire", "module_batterie", "module_missiles", "module_rayons", "module_blindage",
			"module_bouclier", "module_inhibiteur", "plateforme_canon", "plateforme_canon", "plateforme_missiles",
			"plateforme_rayons", "plateforme_antimissile", "bouclier_planetaire_2", "batterie_planetaire"])
	Defenses._sub(st, "mines")[str(home)] = {"o": me, "d": 60}
	main._refresh_all()
	main.set_process(false)
	await _frames(6)
	main.open_system_view(home)
	await _frames(20)
	await _shot(out + "/vue-systeme-defenses.png")
	main.close_system_view()
	await _frames(6)
	# Attaque : une flotte de l'empire 1 entre en guerre et s'arrête devant la station.
	for e in [st.get_empire(0), st.get_empire(1)]:
		e.contacts.append(1 - e.id)
	Combat.start_war(st, 0, 1)
	var foe := st.spawn_ship(1, "croiseur", home)
	for s in ["croiseur", "fregate", "fregate", "corvette", "corvette", "bombarde"]:
		foe.add_ship(s)
	foe.fleet_name = "Ost de l'assaut"
	main.simulation.advance(3)
	main._select(home)
	main._camera.stop_glide()
	main._camera.position = st.galaxy.systems[home].position + Vector2(60, 40)
	main._camera.zoom = Vector2(0.9, 0.9)
	main._refresh_all()
	await _frames(30)
	await _shot(out + "/fiche-systeme-assaut.png")
	main.simulation.advance(3)
	main._refresh_all()
	main.toggle_battle_report()
	await _frames(30)
	await _shot(out + "/rapport-bataille-station.png")
	main.toggle_battle_report()
	await _frames(4)
	if not st.battle_reports.is_empty():
		main._hud.battle_replay.show_replay(st, me, st.battle_reports[-1])
		await _frames(90)
		await _shot(out + "/replay-station.png")
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
