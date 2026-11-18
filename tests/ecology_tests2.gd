class_name EcologyTests2
extends RefCounted
## Tests des extensions de l'écologie (props. 15 à 30, validées le 2026-11-18) : catastrophes,
## centrales allégées par les mégastructures, démantèlement, réfugiés, trait Tolérance, précepte
## Sacralité du vivant, Convention des biosphères, sabotage, siège et terre brûlée, Monde-usine,
## hauts faits, événements, biosphères remarquables, opinion, décor, sauvegarde. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Écologie, extensions…")
	_test_data()
	_test_catastrophes()
	_test_kardashev()
	_test_forge()
	_test_refugees()
	_test_tolerance()
	_test_faith()
	_test_amph()
	_test_spy()
	_test_siege()
	_test_factory()
	_test_deeds()
	_test_events()
	_test_remarkable()
	_test_opinion()
	_test_decor()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(mode := "complete") -> GameState:
	return EcologyTests.new_game(mode)


static func rival(st: GameState) -> Empire:
	var me := EcologyTests.me(st)
	for e in st.empires:
		if e != me and not e.is_npc() and not e.eliminated:
			return e
	return null


func _test_data() -> void:
	_ok(not Faiths.precept_def("sacralite_vivant").is_empty(), "précepte Sacralité du vivant au catalogue")
	_ok(not Species.trait_def("tolerants").is_empty() and bool((Species.trait_def("tolerants")["fields"] as Dictionary).get("eco_tolerant", false)), "trait Tolérants au catalogue")
	_ok(not Espionage.op_def("saboter_biosphere").is_empty(), "opération Sabotage écologique")
	_ok(not Amphictyony.family_def("biospheres").is_empty(), "famille Biosphères de l'Amphictyonie")
	_ok(not Deeds.def("jardinier_kynes").is_empty() and not Deeds.def("terre_brulee").is_empty(), "hauts faits du Jardinier de Kynes et de la Terre brûlée")
	var n := 0
	for c: Dictionary in Events.data()["cards"]:
		if String(c["id"]).begins_with("eco_"):
			n += 1
	_ok(n == 6, "six événements écologiques")


func _test_catastrophes() -> void:
	var st := new_game()
	var c := EcologyTests.home(st)
	var pid := c.planet_id
	Ecology._set_health(st, pid, 5)  # Effondrée : 8 % par mois
	c.buildings.append_array(["mine_profonde", "mine_profonde", "mine_profonde"])
	var added: Array[Dictionary] = []
	var hit := 0
	for i in 120:
		st.tick += 30
		Ecology.sub(st, "cat").erase(str(pid))
		c.population = 10
		EcologyBridges._catastrophe(st, c, added)
		if Ecology.sub(st, "cat").has(str(pid)) or c.population < 10:
			hit += 1
	_ok(hit >= 3 and hit <= 25, "Effondrée : une catastrophe de temps en temps (%d en 120 mois)" % hit)
	Ecology.sub(st, "cat")[str(pid)] = [st.tick + 90, "desert"]
	var g := {"food": 100, "materials": 100, "energy": 100}
	EcologyBridges.adjust_yields(st, c, g)
	_ok(int(g["materials"]) == 75 and int(g["food"]) == 75, "catastrophe en cours : production −25 %")
	_ok(EcologyBridges.catastrophe(st, pid) == "tempête de sable", "infobulle : la catastrophe en cours")
	# Le bouclier planétaire protège.
	Ecology.sub(st, "cat").clear()
	c.buildings.append("bouclier_planetaire")
	var protected := true
	for i in 120:
		st.tick += 30
		c.population = 10
		EcologyBridges._catastrophe(st, c, added)
		protected = protected and not Ecology.sub(st, "cat").has(str(pid)) and c.population == 10
	_ok(protected, "bouclier planétaire : aucune catastrophe ne passe")
	Ecology._set_health(st, pid, 95)
	c.buildings.erase("bouclier_planetaire")
	var none := true
	for i in 60:
		st.tick += 30
		EcologyBridges._catastrophe(st, c, added)
		none = none and not Ecology.sub(st, "cat").has(str(pid))
	_ok(none, "Florissante : pas de catastrophe")


