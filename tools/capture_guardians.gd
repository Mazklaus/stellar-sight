extends SceneTree
## Captures des gardiens (lot 2 de « Créatures spatiales et gardiens »), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_guardians.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : un empire Vael qui a repéré tous les gardiens et en a abattu un ; Bestiaire (section
## Gardiens), carte avec le crâne et la fiche d'un gardien, carte de récit dans les Événements.


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	root.add_child(main)
	await _frames(30)
	main.player_faction = "vael"
	main.game_options = {"creatures": "normales"}
	main.new_game(4242)
	await _frames(5)
	main._main_menu.visible = false
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var e := st.get_empire(0)
	for gid in Guardians.ids(st):
		var sid := int(Guardians.list(st)[gid]["sid"])
		e.explored[sid] = true
		for n in st.galaxy.systems[sid].neighbors:
			e.explored[n] = true
		Guardians.list(st)[gid]["seen"][0] = 0
	var ids := Guardians.ids(st)
	var victim := "vouivre" if ids.has("vouivre") else ids[0]
	var added: Array[Dictionary] = []
	var vf: Fleet = st.fleets[int(Guardians.list(st)[victim]["fleet"])]
	vf.ships.clear()
	vf.hp.clear()
	Guardians.on_battle(st, {"system": vf.system_id}, 0, added)
	sim.advance(2)
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main.close_event_panel()
	main._empire_screens.chron_tab = "bestiary"
	main._refresh_all()
	main.toggle_empire_screen("chronicles")
	await _frames(10)
	var scroll := _find_scroll(main._empire_screens)
	if scroll != null:
		scroll.scroll_vertical = 100000
		await _frames(5)
	await _shot(out + "/bestiaire-gardiens.png")
	if OS.get_environment("DUMP") != "":
		_dump(main._empire_screens)
	main._empire_screens.chron_tab = "events"
	main._refresh_all()
	await _frames(10)
	await _shot(out + "/recit-gardien.png")
	main.toggle_empire_screen("chronicles")
	main.close_event_panel()
	await _frames(4)

	var show := ""
	for gid in ids:
		if String(Guardians.list(st)[gid]["status"]) == "awake":
			show = gid
			break
	var f: Fleet = st.fleets[int(Guardians.list(st)[show]["fleet"])]
	main.select_fleet(f.id)
	await _frames(2)
	main._camera.position = st.galaxy.systems[f.system_id].position
	main._camera.zoom = Vector2(2.2, 2.2)
	if OS.get_environment("DUMP") != "":
		print(main._hud._fleet_title.text, " | ", main._hud._fleet_kind.text, " | ", main._hud._fleet_stats.text)
	await _frames(10)
	await _shot(out + "/carte-gardien.png")
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
