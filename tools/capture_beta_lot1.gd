extends SceneTree
## Captures du lot 1 du bêta-test (corrections visibles), rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_beta_lot1.gd
## Écrit dans CAPTURE_DIR (par défaut user://captures) : l'infobulle de la Ferveur des Murmurants
## près du pointeur, celle du bouton Offrande en bas d'écran, un refus affiché sous le pointeur, la
## gestion du système le plus peuplé de planètes, et « Charger » qui demande confirmation.


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	main.save_dir = "user://capture_saves_beta1"
	main.start_with_menu = false
	root.add_child(main)
	await _frames(5)
	main.player_faction = "murmurants"
	main.new_game(4242)
	await _frames(20)
	var st: GameState = main.simulation.state
	var hud: Hud = main._hud

	# Infobulle de la jauge de Ferveur, sous le pointeur (elle était collée en haut de l'écran) : le
	# pointeur est posé dessus et l'infobulle s'ouvre d'elle-même.
	var gauge: Control = hud.bar._gauge
	await _hover(main, gauge.get_global_rect().get_center())
	await _shot(out + "/infobulle-ferveur.png")
	await _hover(main, Vector2(800, 600))

	# Bouton Offrande de la fiche de système, en bas à gauche : l'infobulle s'ouvre juste au-dessus.
	var me: Empire = st.get_empire(0)
	var home: int = st.galaxy.get_planet(me.capital_planet).system_id
	main.open_system_view(home)
	await _frames(60)
	var ob: Button = main._system_screen.stab_buttons["offering"]
	if ob.is_visible_in_tree():
		await _hover(main, ob.get_global_rect().get_center())
		await _shot(out + "/infobulle-offrande.png")
		await _hover(main, Vector2(1000, 600))
		# Un refus juste après un clic : la raison s'affiche sous le pointeur.
		hud._last_click_ms = Time.get_ticks_msec()
		hud._last_click_pos = ob.get_global_rect().get_center()
		hud.refuse("Ordre refusé : une offrande a déjà été faite ici il y a moins de 6 mois")
		await _frames(4)
		await _shot(out + "/refus-sous-le-pointeur.png")
	main.close_system_view()
	await _frames(10)

	# Gestion du système qui a le plus de planètes.
	var big: StarSystem = null
	for s in st.galaxy.systems:
		if big == null or s.planet_ids.size() > big.planet_ids.size():
			big = s
	if not me.explored.has(big.id):
		me.explored[big.id] = true
	me.surveyed[big.id] = true
	main.open_system_view(big.id)
	await _frames(60)
	main._system_screen.set_manage_mode(true)
	await _frames(30)
	await _shot(out + "/gestion-%d-planetes.png" % big.planet_ids.size())
	main._system_screen.set_manage_mode(false)
	main.close_system_view()
	await _frames(10)

	# Charger avec une partie qui a avancé depuis la sauvegarde : un second clic est demandé.
	main.save_game(SaveGame.new_path(main.save_dir), "manual")
	st.tick += 45
	main.open_pause_menu()
	main._pause_menu.show_page("load")
	await _frames(10)
	var list: SaveList = main._pause_menu.save_list
	var buttons := list.get_tree().get_nodes_in_group("save_list_load").filter(func(n: Node) -> bool: return list.is_ancestor_of(n))
	if not buttons.is_empty():
		(buttons[0] as Button).pressed.emit()
		await _frames(6)
		await _shot(out + "/charger-confirmation.png")
	for sv: Dictionary in SaveGame.list(main.save_dir):
		SaveGame.remove(String(sv["path"]))
	quit()


## Pose le pointeur et attend que l'infobulle s'ouvre (délai, puis mise en page).
func _hover(main: Node, at: Vector2) -> void:
	Input.warp_mouse(at)
	var mm := InputEventMouseMotion.new()
	mm.position = at
	mm.global_position = at
	Input.parse_input_event(mm)
	await _frames(int(main.tips.delay * 60.0) + 30)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
