extends SceneTree
## Captures du multijoueur avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_network.gd
## Écrit dans CAPTURE_DIR (par défaut user://captures) : l'accueil, la page Multijoueur, le salon
## d'avant-partie vu par l'hôte et par un invité, puis une partie
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
	# Salon d'avant-partie : deux places « joueur humain », Alice en prend une et se dit prête.
	main.player_name = "Maître Sentient"
	main.net.autosave_path = "user://saves/capture_multi_auto.json"
	main.net.use_upnp = false  # pas de box dans la machine de capture : on montre le cas réussi
	menu.open_host_new()
	main.net.upnp_state = "ok"
	main.net.upnp_address = "203.0.113.7"  # adresse d'exemple (plage de documentation)
	menu.select_faction("ossarane")
	menu.set_slot_human(0, true)
	menu.set_slot_human(1, true)
	menu.set_player_team(1)
	menu.set_slot_team(0, 1)
	menu.set_slot_team(1, 2)
	menu.set_slot_team(2, 2)
	menu.remove_slot(menu.slots.size() - 1)  # Teyl reste libre pour Alice
	var visitor := NetSession.new()
	visitor.player_name = "Alice"
	visitor.token = "capture-alice"
	root.add_child(visitor)
	var lobby_seen := {}
	visitor.lobby_changed.connect(func(st: Dictionary) -> void: lobby_seen.merge(st, true))
	visitor.join("127.0.0.1", 24570)
	var step := 0
	for _i in 240:
		visitor._poll()
		await process_frame
		if lobby_seen.is_empty():
			continue
		if step == 0:
			visitor.lobby_take(0)
			step = 1
		elif step == 1 and main.net.lobby_seats.size() == 1:
			visitor.lobby_set("teyl", "")
			visitor.lobby_set_ready(true)
			step = 2
		elif step == 2 and main.net.lobby_all_ready():
			break
	menu.set_turn_timer("dernier-60")
	visitor.send_chat("Je prends Teyl. On fait équipe ?")
	for _i in 10:
		visitor._poll()
		await process_frame
	main.net.send_chat("Ça marche, équipe 1 !")
	await _frames(20)
	visitor._poll()
	await _shot(out + "/reseau-salon-hote.png")
	# Le même salon vu par Alice.
	var guest_view := lobby_seen.duplicate(true)
	visitor.close()
	menu.show_lobby(guest_view)
	await _frames(5)
	await _shot(out + "/reseau-salon-invite.png")
	# L'hôte : Nouvelle partie en réseau (tours simultanés), lancée et ouverte aussitôt.
	menu.open_host_new()
	menu.select_faction("ossarane")
	menu.set_turn_timer("dernier-60")
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
	guest.send_chat("Une minute, je place mon éclaireur.")
	for _i in 10:
		guest._poll()
		guest._flush()
		await process_frame
	main.net.send_chat("Le minuteur tourne !")
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
