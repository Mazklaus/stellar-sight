extends SceneTree
## Captures de la vue de replay des batailles avec le rendu réel :
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_replay.gd
## Écrit dans CAPTURE_DIR (par défaut user://captures) : le rapport avec son bouton, puis la vue
## arrêtée au milieu d'un jour de chaque phase (missiles, rayons, canons).


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
	var home := st.galaxy.get_planet(me.capital_planet).system_id
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
	sim.advance(8)
	main._refresh_all()
	main.toggle_battle_report()
	await _frames(30)
	await _shot(out + "/rapport-revoir.png")
	main._hud.battle_report.request_replay()
	var rp: BattleReplayPanel = main._hud.battle_replay
	var names := ["replay-longue-portee", "replay-moyenne-portee", "replay-courte-portee"]
	var days := [0, 2, 4]
	for i in 3:
		rp.playing = false
		rp.t = (days[i] + 0.55) * BattleReplayPanel.DAY_SECONDS
		rp._refresh_buttons()
		await _frames(20)
		await _shot(out + "/%s.png" % names[i])
	quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
