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
	_test_power()
	_test_new_game_steps()
	_test_species_steps()
	_test_save_list()
	_test_map_options()
	_test_first_steps()
	_test_lore_texts()
	_test_first_contact()
	_test_chains()
	_test_defects()
	_test_art()


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
	_ok(UiDomains.locate("order") == [0, 3] and UiDomains.locate("order:tresor") == [0, 5], "Ordre et Trésor dans Empire")
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
	# Peuples (C3) : un onglet à part, des cartes par espèce.
	_ok(UiDomains.locate("peoples") == [0, 2] and UiDomains.locate("order") == [0, 3], "l'onglet Peuples suit Colonies dans Empire")
	var pc := PeoplesScreen.cards(st, 0)
	_ok(UiDomains.offered(st, 0, "peoples") == st.peoples_on, "l'onglet Peuples suit le réglage des peuples mêlés")
	if not pc.is_empty():
		var sum := 0
		for c2: Dictionary in pc:
			sum += int(c2["pct"])
		_ok(bool(pc[0]["founder"]) or int(pc[0]["count"]) >= int(pc[pc.size() - 1]["count"]), "les espèces vont de la plus nombreuse à la moins nombreuse")
		_ok(sum <= 100 and sum > 100 - pc.size(), "les parts des espèces font le tout de l'empire")
	# Administration (C5) : la capacité est au milieu de la jauge.
	var gz := AdminUi.Gauge.new()
	gz.cap = 40
	gz.charge = 40
	_ok(is_equal_approx(gz.fill_ratio(), 0.5), "charge égale à la capacité : la jauge est à moitié")
	gz.charge = 200
	_ok(is_equal_approx(gz.fill_ratio(), 1.0), "la jauge plafonne au double de la capacité")
	gz.free()
	# Trésor (C6) : barres empilées à la même échelle.
	var sb := Widgets.StackBar.new(200, 16)
	sb.size = Vector2(200, 16)
	sb.set_parts([{"value": 30, "color": Color.WHITE, "label": "a"}, {"value": 20, "color": Color.WHITE, "label": "b"}], 100.0)
	var rs := sb.rects()
	_ok(sb.total() == 50 and is_equal_approx(rs[0].size.x, 60.0) and is_equal_approx(rs[1].position.x, 60.0) and is_equal_approx(rs[1].size.x, 40.0), "les parts d'une barre empilée se suivent à l'échelle")
	sb.free()
	# Grands chantiers (C7) : état des cartes de merveille.
	if Wonders.enabled(st):
		var known := ["done", "ruin", "locked", "race", "free", "nosite"]
		var bad := 0
		for wid in Wonders.all_ids():
			if not known.has(String(WondersUi.card_state(st, 0, wid, {})["id"])):
				bad += 1
		_ok(bad == 0, "chaque merveille a un état de carte connu")
	# Recherche (C8) : la file se réordonne, les prérequis repassent devant.
	var rs2 := GameState.create(11)
	var re := rs2.get_empire(0)
	var picked: Array[String] = []
	for tid in Research.visible_ids(re.faction(), rs2, 0):
		if picked.size() >= 3:
			break
		if Research.check_queue(rs2, 0, tid) == "" and (Research.tech(tid).get("pre", []) as Array).is_empty():
			Research.apply_queue(rs2, 0, tid, false)
			picked.append(tid)
	if picked.size() == 3:
		re.research_progress = 7
		_ok(Research.check_move(rs2, 0, picked[2], 2) != "" and Research.check_move(rs2, 0, picked[2], 5) != "" and Research.check_move(rs2, 0, picked[2], 0) == "",
				"déplacer dans la file : rang valide et différent seulement")
		Research.apply_move(rs2, 0, picked[2], 0)
		_ok(re.research_queue[0] == picked[2] and re.research_queue.size() == 3, "la technologie déplacée passe en tête")
		_ok(re.research_progress == 0 and int(re.research_shelf.get(picked[0], 0)) == 7, "le travail entamé est mis de côté")
		Research.apply_move(rs2, 0, picked[0], 0)
		_ok(re.research_progress == 7 and not re.research_shelf.has(picked[0]), "et retrouvé quand elle revient en tête")
		_ok(SimCommands.validate(rs2, SimCommands.research_move(0, picked[1], 0)) == "", "l'ordre research_move est valide")
		_ok(ResearchQueueBar.months(rs2, 0).size() == 3, "un délai par technologie de la file")
	# Fouilles (C11) : avancement d'un site et vitrine du Reliquaire.
	_ok(ArchaeoUi.site_progress({"done": -1, "ch": 2, "chapters": 4}) == 2 and ArchaeoUi.site_progress({"done": 3, "ch": 1, "chapters": 4}) == 4,
			"un site terminé a tous ses chapitres, un site en cours ceux franchis")
	var show := ChronicleScreen.showcase(st, 0)
	var held_n := 0
	for c3: Dictionary in show:
		if bool(c3["held"]):
			held_n += 1
	_ok(show.size() == st.relics.size() and held_n == Relics.owned(st, 0).size(), "la vitrine a une case par relique de la partie")
	# Forces (C12, C14, C15) : onglets Flottes et Batailles, armées groupées par lieu.
	_ok(UiDomains.locate("fleets") == [2, 0] and UiDomains.locate("battles") == [2, 3], "Flottes ouvre le domaine Forces, Batailles le ferme")
	var fr := FleetsScreen.rows(st, 0)
	var own := 0
	for fid in st.fleets:
		if (st.fleets[fid] as Fleet).owner == 0:
			own += 1
	_ok(fr.size() == own and own > 0, "une ligne par flotte de l'empire")
	var by_power := FleetsScreen.sorted_rows(st, 0, "power", true)
	_ok(int(by_power[0]["power"]) >= int(by_power[by_power.size() - 1]["power"]), "tri des flottes par puissance")
	var f0: Fleet = st.fleets[int(fr[0]["id"])]
	_ok(SimCommands.validate(st, SimCommands.rename_fleet(0, f0.id, "  ")) != "" and SimCommands.validate(st, SimCommands.rename_fleet(1, f0.id, "Avant-garde")) != "",
			"renommer une flotte : nom non vide, flotte à soi")
	SimCommands.apply(st, SimCommands.rename_fleet(0, f0.id, " Avant-garde "))
	_ok(f0.fleet_name == "Avant-garde", "la flotte prend son nouveau nom")
	_ok(FleetsScreen.order_text(st, f0) != "", "chaque flotte a un ordre lisible")
	var gr := ArmiesScreen.groups(st, [{"id": 1, "f": f0.id, "s": -1, "hp": 5, "mo": 5, "t": "inf", "sp": ""}, {"id": 2, "f": f0.id, "s": -1, "hp": 5, "mo": 5, "t": "inf", "sp": ""},
			{"id": 3, "f": -1, "s": f0.system_id, "hp": 5, "mo": 5, "t": "inf", "sp": ""}])
	_ok(gr.size() == 2 and String(gr[0]["key"]) == "f:%d" % f0.id and (gr[0]["regs"] as Array).size() == 2, "régiments groupés par lieu, les flottes d'abord")
	st.battle_reports.append({"sides": [{"empire": 0}, {"empire": 1}], "end": 90, "winner": 0, "system_name": "Test"})
	st.battle_reports.append({"sides": [{"empire": 1}, {"empire": 2}], "end": 95, "winner": 1, "system_name": "Ailleurs"})
	var be := BattlesScreen.entries(st, 0)
	_ok(be.size() == 1 and String(be[0]["verdict"]) == "won" and int(be[0]["index"]) == st.battle_reports.size() - 2, "seules les batailles de l'empire sont listées")
	# Diplomatie (C16, C18, C19) : onglets Empires, Ligue, Voisins.
	_ok(UiDomains.locate("diplomacy") == [3, 0] and UiDomains.locate("diplomacy:league") == [3, 1] and UiDomains.locate("diplomacy:neighbors") == [3, 2],
			"Empires, Ligue et Voisins ouvrent le domaine Diplomatie")
	_ok(UiDomains.offered(st, 0, "diplomacy:empires") and UiDomains.locate("amphictyony") == [3, 3], "l'onglet Empires est toujours offert, l'Assemblée suit")
	# Renseignement (C20) : opérations en cartes par famille, les possibles d'abord.
	var fams := IntelScreen.ops_by_family(st, 0, 1)
	var seen := 0
	var sorted_ok := true
	for f: Dictionary in fams:
		seen += (f["ops"] as Array).size()
		var ready := int(f["ready"])
		for i in (f["ops"] as Array).size():
			var free := Espionage.check_op(st, 0, 1, String(f["ops"][i])) == ""
			sorted_ok = sorted_ok and free == (i < ready)
	_ok(fams.size() == Espionage.FAMILY_LABELS.size() and seen == Espionage.op_ids().size(), "chaque opération figure dans une famille, une seule fois")
	_ok(sorted_ok, "dans chaque famille, les opérations possibles viennent d'abord")
	# Volets internes (C17, C20) : un seul visible, le choix survit à une reconstruction.
	var es := EmpireScreens.new()
	var row := es.pane_row("essai", [["a", "A"], ["b", "B"]], "a")
	_ok(es.pane_box("essai", "a").visible and not es.pane_box("essai", "b").visible, "le volet par défaut est montré")
	es.set_pane("essai", "b")
	_ok(es.pane_box("essai", "b").visible and not es.pane_box("essai", "a").visible and (es.panes["essai"]["buttons"]["b"] as Button).button_pressed, "changer de volet")
	for k: String in es.panes["essai"]["boxes"]:
		(es.panes["essai"]["boxes"][k] as Node).free()
	row.free()
	var row2 := es.pane_row("essai", [["a", "A"], ["b", "B"]], "a")
	_ok(es.pane_box("essai", "b").visible, "le volet choisi reste après reconstruction")
	for k: String in es.panes["essai"]["boxes"]:
		(es.panes["essai"]["boxes"][k] as Node).free()
	row2.free()
	es.free()
	# Commerce (C21) : routes bloquées en tête, trajet en miniature.
	var old_routes: Array = st.trade.get("routes", [])
	st.trade["routes"] = [{"from": 0, "to": 1, "kind": "ext", "net": 9, "path": [0, 1], "blocked": false}, {"from": 1, "to": 0, "kind": "ext", "net": 2, "path": [1, 0], "blocked": true, "at": 1},
			{"from": 0, "to": 2, "kind": "ext", "net": 14, "path": [0, 2], "blocked": false}, {"from": 1, "to": 2, "kind": "ext", "net": 50, "path": [1, 2], "blocked": false}]
	var rr := TradeScreen.route_rows(st, 0)
	_ok(rr.size() == 3 and bool(rr[0]["blocked"]) and int(rr[1]["net"]) == 14 and int(rr[2]["net"]) == 9, "routes de l'empire : la bloquée d'abord, puis les plus rentables")
	st.trade["routes"] = old_routes
	var rm := Widgets.RouteMap.new()
	rm.set_path(PackedVector2Array([Vector2(100, 100), Vector2(300, 100), Vector2(300, 180)]), Color.WHITE, 1)
	var fit := rm.fitted(Vector2(120, 34))
	var inside := true
	for q in fit:
		inside = inside and q.x >= 0.0 and q.x <= 120.0 and q.y >= 0.0 and q.y <= 34.0
	_ok(fit.size() == 3 and inside and is_equal_approx(fit[1].x, fit[2].x), "le trajet miniature tient dans son cadre et garde ses proportions")
	rm.free()
	# Accords (C23) : une carte par partenaire, les partenaires commerciaux d'abord.
	var kp := GoodsScreen.knowledge_partners(st, 0)
	var tp := Trade.partners(st, 0)
	var kp_ok := kp.size() >= tp.size()
	for i in tp.size():
		kp_ok = kp_ok and kp[i] == int(tp[i])
	for o in kp:
		kp_ok = kp_ok and o != 0 and kp.count(o) == 1
	_ok(kp_ok, "partenaires de savoir : chacun une fois, les partenaires commerciaux d'abord")
	# Réseau (C24) : schéma des liaisons.
	var sch := PortsUi.schema(st, 0)
	var sch_ok := (sch["nodes"] as Array).size() == Stability.systems_of(st, 0).size()
	var caps := 0
	for n: Dictionary in sch["nodes"]:
		caps += 1 if bool(n["capital"]) else 0
	for l: Array in sch["links"]:
		sch_ok = sch_ok and state_neighbors(st, int(sch["nodes"][int(l[0])]["sid"]), int(sch["nodes"][int(l[1])]["sid"]))
	_ok(sch_ok and caps == 1, "schéma du réseau : un nœud par système colonisé, la capitale marquée, des liens entre voisins seulement")


