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
	_test_lot3()


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


## Lot 3 (espace) : coques par style de peuple, manœuvres selon la tactique, essaims, terrain, son.
func _test_lot3() -> void:
	print("Visuel des combats, lot 3 (espace)…")
	_ok(SpeciesLook.hull_style("khthari") == "organique", "Lot 3 : coques organiques pour l'Essaim")
	_ok(SpeciesLook.hull_style("ferrocornes") == "roc", "Lot 3 : coques de roc pour les Ferrocornes")
	_ok(SpeciesLook.hull_style("vael") != SpeciesLook.hull_style("choeur"), "Lot 3 : deux registres, deux styles de coque")
	_ok(SpeciesLook.hull_style("") == "fuseau", "Lot 3 : style de coque par défaut")
	_ok(HullArt.shape_id("porte_vaisseaux") == "porte_vaisseaux" and HullArt.parts_of("porte_vaisseaux").has("hangar"),
			"Lot 3 : le porte-vaisseaux a sa forme et son hangar")
	_ok(HullArt.shape_id("scout") == "corvette", "Lot 3 : une classe sans modèle prend une forme selon sa taille")
	var styles: Dictionary = HullArt.cfg()["styles"]
	var sizes := {}
	for stl in styles:
		var ct := HullArt.lit_texture(String(stl), "croiseur", Color(0.8, 0.2, 0.2))
		_ok(ct.diffuse_texture != null and ct.normal_texture != null, "Lot 3 : coque %s dessinée avec ses normales" % stl)
		sizes[String(stl)] = ct.diffuse_texture.get_size()
	var small := HullArt.lit_texture("fuseau", "corvette", Color.RED).diffuse_texture.get_width()
	var big := HullArt.lit_texture("fuseau", "titan", Color.RED).diffuse_texture.get_width()
	_ok(big > small * 2, "Lot 3 : un titan est bien plus long qu'une corvette")
	_ok(HullArt.lit_texture("nef", "croiseur", Color.RED) == HullArt.lit_texture("nef", "croiseur", Color.RED), "Lot 3 : coques en cache")
	# Bataille : la tactique est relevée, les lignes avancent selon la phase.
	var pair := _battle(79)
	var st: GameState = pair[0]
	for f in st.fleets.values():
		if f.owner == 0:
			f.tactic = "assaut"
	var sim := Simulation.new(st)
	var guard := 0
	while guard < 40 and st.battle_reports.is_empty():
		sim.step()
		guard += 1
	if st.battle_reports.is_empty():
		_ok(false, "Lot 3 : bataille pour la vue")
		return
	var rep: Dictionary = st.battle_reports[0]
	var tacs := {}
	for sd: Dictionary in rep["sides"]:
		tacs[int(sd["empire"])] = String(sd.get("tac", ""))
	_ok(tacs.get(0, "") == "assaut", "Lot 3 : la tactique du camp est relevée dans le rapport")
	var tree := Engine.get_main_loop() as SceneTree
	var panel := BattleReplayPanel.new()
	panel.size = Vector2(1600, 900)
	tree.root.add_child(panel)
	# Rapport retouché : trois jours aux trois portées, un porte-vaisseaux, un terrain.
	var r: Dictionary = rep.duplicate(true)
	var log: Array = []
	for ph in [0, 1, 2]:
		log.append({"day": ph + 1, "phase": ph, "shots": [], "kills": []})
	r["log"] = log
	r["units"].append([0, "porte_vaisseaux", "rear", 0])
	r["scene"]["terrain"] = ["nebuleuse"]
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.size = Vector2(1600, 900)
	panel.show_replay(st, 0, r)
	var left := panel.side_tactic(true) == "assaut"
	_ok(left, "Lot 3 : la vue lit la tactique de chaque camp")
	_ok(panel.advance_at(true, 0.1) < panel.advance_at(true, BattleReplayPanel.DAY_SECONDS * 2.6), "Lot 3 : les lignes avancent à mesure que la portée raccourcit")
	_ok(panel.advance_at(true, BattleReplayPanel.DAY_SECONDS * 2.6) > panel.advance_at(false, BattleReplayPanel.DAY_SECONDS * 2.6) or panel.side_tactic(false) == "assaut",
			"Lot 3 : l'assaut avance plus que les autres tactiques")
	var i0 := 0
	panel.t = 0.1
	panel._maneuver()
	var p0: Vector2 = panel._pos[i0]
	panel.t = BattleReplayPanel.DAY_SECONDS * 2.6
	panel._maneuver()
	var p1: Vector2 = panel._pos[i0]
	_ok(absf(p1.x - 800.0) < absf(p0.x - 800.0), "Lot 3 : un vaisseau se rapproche du centre en courte portée")
	panel._maneuver()
	_ok(panel._pos[i0] == p1, "Lot 3 : manœuvres fonction du temps du replay")
	panel.toggle_tactical()
	panel._maneuver()
	_ok(panel._pos[i0] == panel._base_pos[i0], "Lot 3 : la vue tactique garde le rangement")
	panel.toggle_tactical()
	_ok(panel._carriers.has(r["units"].size() - 1), "Lot 3 : le porte-vaisseaux a un essaim de chasseurs")
	_ok(not panel._no_fighters, "Lot 3 : les chasseurs décollent dans une nébuleuse")
	_ok(not panel.backdrop.terrain_visuals.is_empty() and not panel.backdrop._clouds.is_empty(), "Lot 3 : la nébuleuse est dessinée dans le décor")
	r["scene"]["terrain"] = ["plasma"]
	panel.show_replay(st, 0, r)
	_ok(panel._no_fighters, "Lot 3 : le plasma cloue les chasseurs au hangar")
	r["scene"]["terrain"] = ["blue_giant"]
	r["scene"]["star"] = "blue_giant"
	panel.show_replay(st, 0, r)
	_ok(panel.backdrop.light_color() != BattleBackdrop.star_light("blue_giant")["color"], "Lot 3 : la lumière du terrain teinte l'arène")
	# Son : les repères passent même sans fichier.
	var rs: Dictionary = rep.duplicate(true)
	panel.show_replay(st, 0, rs)
	panel.sounds.heard.clear()
	panel.emit_cues(0.0, panel.day_count() * BattleReplayPanel.DAY_SECONDS)
	var heard: Array = panel.sounds.heard
	_ok(heard.any(func(x: String) -> bool: return x.begins_with("tir_")), "Lot 3 : repère sonore des tirs")
	_ok(heard.has("fin"), "Lot 3 : repère sonore de fin de bataille")
	_ok(BattleSounds.path_of("tir_kinetic") == "", "Lot 3 : sans fichier, le repère ne joue rien")
	panel.close_silently()
	panel.queue_free()
