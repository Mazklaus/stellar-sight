extends SceneTree
## Captures du pilier Souverain et dynastie, avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_trone.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Ossarane (dynastie) après deux règnes ; le souverain a des héritiers, du renom, un héritage
## acheté et une ambition. Écran Trône en haut puis plus bas, et une planche de la galerie des portraits.


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
	main.game_options = {"rulers": "mortels", "hero_death": "normale", "faiths": "actives"}
	main.new_game(4243)
	await _frames(5)
	var sim: Simulation = main.simulation
	var st: GameState = sim.state
	var me: int = main.view_empire
	sim.advance(720)
	var added: Array[Dictionary] = []
	# Deux règnes passés pour les annales.
	Rulers.die(st, me, "s'éteint", added, "age")
	if Rulers.ruler(st, me).is_empty():
		RulersSuccession.resolve(st, me, added)
	sim.advance(400)
	Rulers.die(st, me, "tombé au combat", added, "front")
	if Rulers.ruler(st, me).is_empty():
		RulersSuccession.resolve(st, me, added)
	sim.advance(200)
	var en := Rulers.entry(st, me)
	en["renown"] = int(en.get("renown", 0)) + 260
	Rulers.act(st, me, "legacy", -1, "administration", added)
	Rulers.give_cognomen(st, me, "deed:cartographe")
	var heirs: Array = en.get("heirs", [])
	if heirs.size() < 2:
		heirs.append({"id": 900, "name": "Ysolde", "g": "f", "born": st.tick - 12 * 360, "apt": {"gestion": 3, "guerre": 1, "eloquence": 2, "intrigue": 1}, "edu": "", "hero": -1})
		heirs.append({"id": 901, "name": "Corvin", "g": "m", "born": st.tick - 7 * 360, "apt": {"gestion": 1, "guerre": 3, "eloquence": 0, "intrigue": 2}, "edu": "", "hero": -1})
	if (en.get("amb", {}) as Dictionary).is_empty():
		Rulers.choose_ambition(st, me, "conquerir")
	st.get_empire(me).resources["influence"] = 300
	main.set_process(false)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._refresh_all()
	await _frames(6)
	main.toggle_empire_screen("throne")
	await _frames(10)
	await _shot(out + "/ecran-trone.png")
	var sc := _find_scroll(main)
	if sc != null:
		sc.scroll_vertical = 700
		await _frames(6)
		await _shot(out + "/ecran-trone-suite.png")
	main.toggle_empire_screen("throne")
	await _frames(4)
	# Planche : un portrait par archétype d'espèce et quelques variantes.
	var layer := CanvasLayer.new()
	layer.layer = 50
	root.add_child(layer)
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08)
	bg.size = Vector2(1600, 900)
	layer.add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.position = Vector2(30, 30)
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	layer.add_child(grid)
	var ids: Array[String] = []
	for p: Dictionary in Rulers.data()["portraits"]:
		ids.append(String(p["id"]))
	for i in mini(24, ids.size()):
		var id: String = ids[(i * 5) % ids.size()]
		var slot := Widgets.ArtSlot.new(id, Vector2(180, 260), Color(0.95, 0.78, 0.36), "faction")
		slot.set_caption(id.trim_prefix("ruler_"), 12)
		grid.add_child(slot)
	await _frames(8)
	await _shot(out + "/galerie-souverains.png")
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
