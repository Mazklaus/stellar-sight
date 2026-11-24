class_name RefonteTests
extends RefCounted
## Tests de la refonte de l'interface : domaines et adresses (A1), sélecteur de lentilles (A3),
## barre d'alertes (A4), points de fin de tour (A6), carte (B1, B2, B4, B5a).
##   TESTS=refonte_tests godot --headless --path . -s res://tests/_only.gd

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Refonte de l'interface…")
	_test_domains()
	_test_lenses()
	_test_alerts()
	_test_map()
	_test_fleet_card()
	_test_screens()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _test_domains() -> void:
	_ok(UiDomains.DOMAINS.size() == 8, "huit domaines")
	var seen := {}
	var dup := []
	for d in UiDomains.DOMAINS.size():
		_ok(String(UiDomains.DOMAINS[d]["key"]) == "F%d" % (d + 1), "le domaine %s est sur F%d" % [UiDomains.DOMAINS[d]["label"], d + 1])
		for t: Array in UiDomains.DOMAINS[d]["tabs"]:
			for a: String in t[1]:
				if seen.has(a):
					dup.append(a)
				seen[a] = true
	_ok(dup.is_empty(), "chaque adresse n'appartient qu'à un onglet (%s)" % str(dup))
	for sc: Dictionary in EmpireBar.SCREENS:
		var id := String(sc["id"])
		if id != "codex":
			_ok(UiDomains.domain_of(id) >= 0, "l'écran %s a un domaine" % id)
	for tid: Array in ChronicleScreen.TABS:
		_ok(UiDomains.domain_of("chronicles:%s" % tid[0]) >= 0, "l'onglet de chronique %s a un domaine" % tid[0])
	_ok(UiDomains.locate("order") == [0, 2] and UiDomains.locate("order:tresor") == [0, 4], "Ordre et Trésor dans Empire")
	_ok(UiDomains.domain_of("chronicles:archeo") == 1 and UiDomains.domain_of("chronicles:quests") == 6, "les Fouilles sont dans Savoir, le Journal dans Chroniques")
	_ok(UiDomains.group("trade:resources").has("trade:market") and UiDomains.group("trade:routes").size() == 1, "Marché réunit Ressources et Marché")
	_ok(UiDomains.group("megas").has("wonders") and UiDomains.domain_of("forge") == 0, "Grands chantiers réunit merveilles, mégastructures et forge")
	var st := GameState.create(11)
	_ok(UiDomains.first_of_domain(st, 0, 0) == "economy" and UiDomains.first_of_domain(st, 0, 4) == "trade:routes", "premier onglet d'Empire et de Commerce")
	_ok(UiDomains.offered(st, 0, "order:admin") == Admin.applies(st, 0) and UiDomains.offered(st, 0, "kardashev") == Kardashev.enabled(st), "un pilier hors jeu cache son onglet")


func _test_lenses() -> void:
	var seen := {}
	for fam: Array in Hud.LENS_FAMILIES:
		for l: Array in fam[1]:
			seen[String(l[0])] = true
			_ok(Hud.LENS_TIPS.has(String(l[0])), "la lentille « %s » dit ce qu'elle montre" % l[1])
	_ok(Hud.LENS_FAMILIES.size() == 5 and seen.size() == 17, "cinq familles, dix-sept lentilles (%d)" % seen.size())
	_ok(Hud.lens_label("") == "Empires" and Hud.lens_label("war") == "Guerre et occupations", "nom des lentilles")


func _test_alerts() -> void:
	var st := GameState.create(11)
	_ok(AlertBar.alerts(st, 0).is_empty() or AlertBar.alerts(st, 0)[0].has("text"), "barre d'alertes : lecture d'une partie neuve")
	_ok(AlertBar.alerts(st, 99).is_empty() and TurnChecks.todo(st, 99).is_empty(), "rien pour un empire absent")
	var me := st.get_empire(0)
	me.research_queue.clear()
	var todo := TurnChecks.todo(st, 0)
	var kinds := []
	for a: Dictionary in todo:
		kinds.append(a["kind"])
	_ok(kinds.has("research"), "fin de tour : la recherche vide est signalée (%s)" % str(kinds))
	_ok(TurnChecks.summary(todo) != "" and TurnChecks.summary([]) == "", "fin de tour : résumé en une ligne")
	st.battles[st.galaxy.get_planet(me.capital_planet).system_id] = {"sides": [{"empire": 0}, {"empire": 1}]}
	var al := AlertBar.alerts(st, 0)
	_ok(not al.is_empty() and String(al[0]["kind"]) == "battle" or (al.size() > 1 and String(al[1]["kind"]) == "battle"), "barre d'alertes : un combat chez soi est signalé")


