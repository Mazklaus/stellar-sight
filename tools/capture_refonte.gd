extends SceneTree
## Inventaire visuel complet de l'interface pour la refonte (fil « Refondre toute l'interface ») :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_refonte.gd
## Menus du titre, puis la partie de fin de banc (tests/data/fin_de_partie.json.gz) : zooms de la carte,
## toutes les lentilles, flotte choisie, vue système, chaque écran d'empire et ses onglets, Codex, options.
## CAPTURE_DIR (défaut user://captures/refonte), EMPIRE (empire joué, défaut 0).

var out := ""
var n := 0


func _initialize() -> void:
	out = OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures/refonte")
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	root.add_child(main)
	await _frames(30)
	var mm = main._main_menu
	await _shot("titre-accueil")
	mm.show_page("new")
	await _frames(5)
	await _shot("titre-nouvelle-partie")
	mm.show_page("options")
	await _frames(5)
	await _shot("titre-options")
	mm.show_page("join")
	await _frames(5)
	await _shot("titre-rejoindre")
	mm.open_species("new")
	await _frames(8)
	await _shot("titre-editeur-especes")
	if mm._species:
		for t in ["layers", "traits"]:
			if mm._species.has_method("show_tab"):
				mm._species.show_tab(t)
				await _frames(5)
				await _shot("titre-editeur-especes-" + t)
	mm.show_page("home")

	# La partie de fin de banc.
	var tmp := ProjectSettings.globalize_path("user://refonte_save.json")
	var f := FileAccess.open_compressed("res://tests/data/fin_de_partie.json.gz", FileAccess.READ, FileAccess.COMPRESSION_GZIP)
	var text := f.get_as_text()
	f.close()
	var w := FileAccess.open(tmp, FileAccess.WRITE)
	w.store_string(text)
	w.close()
	var st: GameState = SaveGame.load_state(tmp)
	if st == null:
		print("chargement impossible : ", SaveGame.last_error)
		quit(1)
		return
	var who := int(OS.get_environment("EMPIRE")) if OS.get_environment("EMPIRE") != "" else 0
	st.get_empire(who).ai_level = ""
	main.local_player = who
	main.close_main_menu()
	main._start(st)
	main.game_in_progress = true
	root.get_node("/root/GameClock").paused = true
	main._refresh_all()
	var cap := FactionTraits.capital_system(st, who)
	main._select(cap)
	main._camera.position = main.galaxy.get_system(cap).position
	for z in [0.12, 0.22, 0.45, 1.0, 2.2]:
		main._camera.zoom = Vector2(z, z)
		await _frames(8)
		await _shot("carte-zoom-%s" % str(z).replace(".", "_"))
	main._camera.zoom = Vector2(0.45, 0.45)
	for l in ["economy", "stability", "corruption", "fiscal", "politics", "trade", "private", "ports", "peoples", "psionics", "faith", "amph", "war", "sensors", "borders", "culture"]:
		main._hud.set_lens(l)
		await _frames(8)
		await _shot("lentille-" + l)
	main._hud.set_lens("")
	# Une flotte du joueur.
	var fid := -1
	for fl in st.fleets.values():
		if fl.owner == who and fid < 0:
			fid = fl.id
	if fid >= 0:
		main.select_fleet(fid)
		main.focus_fleet(fid)
		await _frames(20)
		await _shot("carte-flotte-choisie")
		main._camera.zoom = Vector2(1.6, 1.6)
		await _frames(10)
		await _shot("carte-flotte-zoom")
		main._camera.zoom = Vector2(0.45, 0.45)
	# Vue système.
	main.open_system_view(cap)
	await _frames(20)
	await _shot("systeme-orbital")
	main._system_screen.set_manage_mode(true)
	await _frames(10)
	await _shot("systeme-gestion")
	main.close_system_view()
	await _frames(5)
	# Écrans d'empire.
	var es = main._empire_screens
	for sid in ["economy", "colonies", "research", "diplomacy", "shipyard", "armies", "victory", "intel", "heroes", "throne", "order", "senate", "faith", "culture", "genome", "psionics", "wonders", "megas", "forge", "amphictyony", "chronicles", "transcendence", "contact", "kardashev"]:
		main.toggle_empire_screen(sid)
		await _frames(15)
		await _shot("ecran-" + sid)
		if sid == "trade":
			pass
		main.close_empire_screen()
		await _frames(3)
	# Commerce et ses onglets.
	for t in ["routes", "resources", "market", "knowledge", "private", "ports"]:
		es.trade_tab = t
		main.toggle_empire_screen("trade")
		await _frames(15)
		await _shot("ecran-commerce-" + t)
		main.close_empire_screen()
	for t in ChronicleScreen.TABS:
		es.chron_tab = t[0]
		main.toggle_empire_screen("chronicles")
		await _frames(15)
		await _shot("ecran-chroniques-" + t[0])
		main.close_empire_screen()
	for t in ["admin", "tresor"]:
		OrderScreen.tab = t
		main.toggle_empire_screen("order")
		await _frames(15)
		await _shot("ecran-order-" + t)
		main.close_empire_screen()
	OrderScreen.tab = "ordre"
	ThroneScreen.tab = "cour"
	main.toggle_empire_screen("throne")
	await _frames(15)
	await _shot("ecran-throne-cour")
	main.close_empire_screen()
	ThroneScreen.tab = "trone"
	for t in OptionsPanel.TABS:
		main.open_pause_menu()
		await _frames(3)
		main._pause_menu.show_page("options")
		await _frames(3)
		if main._pause_menu.get("_options") != null and main._pause_menu._options.has_method("show_tab"):
			main._pause_menu._options.show_tab(t[0])
			await _frames(5)
			await _shot("options-" + t[0])
		main.close_pause_menu()
	main.open_codex()
	await _frames(15)
	await _shot("codex")
	main.toggle_codex()
	await _frames(5)
	main.open_pause_menu()
	await _frames(10)
	await _shot("pause")
	main.close_pause_menu()
	main.toggle_battle_report()
	await _frames(10)
	await _shot("rapport-bataille")
	main.toggle_battle_report()
	main.open_victory_panel()
	await _frames(10)
	await _shot("panneau-victoire")
	main.close_victory_panel()
	print("fini : %d captures" % n)
	quit()


func _frames(k: int) -> void:
	for _i in k:
		await process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	n += 1
	var img := root.get_texture().get_image()
	img.save_png("%s/%02d-%s.png" % [out, n, name])
	print("capture : ", name)
