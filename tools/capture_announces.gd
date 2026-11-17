extends SceneTree
## Captures de la fenêtre d'événement généralisée (annonces), avec le rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_announces.gd
## Écrit les images dans le dossier donné par CAPTURE_DIR (par défaut user://captures).
## Scénario : Vaël ; une guerre déclarée par un voisin (Fanfare, vue de guerre), la mort d'un héros
## (mémorial), une fenêtre ordinaire, la colonne et un avis, l'onglet Annonces des Options, puis les
## onglets Annonces et Heures des Chroniques.


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	AnnounceSettings.persist = false
	AnnounceSettings.reset()
	AnnounceSettings.anim = "instant"
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	main.start_with_menu = false
	root.add_child(main)
	await _frames(10)
	var st := GameState.create(2027, 150, 1800.0, "vael", {"ai_level": ""})
	main._start(st)
	main.game_in_progress = true
	main.set_process(false)
	var center: AnnounceCenter = main.announce
	center.opening = true
	var me := 0
	var rival := 1
	if not st.get_empire(me).contacts.has(rival):
		st.get_empire(me).contacts.append(rival)
	st.tick = 900
	var sid: int = FactionTraits.capital_system(st, me)
	# Quelques nouvelles passées pour la colonne, le registre et la frise.
	Announce.next(st, "first_contact", {"actor": me, "target": rival})
	_add(st, 120, "Premier contact avec %s : on échange des salutations et quelques soupçons." % st.get_empire(rival).display_name())
	Announce.next(st, "wonder_done", {"actor": me, "system": sid})
	_add(st, 480, "Le Phare des Âges est achevé : la galaxie entière lève les yeux.")
	Announce.next(st, "pirate_raid", {"target": me, "system": sid})
	_add(st, 870, "Des pirates pillent les docks de la capitale.")
	Announce.next(st, "revolt", {"target": me, "system": sid})
	_add(st, 885, "Révolte sur une colonie : les mineurs réclament des chapeaux.")
	center.seen = 0
	center.opening = false
	center.ingest()
	center.opening = true
	# 1. Fanfare : guerre déclarée.
	Combat.start_war(st, rival, me)
	center.ingest()
	center.try_open(true)
	main._refresh_all()
	await _frames(20)
	await _shot(out + "/fanfare-guerre.png")
	center.close_panel()
	# 2. Mémorial.
	Announce.next(st, "hero_death", {"target": me, "name": "Ilya Sorn", "hero": 7, "seed": 7, "lvl": 5, "cls": "", "born": 120, "why": "est tombée en couvrant la retraite de la flotte"})
	_add(st, 900, "Ilya Sorn est tombée en couvrant la retraite de la flotte.", [me])
	center.ingest()
	center.opened_days.clear()
	center.try_open(false)
	await _frames(20)
	await _shot(out + "/fenetre-memorial.png")
	center.close_panel()
	# 3. Fenêtre ordinaire avec regroupement.
	Announce.next(st, "pirate_raid", {"target": me, "system": sid})
	_add(st, 900, "Nouveau raid pirate : les docks, encore.", [me])
	var idx := center.index_of(Announce.last_id(st))
	center.open_item(idx)
	await _frames(20)
	await _shot(out + "/fenetre-annonce.png")
	center.close_panel()
	# 4. Carte : colonne et avis.
	Announce.next(st, "creature_met", {"target": me, "system": sid})
	_add(st, 900, "Une baleine stellaire croise près de la capitale. Elle a l'air de bonne humeur.", [me])
	center.ingest()
	main._camera.position = st.galaxy.systems[sid].position
	main._view.queue_redraw()
	await _frames(20)
	await _shot(out + "/carte-colonne.png")
	# 5. Options, onglet Annonces.
	main.open_pause_menu()
	await _frames(5)
	var opts := _find_options(main._pause_menu)
	if opts:
		main._pause_menu.show_page("options")
		opts.show_tab("announce")
	await _frames(15)
	await _shot(out + "/options-annonces.png")
	main.close_pause_menu()
	await _frames(5)
	# 6. Chroniques : Annonces puis Heures.
	main._empire_screens.chron_tab = "announces"
	main.toggle_empire_screen("chronicles")
	await _frames(20)
	await _shot(out + "/chroniques-annonces.png")
	main._empire_screens.chron_tab = "hours"
	main._empire_screens.show_screen("chronicles")
	await _frames(20)
	await _shot(out + "/chroniques-heures.png")
	quit()


func _add(st: GameState, day: int, text: String, who: Array = []) -> void:
	var keep := st.tick
	st.tick = day
	if who.is_empty():
		st.add_chronicle(text)
	else:
		st.add_chronicle(text, who)
	st.tick = keep


func _find_options(n: Node) -> OptionsPanel:
	if n is OptionsPanel:
		return n
	for c in n.get_children():
		var f := _find_options(c)
		if f:
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