func _test_map() -> void:
	_ok(GalaxyView.tier_of(0.15) == GalaxyView.TIER_GALAXY and GalaxyView.tier_of(0.45) == GalaxyView.TIER_REGION
			and GalaxyView.tier_of(2.0) == GalaxyView.TIER_SYSTEM, "trois paliers de zoom")
	for i in 3:
		_ok(GalaxyView.tier_of(GalaxyView.TIER_JUMP[i]) == i, "le bouton %s mène à son palier" % GalaxyView.TIER_NAMES[i])
	_ok(GalaxyView.cargo_count({"value": 0}) == 1 and GalaxyView.cargo_count({"value": 500}) == 4, "un à quatre cargos par route")
	for fam: Array in Hud.LENS_FAMILIES:
		for l: Array in fam[1]:
			if String(l[0]) != "":
				_ok(not Hud.lens_legend(String(l[0])).is_empty(), "la lentille « %s » a sa légende" % l[1])
	_ok(Hud.lens_legend("").is_empty(), "pas de légende pour la carte des empires")

	var st := GameState.create(11)
	var view := GalaxyView.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(view)
	view.fog = false
	view.set_state(st)
	var me := st.get_empire(0)
	var home := st.galaxy.get_planet(me.capital_planet).system_id
	var sites := view.territory_sites()
	var mine := 0
	var on_lane := 0
	var known := 0
	for e: Dictionary in sites:
		if int(e["owner"]) == 0:
			mine += 1
		if float(e["r"]) < GalaxyView.TERRITORY_RADIUS:
			on_lane += 1
		else:
			known += 1
	_ok(known == st.galaxy.systems.size(), "territoires : un site par système connu (%d)" % known)
	_ok(mine >= 2 and on_lane > 0, "territoires : le système d'origine et ses voies portent la couleur de l'empire (%d sites)" % mine)
	view.fog = true
	_ok(view.territory_sites().size() < sites.size(), "territoires : rien n'est tracé hors des cartes")
	view.fog = false
	_ok(view.is_capital(home), "la capitale est reconnue")
	var motifs := {}
	for fid: String in GameData.faction_ids():
		var e := GalaxyView.emblem_of(fid)
		motifs[e] = true
		_ok(e == GalaxyView.emblem_of(fid) and e.x >= 0 and e.x < GalaxyView.EMBLEM_MOTIFS and e.y >= 0 and e.y < 3, "emblème stable pour %s" % fid)
	_ok(motifs.size() >= 8, "les emblèmes des peuples sont variés (%d)" % motifs.size())

	# Insignes : éventail sous l'étoile, « +N » au-delà de quatre, nature et état.
	for fid in st.fleets.keys():
		if (st.fleets[fid] as Fleet).system_id == home:
			st.fleets.erase(fid)
	var ids := []
	for i in 6:
		var f := Fleet.new()
		f.id = st.next_fleet_id
		st.next_fleet_id += 1
		f.owner = 0 if i < 5 else 1
		f.fleet_name = "Essai %d" % i
		f.add_ship("scout" if i == 0 else "colony_ship")
		f.system_id = home
		st.fleets[f.id] = f
		ids.append(f.id)
	var pos := view.fleet_positions()
	var shown := 0
	for fid: int in ids:
		if pos.has(fid):
			shown += 1
	_ok(shown == GalaxyView.FAN_MAX and view.overflow_fleets(home).size() == 2, "quatre insignes et un « +2 » (%d, %d)" % [shown, view.overflow_fleets(home).size()])
	_ok(view.overflow_fleets(home).has(ids[5]), "vos flottes passent avant celles des autres")
	var c := st.galaxy.systems[home].position
	var apart := true
	for a: int in pos:
		for b: int in pos:
			if a < b and ids.has(a) and ids.has(b) and (pos[a] as Vector2).distance_to(pos[b]) < 18.0:
				apart = false
	_ok(apart and (pos[ids[0]] as Vector2).y > c.y, "l'éventail se range sous l'étoile, sans recouvrement")
	_ok(view.pick_overflow(view._overflow[home]["pos"], 14.0) == home and view.pick_overflow(c + Vector2(500, 500), 14.0) == -1, "l'insigne « +N » se clique")
	view.selected_fleet = ids[5]
	_ok(view.fleet_positions().has(ids[5]), "la flotte choisie reste visible")
	view.selected_fleet = -1
	_ok(GalaxyView.fleet_kind(st.fleets[ids[0]]) == "scout" and GalaxyView.fleet_kind(st.fleets[ids[1]]) == "civil", "nature d'une flotte : éclaireur, civil")
	_ok(view.fleet_status(st.fleets[ids[0]]) == "idle" and view.fleet_status(st.fleets[ids[5]]) == "", "état : vos flottes sans ordre, pas celles des autres")
	st.battles[home] = {"sides": [{"empire": 0}, {"empire": 1}]}
	_ok(view.fleet_status(st.fleets[ids[5]]) == "battle", "état : le combat se lit sur toutes les flottes")
	st.battles.erase(home)
	view.set_layer("fleets", false)
	_ok(view.pick_fleet(pos[ids[0]], 14.0) == -1, "calque des flottes décoché : rien à cliquer")
	view.set_layer("fleets", true)
	_ok(view.pick_fleet(pos[ids[0]], 14.0) == ids[0], "calque recoché : la flotte se clique")

	# De loin : un tiret par flotte, les vôtres à gauche, les autres à droite.
	var cam := Camera2D.new()
	cam.zoom = Vector2(0.2, 0.2)
	view.add_child(cam)
	cam.make_current()
	if view.tier() == GalaxyView.TIER_GALAXY:
		var far_pos := view.fleet_positions()
		_ok((far_pos[ids[0]] as Vector2).x < c.x and (far_pos[ids[5]] as Vector2).x > c.x and view.overflow_fleets(home).is_empty(),
				"palier Galaxie : tirets à gauche et à droite de l'étoile")
	view.queue_free()


