class_name TranscendenceTests3
extends RefCounted
## Tests de la Transcendance, lot 3 (ponts) : l'Avorté, le Raccourci et ses pièges, talents des
## peuples, credo Transcendance, fêlures du Songe, merveilles-Relais, hauts faits, Fléau exclu.
## Appelés par TranscendenceTests.

static var _check: Callable


static func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func run(check: Callable) -> void:
	_check = check
	print("Transcendance, lot 3…")
	print("  - avorte")
	_test_avorte()
	print("  - raccourci")
	_test_raccourci()
	print("  - talents")
	_test_talents()
	print("  - bridges")
	_test_bridges()


static func _test_avorte() -> void:
	_ok(not Crisis.kind_def("avorte").is_empty() and bool(Crisis.kind_def("avorte").get("summoned", false)), "Crise « l'Avorté » : appelée, jamais tirée")
	var bad := ""
	var kd := Crisis.kind_def("avorte")
	for u in [String(kd["heart"]), String(kd["station"]), String(kd["convoy"]["unit"])] + [String(kd["wave"][0][0]), String(kd["wave"][1][0])]:
		if GameData.ship(u).is_empty():
			bad = u
	_ok(bad == "" and not Relics.def(String(kd["relic"])).is_empty(), "L'Avorté : unités et relique dans les données (%s)" % bad)
	var st := TranscendenceTests.new_game("complete", "ossarane", {"crises": "une"})
	var oss := TranscendenceTests.eid_of(st, "ossarane")
	_ok(TranscendenceBridges.abort_chance(st, oss, 80, false) == 50 and TranscendenceBridges.abort_chance(st, oss, 40, false) == 0, "Passage brisé après 75 % : jet de 50 % ; avant, rien")
	_ok(TranscendenceBridges.abort_chance(st, oss, 0, true) == 25, "Passage mené sous 30 de stabilité : jet de 25 %")
	Transcendence._stat(st, oss, "stolen_notes", 1)
	_ok(TranscendenceBridges.abort_chance(st, oss, 80, false) == 100, "Carnets volés : risque doublé")
	TranscendenceTests.to_passage(st, oss, "apotheose")
	var pop0 := 0
	for pid in st.sorted_colony_ids():
		if (st.colonies[pid] as Colony).owner == oss:
			pop0 += (st.colonies[pid] as Colony).population
	TranscendenceBridges.abort(st, oss, [])
	var pop1 := 0
	for pid in st.sorted_colony_ids():
		if (st.colonies[pid] as Colony).owner == oss:
			pop1 += (st.colonies[pid] as Colony).population
	_ok(pop1 < pop0 and Transcendence.renounced(st, oss) and Transcendence.path_of(st, oss) == "", "Avorté : la moitié du peuple perdue, plus de voie")
	_ok(String(Crisis.cur(st).get("kind", "")) == "avorte", "Avorté : la crise s'ouvre près de l'empire")


static func _test_raccourci() -> void:
	var st := TranscendenceTests.new_game()
	var oss := TranscendenceTests.eid_of(st, "ossarane")
	st.get_empire(oss).techs["oree"] = true
	Transcendence.choose_path(st, oss, "apotheose", [])
	Transcendence.sub(st, "gauge")[str(oss)] = 600
	Transcendence.sub(st, "rest")[str(oss)] = 0
	var offered := false
	for i in 120:
		Transcendence.sub(st, "rest")[str(oss)] = 0
		TranscendenceTests.months(st, 1)
		if Transcendence.sub(st, "offered").has(str(oss)):
			offered = true
			break
	_ok(offered, "Le Raccourci est offert (fenêtre d'événement)")
	var c := Events.card("orree_raccourci")
	Events.apply_fx(st, oss, {"card": "orree_raccourci"}, c["choices"][0]["fx"], [])
	_ok(Transcendence.in_passage(st, oss) and Transcendence.passage_need(st, oss) == 720 and Transcendence.oeuvre(st, oss).is_empty(), "Raccourci accepté : Passage de deux ans, sans Exodium")
	Transcendence.sub(st, "passage")[str(oss)]["prog"] = 9999
	var trapped := Transcendence._h(st, ["piege", oss]) % 100 < Transcendence.c_int("raccourci", "trap_pct", 50)
	TranscendenceTests.months(st, 1)
	if trapped:
		_ok(not Transcendence.done(st, oss) and Transcendence.renounced(st, oss) and Transcendence.stat(st, oss, "trapped") == 1, "Raccourci piégé : le peuple ne part pas (Coquilles)")
		_ok(int((Transcendence.effects(st, oss).get("production_pct", {}) as Dictionary).get("knowledge", 0)) < 0, "Coquilles : elles ne pensent plus")
	else:
		_ok(Transcendence.done(st, oss), "Raccourci honnête : le peuple transcende")
	# L'autre issue, en forçant le tirage dans les deux sens.
	var st2 := TranscendenceTests.new_game()
	var o2 := TranscendenceTests.eid_of(st2, "ossarane")
	st2.get_empire(o2).techs["oree"] = true
	Transcendence.choose_path(st2, o2, "depart", [])
	TranscendenceBridges.take_shortcut(st2, o2, [])
	var keep := Transcendence.c_int("raccourci", "trap_pct", 50)
	Transcendence.cfg("raccourci")["trap_pct"] = 100 if not trapped else 0
	Transcendence.sub(st2, "passage")[str(o2)]["prog"] = 9999
	TranscendenceTests.months(st2, 1)
	if Transcendence.ark_fleet(st2, o2) != null:
		var f := Transcendence.ark_fleet(st2, o2)
		f.system_id = int(Transcendence.ark(st2, o2)["target"])
		f.path.clear()
		TranscendenceTests.months(st2, 1)
	Transcendence.cfg("raccourci")["trap_pct"] = keep
	_ok(Transcendence.done(st2, o2) == trapped, "Raccourci : l'autre issue du tirage")