func state_neighbors(st: GameState, a: int, b: int) -> bool:
	return st.galaxy.systems[a].neighbors.has(b)


func _test_power() -> void:
	# Foi (C28) : préceptes en cartes.
	var st := GameState.create(11)
	_ok(FaithScreen.precept_cards(st, "aucune").is_empty(), "sans foi, pas de carte de précepte")
	# Sénat (C27) : les doléances ne passent en tête que si elles pressent.
	_ok(not SenateScreen.grievance_urgent(st, 0), "au calme, les doléances restent en bas de l'écran")
	# Rayonnement (C29) : l'échelle des paliers monte ; Panthéon (C30) : chaque héros dans un seul groupe.
	var scale := CultureScreen.tier_scale()
	var rising := scale.size() == Culture.tiers().size()
	for i in range(1, scale.size()):
		rising = rising and int(scale[i][2]) > int(scale[i - 1][2])
	_ok(rising, "Rayonnement : l'échelle des paliers suit les seuils croissants")
	var grouped := 0
	var seats_ok := false
	for grp: Dictionary in HeroScreen.groups(st, 0):
		grouped += (grp["ids"] as Array).size()
		if String(grp["key"]) == "council":
			seats_ok = int(grp["vacant"]) == Heroes.seats(st, 0) - Heroes.council(st, 0).size()
	_ok(grouped == Heroes.ids_of(st, 0).size() and seats_ok, "Panthéon : chaque héros a son groupe, les sièges vides du conseil sont comptés")
	# Vue d'un système (B6) : chaque ordre a son onglet, et les quatre onglets sont comptés.
	var acts: Array[Dictionary] = [{"tab": "build"}, {"tab": "yard"}, {"tab": "yard"}, {}]
	var tc := SystemScreen.tab_counts(acts)
	_ok(int(tc["build"]) == 1 and int(tc["yard"]) == 2 and int(tc["overview"]) == 1 and int(tc["troops"]) == 0, "vue système : les ordres se rangent dans quatre onglets")
	# Fenêtres en jeu (C35) : le gabarit à deux colonnes porte son illustration à gauche.
	var layer := CanvasLayer.new()
	var fbox := AnnounceFrame.build(layer, 500.0, "Décision", 10, AnnounceFrame.ART_WIDTH)
	var fart := AnnounceFrame.art_of(layer)
	_ok(fart != null and fart.get_parent() == fbox.get_parent() and fart.get_index() == 0, "fenêtres en jeu : illustration à gauche du texte")
	layer.free()
	# Journal (C31) et Annales (C32).
	_ok(QuestPanel.pressing(st, 0).is_empty(), "Journal : rien ne presse au premier jour")
	var tl := DeedsUi.timeline(st, 0, 0)
	var tl_ok := true
	for i in range(1, tl.size()):
		tl_ok = tl_ok and int(tl[i - 1]["t"]) >= int(tl[i]["t"])
	_ok(tl_ok and DeedsUi.timeline(st, 0, 0, "deed").size() <= tl.size(), "Annales : la frise va du plus récent au plus ancien, le filtre ne fait que retirer")
	_ok(ChronicleScreen.tabs(st).has("annals") and not ChronicleScreen.tabs(st).has("hours"), "Annales : les Heures ont rejoint la frise")
	var gr := DeedsUi.glory_ranking(st, 0, true)
	_ok(gr.size() == st.empires.size(), "Annales : un rang de Gloire par empire en lice")
	# Victoires (C34) : un rang par empire en lice, le plus avancé d'abord.
	var lead := EmpireScreens.victory_leaders(st, -1, st.empires)
	var sorted_ok := lead.size() == st.empires.size()
	for i in range(1, lead.size()):
		sorted_ok = sorted_ok and int(lead[i - 1]["pct"]) >= int(lead[i]["pct"])
	_ok(sorted_ok, "Victoires : la course classe chaque empire par sa voie la plus avancée")
	_ok(BestiaryPanel.shade_of(st, 0, String(Fauna.species_ids()[0])) == "shadow", "Bestiaire : une espèce non étudiée reste une silhouette")
	# Anneau des relations (C16) : un empire par place, les sujets après leur suzerain.
	var ring := DiplomacyTable.ring_order(st, 0)
	var ring_ok := ring.size() == st.empires.size() - 1 and not ring.has(0)
	for e in st.empires:
		ring_ok = ring_ok and (e.id == 0 or ring.count(e.id) == 1)
	_ok(ring_ok, "anneau des relations : chaque autre empire y figure une fois")
	var table := DiplomacyTable.new(430.0)
	table.size = Vector2(430, 430)
	table.setup(st, 0, ring[0])
	var inside := true
	for id in ring:
		var lr := table.label_rect(id)
		var rect := Rect2(lr[0], lr[1])
		inside = inside and rect.position.x >= 0.0 and rect.position.y >= 0.0 and rect.end.x <= 430.0 and rect.end.y <= 430.0
	_ok(inside and table.buttons.size() == ring.size(), "anneau des relations : toutes les étiquettes tiennent dans le bloc")
	table.free()