func _test_fleet_card() -> void:
	# Fiche de flotte (B3) : groupes d'ordres et rangées de composition.
	_ok(Hud.fleet_group_of("patrol") == "move" and Hud.fleet_group_of("invade") == "here" and Hud.fleet_group_of("tactic") == "conduct"
			and Hud.fleet_group_of("merge") == "more", "les ordres sont rangés par usage, les rares dans « Autres ordres »")
	var f := Fleet.new()
	f.add_ship("scout")
	f.add_ship("colony_ship")
	f.add_ship("colony_ship")
	f.hp[f.ships.find("scout")] = 1
	var rows := Hud.fleet_rows(f)
	var total := 0
	for r: Dictionary in rows:
		total += int(r["n"])
	_ok(rows.size() == 2 and total == 3, "composition : une rangée par classe (%s)" % str(rows))
	var scout_row: Dictionary = rows[0] if String(rows[0]["ship"]) == "scout" else rows[1]
	_ok(int(scout_row["hp"]) == 1 and int(scout_row["max"]) == Fleet.max_hp_of("scout"), "composition : état des coques par classe")

	# Navigateur (A4) : colonies, chantiers, à faire.
	var st := GameState.create(11)
	var me := st.get_empire(0)
	var home := st.galaxy.get_planet(me.capital_planet).system_id
	var cols := FleetListPanel.colony_rows(st, 0)
	_ok(cols.size() >= 1 and int(cols[0]["planets"]) >= 1 and cols.any(func(r: Dictionary) -> bool: return int(r["sid"]) == home), "navigateur : la colonie d'origine est listée")
	_ok(FleetListPanel.colony_rows(st, 99).is_empty() and FleetListPanel.yard_rows(st, 99).is_empty(), "navigateur : rien pour un empire absent")
	var cap: Colony = st.colonies[me.capital_planet]
	var before := FleetListPanel.yard_rows(st, 0).size()
	if cap.ship_build == "":
		cap.ship_build = "scout"
		cap.ship_days = 7
		var yards := FleetListPanel.yard_rows(st, 0)
		_ok(yards.size() == before + 1 and yards.any(func(r: Dictionary) -> bool: return int(r["days"]) == 7 and int(r["sid"]) == home), "navigateur : un vaisseau en chantier est listé avec son délai")
	var panel := FleetListPanel.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(panel)
	panel.set_state(st, 0)
	_ok(panel.tab == "fleets" and panel.tab_buttons.size() == 4, "navigateur : quatre onglets, Flottes d'abord")
	me.research_queue.clear()
	panel.set_tab("todo")
	var got := []
	panel.todo_requested.connect(func(item: Dictionary) -> void: got.append(item["kind"]))
	_ok(panel.alt_buttons.size() == TurnChecks.todo(st, 0).size() and not panel.alt_buttons.is_empty(), "navigateur : « À faire » liste ce qui attend")
	_ok((panel.tab_buttons["todo"] as Button).text.begins_with("À FAIRE ("), "navigateur : l'onglet « À faire » porte son compte")
	panel.alt_buttons[0].pressed.emit()
	_ok(got.size() == 1, "navigateur : un clic mène à ce qui attend")
	panel.set_tab("colonies")
	var went := []
	panel.system_requested.connect(func(sid: int, open: bool) -> void: went.append([sid, open]))
	panel.alt_buttons[0].pressed.emit()
	_ok(panel.alt_buttons.size() == cols.size() and went.size() == 1 and went[0][1] == false, "navigateur : un clic sur une colonie centre la carte")
	panel.set_tab("fleets")
	_ok(panel.row_count() == Fleets.empire_fleets(st, 0).size(), "navigateur : retour à la liste des flottes")
	panel.queue_free()


