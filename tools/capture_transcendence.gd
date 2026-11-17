extends SceneTree
## Capture de l'onglet Transcendance de l'écran Victoires, et du marqueur de l'Œuvre sur la carte, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_transcendence.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Chœur Éternel, Transcendance complète. L'Orée, l'Apothéose, la jauge pleine, l'Œuvre (le
## Trône vide) achevée, un Relais, et le Passage en cours ; un rival sur le Grand Départ à mi-jauge.


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
	var st := GameState.create(2026, 150, 1800.0, "choeur", {"ai_level": "", "transcendence": "complete"})
	main._start(st)
	main.game_in_progress = true
	var me := 0
	var e := st.get_empire(me)
	e.techs["oree"] = true
	Transcendence.sub(st, "path")[str(me)] = "apotheose"
	Transcendence.sub(st, "gauge")[str(me)] = Transcendence.gauge_max()
	var c: Colony = st.colonies[e.capital_planet]
	c.buildings.append("relais_passage")
	var sid := st.galaxy.get_planet(e.capital_planet).system_id
	Transcendence.sub(st, "oeuvre")[str(me)] = {"sys": sid, "stage": 3, "until": 0}
	Transcendence.begin_passage(st, me, [])
	Transcendence.sub(st, "passage")[str(me)]["prog"] = 540
	var rival := 1
	st.get_empire(rival).techs["oree"] = true
	Transcendence.sub(st, "path")[str(rival)] = "depart"
	Transcendence.sub(st, "gauge")[str(rival)] = 560
	main._refresh_all()
	main.set_process(false)
	main.toggle_empire_screen("victory")
	await _frames(5)
	main._empire_screens.show_screen("transcendence")
	await _frames(30)
	await _shot(out + "/ecran-transcendance.png")
	main.close_empire_screen()
	await _frames(5)
	main._camera.position = st.galaxy.systems[sid].position
	main._camera.zoom = Vector2(0.9, 0.9)
	main._view.queue_redraw()
	await _frames(20)
	await _shot(out + "/carte-oeuvre.png")
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