## Menus guidés (D1) : la Nouvelle partie en cinq étapes.
func _test_new_game_steps() -> void:
	var menu := MainMenu.new()
	Engine.get_main_loop().root.add_child(menu)
	menu.show_page("new")
	_ok(menu.new_step == 0 and menu.step_buttons.size() == MainMenu.STEPS.size(), "nouvelle partie : cinq étapes, la première d'abord")
	menu.set_step(3)
	_ok(menu.back() and menu.new_step == 2 and menu.page == "new", "nouvelle partie : Échap revient à l'étape précédente")
	menu.set_step(99)
	_ok(menu.new_step == MainMenu.STEPS.size() - 1 and menu._np_go.visible and not menu._np_next.visible, "nouvelle partie : la dernière étape porte Commencer")
	var classic := str(MainMenu.rules_part(menu.settings()))
	_ok(menu.apply_rules_preset("decouverte") and menu.rules_preset_id == "decouverte" and str(MainMenu.rules_part(menu.settings())) != classic,
			"nouvelle partie : Découverte change les règles")
	_ok(menu.crises != Crisis.default_mode() and not menu.plagues, "nouvelle partie : Découverte retire la crise et les fléaux")
	_ok(menu.apply_rules_preset("classique") and str(MainMenu.rules_part(menu.settings())) == classic, "nouvelle partie : Classique rend les réglages par défaut")
	_ok(menu.recap_lines().size() >= 5, "nouvelle partie : le récapitulatif dit le peuple, la galaxie, les rivaux, les règles et la victoire")
	_ok(MainMenu.home_line(3) != "" and not MainMenu.home_line(3).begins_with("Prototype"), "accueil : une phrase de chronique à la place de la ligne Prototype")
	menu.queue_free()


