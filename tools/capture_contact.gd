extends SceneTree
## Capture de l'onglet Contact de l'écran Victoires, et des marqueurs du Signal sur la carte, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_contact.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Lignées d'Ossarane, Contact complet. Écoute profonde, une Oreille à la capitale qui a fini
## d'écouter, un Écho relevé, la jauge à 62 % (Porteuse et Écho déchiffrées) ; un rival à l'écoute.


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
	var st := GameState.create(2026, 150, 1800.0, "ossarane", {"ai_level": "", "contact": "complete"})
	main._start(st)
	main.game_in_progress = true
	var me := 0
	var e := st.get_empire(me)
	e.techs[Contact.listen_tech()] = true
	var c: Colony = st.colonies[e.capital_planet]
	c.buildings.append(Contact.ear_building())
	var sid := st.galaxy.get_planet(e.capital_planet).system_id
	Contact.sub(st, "ears")[str(e.capital_planet)] = Contact.ear_need(st, sid)
	Contact.add_route(st, me, "ear", [])
	Contact.add_route(st, me, "echo", [])
	Contact.sub(st, "share")[str(me)] = 20
	Contact.add_gauge(st, me, 620, [])
	Contact.read_layer(st, me, "outil")
	for s in Contact.echo_sites(st):
		e.explored[s] = true
	var rival := 1
	st.get_empire(rival).techs[Contact.listen_tech()] = true
	Contact.add_route(st, rival, "grammar", [])
	Contact.add_gauge(st, rival, 180, [])
	if not e.contacts.has(rival):
		e.contacts.append(rival)
	main._refresh_all()
	main.set_process(false)
	main.toggle_empire_screen("victory")
	await _frames(5)
	main._empire_screens.show_screen("contact")
	await _frames(30)
	await _shot(out + "/ecran-contact.png")
	main.close_empire_screen()
	await _frames(5)
	main._camera.position = st.galaxy.systems[sid].position
	main._camera.zoom = Vector2(0.9, 0.9)
	main._view.queue_redraw()
	await _frames(20)
	await _shot(out + "/carte-contact.png")
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