static func _test_talents() -> void:
	var st := TranscendenceTests.new_game("complete", "ossarane", {"psionics": "complet", "genetics": "complete"})
	_ok(Transcendence.talent(st, TranscendenceTests.eid_of(st, "ossarane")).has("label"), "Talents : les huit peuples en ont un")
	var mu := TranscendenceTests.eid_of(st, "murmurants")
	if mu >= 0:
		st.get_empire(mu).techs["oree"] = true
		st.get_empire(mu).techs["theorie_psionique"] = true
		_ok(Transcendence.path_why(st, mu, "songe") == "", "Murmurants : le Songe sans couronnement")
	var ch := TranscendenceTests.eid_of(st, "choeur")
	if ch >= 0:
		st.get_empire(ch).techs["oree"] = true
		Transcendence.sub(st, "path")[str(ch)] = "apotheose"
		var has := false
		for x in Transcendence.gain_parts(st, ch):
			if String(x[0]).begins_with("Talent"):
				has = true
		_ok(has, "Chœur Éternel : Apothéose +25 %")
	var va := TranscendenceTests.eid_of(st, "vael")
	if va >= 0:
		_ok(Transcendence.t_int(st, va, "referendum_stab") == 50 and Transcendence.t_int(st, va, "join_free") > 0, "Vael : référendum de l'Orée, Transcendance commune sans Relais")
	var kh := TranscendenceTests.eid_of(st, "khthari")
	var oss := TranscendenceTests.eid_of(st, "ossarane")
	if kh >= 0:
		TranscendenceTests.to_passage(st, oss, "apotheose")
		var sys := FactionTraits.capital_system(st, oss)
		var fk := st.spawn_ship(kh, "corvette", sys)
		st.spawn_ship(oss, "corvette", sys)
		_ok(TranscendenceBridges.damage_pct(st, fk, sys) == 50, "Kh'thari : +50 % de dégâts contre un empire en Passage")
	var te := TranscendenceTests.eid_of(st, "teyl")
	if te >= 0:
		Transcendence.sub(st, "path")[str(te)] = "televersement"
		_ok(TranscendenceBridges.extra_relays(st, te) == FactionTraits.network_nodes(st, te), "Teyl : chaque colonie du réseau vaut un Relais")
	var fe := TranscendenceTests.eid_of(st, "ferrocornes")
	if fe >= 0:
		st.get_empire(fe).techs["oree"] = true
		Transcendence.choose_path(st, fe, "depart", [])
		Transcendence.sub(st, "gauge")[str(fe)] = Transcendence.gauge_max()
		_ok(Transcendence.check_oeuvre(st, fe).contains("flotte-ville"), "Ferrocornes : la flotte-ville sert d'Arche")
	var bc := TranscendenceTests.eid_of(st, "brisecomete")
	if bc >= 0:
		_ok(Transcendence.t_int(st, bc, "curee_x") == 2 and Transcendence.t_int(st, bc, "gauge_pct") < 0, "Brisecomète : rois de la Curée, partent en dernier")


static func _test_bridges() -> void:
	var cr: Array = []
	for c: Dictionary in GameData.species_parts()["credo"]:
		cr.append(String(c["id"]))
	_ok(cr.has("transcendance"), "Credo Transcendance dans l'éditeur d'espèces")
	var st := TranscendenceTests.new_game("complete", "ossarane", {"psionics": "complet"})
	var oss := TranscendenceTests.eid_of(st, "ossarane")
	TranscendenceTests.to_passage(st, oss, "apotheose")
	Transcendence.sub(st, "path")[str(oss)] = "songe"
	_ok(TranscendenceBridges.felure_pct(st, oss) == 100, "Passage du Songe : fêlures deux fois plus probables")
	Transcendence.sub(st, "path")[str(oss)] = "apotheose"
	var c: Colony = st.colonies[st.get_empire(oss).capital_planet]
	c.buildings.append(String(TranscendenceBridges.relay_wonders()[0]))
	_ok(TranscendenceBridges.extra_relays(st, oss) == 1, "Une merveille compte comme Relais")
	_ok(TranscendenceBridges.hero_epitaph(st, oss) != "", "Un héros mort pendant le Passage part avec les siens")
	_ok(DeedsEval.value(st, oss, "tr_path") >= 1, "Haut fait : Premier à l'Orée")
	for id in ["premier_oree", "grande_curee", "revenu_au_dela"]:
		_ok(not (GameData.deeds()["deeds"] as Dictionary).get(id, {}).is_empty(), "Haut fait %s dans les données" % id)
	# Le Fléau ne transcende pas.
	var st2 := TranscendenceTests.new_game("complete", "ossarane", {"crises": "une", "crisis_nemesis": true})
	var o2 := TranscendenceTests.eid_of(st2, "ossarane")
	st2.get_empire(o2).techs["oree"] = true
	if CrisisNemesis.enabled(st2):
		(st2.crisis["nem"] as Dictionary)["who"] = o2
		(st2.crisis["nem"] as Dictionary)["tier"] = CrisisNemesis.tiers().size()
		_ok(CrisisNemesis.is_scourge(st2, o2) and Transcendence.path_why(st2, o2, "depart") != "", "Le Fléau des étoiles ne franchit pas l'Orée")