## Menus guidés (D2) : la création d'un peuple en six étapes, et la vue complète à trois onglets.
func _test_species_steps() -> void:
	var ed := SpeciesEditor.new()
	Engine.get_main_loop().root.add_child(ed)
	_ok(ed.guided and ed.step == 0 and ed._step_buttons.size() == 6 and ed._step_pages[0].visible, "peuple : six étapes, « D'où partir » d'abord")
	_ok(ed._sections["layer_registre"].get_parent() == ed._slots["step1"] and ed._sections["traits"].get_parent() == ed._slots["step3"], "peuple : registre à l'étape 2, traits à l'étape 4")
	var placed := 0
	for id in ed._sections:
		if (ed._sections[id] as Control).get_parent() != null:
			placed += 1
	_ok(placed == ed._sections.size(), "peuple : chaque section a sa place dans la vue guidée")
	ed.set_step(2)
	_ok(ed._step_pages[2].visible and not ed._step_pages[0].visible and ed._next_b.text.contains("Ce qui les distingue") and ed._prev_b.text.contains("Qui sont-ils"),
			"peuple : Suivant et Précédent portent le nom de l'étape où ils mènent")
	# Page blanche : le portrait suit l'archétype tant qu'on ne l'a pas choisi.
	ed.set_layer("archetype", "lithoide")
	_ok(String(ed.spec["portrait"]).begins_with("lithoide"), "peuple : sur une page blanche, le portrait suit l'archétype (%s)" % ed.spec["portrait"])
	ed.set_portrait("humanoide_3")
	ed.set_layer("archetype", "reptilien")
	_ok(String(ed.spec["portrait"]) == "humanoide_3", "peuple : un portrait choisi ne bouge plus")
	# Le refus se montre à l'étape en cause.
	ed.set_layer("archetype", "ruche")
	var errs := ed.step_errors()
	_ok(not (errs[1] as PackedStringArray).is_empty() and not (errs[2] as PackedStringArray).is_empty() and (errs[3] as PackedStringArray).is_empty(),
			"peuple : une ruche sans esprit de ruche est signalée à Nature et à Mœurs, pas aux Traits")
	_ok(ed._step_buttons[1].text.ends_with("!") and ed._step_errors[1].visible and not ed._step_errors[3].visible, "peuple : le fil marque l'étape à corriger")
	ed.set_layer("archetype", "humanoide")
	ed._name_edit.text = ""
	ed._name_edit.text_changed.emit("")
	errs = ed.step_errors()
	_ok(not (errs[5] as PackedStringArray).is_empty() and (errs[1] as PackedStringArray).is_empty(), "peuple : un nom vide est signalé à la dernière étape")
	ed._name_edit.text = "Gens du Sel"
	ed._name_edit.text_changed.emit("Gens du Sel")
	ed.toggle_trait("prolifiques")
	ed.toggle_trait("pelerins")
	(ed.spec["traits"] as Array).append("pelerins")
	ed._refresh()
	_ok(not (ed.step_errors()[3] as PackedStringArray).is_empty(), "peuple : deux traits de croissance sont signalés aux Traits")
	(ed.spec["traits"] as Array).clear()
	ed._refresh()
	# Chronique proposée : trois lignes, une phrase par brique, et pas d'écrasement sans second clic.
	var c := SpeciesEditor.chronicle(ed.spec)
	_ok(c.split("\n").size() == 3 and not c.contains("%"), "peuple : la chronique proposée tient en trois lignes")
	var missing := []
	for layer in ["archetype", "gouvernement", "credo", "origine"]:
		for b: Dictionary in Species.options(layer):
			if not (SpeciesEditor.chronicle_parts().get(layer, {}) as Dictionary).has(String(b["id"])):
				missing.append("%s/%s" % [layer, b["id"]])
	for bm in Species.parts()["biomes"]:
		if not (SpeciesEditor.chronicle_parts().get("biome", {}) as Dictionary).has(String(bm)):
			missing.append("biome/%s" % bm)
	_ok(missing.is_empty(), "peuple : chaque brique a sa phrase de chronique (%s)" % str(missing))
	_ok(ed.propose_chronicle() and String(ed.spec["lore"]) == c and ed._lore_edit.text == c, "peuple : la chronique s'écrit dans l'histoire vide")
	ed.set_layer("credo", "profit")
	_ok(ed.propose_chronicle() and String(ed.spec["lore"]) != c, "peuple : une proposition non retouchée se remplace d'un clic")
	ed.spec["lore"] = "Texte du joueur."
	_ok(not ed.propose_chronicle() and String(ed.spec["lore"]) == "Texte du joueur." and ed.propose_chronicle(), "peuple : un texte du joueur n'est remplacé qu'au second clic")
	# Vue complète : les trois onglets d'origine, avec les mêmes contrôles.
	ed.show_tab("layers")
	_ok(not ed.guided and ed._pages["layers"].visible and not ed._step_pages[2].visible and ed._sections["layer_registre"].get_parent() == ed._slots["layers"]
			and ed._sections["names"].get_parent() == ed._slots["identity_form"], "peuple : la vue complète range les sections dans les trois onglets")
	ed.set_step(4)
	_ok(ed.guided and ed._step_pages[4].visible and ed._sections["portraits"].get_parent() == ed._slots["step4"] and not ed._pages["layers"].visible, "peuple : retour à la vue guidée")
	_ok(Species.errors(ed.spec.merged({"id": "p_gens_du_sel"}, true)).is_empty(), "peuple : le peuple composé par étapes est valide")
	ed.queue_free()


