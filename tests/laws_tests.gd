extends RefCounted
## Tests des lois (Laws, lot 2 de la politique) : données, emplacements, loi de pouvoir, adoption et
## abrogation, niveaux des courants, lois qui tombent avec leur courant, lois indépendantes et ruche,
## entretien et abrogation faute d'influence, actions électorales, héros chefs de courant, effets
## branchés (lassitude de guerre, chantiers, Triomphes), IA, sauvegarde 31. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Lois…")
	_test_data()
	_test_slots_power()
	_test_adopt()
	_test_independent()
	_test_election_xp()
	_test_upkeep()
	_test_actions()
	_test_heroes()
	_test_effects()
	_test_ai()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 7, faction := "vael") -> GameState:
	return GameState.create(seed_value, 150, 1800.0, faction, {"ai_level": "", "politics": "active"})


func _emp(st: GameState, faction_id: String) -> int:
	for e in st.empires:
		if e.faction_id == faction_id:
			return e.id
	return -1


## Met un courant seul au pouvoir, au niveau voulu.
func _rule(st: GameState, eid: int, current: String, lvl := 1) -> int:
	var i := Politics.index_of(current)
	var en := Laws._w(st, eid)
	en["ruling"] = [i]
	en["xp"][i] = lvl
	st.relic_rev += 1
	return i


func _submit(st: GameState, cmd: Dictionary) -> bool:
	var sim := Simulation.new(st)
	var ok := sim.submit(cmd)
	sim.flush_commands()
	return ok


func _test_data() -> void:
	var ids := {}
	var n := 0
	for i in Politics.N:
		var pw := Laws.power_law(i)
		ids[String(pw["id"])] = true
		n += 1
		var lv := []
		for l: Dictionary in Laws.current_laws(i):
			ids[String(l["id"])] = true
			lv.append(int(l["level"]))
			n += 1
		_ok(lv == [1, 2, 3, 4], "lois : 4 lois de niveau 1 à 4 pour %s" % Politics.current_id(i))
	_ok(n == 30, "lois : 30 lois de courant (6 de pouvoir + 24)")
	_ok(Laws.independent().size() == 8, "lois : 8 lois indépendantes")
	for l: Dictionary in Laws.independent():
		ids[String(l["id"])] = true
	_ok(ids.size() == 38, "lois : identifiants uniques")
	_ok(int(Laws.law_def("cadences")["current"]) == Politics.index_of("forge") and not bool(Laws.law_def("cadences")["power"]), "lois : courant d'une loi")
	_ok(bool(Laws.law_def("mobilisation")["power"]) and int(Laws.law_def("pain_jeux")["current"]) == -1, "lois : loi de pouvoir, loi indépendante")


func _test_slots_power() -> void:
	var st := _new()
	_ok(Laws.slots(st, 0) == 4, "lois : 4 emplacements en République à l'ère I (obtenu %d)" % Laws.slots(st, 0))
	var kh := _emp(st, "khthari")
	_ok(kh >= 0 and Laws.applies(st, kh) and Laws.slots(st, kh) == 2, "lois : la ruche a 2 Instincts")
	var lead := Politics.lead(st, 0)
	_ok(Laws.power_active(st, 0) == String(Laws.power_law(lead)["id"]), "lois : la loi de pouvoir suit le courant en tête")
	_ok(Laws.level(st, 0, lead) == 1, "lois : les courants au pouvoir au départ sont au niveau 1")
	_rule(st, 0, "academie")
	_ok(Research.production_bonus(st, 0, "knowledge") >= 20, "lois : Recherche ouverte (+20 % de Savoir) entre dans les effets")
	_ok(Laws.power_active(st, kh) == "", "lois : pas de loi de pouvoir pour la ruche")