func _test_kardashev() -> void:
	var st := new_game()
	var c := EcologyTests.home(st)
	var e := EcologyTests.me(st)
	c.buildings.append_array(["centrale_fusion", "centrale_fusion"])  # 8
	var before := Ecology.footprint(st, c.planet_id)
	st.megas = {"next": 2, "list": {"1": {"id": 1, "k": "essaim_dyson", "o": e.id, "s": 0, "st": 99}}}
	var m: Dictionary = st.megas["list"]["1"]
	m["st"] = Megastructures.stage_count("essaim_dyson")
	_ok(Megastructures.complete(m) and EcologyBridges.energy_megas(st, e.id) == 1, "un Essaim de Dyson achevé compte")
	_ok(Ecology.footprint(st, c.planet_id) == before - 2, "centrales allégées de 25 %% (%d → %d)" % [before, Ecology.footprint(st, c.planet_id)])
	_ok(Ecology.tooltip(st, c.planet_id).contains("allégée par vos mégastructures"), "infobulle : centrales allégées")
	_ok(EcologyBridges.plant_pct(st, e.id, "mine_profonde") == 100, "une mine n'est pas allégée")


func _test_forge() -> void:
	var st := new_game()
	var c := EcologyTests.home(st)
	var sid := st.galaxy.get_planet(c.planet_id).system_id
	var added: Array[Dictionary] = []
	EcologyBridges.on_dismantle(st, sid, added)
	_ok(Ecology.health(st, c.planet_id) == 50 and not added.is_empty(), "démantèlement : −20 aux biosphères du système")
	for t in ["coquille", "creux", "abri"]:
		_ok(not Ecology.living_type(t), "%s : sous cloche, sans biosphère" % t)


func _test_refugees() -> void:
	var st := new_game()
	var c := EcologyTests.home(st)
	Ecology._set_health(st, c.planet_id, 30)
	_ok(Movements.push_reason(st, c) == "climat", "Dégradée : les habitants veulent partir")
	Ecology._set_health(st, c.planet_id, 70)
	_ok(Movements.push_reason(st, c) != "climat", "Saine : personne ne part pour le climat")
	Ecology._set_health(st, c.planet_id, 5)
	c.population = 8
	var added: Array[Dictionary] = []
	for i in 12:
		EcologyBridges._refugees(st, c, added)
	_ok(c.population == 7 or not Movements.enabled(st), "Effondrée : un réfugié par an (%d)" % c.population)


func _test_tolerance() -> void:
	var st := new_game()
	var c := EcologyTests.home(st)
	var e := EcologyTests.me(st)
	Ecology._set_health(st, c.planet_id, 30)
	var g := {"food": 100}
	Ecology.adjust_yields(st, c, g)
	_ok(int(g["food"]) == 75, "sans le trait : −25 % nourriture")
	var f := e.faction()  # fiche en cache : on la modifie le temps du test, puis on la rend
	f["eco_tolerant"] = true
	g = {"food": 100}
	Ecology.adjust_yields(st, c, g)
	_ok(int(g["food"]) == 100, "Tolérants : pas de malus de nourriture")
	f.erase("eco_tolerant")
	Ecology._set_health(st, c.planet_id, 85)
	g = {"food": 100}
	Ecology.adjust_yields(st, c, g)
	_ok(int(g["food"]) == 115, "le bonus Florissant reste")


func _test_faith() -> void:
	var st := new_game()
	var c := EcologyTests.home(st)
	var e := EcologyTests.me(st)
	var sid := st.galaxy.get_planet(c.planet_id).system_id
	_ok(EcologyBridges.stability_parts(st, sid, e.id).is_empty(), "sans foi : rien")
	st.faith_on = true
	st.faiths = {"list": {"verte": {"name": "Voie verte", "precepts": ["sacralite_vivant"]}}, "state": {str(e.id): "verte"}}
	Ecology._set_health(st, c.planet_id, 90)
	_ok(EcologyBridges.stability_parts(st, sid, e.id) == [["Sacralité du vivant : monde florissant", 3]], "Sacralité du vivant : +3 sur un monde florissant")
	EcologyBridges.on_shift(st, e.id)
	Ecology._set_health(st, c.planet_id, 50)
	_ok(EcologyBridges.stability_parts(st, sid, e.id) == [["Sacralité du vivant : un monde a basculé", -5]], "Sacralité du vivant : −5 après un basculement")
	st.tick += 400
	_ok(EcologyBridges.stability_parts(st, sid, e.id).is_empty(), "la colère passe au bout d'un an")
	st.faith_on = false


func _test_amph() -> void:
	var st := new_game()
	var e := EcologyTests.me(st)
	_ok(Amphictyony.family_available(st, "biospheres"), "famille Biosphères disponible quand l'écologie est en jeu")
	_ok(not Amphictyony.family_available(new_game("desactivee"), "biospheres"), "écologie coupée : pas de famille Biosphères")
	_ok(not EcologyBridges.extraction_banned(st, e.id), "pas de Convention : Extraction permise")


