extends SceneTree
## Captures du multijoueur (lot 2) avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_network.gd
## Écrit dans CAPTURE_DIR (par défaut user://captures) : l'accueil avec « Rejoindre », la page
## Rejoindre une partie, le menu du jeu avec « Ouvrir en réseau », puis la partie ouverte au réseau
## quand un second joueur (une autre session dans le même processus) la rejoint.


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	root.add_child(main)
	await _frames(30)
	var menu: MainMenu = main._main_menu
	await _shot(out + "/reseau-accueil.png")
	menu.show_page("join")
	menu._join_name.text = "Alice"
	menu._join_address.text = "192.168.1.20"
	menu.set_join_status("Connexion à 192.168.1.20…")
	await _frames(5)
	await _shot(out + "/reseau-rejoindre.png")
	menu.show_page("home")
	menu.show_page("new")
	menu.select_faction("ossarane")
	menu.launch()
	await _frames(20)
	main.open_pause_menu()
	await _frames(5)
	await _shot(out + "/reseau-menu-du-jeu.png")
	main.close_pause_menu()
	main.player_name = "Maître Sentient"
	main.host_game(24598)
	# Un second joueur rejoint, depuis une autre session dans ce même processus.
	var guest := NetSession.new()
	guest.player_name = "Alice"
	root.add_child(guest)
	guest.joined.connect(func(state: GameState, _e: int) -> void:
		guest.core = Lockstep.new(Simulation.new(state), false))
	guest.join("127.0.0.1", 24598)
	for _i in 120:
		guest._poll()
		guest._flush()
		await process_frame
		if guest.core != null:
			break
	await _frames(20)
	await _shot(out + "/reseau-partie-ouverte.png")
	guest.close()
	quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("capture : ", path)
