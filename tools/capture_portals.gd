extends SceneTree
## Captures du pilier Portails de saut, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_portals.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael, portails complets, toute la carte explorée et les technologies connues ; la capitale
## porte un relais et un portail, un voisin un relais (corridor), un système lointain un portail.
## Carte (trous de ver, corridor, portails, ruines), puis vue système (ligne Passages).


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
	var st := GameState.create(2026, 120, 1600.0, "vael", {"ai_level": "", "portals": "complets"})
	main._start(st)
	main.game_in_progress = true
	var me := 0
	var e := st.get_empire(me)
	for s in st.galaxy.systems:
		e.explored[s.id] = true
	for t in ["stabilisation_ver", "relais_hyperspatiaux", "portails_saut"]:
		e.techs[t] = true
	var T := preload("res://tests/portals_tests.gd")
	var home := T.cap_sys(st, me)
	var n1 := -1
	for n in st.galaxy.systems[home].neighbors:
		if st.system_owner(n) < 0 and not st.galaxy.systems[n].planet_ids.is_empty():
			n1 = n
			break
	if n1 >= 0:
		T.colonize(st, me, n1)
		T.build(st, n1, "relais_hyper")
	T.build(st, home, "relais_hyper")
	var far := T.free_at(st, home, 5)
	if far >= 0:
		T.colonize(st, me, far)
		T.build(st, far, "portail_saut")
	T.build(st, home, "portail_saut")
	# Les trous de ver dont une bouche est explorée sont connus.
	var added: Array[Dictionary] = []
	Portals._discover(st, added)
	main._refresh_all()
	main.set_process(false)
	await _frames(6)
	main._select(home)
	main._camera.stop_glide()
	main._camera.position = st.galaxy.systems[home].position
	main._camera.zoom = Vector2(0.45, 0.45)
	main._refresh_all()
	await _frames(30)
	await _shot(out + "/carte-portails.png")
	main.open_system_view(home)
	await _frames(20)
	await _shot(out + "/vue-systeme-passages.png")
	main.close_system_view()
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