func _test_adopt() -> void:
	var st := _new()
	var e := st.get_empire(0)
	_rule(st, 0, "forge", 1)
	e.resources["influence"] = 100
	_ok(Laws.check_adopt(st, 0, "normes_serie") != "", "lois : niveau 2 refusé à un courant de niveau 1")
	_ok(Laws.check_adopt(st, 0, "bourses") != "", "lois : loi d'un courant hors du pouvoir refusée")
	_ok(Laws.check_adopt(st, 0, "plein_emploi") != "", "lois : une loi de pouvoir ne s'adopte pas")
	_ok(_submit(st, SimCommands.law_adopt(0, "cadences")), "lois : adopter « Cadences »")
	_ok(Laws.is_enacted(st, 0, "cadences") and int(e.resources["influence"]) == 80, "lois : en vigueur, 20 d'influence payés")
	_ok(Research.fx_int(st, 0, "building_days_pct") == -25, "lois : effet branché (chantiers -25 %)")
	var stab := 0
	for p in Stability.parts(st, FactionTraits.capital_system(st, 0)):
		if String(p[0]) == "Lois en vigueur":
			stab = int(p[1])
	_ok(stab == -10, "lois : ligne « Lois en vigueur » dans l'Ordre intérieur (obtenu %d)" % stab)
	_ok(Laws.check_adopt(st, 0, "cadences") != "", "lois : pas deux fois la même")
	_ok(_submit(st, SimCommands.law_revoke(0, "cadences")) and not Laws.is_enacted(st, 0, "cadences"), "lois : abroger")
	_ok(Research.fx_int(st, 0, "building_days_pct") == 0, "lois : effet retiré à l'abrogation")
	# Emplacements pleins.
	_rule(st, 0, "forge", 4)
	e.resources["influence"] = 1000
	for id in ["cadences", "normes_serie", "grands_chantiers", "concessions"]:
		_submit(st, SimCommands.law_adopt(0, id))
	_ok(Laws.used(st, 0) == 4, "lois : quatre lois adoptées")
	_ok(Laws.check_adopt(st, 0, "pain_jeux").begins_with("plus d'emplacement"), "lois : emplacements pleins")


func _test_independent() -> void:
	var st := _new()
	var cap := FactionTraits.capital_system(st, 0)
	var before := Research.production_bonus(st, 0, "energy")
	_ok(_submit(st, SimCommands.law_adopt(0, "pain_jeux")), "lois : loi indépendante gratuite")
	_ok(Research.production_bonus(st, 0, "energy") == before - 10, "lois : Pain et jeux, production -10 %")
	var found := false
	for p in Stability.parts(st, cap):
		if String(p[0]) == "Lois en vigueur" and int(p[1]) == 15:
			found = true
	_ok(found, "lois : Pain et jeux, stabilité +15")
	var kh := _emp(st, "khthari")
	st.get_empire(kh).resources["influence"] = 500
	_ok(Laws.check_adopt(st, kh, "bourses") != "", "lois : la ruche n'adopte pas de loi de courant")
	_ok(Laws.check_adopt(st, kh, "levee_masse") == "", "lois : la ruche adopte ses Instincts")
	Laws.adopt(st, 0, "examens_forces")
	var pen := 0
	for p in Stability.parts(st, cap):
		if String(p[0]).begins_with("Examens forcés"):
			pen = int(p[1])
	@warning_ignore("integer_division")
	_ok(pen == -(Stability.system_pop(st, cap, 0) / 5), "lois : Examens forcés, -1 stabilité par 5 habitants")


func _test_election_xp() -> void:
	var st := _new()
	var e := st.get_empire(0)
	e.resources["influence"] = 500
	var fo := _rule(st, 0, "forge", 1)
	Laws.adopt(st, 0, "cadences")
	Laws.adopt(st, 0, "pain_jeux")
	# Tout le peuple vote Académie : la Forge perd le pouvoir.
	var ac := Politics.index_of("academie")
	for sid in Stability.systems_of(st, 0):
		var se := Politics._sys_w(st, sid, 0)
		var op := [0, 0, 0, 0, 0, 0]
		op[ac] = 1000
		se["op"] = op
	var ac0 := Laws.level(st, 0, ac)
	st.tick = 1080
	var out := Politics.run_election(st, 0)
	_ok(Politics.in_power(st, 0, ac) and not Politics.in_power(st, 0, fo), "lois : élection perdue par la Forge")
	_ok(not Laws.is_enacted(st, 0, "cadences") and Laws.is_enacted(st, 0, "pain_jeux"), "lois : les lois du courant battu tombent, pas les indépendantes")
	_ok(not out.is_empty() and String(out[0]["text"]).find("Cadences") >= 0, "lois : la chronique cite les lois abrogées")
	_ok(Laws.level(st, 0, ac) == ac0 + 1 and Laws.level(st, 0, fo) == 1, "lois : niveau gagné au pouvoir, gardé dans l'opposition")
	st.tick = 2160
	Politics.run_election(st, 0)
	_ok(Laws.level(st, 0, ac) == ac0 + 2, "lois : un niveau par mandat")
	Laws._w(st, 0)["xp"][ac] = 4
	st.tick = 3240
	Politics.run_election(st, 0)
	_ok(Laws.level(st, 0, ac) == 4, "lois : niveau 4 au plus")