func _test_screens() -> void:
	# Colonies (C2) : clés de tri du tableau.
	var a := {"planet_id": 1, "name": "Brume", "type_label": "Océan", "population": 4, "established": true, "construction": "", "construction_days": 0, "net": {"energy": 3, "materials": -1}}
	var b := {"planet_id": 2, "name": "aube", "type_label": "Aride", "population": 9, "established": true, "construction": "Mine", "construction_days": 12, "net": {"energy": 1}}
	var c := {"planet_id": 3, "name": "Cendre", "type_label": "Lave", "population": 0, "established": false, "construction": "", "construction_days": 0, "net": {}}
	_ok(EmpireScreens.colony_sort_key(b, "name", []) < EmpireScreens.colony_sort_key(a, "name", []), "tri des colonies par nom, sans égard à la casse")
	_ok(EmpireScreens.colony_sort_key(b, "pop", []) > EmpireScreens.colony_sort_key(a, "pop", []) and EmpireScreens.colony_sort_key(c, "pop", []) == -1, "tri par population, fondations en dernier")
	_ok(EmpireScreens.colony_sort_key(a, "build", [1]) < EmpireScreens.colony_sort_key(b, "build", [1])
			and EmpireScreens.colony_sort_key(b, "build", [1]) < EmpireScreens.colony_sort_key(c, "build", [1]), "tri par chantier : les libres d'abord, puis les plus proches de la fin")
	_ok(EmpireScreens.colony_sort_key(a, "net", []) == 2 and EmpireScreens.colony_sort_key(c, "net", []) == 0, "tri par bilan")
	# Ordre (C4) : les systèmes calmes se replient.
	var st := GameState.create(11)
	var mine := Stability.systems_of(st, 0)
	var tiers := Stability.tiers()
	var best := String(tiers[tiers.size() - 1]["id"])
	var calm := OrderScreen.calm_systems(st, 0)
	var wrong := 0
	for sid in calm:
		if Stability.tier_id(st, sid) != best or not mine.has(sid):
			wrong += 1
	_ok(wrong == 0, "les systèmes calmes sont à l'empire et au meilleur palier")
	_ok(OrderScreen.FOLD_FROM == 3 and OrderScreen.fold_calm, "le repli des systèmes calmes est actif par défaut, au-delà de trois")
	# Bilan (C1) : registre des 24 derniers mois et alertes qui mènent à la colonie en cause.
	var me := st.get_empire(0)
	for i in 30:
		me.note_month({"energy": i, "materials": -2})
	_ok((me.ledger["energy"] as Array).size() == Empire.LEDGER_MONTHS and int(me.ledger["energy"][0]) == 6 and int(me.ledger["energy"][23]) == 29,
			"le registre garde les 24 derniers mois")
	var back := GameState.from_dict(st.to_dict())
	_ok(back.get_empire(0).ledger == me.ledger and back.checksum() == st.checksum(), "le registre survit à la sauvegarde")
	var sl := Widgets.Sparkline.new(130, 26)
	sl.size = Vector2(130, 26)
	sl.set_values(me.ledger["energy"], Color.WHITE)
	var pts := sl.points()
	_ok(pts.size() == 24 and pts[0].y > pts[23].y and pts[0].x < pts[23].x, "la courbe monte quand le bilan monte")
	sl.free()
	_ok(EmpireScreens.economy_alerts(st, 0).is_empty(), "pas d'alerte dans un empire sain")
	me.starving = true
	var al := EmpireScreens.economy_alerts(st, 0)
	_ok(al.size() >= 1 and int(al[0]["planet"]) == me.capital_planet and bool(al[0]["bad"]), "la famine désigne la colonie la plus peuplée")
	me.starving = false
