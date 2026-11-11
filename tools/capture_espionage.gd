extends SceneTree
## Captures de l'espionnage (lot 1), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_espionage.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : deux rivaux rencontrés ; un réseau Amirauté chez l'un, un réseau naissant chez l'autre,
## une cellule de contre-espionnage, puis la vue système d'un système hors de vue avec le bouton Sonde.


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
	main.player_faction = "ossarane"
	main.new_game(4242)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	sim.advance(200)
	var me: Empire = st.get_empire(0)
	for r in [1, 2]:
		for pair in [[0, r], [r, 0]]:
			if not st.get_empire(pair[0]).contacts.has(pair[1]):
				st.get_empire(pair[0]).contacts.append(pair[1])
				st.get_empire(pair[0]).contacts.sort()
	for k in st.networks.keys():
		if int(st.networks[k]["a"]) == 0:
			st.networks.erase(k)
	st.networks[Espionage.key(0, 1)] = {"a": 0, "b": 1, "cells": 1, "inf": 66}
	st.networks[Espionage.key(0, 0)] = {"a": 0, "b": 0, "cells": 1, "inf": 0}
	st.networks[Espionage.key(0, 2)] = {"a": 0, "b": 2, "cells": 0, "inf": 12}
	Espionage.monthly(st)
	main._refresh_all()
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()

	# 1. L'écran Renseignement, dossier Amirauté ouvert.
	main._empire_screens.intel_selected = 1
	main.toggle_empire_screen("intel")
	await _frames(10)
	await _shot(out + "/renseignement-ecran.png")
	# 2. Un empire sans dossier.
	main._empire_screens.intel_selected = 2
	main._empire_screens.show_screen("intel")
	await _frames(8)
	await _shot(out + "/renseignement-sans-dossier.png")
	main.toggle_empire_screen("intel")
	await _frames(4)

	# 3. Vue système d'un système connu hors de vue : le bouton Sonde.
	var target := -1
	for sid in me.sorted_explored():
		if not Intel.is_live(st, 0, sid) and st.galaxy.systems[sid].planet_count > 0:
			target = sid
			break
	if target >= 0:
		main.set_process(true)
		main.open_system_view(target)
		await _frames(15)
		await _shot(out + "/renseignement-sonde.png")
		main.close_system_view()
	quit()


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
