extends SceneTree
## Captures du pilier Spatioports, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_ports.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael après un an, des colonies de un à six sauts de la capitale, un Comptoir relais,
## un port lointain sans liaison (enclave). Onglet Réseau de l'écran Commerce, puis le mode
## Spatioports de la lentille du commerce.

const T := preload("res://tests/ports_tests.gd")


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
	main.player_faction = "vael"
	main.game_options = {"ports": "complet", "private": "complete", "logistics": "complete"}
	main.new_game(4344)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: int = main.view_empire
	var used: Array = []
	for d in [1, 1, 2, 2, 3, 3, 4, 5, 6]:
		var s := T.free_at(st, me, d, used)
		if s < 0:
			continue
		used.append(s)
		var c := T.colonize(st, me, s, 6)
		if d == 3 and not used.has(-3):
			c.buildings.append("comptoir")
			used.append(-3)
		if d == 6:
			c.buildings.append("comptoir")
	sim.advance(360)
	main.set_process(false)
	Ports.refresh(st)
	st.relic_rev += 1
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._refresh_all()
	await _frames(6)
	main._empire_screens.trade_tab = "ports"
	main.toggle_empire_screen("trade")
	await _frames(10)
	await _shot(out + "/ecran-reseau.png")
	main.toggle_empire_screen("trade")
	await _frames(4)
	main._hud.set_lens("ports")
	main._view.lens = "ports"
	main._view.queue_redraw()
	await _frames(8)
	await _shot(out + "/lentille-ports.png")
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
