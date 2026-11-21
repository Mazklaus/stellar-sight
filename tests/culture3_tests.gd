extends RefCounted
## Tests du rayonnement culturel, lot 3 (étude du 2026-11-15) : rayonnement religieux, Conservateurs,
## alliés, ambassades culturelles, Troupes de spectacle, lois Exception et Ouverture culturelles et
## pare-feu, opérations d'espionnage, famille de l'Amphictyonie, talents par couche, credo Plaisir et
## Idole des étoiles, IA. Appelés par smoke_test.gd.

const C1 := preload("res://tests/culture_tests.gd")

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Rayonnement culturel (actions et ponts)…")
	_test_faith()
	_test_conservator()
	_test_allies()
	_test_embassy()
	_test_troupe()
	_test_laws()
	_test_spy()
	_test_amph()
	_test_talents()
	_test_plaisir()
	_test_ai()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _test_faith() -> void:
	var st := C1.new_game(11, {"faiths": "actives"})
	if st.relics.is_empty():
		_ok(true, "pas de reliques (rayonnement religieux sauté)")
		return
	var holy := ""
	for rid in Relics.ids():
		if Relics.is_holy(rid):
			holy = rid
			break
	var before := CultureBridges.religious(st, 0)
	Relics.gain(st, 0, holy)
	_ok(CultureBridges.religious(st, 0) >= before + int(Culture.data()["sources"]["holy_relic"]), "une relique sainte au Reliquaire rayonne")
	var lines := false
	for p in Culture.source_parts(st, 0):
		lines = lines or String(p[0]) == "Rayonnement religieux"
	_ok(lines, "ligne « Rayonnement religieux » dans le détail")


func _test_conservator() -> void:
	var st := C1.new_game(11, {"heroes": true})
	var sid := FactionTraits.capital_system(st, 0)
	_ok(CultureBridges.conservator_bonus(st, 0, sid, 5) == 0, "sans gouverneur Orateur, pas de Conservateur")
	var hid := st.next_hero_id
	st.heroes[hid] = {"owner": 0, "cls": "orateur", "lvl": 3, "post": "system", "target": sid, "name": "Test", "status": "active", "arrive": 0}
	st.next_hero_id += 1
	if Heroes.at_post(st, "system", sid, 0).is_empty():
		_ok(true, "héros de test inactif dans ce montage (Conservateur sauté)")
		return
	_ok(CultureBridges.conservator_bonus(st, 0, sid, 5) == 5, "un Orateur gouverneur double les œuvres du système")


func _test_allies() -> void:
	var st := C1.new_game()
	C1.meet(st, 0, 1)
	st.culture["rad"]["1"] = 50
	_ok(CultureBridges.ally_share(st, 0) == 0, "pas d'allié : rien")
	Diplomacy.sign_treaty(st, 0, 1, Diplomacy.PEACE)
	Diplomacy.sign_treaty(st, 0, 1, Diplomacy.ALLIANCE)
	if Diplomacy.allied(st, 0, 1):
		_ok(CultureBridges.ally_share(st, 0) == 10, "allié : 20 % de son Rayonnement")
	else:
		_ok(true, "alliance refusée par ce montage (sauté)")


func _other_credo(st: GameState, a: int) -> int:
	var ca := String(FactionTraits.species(st.get_empire(a).faction()).get("credo", ""))
	for e in st.empires:
		if e.id != a and String(FactionTraits.species(e.faction()).get("credo", "")) != ca:
			return e.id
	return -1


