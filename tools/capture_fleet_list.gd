extends SceneTree
## Captures de l'ergonomie des flottes (liste, flottes inactives, exploration auto) :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_fleet_list.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).


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
	var me: Empire = st.get_empire(0)
	var scout := _fleet(st, "scout")

	# L'éclaireur explore tout seul ; un second éclaireur sort des chantiers et reste à quai.
	sim.submit(SimCommands.set_fleet_order(0, scout.id, Fleet.ORDER_EXPLORE))
	sim.submit(SimCommands.build_ship(0, me.capital_planet, "scout"))
	sim.advance(int(GameData.ship("scout")["days"]) + 1)
	var scout2: Fleet = Fleets.empire_fleets(st, 0)[-1]
	sim.submit(SimCommands.build_ship(0, me.capital_planet, "scout"))
	sim.advance(int(GameData.ship("scout")["days"]) + 1)
	sim.submit(SimCommands.set_fleet_order(0, scout2.id, Fleet.ORDER_EXPLORE))
	sim.advance(25)
	main._refresh_all()

	main.select_fleet(scout.id)
	main._select(-1)
	main._camera.position = Fleets.position(st, scout).lerp(st.galaxy.get_system(st.galaxy.get_planet(me.capital_planet).system_id).position, 0.4)
	main._camera.zoom = Vector2(0.38, 0.38)
	main.set_process(false)
	main._hud.show_hover(null, Vector2.ZERO)
	for t in main._hud._toasts.get_children():
		t.queue_free()
	main._hud.notify("%s : part explorer l'inconnu." % scout.fleet_name)
	main._hud.refresh()
	await _frames(8)
	await _shot(out + "/flottes-liste-exploration.png")
	quit()


func _fleet(st: GameState, ship_id: String) -> Fleet:
	for f in Fleets.empire_fleets(st, 0):
		if f.count(ship_id) > 0:
			return f
	return null


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
