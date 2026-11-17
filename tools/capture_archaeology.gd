extends SceneTree
## Capture de l'onglet Archéologie des Chroniques, et des repères sur la carte, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_archaeology.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Concorde de Vael, archéologie complète. Deux sites connus (dont un en fouille Prudente), une
## piste avancée vers un Monde-berceau, trois antiquités, Déchiffrement des Strates connu.


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
	var st := GameState.create(2026, 150, 1800.0, "vael", {"ai_level": "", "curios": "normales", "archaeology": "complete"})
	main._start(st)
	main.game_in_progress = true
	var me := 0
	var e := st.get_empire(me)
	for r in ["materials", "energy", "influence", "food"]:
		e.resources[r] = 6000
	Research.grant(st, me, ["archeologie_stellaire", "dechiffrement_strates"])
	Relics.add_fragments(st, me, 320)
	var keys := st.digs.keys()
	keys.sort()
	for k in keys:
		e.explored[int(k)] = true
	var sid := int(keys[0])
	st.spawn_ship(me, FactionTraits.ship_ids_for(e.faction_id)[0], sid)
	Relics.start(st, me, sid, "prudente")
	var d := Archaeology.in_game_disparus(st)[0]
	ArchaeoWorld.add_vestiges(st, me, d, 4, [] as Array[Dictionary])
	for i in 3:
		Archaeology.add_antiq(st, me, -1, "d:" + d)
	Archaeology.touch(st)
	main._refresh_all()
	main.set_process(false)
	main.toggle_empire_screen("chronicles")
	await _frames(5)
	main._empire_screens.chron_tab = "archeo"
	main._empire_screens.show_screen("chronicles")
	await _frames(30)
	await _shot(out + "/ecran-archeologie.png")
	main.close_empire_screen()
	await _frames(5)
	main._camera.position = st.galaxy.systems[sid].position
	main._camera.zoom = Vector2(0.9, 0.9)
	main._view.queue_redraw()
	await _frames(20)
	await _shot(out + "/carte-archeologie.png")
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
