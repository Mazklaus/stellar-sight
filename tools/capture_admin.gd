extends SceneTree
## Captures du pilier Administration et corruption, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_admin.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vael après deux ans, une douzaine de systèmes (dont un lointain avec un Tribunal), effort
## Généreux. Onglet Administration de l'Ordre intérieur, puis le mode Corruption de la lentille.


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
	main.game_options = {"admin": "complete", "politics": "active"}
	main.new_game(4344)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: int = main.view_empire
	var helper := preload("res://tests/admin_tests.gd")
	var got: Array[int] = []
	for _i in 12:
		var s: int = helper.give_system(st, me, got)
		if s >= 0:
			got.append(s)
	for c: Colony in st.colonies.values():
		if c.owner == me and c.planet_id != st.get_empire(me).capital_planet:
			c.population = 8
	if not got.is_empty():
		var far: Colony = st.colonies[st.galaxy.systems[got[-1]].planet_ids[0]]
		far.buildings.append("tribunal")
	sim.advance(720)
	var e := st.get_empire(me)
	e.resources["energy"] = 3000
	e.resources["influence"] = 400
	Admin.set_effort(st, me, "genereux")
	Admin.refresh(st)
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._refresh_all()
	await _frames(6)
	OrderScreen.tab = "admin"
	main.toggle_empire_screen("order")
	await _frames(10)
	await _shot(out + "/ecran-administration.png")
	var sc := _find_scroll(main)
	if sc != null:
		sc.scroll_vertical = 100000
		await _frames(6)
		await _shot(out + "/ecran-administration-systemes.png")
	main.toggle_empire_screen("order")
	await _frames(4)
	main._hud.set_lens("corruption")
	main._view.lens = "corruption"
	main._view.queue_redraw()
	await _frames(8)
	await _shot(out + "/lentille-corruption.png")
	quit()


func _find_scroll(n: Node) -> ScrollContainer:
	var best: ScrollContainer = null
	for c in n.find_children("*", "ScrollContainer", true, false):
		var s := c as ScrollContainer
		if s.is_visible_in_tree() and (best == null or s.size.x > best.size.x):
			best = s
	return best


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
