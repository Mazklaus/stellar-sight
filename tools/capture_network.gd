extends SceneTree
## Captures du multijoueur avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_network.gd
## Écrit dans CAPTURE_DIR (par défaut user://captures) : l'accueil, la page Multijoueur, puis une partie
## hébergée au tour par tour qu'un second joueur (une autre session dans le même processus) rejoint :
## le choix de son empire, et le cadran de l'hôte qui a terminé son tour et attend l'autre joueur.


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
	# Une partie hébergée sur le réseau local apparaît toute seule dans la liste.
	var beacon := LanDiscovery.new()
	for _i in 30:
		beacon.announce({"name": "Maître Sentient", "port": 24570, "players": 2, "turns": true, "date": "14 mars 2403", "version": GameVersion.fingerprint()})
		await process_frame
	await _frames(5)
	await _shot(out + "/reseau-multijoueur.png")
	# L'hôte : Nouvelle partie en réseau (tours simultanés), lancée et ouverte aussitôt.
	main.player_name = "Maître Sentient"
	main.net.autosave_path = "user://saves/capture_multi_auto.json"
	menu.open_host_new()
	menu.select_faction("ossarane")
	menu.launch()
	await _frames(20)
	# Un second joueur rejoint, depuis une autre session dans ce même processus.
	var guest := NetSession.new()
	guest.player_name = "Alice"
	guest.token = "capture-alice"
	root.add_child(guest)
	var offer := []
	guest.choose_empire.connect(func(list: Array) -> void: offer.assign(list))
	guest.joined.connect(func(state: GameState, _e: int) -> void:
		guest.core = Lockstep.new(Simulation.new(state), false))
	guest.join("127.0.0.1", 24570)
	for _i in 120:
		guest._poll()
		await process_frame
		if not offer.is_empty():
			break
	menu.visible = true
	menu.show_empire_choice(offer)
	await _frames(5)
	await _shot(out + "/reseau-choix-empire.png")
	menu.visible = false
	for d in offer:
		if d["free"]:
			guest.pick(int(d["id"]))
			break
	for _i in 120:
		guest._poll()
		guest._flush()
		await process_frame
		if guest.core != null:
			break
	get_root().get_node("GameClock").toggle_pause()  # l'hôte termine son tour
	# L'invité partage l'horloge de ce processus : on n'écoute plus que l'hôte pour l'affichage.
	await _frames(10)
	main.net._sync_clock()
	await _frames(5)
	await _shot(out + "/reseau-tour-simultane.png")
	guest.close()
	main.leave_network("")
	quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_viewport().get_texture().get_image().save_png(path)
	print("capture : ", path)