func _test_upkeep() -> void:
	var st := _new()
	var e := st.get_empire(0)
	_rule(st, 0, "forge", 4)
	var base := int(Economy.empire_income(st, 0)["upkeep"]["influence"])
	e.resources["influence"] = 1000
	Laws.adopt(st, 0, "normes_serie")
	var pop := Laws.empire_pop(st, 0)
	@warning_ignore("integer_division")
	var expect := 2 * (1 + pop / 10)
	_ok(Laws.upkeep(st, 0) == expect, "lois : entretien = niveau × (1 + population / 10) (obtenu %d, attendu %d)" % [Laws.upkeep(st, 0), expect])
	_ok(int(Economy.empire_income(st, 0)["upkeep"]["influence"]) == base + expect, "lois : entretien compté au bilan d'influence")
	Laws.adopt(st, 0, "concessions")
	Laws.adopt(st, 0, "grands_chantiers")
	Laws.adopt(st, 0, "cadences")
	# Entretien énorme, caisses vides : la loi la plus chère est abrogée.
	Politics.data()["law_rules"]["upkeep_pop_div"] = 1
	e.resources["influence"] = 0
	var added: Array[Dictionary] = []
	Laws.monthly(st, 0, added)
	Politics.data()["law_rules"]["upkeep_pop_div"] = 10
	_ok(not Laws.is_enacted(st, 0, "concessions") and Laws.used(st, 0) == 3, "lois : caisses vides, la loi de plus haut niveau est abrogée")
	_ok(not added.is_empty(), "lois : la chronique le dit")


func _test_actions() -> void:
	var st := _new()
	var e := st.get_empire(0)
	_ok(Laws.actions_for(st, 0) == ["campagne"], "actions : la République fait campagne")
	e.resources["influence"] = 100
	_ok(Laws.check_action(st, 0, "campagne") != "", "actions : il faut d'abord soutenir un courant")
	var ac := Politics.index_of("academie")
	_submit(st, SimCommands.politics_support(0, ac))
	_ok(_submit(st, SimCommands.politics_action(0, "campagne")), "actions : campagne lancée")
	_ok(int(e.resources["influence"]) == 60 and Laws.action(st, 0) == "campagne", "actions : 40 d'influence payés")
	_ok(int(Laws.vote_weights(st, 0)[ac]) >= 150, "actions : poids en plus au courant soutenu")
	_ok(Laws.check_action(st, 0, "campagne") != "", "actions : une seule par vote")
	_ok(Laws.check_action(st, 0, "rachat") != "", "actions : pas de rachat de voix en République")
	st.tick = 1080
	Politics.run_election(st, 0)
	_ok(Laws.action(st, 0) == "", "actions : remise à zéro après le vote")
	# Diète (féodalité) : intimidation.
	var os := _emp(st, "ossarane")
	_ok(os >= 0 and Laws.actions_for(st, os).has("intimidation"), "actions : la Diète peut intimider")
	var oe := st.get_empire(os)
	oe.resources["influence"] = 100
	var away := (Politics.principal(st, os) + 3) % Politics.N
	Politics.support(st, os, away)
	Laws.do_action(st, os, "intimidation")
	var hit := false
	for p in Stability.parts(st, FactionTraits.capital_system(st, os)):
		if String(p[0]) == "Intimidation électorale":
			hit = true
	_ok(hit, "actions : l'intimidation coûte de la stabilité là où le courant soutenu n'est pas en tête")
	_ok(Laws.actions_for(st, _emp(st, "choeur")).is_empty(), "actions : pas d'action au Conclave (choix direct)")


