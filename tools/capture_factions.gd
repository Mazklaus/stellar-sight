extends SceneTree
## Captures des traits de faction avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_factions.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures) :
## le choix de chacun des 4 peuples, puis une partie du Chœur Éternel (jauge de ferveur, offrande)
## et une partie de la Concorde de Vael (vote d'urgence).


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	root.add_child(main)
	await _frames(30)
	main._main_menu.show_page("new")
	for fid in GameData.faction_ids():
		main._main_menu.select_faction(fid)
		await _frames(5)
		await _shot(out + "/nouvelle-partie-%s.png" % fid)

	# Chœur Éternel : la ferveur dans le panneau d'empire, l'offrande dans la vue système.
	main._main_menu.select_faction("choeur")
	main._main_menu._seed_edit.text = "4242"
	main._main_menu.launch()
	await _frames(10)
	var st: GameState = main.simulation.state
	main.simulation.advance(61)
	main._refresh_all()
	var me: Empire = st.get_empire(0)
	main.open_system_view(st.galaxy.get_planet(me.capital_planet).system_id, me.capital_planet)
	await _frames(90)
	await _shot(out + "/choeur-offrande.png")
	main.close_system_view()

	# Concorde de Vael : vote d'urgence sur un chantier en cours.
	main.player_faction = "vael"
	main.new_game(4242)
	await _frames(10)
	st = main.simulation.state
	me = st.get_empire(0)
	main.simulation.submit(SimCommands.build(0, me.capital_planet, "centrale_fusion"))
	main.simulation.flush_commands()
	main.simulation.advance(5)
	main._refresh_all()
	main.open_system_view(st.galaxy.get_planet(me.capital_planet).system_id, me.capital_planet)
	await _frames(90)
	await _shot(out + "/vael-vote-urgence.png")
	quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