## Menus (D3b) : en-tête lisible sans charger la partie, liste triée, trois fichiers automatiques qui tournent.
func _test_save_list() -> void:
	var dir := "user://test_saves_refonte"
	for old: Dictionary in SaveGame.list(dir):
		SaveGame.remove(String(old["path"]))
	var st := GameState.create(5)
	var first := SaveGame.new_path(dir)
	_ok(SaveGame.save_state(st, first, {"mode": "turns", "turn_days": 30}, {"announce": {"big": "x".repeat(6000)}}, {"empire": "Gens du Sel", "color": "c0392b", "kind": "manual"}) == OK, "sauvegarde à part écrite")
	var h := SaveGame.head(first)
	_ok(String(h.get("empire", "")) == "Gens du Sel" and String(h.get("kind", "")) == "manual" and String(h.get("date", "")) != "" and not h.has("state"),
			"sauvegarde : l'en-tête se lit sans l'état, même avec un gros état de poste")
	var loaded := SaveGame.load_state(first)
	_ok(loaded != null and loaded.checksum() == st.checksum() and String(SaveGame.last_clock.get("mode", "")) == "turns", "sauvegarde : l'en-tête ne change rien au chargement")
	_ok(SaveGame.new_path(dir) != first, "sauvegarde : un nouveau fichier n'écrase pas le précédent")
	var autos := {}
	for i in SaveGame.AUTOSAVE_SLOTS:
		var p := SaveGame.autosave_path(dir)
		autos[p] = true
		SaveGame.save_state(st, p, {}, {}, {"kind": "auto"})
	_ok(autos.size() == SaveGame.AUTOSAVE_SLOTS and autos.has(SaveGame.autosave_path(dir)), "sauvegarde automatique : trois fichiers, puis on réécrit l'un d'eux")
	var f := FileAccess.open(dir.path_join("notes.json"), FileAccess.WRITE)
	f.store_string("{\"autre\": 1}")
	f.close()
	_ok(SaveGame.list(dir).size() == 1 + SaveGame.AUTOSAVE_SLOTS, "liste : un fichier qui n'est pas une sauvegarde est ignoré")
	_ok(SaveList.when_text("2026-11-24T19:23:40") == "24/11/2026, 19 h 23", "liste : le moment de l'enregistrement se lit en clair")
	var list := SaveList.new()
	list.dir = dir
	Engine.get_main_loop().root.add_child(list)
	_ok(list.paths.size() == 1 + SaveGame.AUTOSAVE_SLOTS and list._rows.get_child_count() == list.paths.size(), "liste : une ligne par sauvegarde")
	list.remove(first)
	_ok(not list.paths.has(first) and not FileAccess.file_exists(first), "liste : supprimer efface le fichier et la ligne")
	for old: Dictionary in SaveGame.list(dir):
		SaveGame.remove(String(old["path"]))
	DirAccess.remove_absolute(dir.path_join("notes.json"))
	list.refresh()
	_ok(list.paths.is_empty() and list._empty.visible, "liste : vide, elle le dit")
	list.queue_free()


## Options (D3f) : l'onglet Carte et ses cinq réglages.
func _test_map_options() -> void:
	var before := [UiSettings.map_emblems, UiSettings.map_cargos, UiSettings.map_labels, UiSettings.map_glide, UiSettings.fleet_silhouettes]
	var path_guard := UiSettings.PATH
	_ok(path_guard != "", "options : chemin des réglages")
	var panel := OptionsPanel.new()
	Engine.get_main_loop().root.add_child(panel)
	panel.show_tab("map")
	_ok(panel._pages.has("map") and panel._pages["map"].visible and OptionsPanel.TABS.size() == 6, "options : onglet Carte, six onglets avec le Son")
	UiSettings.map_glide = "normal"
	UiSettings.map_labels = "all"
	panel.sync()
	_ok(panel._glide.text == "Posé" and is_equal_approx(UiSettings.map_glide_seconds(), 0.45), "options : le glissement entre paliers part de Posé")
	UiSettings.map_glide = "none"
	_ok(UiSettings.map_glide_seconds() == 0.0, "options : Immédiat ne glisse pas")
	UiSettings.map_glide = before[3]
	UiSettings.map_labels = before[2]
	_ok(panel._silhouettes.get_parent().get_parent() == panel._pages["map"], "options : les silhouettes des flottes sont rangées dans Carte")
	panel.queue_free()


## Premières minutes (D3d) : trois objectifs à la suite, lus dans l'état de la partie.
func _test_first_steps() -> void:
	var st := GameState.create(21, 60, 900.0, "ossarane")
	_ok(FirstSteps.active(st, 0) and FirstSteps.steps(st, 0) == [0, 1, 2] and FirstSteps.current(st, 0) == 0, "premiers pas : trois objectifs, sonder d'abord")
	var ls := FirstSteps.lines(st, 0)
	_ok(ls.size() == 4 and String(ls[0][0]).begins_with("▸") and String(ls[1][0]).contains("éclaireur"), "premiers pas : l'objectif en cours dit le geste")
	var e := st.get_empire(0)
	for s in st.galaxy.systems:
		if not e.surveyed.has(s.id):
			e.surveyed[s.id] = true
			e.explored[s.id] = true
			break
	_ok(FirstSteps.current(st, 0) == 1 and String(FirstSteps.lines(st, 0)[0][0]).begins_with("✓"), "premiers pas : un système sondé, on passe à la colonie")
	e.research_queue.append("x")
	_ok(FirstSteps.done(st, 0)[2] and FirstSteps.current(st, 0) == 1, "premiers pas : une recherche en file compte, la colonie reste à faire")
	for fid in st.fleets.keys():
		if (st.fleets[fid] as Fleet).owner == 0 and Fleets.colonizer_ship(st.fleets[fid]) != "":
			st.fleets.erase(fid)
	_ok(FirstSteps.steps(st, 0) == [0, 2] and not FirstSteps.active(st, 0), "premiers pas : sans vaisseau colon, l'objectif de colonie tombe et le suivi se ferme")
	e.research_queue.clear()
	_ok(FirstSteps.active(st, 0) and FirstSteps.current(st, 0) == 2, "premiers pas : file de recherche vide, le rappel revient")
	st.tick = FirstSteps.LIMIT_DAYS + 1
	_ok(not FirstSteps.active(st, 0) and FirstSteps.lines(st, 0).is_empty(), "premiers pas : plus de guide passé deux ans")
	var odd := GameState.create(21, 60, 900.0, "signal")
	_ok(FirstSteps.steps(odd, 0).is_empty() and not FirstSteps.active(odd, 0), "premiers pas : un peuple sans monde natal n'est pas guidé")
	var tracker := QuestTracker.new()
	Engine.get_main_loop().root.add_child(tracker)
	tracker.set_state(GameState.create(21, 60, 900.0, "ossarane"), 0)
	_ok(tracker.visible and tracker._box.get_child_count() >= 5, "premiers pas : le suivi les montre au-dessus des quêtes")
	tracker.queue_free()


