extends SceneTree
## Captures des bêtes de guerre et des talents par couche (lot 3 B de « Créatures spatiales et gardiens »),
## avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_war_beasts.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : un empire qui a apprivoisé les Nacrelles, avec un Vivarium, une jeune bête et une adulte ;
## Bestiaire (talents du peuple et Vivarium).


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	root.add_child(main)
	await _frames(30)
	var fac := OS.get_environment("FACTION")
	if fac == "":
		fac = "khthari"
	main.player_faction = fac
	main.game_options = {"creatures": "normales"}
	main.new_game(4242)
	await _frames(5)
	main._main_menu.visible = false
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var added: Array[Dictionary] = []
	Fauna.see(st, 0, "nacrelles", 0, added)
	Fauna._meta(st, 0)["study"]["nacrelles"] = -1
	Fauna._meta(st, 0)["stance"]["nacrelles"] = "apprivoise"
	var cap: Colony = st.colonies[st.get_empire(0).capital_planet]
	cap.buildings.append("vivarium")
	st.tick = 2000
	st.fauna["beasts"] = {0: [{"sp": "nacrelles", "born": 1900}, {"sp": "nacrelles", "born": 1500}, {"sp": "nacrelles", "born": 400}]}
	sim.advance(2)
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main.close_event_panel()
	main._empire_screens.chron_tab = "bestiary"
	main._refresh_all()
	main.toggle_empire_screen("chronicles")
	await _frames(10)
	if OS.get_environment("DUMP") != "":
		_dump(main._empire_screens)
	await _shot(out + "/bestiaire-vivarium.png")
	quit()


func _find_scroll(n: Node) -> ScrollContainer:
	if n is ScrollContainer and (n as CanvasItem).is_visible_in_tree():
		return n
	for c in n.get_children():
		var s := _find_scroll(c)
		if s != null:
			return s
	return null


## Textes visibles d'un écran (vérification sans regarder l'image).
func _dump(n: Node) -> void:
	if n is CanvasItem and not (n as CanvasItem).is_visible_in_tree():
		return
	if n is Button and (n as Button).text != "":
		print("  [", (n as Button).text, "]", " (inactif)" if (n as Button).disabled else "", " @", (n as Control).global_position.round())
	elif n is Label and (n as Label).text != "":
		print("  ", (n as Label).text.left(110), " @", (n as Control).global_position.round())
	for c in n.get_children():
		_dump(c)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
