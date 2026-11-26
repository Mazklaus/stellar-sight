extends SceneTree
## Captures du lot 2 du bêta-test (ne plus perdre sans comprendre), rendu réel :
##   xvfb-run -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --resolution 1600x900 -s res://tools/capture_beta_lot2.gd
## Écrit dans CAPTURE_DIR (par défaut user://captures) : la Fanfare de guerre avec ses deux boutons, la
## fenêtre du sujet malgré lui, la flotte perdue sous les bastions (touche B), la pastille de guerre et les
## options « Ce qui arrête le jeu », puis la reddition (2.2) : dernier rempart, reddition sans conditions,
## volet Traiter au score maximum, jauge des systèmes libres.


func _initialize() -> void:
	var out := OS.get_environment("CAPTURE_DIR")
	if out == "":
		out = ProjectSettings.globalize_path("user://captures")
	DirAccess.make_dir_recursive_absolute(out)
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.save_path = "user://saves/capture_quicksave.json"
	main.save_dir = "user://capture_saves_beta2"
	main.start_with_menu = false
	root.add_child(main)
	await _frames(5)
	main.player_faction = "vael"
	main.new_game(4243)
	await _frames(20)
	var st: GameState = main.simulation.state
	var me := 0
	var foe := 1
	var other := 2
	for o in [foe, other]:
		for pair in [[me, o], [o, me]]:
			if not st.get_empire(pair[0]).contacts.has(pair[1]):
				st.get_empire(pair[0]).contacts.append(pair[1])
	# Une flotte armée qui attend à la capitale, pour la liste des flottes sans ordres.
	var home: int = st.galaxy.get_planet(st.get_empire(me).capital_planet).system_id
	var guard := st.spawn_ship(me, "fregate", home)
	guard.fleet_name = "Première escadre"

	# Fanfare de guerre : conditions de paix et flottes sans ordres.
	Diplomacy._rel_w(st, me, foe)["truce"] = 0
	Diplomacy._rel_w(st, me, foe)["pact"] = Diplomacy.COLD
	Combat.start_war(st, foe, me)
	Announce.next(st, "war_declared", {"actor": foe, "target": me})
	st.add_chronicle("%s déclare la guerre à %s." % [st.get_empire(foe).display_name(), st.get_empire(me).display_name()])
	main.announce.open_record(Announce.last_id(st))
	await _frames(40)
	await _shot(out + "/fanfare-guerre-boutons.png")
	main.announce.close_panel()
	await _frames(10)

	# Pastille de guerre dans la barre d'alertes, avec son infobulle.
	main._hud.refresh()
	await _frames(10)
	var ab: Button = main._hud.alert_bar.buttons.get("war") if main._hud.alert_bar != null else null
	if ab != null:
		await _hover(main, ab.get_global_rect().get_center())
		await _shot(out + "/alerte-guerre.png")
		await _hover(main, Vector2(800, 500))

	# Flotte abattue par les bastions : avis, puis la touche B rouvre la perte.
	var col: Colony = null
	for pid in st.sorted_colony_ids():
		var x: Colony = st.colonies[pid]
		if x.owner == foe and x.is_colony() and x.is_established():
			col = x
			break
	if not col.buildings.has("bastion"):
		col.buildings.append("bastion")
	var sid := st.galaxy.get_planet(col.planet_id).system_id
	var f := st.spawn_ship(me, "fregate", sid)
	st.sieges[sid] = {"system": sid, "by": me, "start": st.tick}
	if not st.get_empire(me).explored.has(sid):
		st.get_empire(me).explored[sid] = true
	f.fleet_name = "Escorte de Vaëlis"
	var added: Array[Dictionary] = []
	for _i in 30:
		if st.fleets.has(f.id):
			f.hp[0] = 1
			CombatSystem._battery_fire(st, sid, [f] as Array[Fleet], added)
	main.toggle_battle_report()
	await _frames(40)
	await _shot(out + "/flotte-perdue-bastions.png")
	main.announce.close_panel()
	await _frames(10)

	# Sujet malgré lui : trois voies.
	Diplomacy.sign_treaty(st, me, foe, Diplomacy.PEACE)
	st.vassals_on = true
	Vassals.bind(st, foe, me, "vassal", Vassals.preset_clauses("vassal"), 0, true)
	main.announce.open_record(Announce.last_id(st))
	await _frames(40)
	await _shot(out + "/fenetre-sujet.png")
	main.announce.close_panel()
	await _frames(10)

	# Reddition sans conditions (2.2) : dernier rempart, puis la fenêtre du vainqueur.
	Vassals.unbind(st, me)
	st.wars_on = true
	st.wars["occ_on"] = true
	var foe2 := other
	for pair in [[me, foe2], [foe2, me]]:
		Diplomacy._rel_w(st, pair[0], pair[1])["truce"] = 0
		Diplomacy._rel_w(st, pair[0], pair[1])["pact"] = Diplomacy.COLD
	SimCommands.apply(st, SimCommands.declare_war(me, foe2, "agression", "humiliation"))
	var wrec := Wars.war(st, me, foe2)
	if not wrec.is_empty():
		wrec["t"] = st.tick - 200
		var own := EmpireReport.owned_systems(st, foe2)
		if own.size() == 1:
			var extra := -1
			for s2 in st.galaxy.systems:
				if s2.planet_ids.size() > 0 and st.system_owner(s2.id) == -1:
					extra = s2.id
					break
			var c2 := Colony.new()
			c2.planet_id = st.galaxy.get_system(extra).planet_ids[0]
			c2.owner = foe2
			c2.kind = Colony.KIND_COLONY
			c2.population = 3
			st.add_colony(c2)
			own = EmpireReport.owned_systems(st, foe2)
		for i in own.size() - 1:
			WarPeace.invade(st, own[i], me)
		main.announce.open_record(Announce.last_id(st))
		await _frames(40)
		await _shot(out + "/dernier-rempart.png")
		main.announce.close_panel()
		await _frames(10)
		WarPeace.invade(st, own[own.size() - 1], me)
		Wars.monthly(st)
		main.announce.open_record(Announce.last_id(st))
		await _frames(40)
		await _shot(out + "/reddition-sans-conditions.png")
		main.announce.close_panel()
		await _frames(10)
		main.open_relation(foe2, "deal")
		await _frames(30)
		await _shot(out + "/reddition-termes.png")
		main.open_relation(foe2, "war")
		await _frames(30)
		await _shot(out + "/reddition-volet-guerre.png")
		main.close_empire_screen()
		await _frames(10)

	# Options : ce qui arrête le jeu.
	main.open_pause_menu()
	main._pause_menu.show_page("options")
	var opts: OptionsPanel = main._pause_menu._options
	opts.show_tab("game")
	await _frames(10)
	var row: Control = opts._realtime_stops
	var sc := row.get_parent()
	while sc != null and not (sc is ScrollContainer):
		sc = sc.get_parent()
	if sc != null:
		(sc as ScrollContainer).ensure_control_visible(row)
	await _frames(10)
	await _shot(out + "/options-arrets.png")
	quit()


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