## Textes (E2) : descriptions d'univers des technologies, règles d'écriture vérifiables à la machine.
func _test_lore_texts() -> void:
	var techs: Dictionary = GameData.technologies()["technologies"]
	var with_lore := 0
	var bad := []
	var quotes := 0
	for tid: String in techs:
		var t: Dictionary = techs[tid]
		var lore := String(t.get("lore", ""))
		if lore == "":
			continue
		with_lore += 1
		if bool(t.get("quote", false)):
			quotes += 1
		# Pas de tiret long, pas de chiffre d'effet répété (« % », « × »), trois phrases au plus, 400 caractères au plus.
		if lore.contains("—") or lore.contains("–") or lore.contains("%") or lore.contains("×") or lore.length() > 400 or lore.count(". ") > 2 or not lore.ends_with("."):
			bad.append(tid)
	_ok(with_lore == techs.size(), "textes : toutes les technologies ont leur description d'univers (%d sur %d)" % [with_lore, techs.size()])
	_ok(bad.is_empty(), "textes : les descriptions tiennent les règles d'écriture (%s)" % str(bad))
	_ok(quotes * 10 <= with_lore, "textes : une technologie décrite sur dix au plus garde une citation")
	var t0: Dictionary = techs["propulseurs"]
	_ok(String(t0["lore"]).contains("deutérium") and not Research.shows_flavor(techs["canons_masse"]) and Research.shows_flavor({"flavor": "x"}) and Research.shows_flavor({"flavor": "x", "lore": "y", "quote": true}),
			"textes : la description remplace le bon mot, sauf citation gardée")
	var era1 := []
	for tid: String in ["canons_masse", "lentilles", "blindage_composite", "debarquement", "propulseurs", "capteurs", "cales_rapides", "hydroponie",
			"fusion_compacte", "extraction", "academies", "reseau_planetaire", "adaptation", "administration", "rhetorique", "medecine"]:
		if String(techs[tid].get("lore", "")) == "":
			era1.append(tid)
	_ok(era1.is_empty(), "textes : aucune technologie commune de l'ère I sans description (%s)" % str(era1))
	# E3 : une ligne par type de monde, par terrain, et pour les bâtiments de départ et de la première ère.
	var lines := {}
	var pt: Dictionary = GameData.planet_types()
	for k: String in pt:
		if pt[k] is Dictionary and (pt[k] as Dictionary).has("label"):
			lines["monde " + k] = String(pt[k].get("lore", ""))
	var tr: Dictionary = Terrain.data()["terrains"]
	for k: String in tr:
		lines["terrain " + k] = String(tr[k].get("lore", ""))
	for k: String in ["capitale", "ferme_hydroponique", "centrale_fusion", "complexe_minier", "forum", "comptoir", "temple", "tribunal", "depot_flotte", "station_etude",
			"academie", "clinique", "dome_biospherique", "poste_securite", "maison_spectacles", "cale_seche", "enrichissement_sols", "forage_geothermique", "puits_extraction", "tripot_portuaire"]:
		lines["bâtiment " + k] = String(GameData.building(k).get("lore", ""))
	var wrong := []
	for k: String in lines:
		var l: String = lines[k]
		if l == "" or l.length() > 200 or l.count(". ") > 1 or not l.ends_with(".") or l.contains("—") or l.contains("–") or l.contains("%") or l.contains("+"):
			wrong.append(k)
	_ok(lines.size() == 49 and wrong.is_empty(), "textes : mondes, terrains et premiers bâtiments ont une ligne aux règles (%d, %s)" % [lines.size(), str(wrong)])
	var bare := []
	var bd: Dictionary = GameData.buildings()
	for k: String in bd:
		if bd[k] is Dictionary and (bd[k] as Dictionary).has("label"):
			var l := String(bd[k].get("lore", ""))
			if l == "" or l.length() > 200 or l.count(". ") > 1 or not l.ends_with(".") or l.contains("%") or l.contains("+") or l.contains("—"):
				bare.append(k)
	_ok(bare.is_empty(), "textes : chaque bâtiment a sa ligne (%s)" % str(bare))
	_ok(GameData.lore_then("A.", "B.") == "A.\n\nB." and GameData.lore_then("", "B.") == "B." and GameData.lore_then("A.", "") == "A.", "textes : la description passe avant l'effet")
	var st := GameState.create(3, 100, 1500.0, "vael", {"ai_level": "", "terrain": "normal"})
	var found := false
	for sid: int in st.galaxy.systems.size():
		if not Terrain.at(st, sid).is_empty():
			found = Terrain.lore_lines(st, sid).size() == Terrain.at(st, sid).size()
			break
	_ok(found, "textes : un système à terrain donne sa description au survol")
	var cats := {}
	for e: Dictionary in CodexCatalogs.entries("mondes") + CodexCatalogs.entries("terrains"):
		cats[String(e["id"])] = String(e["body"])
	_ok(cats.size() == 29 and String(cats.get("cat:mondes:ocean", "")).contains("hauts-fonds") and String(cats.get("cat:terrains:neutron", "")).contains("vingt kilomètres"), "textes : le Codex liste les mondes et les terrains (%d)" % cats.size())
	_ok(Research.new_techs({"b": true, "a": true, "c": true}, {"c": true}) == ["a", "b"], "textes : une découverte se signale une fois, dans un ordre stable")