func _test_heroes() -> void:
	var st := _new()
	var orateur := {"cls": "orateur", "amb": "gloire", "owner": 0}
	var soldat := {"cls": "stratege", "amb": "gloire", "owner": 0}
	var avatar := {"cls": "stratege", "amb": "", "owner": 0}
	_ok(Laws.hero_current(st, orateur) == Politics.index_of("concorde"), "héros : les Orateurs penchent Concorde")
	_ok(Laws.hero_current(st, soldat) == Politics.index_of("glaive"), "héros : l'ambition de gloire penche Glaive")
	_ok(Laws.hero_current(st, avatar) == -1, "héros : un Avatar n'a pas de courant")
	_rule(st, 0, "glaive")
	_ok(Laws.hero_backing(st, soldat) == 1 and Laws.council_pct(st, soldat) == 50, "héros : bonus de Conseil +50 % quand son courant gouverne")
	_ok(Laws.hero_backing(st, orateur) == -1 and Laws.council_pct(st, orateur) == 0, "héros : dans l'opposition, pas de bonus")


func _test_effects() -> void:
	var st := _new()
	_rule(st, 0, "glaive")
	_ok(Laws.no_war_weariness(st, 0), "effets : Mobilisation, pas de lassitude de guerre")
	_rule(st, 0, "autel")
	_ok(Research.fx_int(st, 0, "triumph_cooldown_pct") == -50, "effets : Processions, Triomphes deux fois plus fréquents")
	_rule(st, 0, "seve")
	_ok(int(Research.effects(st, 0).get("hab_bonus", {}).get("all", 0)) >= 10, "effets : Colons adaptés, habitabilité +10")
	_rule(st, 0, "concorde")
	_ok(int(Research.effects(st, 0).get("per_treaty", {}).get("energy", 0)) == 3, "effets : Dividende de la paix")
	var off := GameState.create(7, 150, 1800.0, "vael", {"ai_level": ""})
	_ok(Laws.effects(off, 0).is_empty() and Laws.upkeep(off, 0) == 0, "effets : rien sans l'option")


func _test_ai() -> void:
	var st := GameState.create(11, 150, 1800.0, "vael", {"ai_level": "normale", "politics": "active"})
	var sim := Simulation.new(st)
	sim.advance(1500)
	var with_laws := 0
	var ais := 0
	for e in st.empires:
		if e.is_ai() and not e.eliminated and Laws.applies(st, e.id):
			ais += 1
			if Laws.used(st, e.id) > 0:
				with_laws += 1
	_ok(ais > 0 and with_laws * 2 >= ais, "IA : adopte des lois (%d empires sur %d)" % [with_laws, ais])


func _test_save() -> void:
	var st := _new()
	st.get_empire(0).resources["influence"] = 200
	_rule(st, 0, "forge", 2)
	Laws.adopt(st, 0, "normes_serie")
	Laws.adopt(st, 0, "couvre_feu")
	Politics.support(st, 0, Politics.index_of("forge"))
	Laws.do_action(st, 0, "campagne")
	var d := st.to_dict()
	_ok(int(d["version"]) >= 31, "lois : sauvegarde 31 ou plus")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and Laws.enacted(back, 0) == ["normes_serie", "couvre_feu"], "lois : lois rechargées")
	_ok(back != null and Laws.level(back, 0, Politics.index_of("forge")) == 2 and Laws.action(back, 0) == "campagne", "lois : niveaux et action rechargés")
	_ok(back != null and back.checksum() == st.checksum(), "lois : même empreinte après rechargement")
	_ok(back != null and Research.fx_int(back, 0, "ship_cost_pct") == Research.fx_int(st, 0, "ship_cost_pct"), "lois : mêmes effets après rechargement")