func _test_spy() -> void:
	var st := new_game()
	var c := EcologyTests.home(st)
	var e := EcologyTests.me(st)
	_ok(EcologyBridges.spy_check(st, -1, e.id, "saboter_biosphere") == "", "sabotage : une cible")
	var before := Ecology.footprint(st, c.planet_id)
	var msg := EcologyBridges.spy_apply(st, -1, e.id, {"id": "saboter_biosphere"})
	_ok(msg != "" and Ecology.footprint(st, c.planet_id) == before + 12, "sabotage : +12 d'empreinte (%d → %d)" % [before, Ecology.footprint(st, c.planet_id)])
	st.tick += 400
	_ok(Ecology.footprint(st, c.planet_id) == before, "sabotage : un an seulement")
	_ok(EcologyBridges.spy_check(new_game("desactivee"), -1, e.id, "saboter_biosphere") != "", "écologie coupée : pas de sabotage")


func _test_siege() -> void:
	var st := new_game()
	var c := EcologyTests.home(st)
	var e := EcologyTests.me(st)
	var sid := st.galaxy.get_planet(c.planet_id).system_id
	var added: Array[Dictionary] = []
	_ok(EcologyBridges.check_scorch(st, e.id, c.planet_id) != "", "terre brûlée : pas sans siège ni évacuation")
	st.sieges[sid] = 1
	EcologyBridges.colony_monthly(st, c, added)
	_ok(Ecology.health(st, c.planet_id) == 65, "siège : −5 par mois")
	_ok(EcologyBridges.check_scorch(st, e.id, c.planet_id) == "", "terre brûlée : permise pendant un siège")
	SimCommands.apply(st, SimCommands.eco_act(e.id, "scorch", {"pid": c.planet_id}))
	_ok(Ecology.health(st, c.planet_id) == 0 and EcologyBridges.stat(st, e.id, "scorched") == 1, "terre brûlée : biosphère à 0")
	st.sieges.erase(sid)
	c.buildings.append_array(["mine_profonde", "mine_profonde", "mine_profonde"])
	EcologyTests.months(st, 1)
	_ok(st.galaxy.get_planet(c.planet_id).type == "desert" and EcologyBridges.stat(st, e.id, "shift") == 1, "terre brûlée : le climat bascule le mois suivant")


func _test_factory() -> void:
	var st := new_game()
	var c := EcologyTests.home(st)
	var e := EcologyTests.me(st)
	var sid := st.galaxy.get_planet(c.planet_id).system_id
	_ok(EcologyBridges.check_factory(st, e.id, c.planet_id) != "", "monde-usine : pas sur un monde sain")
	Ecology._set_health(st, c.planet_id, 5)
	_ok(SimCommands.validate(st, SimCommands.eco_act(e.id, "factory", {"pid": c.planet_id})) == "", "monde-usine : permis sur un monde effondré")
	SimCommands.apply(st, SimCommands.eco_act(e.id, "factory", {"pid": c.planet_id}))
	_ok(EcologyBridges.is_factory(st, c.planet_id) and not Ecology.has_biosphere(st, c.planet_id) and Ecology.health(st, c.planet_id) == -1, "monde-usine : plus de biosphère")
	var g := {"food": 100, "materials": 100, "energy": 100}
	Ecology.adjust_yields(st, c, g)
	_ok(int(g["materials"]) == 125 and int(g["energy"]) == 125 and int(g["food"]) == 100, "monde-usine : +25 % matériaux et énergie, pas de malus de nourriture")
	var found := false
	for p in Ecology.stability_parts(st, sid, e.id):
		found = found or (String(p[0]) == "Monde-usine" and int(p[1]) == -10)
	_ok(found, "monde-usine : −10 stabilité")
	EcologyTests.months(st, 30)
	_ok(st.galaxy.get_planet(c.planet_id).type == "continental", "monde-usine : jamais de basculement")


func _test_deeds() -> void:
	var st := new_game()
	var e := EcologyTests.me(st)
	EcologyBridges.on_regreen(st, e.id)
	EcologyBridges.on_shift(st, e.id)
	EcologyBridges.on_shift(st, e.id)
	_ok(DeedsEval.value(st, e.id, "eco_regreen") == 1 and DeedsEval.value(st, e.id, "eco_shift") == 2, "hauts faits : reverdissements et basculements comptés")


func _test_events() -> void:
	var st := new_game()
	var c := EcologyTests.home(st)
	var e := EcologyTests.me(st)
	var sid := st.galaxy.get_planet(c.planet_id).system_id
	_ok(EcologyBridges.event_systems(st, e.id).has(sid), "sujet monde vivant : le système natal")
	var item := {"card": "eco_maree_rouge", "system": sid}
	Events.apply_fx(st, e.id, item, [{"k": "eco", "v": 6}], [] as Array[Dictionary])
	_ok(Ecology.health(st, c.planet_id) == 76, "effet eco : +6 à la biosphère")
	_ok(Events.fx_lines(st, e.id, item, [{"k": "eco", "v": -6}])[0].begins_with("Biosphère -6"), "effet eco : ligne lisible")
	_ok(EcologyBridges.event_systems(new_game("desactivee"), e.id).is_empty(), "écologie coupée : pas de sujet")