## E4 : le premier contact en fenêtre pleine. Une carte par rencontre, le salut du peuple rencontré, trois réponses.
func _test_first_contact() -> void:
	var fc: Dictionary = GameData.first_contact()
	var missing := []
	var wrong := []
	for f: Dictionary in GameData.factions():
		var id := String(f["id"])
		var t: Dictionary = (fc["peuples"] as Dictionary).get(id, {})
		if t.is_empty():
			missing.append(id)
			continue
		for k: String in ["voix", "salut", "replique"]:
			var s := String(t.get(k, ""))
			if s == "" or s.contains("—") or s.contains("–") or s.contains("«") or s.length() > 330:
				wrong.append("%s.%s" % [id, k])
	_ok(missing.is_empty() and wrong.is_empty(), "contact : chaque peuple a sa voix, son salut et sa réplique (%s, %s)" % [str(missing), str(wrong)])
	_ok(Events.contact_texts("peuple_inconnu") == fc["defaut"], "contact : un peuple créé prend les textes par défaut")
	var st := GameState.create(11, 60, 1200.0, "ossarane", {"ai_level": "", "events": "aucun"})
	var a := st.empires[0]
	var b: Empire = null
	for e in st.empires:
		if e.id != a.id and not e.is_npc():
			b = e
			break
	_ok(b != null, "contact : un rival pour la rencontre")
	if b == null:
		return
	var added: Array[Dictionary] = []
	Events.on_contact(st, a, b, added)
	var mine := []
	for it: Dictionary in Events.inbox(st, a.id):
		if String(it["card"]) == Events.CONTACT_CARD:
			mine.append(it)
	var theirs := []
	for it: Dictionary in Events.inbox(st, b.id):
		if String(it["card"]) == Events.CONTACT_CARD:
			theirs.append(it)
	_ok(mine.size() == 1 and theirs.size() == 1 and int(mine[0]["rival"]) == b.id, "contact : chacun reçoit la fenêtre, même événements coupés")
	var item: Dictionary = mine[0]
	var c := Events.card(Events.CONTACT_CARD)
	var txt := Events.fill(st, a.id, item, String(c["text"]))
	_ok(txt.contains(String(Events.contact_texts(b.faction_id)["salut"])) and not txt.contains("{"), "contact : le salut est celui du peuple rencontré")
	var opts := Events.choices(st, a.id, item)
	_ok(opts.size() == 3 and String(opts[2]["label"]).contains("propre table") and not (opts[0]["lines"] as Array).is_empty() and (opts[1]["lines"] as Array).size() == 1,
			"contact : trois réponses, la troisième propre à votre peuple, l'effet écrit sous chacune")
	_ok(Events.contact_voice(st, item) != "", "contact : quelqu'un parle au nom du peuple rencontré")
	var before := Diplomacy.opinion(st, b.id, a.id)
	var inf := int(a.resources.get("influence", 0))
	Events.choose(st, a.id, int(item["id"]), 2, added)
	_ok(Diplomacy.opinion(st, b.id, a.id) == before - 10 and int(a.resources.get("influence", 0)) == inf + 20, "contact : la réplique du peuple coûte 10 d'opinion et rapporte 20 d'influence")
	var log: Array = Events.meta(st, a.id)["log"]
	_ok(String(log[-1]["title"]) == "Premier contact : %s" % b.display_name(), "contact : le journal garde la rencontre sous son nom")
	Events.choose(st, b.id, int(theirs[0]["id"]), 0, added)
	_ok(Diplomacy.opinion(st, a.id, b.id) >= 15 - 20, "contact : venir en voisins vaut 15 d'opinion")
	var panel := EventPanel.new()
	Engine.get_main_loop().root.add_child(panel)
	Events.on_contact(st, a, b, added)
	var again: Dictionary = Events.inbox(st, a.id)[-1]
	panel.open(st, a.id, again)
	_ok(panel._voice.visible and panel._voice.text == Events.contact_voice(st, again) and panel._head.text == "Votre réponse" and panel.choice_buttons.size() == 3, "contact : la fenêtre montre la voix et trois réponses")
	panel.queue_free()


## E7 : chaînes d'événements. La carte suivante arrive plus tard (délai caché) ou quand l'objectif est rempli.
## Lot 6 : images provisoires et Galerie (F3, F4).
func _test_art() -> void:
	var slots := ArtCatalog.slots()
	var ids := {}
	var bad := []
	for s: Dictionary in slots:
		if ids.has(s["id"]) or String(s["label"]) == "" or ArtCatalog.family(String(s["family"])).is_empty():
			bad.append(s["id"])
		ids[s["id"]] = true
	_ok(slots.size() >= 300 and bad.is_empty(), "images : %d emplacements recensés, chacun nommé une seule fois %s" % [slots.size(), str(bad)])
	_ok(ids.has("event_pn_1") and ids.has("wonder_bourse_galactique") and ids.has("planet_ocean") and ids.has("screen_colonies")
			and ids.has("faction_ossarane_scene") and ids.has("annonces/war_declared"), "images : cartes, merveilles, mondes, écrans, peuples et annonces y sont")
	var pr := ArtCatalog.progress()
	_ok(int(pr[1]) == slots.size() and int(pr[0]) <= int(pr[1]), "images : le décompte des illustrations déposées")
	_ok(CodexCatalogs.entries("galerie").size() == slots.size() and String(CodexCatalogs.entry("cat:galerie:annonces__war_declared").get("name", "")) != "",
			"images : la Galerie du Codex a une fiche par emplacement")
	var slot := Widgets.ArtSlot.new("event_pn_1", Vector2(300, 160), UiTheme.ACCENT, "star")
	slot.size = Vector2(300, 160)
	var small := Widgets.ArtSlot.new("relic_x", Vector2(58, 42), UiTheme.ACCENT, "star")
	small.size = Vector2(58, 42)
	var locked := Widgets.ArtSlot.new("", Vector2(300, 160), UiTheme.ACCENT, "lock")
	locked.size = Vector2(300, 160)
	_ok(slot._wants_tableau() and not small._wants_tableau() and not locked._wants_tableau(), "images : tableau provisoire pour un emplacement nommé et assez grand")
	slot.free()
	small.free()
	locked.free()


## Lot 6 : défauts relevés pendant l'étude.
func _test_defects() -> void:
	var seen := {}
	var twice := []
	for o: Dictionary in Espionage.data()["operations"]:
		if seen.has(String(o["id"])):
			twice.append(String(o["id"]))
		seen[String(o["id"])] = true
	_ok(twice.is_empty() and bool(Espionage.op_def("voler_plans_modele").get("capture", false)) and bool(Espionage.op_def("voler_plans").get("wonders", false)),
			"défauts : chaque opération d'espionnage a son identifiant %s" % str(twice))
	var placed: Array[Rect2] = [Rect2(100, 100, 120, 60)]
	var free := SystemView.card_shift(Rect2(300, 100, 120, 60), placed, 4.0)
	var down := SystemView.card_shift(Rect2(150, 130, 120, 60), placed, 4.0)
	var up := SystemView.card_shift(Rect2(150, 70, 120, 60), placed, 4.0)
	_ok(free == 0.0 and down == 34.0 and up == -34.0, "défauts : une fiche de planète gênée glisse du côté le plus court (%s, %s, %s)" % [free, down, up])
	var st := GameState.create(11, 60, 1200.0, "ossarane", {"ai_level": ""})
	for cls: String in Heroes.data()["classes"]:
		var txt := Heroes.post_effect_text(st, {"post": "council", "cls": cls, "lvl": 3, "traits": [], "owner": 0})
		_ok(txt != "" and not txt.contains("%d"), "défauts : un héros %s au conseil a son texte d'effet" % cls)


