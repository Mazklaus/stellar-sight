extends SceneTree
## Captures de la diplomatie avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_diplomacy.gd
## Écrit les images dans CAPTURE_DIR (par défaut user://captures) : l'écran Diplomatie de Vael (paix,
## commerce, proposition reçue, arbitrage possible), la relation avec le Chœur (ce que l'IA pense
## de chaque offre), l'héritier d'Ossarane courtisé par un rival, et une partie de spectateur.


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	main.start_with_menu = false
	root.add_child(main)
	await _frames(30)

	# Vael (0) face à des IA vétérans : Ossarane (1), Chœur (2), Kh'thari (3).
	var st := GameState.create(2026, 150, 1800.0, "vael", {"ai_level": "veteran"})
	main._start(st)
	main.game_in_progress = true
	for a in 4:
		for b in 4:
			if a != b and not st.get_empire(a).contacts.has(b):
				st.get_empire(a).contacts.append(b)
				st.get_empire(a).contacts.sort()
	st.tick = 900
	Diplomacy.sign_treaty(st, 0, 1, Diplomacy.PEACE)
	Diplomacy.sign_treaty(st, 0, 1, Diplomacy.TRADE)
	Diplomacy._rel_w(st, 0, 1)["since"] = st.tick - 240
	Diplomacy._rel_w(st, 0, 1)["truce"] = st.tick + 120
	Diplomacy._rel_w(st, 0, 1)["trust"] = 16
	Combat.start_war(st, 2, 1)
	Diplomacy._rel_w(st, 1, 2)["since"] = st.tick - 150
	Combat.start_war(st, 3, 0, true)
	Combat.start_war(st, 3, 1, true)
	Combat.start_war(st, 3, 2, true)
	Diplomacy.remember(st, 1, 0, "peace_signed")
	Diplomacy.remember(st, 2, 0, "peace_signed")
	st.get_empire(0).resources["influence"] = 140
	st.proposals.append({"id": st.next_proposal_id, "from": 1, "to": 0, "treaty": "alliance", "tick": st.tick - 4})
	st.next_proposal_id += 1
	main._proposals_told = st.next_proposal_id - 1
	main._refresh_all()
	main.toggle_empire_screen("diplomacy")
	main._empire_screens.diplo_selected = 1
	main._empire_screens.show_screen("diplomacy")
	await _frames(40)
	await _shot(out + "/diplomatie-vael.png")

	main._empire_screens.diplo_selected = 2
	main._empire_screens.show_screen("diplomacy")
	await _frames(30)
	await _shot(out + "/diplomatie-choeur-arbitrage.png")
	main.close_empire_screen()

	# Ossarane : l'héritier vacille, Vael l'a soudoyé.
	var so := GameState.create(2026, 150, 1800.0, "ossarane", {"ai_level": "normal"})
	main._start(so)
	for a in 4:
		for b in 4:
			if a != b and not so.get_empire(a).contacts.has(b):
				so.get_empire(a).contacts.append(b)
	so.tick = 700
	Combat.start_war(so, 3, 0, true)
	Combat.start_war(so, 0, 1)
	Diplomacy._rel_w(so, 0, 1)["since"] = so.tick - 300
	Diplomacy.add_war_score(so, 1, 0, 60)
	so.get_empire(2).resources["influence"] = 100
	Diplomacy.bribe(so, 2, 0)
	so.get_empire(0).heir_loyalty = 22
	so.get_empire(0).dissent = true
	so.get_empire(0).resources["influence"] = 60
	so.get_empire(0).resources["crystals"] = 12
	main._refresh_all()
	main.toggle_empire_screen("diplomacy")
	main._empire_screens.diplo_selected = 1
	main._empire_screens.show_screen("diplomacy")
	await _frames(40)
	await _shot(out + "/diplomatie-ossarane-heritier.png")
	main.close_empire_screen()

	# Spectateur : quatre IA vétérans, quatre ans, puis la table diplomatique d'un empire.
	var sp := GameState.create(777, 150, 1800.0, "", {"spectator": true, "ai_level": "veteran"})
	main._start(sp)
	main.simulation.advance(1440)
	main.follow_empire(0)
	main._refresh_all()
	main.toggle_empire_screen("diplomacy")
	await _frames(40)
	await _shot(out + "/diplomatie-spectateur.png")
	quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _shot(path: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(path)
	print("capture : ", path)