func _test_remarkable() -> void:
	var st := new_game()
	var n := Ecology.sub(st, "rem").size()
	var living := 0
	for s in st.galaxy.systems:
		for pid in s.planet_ids:
			if Ecology.living_type(st.galaxy.get_planet(pid).type):
				living += 1
	_ok(n > 0 and n * 3 < living, "biosphères remarquables : environ une sur six (%d / %d)" % [n, living])
	var c := EcologyTests.home(st)
	_ok(not EcologyBridges.remarkable(st, c.planet_id), "le monde natal n'est jamais remarquable")
	Ecology.sub(st, "rem")[str(c.planet_id)] = 1
	_ok(Ecology.health(st, c.planet_id) == 90 and Ecology.planet_vitality(st, c.planet_id) == 90, "remarquable : vitalité +20 (90)")
	c.buildings.append_array(["complexe_minier", "complexe_minier"])  # 3 + 12 = 15, ×150 % = 22
	_ok(Ecology.footprint(st, c.planet_id) == 22, "remarquable : empreinte ×1,5 (%d)" % Ecology.footprint(st, c.planet_id))
	var g := {"knowledge": 0}
	EcologyBridges.adjust_yields(st, c, g)
	_ok(int(g["knowledge"]) == 3, "remarquable : +3 Savoir")
	_ok(Ecology.tooltip(st, c.planet_id).contains("Biosphère remarquable"), "infobulle : biosphère remarquable")


func _test_opinion() -> void:
	var st := new_game()
	var e := EcologyTests.me(st)
	var r := rival(st)
	if r == null:
		_ok(false, "un rival pour tester l'opinion")
		return
	Ecology.sub(st, "doc")[str(e.id)] = "preservation"
	Ecology.sub(st, "doc")[str(r.id)] = "extraction"
	_ok(EcologyBridges.opinion_parts(st, e.id, r.id) == [["Pille ses mondes (doctrine Extraction)", -10]], "Préservation : −10 envers l'Extraction")
	_ok(EcologyBridges.opinion_parts(st, r.id, e.id).is_empty(), "l'Extraction ne se fâche pas")


func _test_decor() -> void:
	var st := new_game()
	var c := EcologyTests.home(st)
	Ecology._set_health(st, c.planet_id, 70)
	_ok(EcologyBridges.tint(st, c.planet_id).is_empty(), "Saine : pas de teinte")
	Ecology._set_health(st, c.planet_id, 90)
	var t := EcologyBridges.tint(st, c.planet_id)
	_ok(not t.is_empty() and (t[0] as Color).g > (t[0] as Color).r, "Florissante : plus verte")
	Ecology._set_health(st, c.planet_id, 5)
	var m := SystemView.make_planet_material(st.galaxy.get_planet(c.planet_id))
	var before: Color = m.get_shader_parameter("c_low")
	SystemView.tint_for_biosphere(st, c.planet_id, m)
	_ok(m.get_shader_parameter("c_low") != before, "Effondrée : la planète grisonne dans la vue système")


func _test_save() -> void:
	var st := new_game()
	var c := EcologyTests.home(st)
	var e := EcologyTests.me(st)
	Ecology.sub(st, "factory")[str(c.planet_id)] = 1
	Ecology.sub(st, "sabot")["7"] = 500
	EcologyBridges.on_shift(st, e.id)
	var d := st.to_dict()
	_ok(int(d["version"]) == GameState.FORMAT_VERSION and GameState.FORMAT_VERSION >= 100, "Sauvegarde 100")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and JSON.stringify(back.to_dict()) == JSON.stringify(d), "Sauvegarde : aller-retour identique")
	_ok(back != null and EcologyBridges.is_factory(back, c.planet_id) and EcologyBridges.stat(back, e.id, "shift") == 1, "Sauvegarde : monde-usine et statistiques")
	var old := d.duplicate(true)
	var eco: Dictionary = old["ecology"]
	for k in EcologyBridges.SUBS:
		eco.erase(k)
	old["version"] = 99
	var back2 := GameState.from_dict(JSON.parse_string(JSON.stringify(old)))
	_ok(back2 != null and Ecology.sub(back2, "rem").is_empty() and Ecology.sub(back2, "factory").is_empty(), "Sauvegarde 99 : relue sans extensions")