func _test_chains() -> void:
	var st := GameState.create(11, 60, 1200.0, "ossarane", {"ai_level": "", "events": "normaux"})
	var a := st.empires[0]
	var cap := FactionTraits.capital_system(st, a.id)
	var added: Array[Dictionary] = []
	_ok(Events.card_ids("monthly").has("pn_1") and not Events.card_ids("monthly").has("pn_2") and Events.card_ids("chain").size() >= 2, "chaînes : seule la première carte se tire, les suites attendent leur tour")
	var chain_ids: Array = Events.card_ids("chain")
	var heads := 0
	var loose := []
	for c: Dictionary in Events.data()["cards"]:
		if not c.has("chain"):
			continue
		var id := String(c["id"])
		var txt := String(c["text"])
		_ok(txt.length() > 900 and txt.count("\n\n") >= 2 and not txt.contains("—") and not txt.contains("!"), "chaînes : %s est un récit long, en paragraphes" % id)
		if String(c["trigger"]) != "chain":
			heads += 1
		if Events.chain_def(String(c["chain"])).is_empty():
			loose.append(id)
		for ch: Dictionary in c["choices"]:
			if ch.has("then"):
				var t: Dictionary = ch["then"]
				if not chain_ids.has(String(t["card"])) or String(Events.card(String(t["card"])).get("chain", "")) != String(c["chain"]) \
						or (t.has("goal") and (String(t["goal"]) != "fleet" or String(t.get("text", "")) == "" or not ch.has("note"))):
					loose.append(id)
	_ok(heads >= 7 and loose.is_empty(), "chaînes : %d affaires, chaque suite existe et reste dans son affaire %s" % [heads, str(loose)])
	Events.push(st, a.id, "pn_1", {"system": cap}, added)
	var it1: Dictionary = Events.inbox(st, a.id)[-1]
	var opts := Events.choices(st, a.id, it1)
	_ok(opts.size() == 3 and (opts[1]["lines"] as Array).has("On ne saura pas ce qu'il y a derrière."), "chaînes : un choix qui clôt l'affaire le dit")
	Events.choose(st, a.id, int(it1["id"]), 0, added)
	var ws := Events.waits(st, a.id)
	_ok(ws.size() == 1 and String(ws[0]["card"]) == "pn_2" and int(ws[0]["at"]) >= st.tick + 150 and int(ws[0]["at"]) <= st.tick + 270, "chaînes : la suite est attendue entre 150 et 270 jours")
	var lines := Events.affair_lines(st, a.id)
	_ok(lines.size() == 2 and String(lines[0][0]).contains("Le puits Neuf") and not String(lines[1][0]).contains("jour"), "chaînes : le suivi nomme l'affaire sans dire le délai")
	# La sauvegarde garde l'attente.
	var copy := GameState.from_dict(st.to_dict())
	_ok(Events.waits(copy, a.id).size() == 1 and int(Events.waits(copy, a.id)[0]["at"]) == int(ws[0]["at"]) and copy.checksum() == st.checksum(), "chaînes : l'attente passe la sauvegarde")
	st.tick = int(ws[0]["at"]) - 1
	Events.daily(st, added)
	_ok(Events.waits(st, a.id).size() == 1, "chaînes : rien n'arrive avant l'heure")
	st.tick += 1
	Events.daily(st, added)
	var box := Events.inbox(st, a.id)
	_ok(Events.waits(st, a.id).is_empty() and not box.is_empty() and String(box[-1]["card"]) == "pn_2" and int(box[-1]["system"]) == cap, "chaînes : la deuxième carte arrive, au même endroit")
	var it2: Dictionary = box[-1]
	Events.choose(st, a.id, int(it2["id"]), 0, added)
	ws = Events.waits(st, a.id)
	_ok(ws.size() == 1 and String(ws[0]["goal"]) == "fleet" and String(ws[0]["text"]).begins_with("Amener une flotte à "), "chaînes : un objectif remplace le délai")
	var far := ws[0].duplicate() as Dictionary
	for sid: int in st.galaxy.systems.size():
		if Fleets.fleets_at(st, sid, a.id).is_empty():
			far["system"] = sid
			break
	_ok(not Events.wait_ready(st, a.id, far) and Events.wait_ready(st, a.id, ws[0]) == (not Fleets.fleets_at(st, cap, a.id).is_empty()), "chaînes : l'objectif attend une flotte sur place")
	var tracker := QuestTracker.new()
	Engine.get_main_loop().root.add_child(tracker)
	tracker.set_state(st, a.id)
	var shown := ""
	for n in tracker._box.get_children():
		if n is Label:
			shown += (n as Label).text + "|"
	_ok(shown.contains("AFFAIRES EN COURS") or shown.contains("Affaires en cours"), "chaînes : le suivi de droite montre l'affaire (%s)" % shown.left(80))
	_ok(shown.contains("Amener une flotte à "), "chaînes : et son objectif")
	tracker.queue_free()
	if Fleets.fleets_at(st, cap, a.id).is_empty():
		st.spawn_ship(a.id, "corvette", cap)
	Events.daily(st, added)
	box = Events.inbox(st, a.id)
	_ok(not box.is_empty() and String(box[-1]["card"]) == "pn_3", "chaînes : l'objectif rempli, la troisième carte arrive")
	Events.choose(st, a.id, int((box[-1] as Dictionary)["id"]), 2, added)
	var story := Events.chain_story(st, a.id, "puits_neuf")
	_ok(story.size() == 3 and String(story[0]["title"]) == "Le puits Neuf" and String(story[2]["title"]) == "La salle" and not String(story[1]["text"]).contains("{"), "chaînes : le Journal garde les trois cartes à relire")
	_ok(Events.chains_logged(st, a.id) == ["puits_neuf"] and Events.waits(st, a.id).is_empty() and not Events.meta(st, a.id).has("wait"), "chaînes : l'affaire close ne laisse rien en attente")
	var panel := EventPanel.new()
	Engine.get_main_loop().root.add_child(panel)
	Events.push(st, a.id, "pn_2", {"system": cap}, added)
	panel.open(st, a.id, Events.inbox(st, a.id)[-1])
	_ok(panel._text.scroll_active and not panel._text.fit_content and not panel._voice.visible, "chaînes : un récit long défile dans la fenêtre")
	panel.queue_free()
