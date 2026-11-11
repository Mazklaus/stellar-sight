extends SceneTree
## Captures des sprites tirés des modèles 3D (docs/vaisseaux-3d.md) avec le rendu réel :
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_vaisseaux_3d.gd
## Écrit dans CAPTURE_DIR (par défaut user://captures) : une bataille de frégates Ossarane contre
## l'Essaim Kh'thari dans la vue de replay et dans la cinématique 3D, puis la frégate au Chantier pour
## chacun des deux peuples.


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
	var foe_e: Empire = null
	for e in st.empires:
		if e.faction_id == "khthari":
			foe_e = e
	var home := st.galaxy.get_planet(me.capital_planet).system_id
	for s in st.galaxy.systems:
		me.explored[s.id] = true
	var front: int = st.galaxy.systems[home].neighbors[0]
	me.contacts.append(foe_e.id)
	foe_e.contacts.append(me.id)
	Combat.start_war(st, me.id, foe_e.id)
	var mine := st.spawn_ship(me.id, "fregate", front)
	mine.fleet_name = "Ost de Saphène"
	for s in ["fregate", "fregate", "fregate", "corvette", "corvette"]:
		mine.add_ship(s)
	var foe := st.spawn_ship(foe_e.id, "fregate", front)
	for s in ["fregate", "fregate", "fregate", "fregate", "corvette"]:
		foe.add_ship(s)
	var sim: Simulation = main.simulation
	sim.advance(8)
	main._refresh_all()
	main.toggle_battle_report()
	await _frames(30)
	main._hud.battle_report.request_replay()
	var rp: BattleReplayPanel = main._hud.battle_replay
	rp.playing = false
	rp.t = 2.55 * BattleReplayPanel.DAY_SECONDS
	rp._refresh_buttons()
	await _frames(20)
	await _shot(out + "/vaisseaux-3d-replay.png")
	# Cinématique 3D : quelques instants (plans différents), puis la vue d'ensemble.
	rp.open_cinematic()
	var cin := rp.cinematic
	cin.playing = false
	cin._refresh_buttons()
	var end := cin.day_count() * BattleCinematic.DAY_SECONDS
	for f in [0.05, 0.3, 0.45, 0.7, 0.8, 0.9]:
		cin.t = end * f
		cin._update(0.0)
		await _frames(6)
		await _shot(out + "/vaisseaux-3d-cinematique-%02d.png" % int(f * 100))
	cin.overview = true
	cin.t = end * 0.55
	cin._update(0.0)
	await _frames(6)
	await _shot(out + "/vaisseaux-3d-cinematique-ensemble.png")
	cin.hide_cinematic()
	rp.close_silently()
	main.toggle_battle_report()

	for faction in ["ossarane", "khthari"]:
		var st2 := GameState.create(2026, 150, 1800.0, faction, {"ai_level": "normal"})
		main._start(st2)
		main.game_in_progress = true
		main._refresh_all()
		main.toggle_empire_screen("shipyard")
		var screens: EmpireScreens = main._empire_screens
		screens.shipyard.select_design("fregate")
		await _frames(20)
		await _shot(out + "/vaisseaux-3d-chantier-%s.png" % faction)
		main.toggle_empire_screen("shipyard")
		await _frames(5)
	quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