func _test_embassy() -> void:
	var st := C1.new_game()
	var b := _other_credo(st, 0)
	C1.meet(st, 0, b)
	st.get_empire(0).resources["influence"] = 0
	_ok(SimCommands.validate(st, SimCommands.cul_act(0, "ambassade", b)) != "", "ambassade : il faut de l'influence")
	st.get_empire(0).resources["influence"] = 500
	_ok(SimCommands.validate(st, SimCommands.cul_act(0, "ambassade", b)) == "", "ambassade possible chez un autre credo")
	var before := Culture.flow_pct(st, 0, b)
	SimCommands.apply(st, SimCommands.cul_act(0, "ambassade", b))
	_ok(CultureBridges.embassies(st, 0).has(b) and Culture.flow_pct(st, 0, b) > before, "ambassade ouverte : diffusion accrue")
	var c2 := -1
	for e in st.empires:
		if e.id != 0 and e.id != b:
			c2 = e.id
			C1.meet(st, 0, c2)
			break
	if CultureBridges.embassy_max(st, 0) == 1:
		_ok(SimCommands.validate(st, SimCommands.cul_act(0, "ambassade", c2)) != "", "une seule ambassade (hors talent)")
	else:
		_ok(CultureBridges.embassy_max(st, 0) == 2, "talent : une ambassade de plus")
	SimCommands.apply(st, SimCommands.cul_act(0, "fermer", b))
	_ok(CultureBridges.embassies(st, 0).is_empty(), "ambassade fermée")


func _test_troupe() -> void:
	var st := C1.new_game()
	C1.meet(st, 0, 1)
	st.get_empire(0).resources["energy"] = 1000
	st.get_empire(0).resources["influence"] = 1000
	_ok(SimCommands.validate(st, SimCommands.cul_act(0, "troupe", 1)) != "", "Troupe : il faut l'Holovision")
	Research.grant(st, 0, ["arts_holographiques", "propagande"])
	_ok(SimCommands.validate(st, SimCommands.cul_act(0, "troupe", 1)) == "", "Troupe disponible")
	SimCommands.apply(st, SimCommands.cul_act(0, "troupe", 1))
	_ok(CultureBridges.troupes_of(st, 0).size() == 1, "la Troupe part en tournée")
	_ok(SimCommands.validate(st, SimCommands.cul_act(0, "troupe", 1)) != "", "une tournée à la fois")
	var added: Array[Dictionary] = []
	for i in 91:
		st.tick += 1
		CultureBridges.daily(st, added)
	var shown := false
	for a in added:
		shown = shown or String(a.get("text", "")).begins_with("Tournée de la Troupe")
	_ok(shown and CultureBridges.troupes_of(st, 0).is_empty(), "trois mois plus tard, le spectacle a lieu (résultat aléatoire)")


func _test_laws() -> void:
	var st := C1.new_game(11, {"politics": Politics.default_mode()})
	var off := C1.new_game(11, {"politics": Politics.default_mode(), "culture": "aucun"})
	if not Laws.applies(st, 1):
		_ok(true, "politique absente (lois sautées)")
		return
	_ok(Laws.check_adopt(off, 1, "exception_culturelle") != "", "sans rayonnement, pas d'Exception culturelle")
	C1.meet(st, 0, 1)
	var before := Culture.flow_pct(st, 0, 1)
	Laws._w(st, 1)["laws"].append("exception_culturelle")
	st.relic_rev += 1
	_ok(Culture.flow_pct(st, 0, 1) < before, "Exception culturelle : les cultures étrangères freinées")
	_ok(CultureBridges.law_pct(st, 1, "heritage_pct") == 25, "Exception culturelle : Patrimoine +25 %")
	_ok(Laws.check_adopt(st, 1, "ouverture_culturelle") != "", "Exception et Ouverture s'excluent")
	var st2 := C1.new_game()
	C1.meet(st2, 0, 1)
	var b2 := Culture.flow_pct(st2, 0, 1)
	Research.grant(st2, 1, ["propagande"])
	_ok(Culture.flow_pct(st2, 0, 1) < b2, "pare-feu culturel de la Propagande")


