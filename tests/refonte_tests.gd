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
	var cells := view.territory_cells()
	_ok(cells.has(home) and int(cells[home]["owner"]) == 0, "le système d'origine a son territoire")
	var fill: PackedVector2Array = cells[home]["fill"]
	var far := 0.0
	for p in fill:
		far = maxf(far, p.distance_to(st.galaxy.systems[home].position))
	_ok(fill.size() == GalaxyView.TERRITORY_STEPS and far <= GalaxyView.TERRITORY_RADIUS * 1.06, "un territoire ne dépasse pas sa portée (%.0f)" % far)
	_ok(not (cells[home]["edges"] as Array).is_empty(), "un territoire isolé a son bord")
	var owned := 0
	for s in st.galaxy.systems:
		if st.system_owner(s.id) >= 0 and st.get_empire(st.system_owner(s.id)) != null:
			owned += 1
	_ok(cells.size() == owned, "une cellule par système possédé (%d pour %d)" % [cells.size(), owned])
	_ok(view.territory_cells() == cells, "les territoires ne sont recalculés que si la carte change")
	_ok(view.is_capital(home), "la capitale est reconnue")

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
