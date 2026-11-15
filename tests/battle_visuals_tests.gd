extends RefCounted
## Tests du visuel des combats, lot 1 (décors spatiaux) : décor relevé au début de la bataille et
## recopié dans le rapport, cimetière d'épaves, siège, sauvegarde 63, déterminisme, vue de replay
## habillée (décor, sprites éclairés, vue tactique, détail). Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Visuel des combats, lot 1…")
	_test_data()
	_test_scene()
	_test_panel()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _test_data() -> void:
	var v := GameData.battle_visuals()
	for star in ["yellow", "red", "white", "blue_giant", "neutron", "black_hole"]:
		_ok(v["stars"].has(star), "Visuel : lumière de l'étoile %s" % star)
	_ok((v["detail"]["levels"] as Array).size() == 3, "Visuel : trois niveaux de détail")
	_ok(BattleBackdrop.art_path("planet", "continental") == "", "Visuel : sans asset final, dessin procédural")


func _battle(seed_value := 77) -> Array:
	var st := GameState.create(seed_value, 120, 1600.0, "ossarane", {"ai_level": "", "rivals": ["khthari"]})
	for e in [st.get_empire(0), st.get_empire(1)]:
		e.contacts.append(1 - e.id)
	Combat.start_war(st, 0, 1)
	var target := st.galaxy.get_planet(st.get_empire(1).capital_planet).system_id
	var mine := st.spawn_ship(0, "fregate", target)
	for s in ["fregate", "fregate", "croiseur"]:
		mine.add_ship(s)
	var foe := st.spawn_ship(1, "corvette", target)
	foe.add_ship("corvette")
	return [st, target]


func _test_scene() -> void:
	var pair := _battle()
	var st: GameState = pair[0]
	var target: int = pair[1]
	var sim := Simulation.new(st)
	var guard := 0
	while guard < 40 and st.battle_reports.is_empty():
		sim.step()
		guard += 1
	_ok(not st.battle_reports.is_empty(), "Visuel : une bataille a lieu")
	if st.battle_reports.is_empty():
		return
	var rep: Dictionary = st.battle_reports[0]
	var sc: Dictionary = rep.get("scene", {})
	_ok(String(sc.get("star", "")) == st.galaxy.systems[target].star_type, "Visuel : l'arène reprend l'étoile du système")
	_ok(int(sc.get("owner", -2)) == 1, "Visuel : propriétaire du système relevé")
	var pl: Dictionary = sc.get("planet", {})
	var pid := int(pl.get("id", -1))
	_ok(pid >= 0 and st.colonies.has(pid) and st.colonies[pid].owner == 1, "Visuel : la planète montrée est celle du défenseur")
	_ok(int(sc.get("wrecks", -1)) == 0, "Visuel : pas d'épaves avant la première bataille")
	var lost := 0
	for side: Dictionary in rep["sides"]:
		lost += Combat.count_ships(side["lost"])
	_ok(lost > 0 and int(st.battle_wrecks.get(target, 0)) == lost, "Visuel : les vaisseaux détruits restent au cimetière (%d)" % lost)
	# Une seconde bataille au même endroit voit les épaves de la première.
	var foe := st.spawn_ship(1, "corvette", target)
	foe.add_ship("corvette")
	var before := st.battle_reports.size()
	guard = 0
	while guard < 40 and st.battle_reports.size() == before:
		sim.step()
		guard += 1
	if st.battle_reports.size() > before:
		var sc2: Dictionary = st.battle_reports[-1].get("scene", {})
		_ok(int(sc2.get("wrecks", 0)) == lost, "Visuel : la bataille suivante montre le cimetière")
		_ok(int(sc2.get("seed", 0)) != int(sc.get("seed", 0)), "Visuel : chaque bataille a sa graine de décor")
	# Plafond du cimetière.
	st.battle_wrecks[target] = 59
	BattleScene.finish(st, target, {"scene": {"siege": false}, "sides": [{"lost": {"fregate": 5}}]})
	_ok(int(st.battle_wrecks[target]) == int(GameData.battle_visuals()["objects"]["wrecks_cap"]), "Visuel : cimetière plafonné")
	# Sauvegarde 63 et déterminisme.
	var d := st.to_dict()
	_ok(int(d["version"]) == GameState.FORMAT_VERSION and GameState.FORMAT_VERSION >= 63, "Visuel : sauvegarde 63")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and int(back.battle_wrecks.get(target, 0)) == int(st.battle_wrecks[target]), "Visuel : cimetière sauvegardé")
	_ok(back != null and back.checksum() == st.checksum(), "Visuel : partie identique après rechargement")
	var p2 := _battle()
	var st2: GameState = p2[0]
	var sim2 := Simulation.new(st2)
	guard = 0
	while guard < 40 and st2.battle_reports.is_empty():
		sim2.step()
		guard += 1
	_ok(not st2.battle_reports.is_empty() and JSON.stringify(st2.battle_reports[0].get("scene", {})) == JSON.stringify(sc),
			"Visuel : même partie, même décor")


func _test_panel() -> void:
	var pair := _battle(78)
	var st: GameState = pair[0]
	var sim := Simulation.new(st)
	var guard := 0
	while guard < 40 and st.battle_reports.is_empty():
		sim.step()
		guard += 1
	if st.battle_reports.is_empty():
		_ok(false, "Visuel : bataille pour la vue")
		return
	var tree := Engine.get_main_loop() as SceneTree
	var panel := BattleReplayPanel.new()
	panel.size = Vector2(1600, 900)
	tree.root.add_child(panel)
	panel.show_replay(st, 0, st.battle_reports[0])
	_ok(panel.backdrop.visible and panel.backdrop.get_child_count() >= 3, "Visuel : décor monté derrière la vue")
	_ok(panel.backdrop.star_pos.y < 900.0 * 0.3, "Visuel : l'étoile est en haut de l'arène")
	_ok(not panel._sprites.is_empty(), "Visuel : sprites éclairés pour les peuples qui en ont")
	panel.t = panel.day_count() * BattleReplayPanel.DAY_SECONDS * 0.5
	panel._update_scene()
	var cam := panel.backdrop.cam
	panel._update_scene()
	_ok(panel.backdrop.cam == cam and cam != Vector2.ZERO, "Visuel : caméra fonction du temps du replay")
	panel.toggle_tactical()
	_ok(not panel.backdrop.visible and not panel._ships.visible, "Visuel : la vue tactique cache le décor")
	panel.toggle_tactical()
	_ok(panel.backdrop.visible, "Visuel : retour au décor")
	var old := UiSettings.replay_detail
	UiSettings.replay_detail = "sobre"
	panel.show_replay(st, 0, st.battle_reports[0])
	_ok(panel._detail == 0 and panel.backdrop.detail == 0, "Visuel : détail sobre appliqué")
	UiSettings.replay_detail = old
	# Un vieux rapport sans décor garde un décor par défaut.
	var legacy: Dictionary = st.battle_reports[0].duplicate(true)
	legacy.erase("scene")
	panel.show_replay(st, 0, legacy)
	_ok(not panel.backdrop.scene.is_empty(), "Visuel : décor par défaut pour un ancien rapport")
	panel.close_silently()
	panel.queue_free()