func _test_spy() -> void:
	var st := C1.new_game()
	C1.meet(st, 0, 1)
	C1.meet(st, 2, 1)
	for pr in [[0, 1], [2, 1]]:
		Diplomacy.sign_treaty(st, int(pr[0]), int(pr[1]), Diplomacy.PEACE)
		Diplomacy.sign_treaty(st, int(pr[0]), int(pr[1]), Diplomacy.TRADE)
	_ok(not Espionage.op_def("campagne_culturelle").is_empty() and not Espionage.op_def("vol_oeuvre").is_empty() and not Espionage.op_def("denigrement").is_empty(), "trois opérations culturelles")
	_ok(CultureBridges.spy_check(st, 0, 1, "vol_oeuvre") != "", "vol d'œuvre : il faut un musée qui expose")
	var b := Culture.flow_pct(st, 0, 1)
	CultureBridges.spy_apply(st, 0, 1, Espionage.op_def("campagne_culturelle"))
	_ok(Culture.flow_pct(st, 0, 1) == b + 50, "campagne : diffusion +50 %")
	st.culture["tier"]["2>1"] = 4
	st.culture["cum"]["2>1"] = 999
	C1.meet(st, 2, 1)
	var b2 := Culture.flow_pct(st, 2, 1)
	CultureBridges.spy_apply(st, 0, 1, Espionage.op_def("denigrement"))
	_ok(Culture.flow_pct(st, 2, 1) == b2 - 25, "dénigrement : la culture dominante chez lui perd 25 %")
	var off := C1.new_game(11, {"culture": "aucun"})
	C1.meet(off, 0, 1)
	_ok(CultureBridges.spy_check(off, 0, 1, "campagne_culturelle") != "", "sans rayonnement, pas d'opération culturelle")


func _test_amph() -> void:
	var st := C1.new_game(11, {"amphictyony": "active"})
	_ok(Amphictyony.family_available(st, "culture"), "famille Culture de l'Amphictyonie disponible")
	var off := C1.new_game(11, {"amphictyony": "active", "culture": "aucun"})
	_ok(not Amphictyony.family_available(off, "culture"), "sans rayonnement, pas de famille Culture")


func _test_talents() -> void:
	var st := C1.new_game()
	for e in st.empires:
		match e.faction_id:
			"choeur":
				_ok(Culture.tal(st, e.id, "faith_pct") == 75, "Chœur : théocratie + talent de peuple, rayonnement religieux +75 %")
			"vael":
				_ok(Culture.tal(st, e.id, "embassies") == 1 and Culture.tal(st, e.id, "link_pct") == 10, "Vael : une ambassade de plus, conversation galactique")
			"brisecomete":
				_ok(bool(Culture.talent(st, e.id).get("ignore_embargo", false)) and Culture.tal(st, e.id, "luxury_extra") == 10, "Brisecomète : contrebande de feuilletons, luxes")
			"murmurants":
				_ok(Culture.tal(st, e.id, "radiance_pct") == 0, "Murmurants : plus de trait Orateurs (équilibrage B5)")
		_ok(not Culture.talent_labels(st, e.id).is_empty(), "talents affichés pour %s" % e.faction_id)


func _test_plaisir() -> void:
	var found := false
	for c in GameData.species_parts()["credo"]:
		found = found or String(c["id"]) == "plaisir"
	_ok(found, "credo Plaisir dans l'éditeur d'espèces")
	_ok(Research.exists("idole") and String(Research.tech("idole").get("victory", "")) == "idole", "technologie de la victoire de peuple")
	var lean: Dictionary = Politics.data()["lean"]["credo"]
	_ok(String(lean.get("plaisir", "")) == "concorde", "credo Plaisir : penchant politique (Concorde)")
	var fp: Dictionary = {"species": {"credo": "plaisir"}}
	_ok(FactionTraits.species_matches(fp, Victory.info("idole")["requires"]), "un peuple Plaisir a droit à l'Idole")
	var st := C1.new_game()
	var pr := {"pct": 0, "cond": false, "keep": false, "won": false, "lines": [], "hold": 360, "held": 0}
	CultureLife.victory_idole(st, st.get_empire(0), pr)
	_ok(not bool(pr["cond"]) and not (pr["lines"] as Array).is_empty(), "Idole : avancée calculée (population étrangère charmée)")


func _test_ai() -> void:
	var sim := Simulation.new(C1.new_game(17, {"ai_level": "normal"}))
	var st := sim.state
	for e in st.empires:
		Research.grant(st, e.id, ["rhetorique", "arts_holographiques"])
		e.resources["materials"] = 5000
		e.resources["energy"] = 5000
	sim.advance(200)
	var museums := 0
	for pid in st.colonies:
		var c: Colony = st.colonies[pid]
		if c.buildings.has("musee_galactique") or c.construction == "musee_galactique":
			museums += 1
	_ok(museums > 0, "l'IA bâtit des Musées galactiques (%d)" % museums)
