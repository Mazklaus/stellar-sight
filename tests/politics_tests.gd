extends RefCounted
## Tests de la politique intérieure (Politics, PoliticsSystem, AiPolitics) : penchant des peuples,
## opinion en pour mille, actes, élections et redistribution des voix, régimes par gouvernement
## (Conclave, Kurultaï, consensus des nœuds, ruche sans courants), représentation et stabilité,
## soutien officiel, IA, option de partie, sauvegarde 28 et déterminisme. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Politique…")
	_test_option()
	_test_nature()
	_test_push()
	_test_acts()
	_test_election()
	_test_appoint()
	_test_consensus()
	_test_representation()
	_test_support_command()
	_test_ai()
	_test_save()
	_test_determinism()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 7, faction := "vael", on := true) -> GameState:
	var opts := {"ai_level": ""}
	if on:
		opts["politics"] = "active"
	return GameState.create(seed_value, 150, 1800.0, faction, opts)


func _emp(st: GameState, faction_id: String) -> int:
	for e in st.empires:
		if e.faction_id == faction_id:
			return e.id
	return -1


func _sum(a: Array) -> int:
	var s := 0
	for x in a:
		s += int(x)
	return s


## Fonde une colonie établie dans un système libre proche de la capitale. Renvoie le système.
func _plant(st: GameState, empire_id: int, pop := 4) -> int:
	var jumps := FactionTraits.jumps_from(st.galaxy, FactionTraits.capital_system(st, empire_id))
	var best := -1
	var bj := 999
	for s in st.galaxy.systems:
		var j := int(jumps.get(s.id, 999))
		if j < 1 or j >= bj or st.system_owner(s.id) >= 0 or s.planet_ids.is_empty():
			continue
		best = s.id
		bj = j
	if best < 0:
		return -1
	var c := Colony.new()
	c.planet_id = st.galaxy.systems[best].planet_ids[0]
	c.owner = empire_id
	c.kind = Colony.KIND_COLONY
	c.population = pop
	st.add_colony(c)
	return best


func _test_option() -> void:
	var off := _new(7, "vael", false)
	_ok(not off.politics_on and not Politics.applies(off, 0), "politique : coupée sans l'option (tests, bancs)")
	var st := _new()
	_ok(st.politics_on and Politics.applies(st, 0), "politique : active avec l'option")
	var kh := _emp(st, "khthari")
	_ok(kh >= 0 and not Politics.applies(st, kh), "politique : l'esprit de ruche n'a pas de courants")
	_ok(Politics.emp(st, 0).has("ruling") and Politics.next_election(st, 0) == 1080, "politique : première élection au jour 1080")


func _test_nature() -> void:
	var st := _new()
	var vael := Politics.nature(st, 0)
	_ok(_sum(vael) == 1000, "penchant : 1000 pour mille")
	_ok(Politics.principal(st, 0) == Politics.index_of("academie"), "penchant : Vael (raison) penche Académie")
	_ok(int(vael[Politics.index_of("concorde")]) == 300, "penchant : Vael (république) a la Concorde en second")
	var oss := _emp(st, "ossarane")
	var on := Politics.nature(st, oss)
	_ok(Politics.principal(st, oss) == Politics.index_of("glaive") and int(on[Politics.index_of("forge")]) == 300,
			"penchant : Ossarane (honneur, féodalité) Glaive, et le voisin de roue en second")
	_ok(Politics.wheel_dist(Politics.index_of("glaive"), Politics.index_of("concorde")) == 3 and Politics.opposite(Politics.index_of("forge")) == Politics.index_of("seve"),
			"roue : Glaive face à Concorde, Forge face à Sève")
	var ch := _emp(st, "choeur")
	_ok(Politics.label(st, ch, Politics.index_of("autel")) == "l'Ecclésiarchat" and Politics.short(st, ch, Politics.index_of("autel")) == "Ecclésiarchat",
			"courants : le registre Grimdark renomme l'Autel")
	_ok(Politics.regime_id(st, oss) == "feodalite" and Politics.seats(st, 0) == 3 and Politics.seats(st, ch) == 1, "régimes : Diète, République à 3 courants, Conclave à 1")


func _test_push() -> void:
	var st := _new()
	var home := FactionTraits.capital_system(st, 0)
	var gl := Politics.index_of("glaive")
	var before := int(Politics.opinion(st, home)[gl])
	Politics.push(st, home, gl, 100)
	var op := Politics.opinion(st, home)
	_ok(_sum(op) == 1000 and int(op[gl]) > before + 80, "opinion : une poussée fait monter le courant, la somme reste 1000")
	var off := _new(7, "vael", false)
	Politics.push(off, home, gl, 100)
	_ok(off.politics["sys"].is_empty(), "opinion : rien n'est écrit sans l'option")
	# Retour vers le penchant.
	for _m in 12:
		Politics.monthly(st, 0, [])
	_ok(int(Politics.opinion(st, home)[gl]) < int(op[gl]), "opinion : elle revient vers le penchant du peuple chaque mois")


func _test_acts() -> void:
	var st := _new()
	var home := FactionTraits.capital_system(st, 0)
	var ac := Politics.index_of("academie")
	var a0 := int(Politics.opinion(st, home)[ac])
	Heroes.act(st, 0, "tech")
	_ok(int(Politics.opinion(st, home)[ac]) > a0, "actes : une technologie pousse l'Académie")
	var gl := Politics.index_of("glaive")
	var g0 := int(Politics.opinion(st, home)[gl])
	Research.count_stat(st, 0, "wars")
	_ok(int(Politics.opinion(st, home)[gl]) >= g0 + 20, "actes : une guerre pousse le Glaive")
	var sv := Politics.index_of("seve")
	var s0 := int(Politics.opinion(st, home)[sv])
	Politics.on_colony(st, home)
	_ok(int(Politics.opinion(st, home)[sv]) > s0 + 50, "actes : une colonie pousse la Sève dans son système")
	var au := Politics.index_of("autel")
	var u0 := int(Politics.opinion(st, home)[au])
	Politics.on_building(st, home, "cathedrale")
	_ok(int(Politics.opinion(st, home)[au]) > u0, "actes : une cathédrale pousse l'Autel")


func _test_election() -> void:
	var st := _new()
	_plant(st, 0, 5)
	_plant(st, 0, 3)
	var syss := Stability.systems_of(st, 0)
	var out := Politics.run_election(st, 0)
	var en := Politics.emp(st, 0)
	_ok(out.size() == 1 and (en["ruling"] as Array).size() == 3, "élection : la République met 3 courants au pouvoir")
	var reps := 0
	for sid in syss:
		reps += _sum(Politics.sys_entry(st, sid).get("reps", []))
	var pop := 0
	for sid in syss:
		pop += Stability.system_pop(st, sid, 0)
	_ok(reps == pop and _sum(en["votes"]) == pop, "élection : un représentant par habitant en République")
	_ok(_sum(en["final"]) <= _sum(en["votes"]) and _sum(en["final"]) >= _sum(en["votes"]) - 3, "élection : les voix des battus vont aux vainqueurs")
	_ok(int(en["next"]) == st.tick + 1080 and int(en["n"]) == 1, "élection : la suivante dans 1080 jours")
	# Redistribution : jamais vers l'opposé.
	var fake := _new()
	fake.politics["sys"].clear()
	var home := FactionTraits.capital_system(fake, 0)
	var se := Politics._sys_w(fake, home, 0)
	se["op"] = [0, 0, 0, 0, 0, 1000]
	Politics.run_election(fake, 0)
	var f2 := Politics.emp(fake, 0)
	_ok(Politics.ruling(fake, 0)[0] == Politics.index_of("glaive"), "élection : le courant plébiscité gouverne")
	_ok(Politics.sys_entry(fake, home)["rep"] == Politics.index_of("glaive"), "élection : le système est représenté par son courant majoritaire")
	var gl := Politics.index_of("glaive")
	var cc := Politics.index_of("concorde")
	_ok(int(f2["final"][cc]) == int(f2["votes"][cc]), "élection : le courant opposé ne reçoit aucune voix du Glaive")
	# Même élection, mêmes représentants.
	var b := _new()
	_plant(b, 0, 5)
	_plant(b, 0, 3)
	Politics.run_election(b, 0)
	_ok(str(Politics.emp(b, 0)["votes"]) == str(en["votes"]), "élection : tirage déterministe (hachage de la graine)")
	_ok(gl >= 0, "élection : courants valides")


func _test_appoint() -> void:
	var st := _new()
	var ch := _emp(st, "choeur")
	var e := st.get_empire(ch)
	e.fervor = 60
	var home := FactionTraits.capital_system(st, ch)
	Politics._sys_w(st, home, ch)["op"] = [0, 0, 0, 0, 1000, 0]
	var fo := Politics.index_of("forge")
	Politics.support(st, ch, fo)
	Politics.run_election(st, ch)
	_ok(Politics.ruling(st, ch) == [fo], "Conclave : le courant nommé gouverne, même contre le vote")
	_ok(e.fervor == 45 and int(Politics.emp(st, ch)["fervor"]) == 15, "Conclave : contredire le peuple coûte 15 de ferveur")
	Politics.support(st, ch, -1)
	Politics.run_election(st, ch)
	_ok(Politics.ruling(st, ch) == [Politics.index_of("autel")] and e.fervor == 45, "Conclave : sans choix, le vote du peuple, sans frais")
	var fr := _emp(st, "ferrocornes")
	var city := FactionTraits.city_fleet(st, fr)
	var fhome := FactionTraits.capital_system(st, fr)
	Politics._sys_w(st, fhome, fr)["op"] = [1000, 0, 0, 0, 0, 0]
	Politics.support(st, fr, Politics.index_of("glaive"))
	Politics.run_election(st, fr)
	_ok(Politics.ruling(st, fr) == [Politics.index_of("glaive")], "Kurultaï : le clan choisi gouverne")
	var part := Politics.stability_part(st, fhome, fr)
	if city != null and city.system_id == fhome and not city.is_moving():
		_ok(not part.is_empty() and int(part[1]) == 0, "Kurultaï : la flotte-ville fait taire les clans écartés")
	else:
		_ok(not part.is_empty() and int(part[1]) == -8, "Kurultaï : les clans écartés grognent plus fort")


func _test_consensus() -> void:
	var st := _new()
	var ty := _emp(st, "teyl")
	_ok(Politics.mode(st, ty) == "continuous", "Consensus : la conscience distribuée ne vote pas")
	var home := FactionTraits.capital_system(st, ty)
	Politics._sys_w(st, home, ty)["op"] = [0, 0, 0, 600, 400, 0]
	Politics.monthly(st, ty, [])
	var r := Politics.ruling(st, ty)
	_ok(r.size() == 2 and r.has(Politics.index_of("seve")) and r.has(Politics.index_of("autel")), "Consensus : les deux courants dominants des nœuds gouvernent")
	_ok(Politics.check_support(st, ty, 0) != "", "Consensus : pas de soutien officiel")


func _test_representation() -> void:
	var st := _new()
	var home := FactionTraits.capital_system(st, 0)
	_ok(Politics.stability_part(st, home, 0).is_empty(), "représentation : rien avant la première élection")
	Politics._sys_w(st, home, 0)["op"] = [0, 1000, 0, 0, 0, 0]
	Politics.run_election(st, 0)
	var p := Politics.stability_part(st, home, 0)
	_ok(not p.is_empty() and int(p[1]) == 5, "représentation : +5 stabilité au pouvoir")
	var found := false
	for x in Stability.parts(st, home):
		if String(x[0]).begins_with("Représenté au pouvoir"):
			found = true
	_ok(found, "représentation : la source apparaît dans l'Ordre intérieur")
	st.politics["emp"][0]["ruling"] = [Politics.index_of("glaive")]
	p = Politics.stability_part(st, home, 0)
	_ok(not p.is_empty() and int(p[1]) == -5, "représentation : -5 dans l'opposition")


func _test_support_command() -> void:
	var st := _new()
	var sim := Simulation.new(st)
	_ok(sim.submit(SimCommands.politics_support(0, Politics.index_of("seve"))), "soutien officiel : ordre accepté")
	sim.flush_commands()
	_ok(Politics.pick(st, 0) == Politics.index_of("seve"), "soutien officiel : le courant est noté")
	_ok(not sim.submit(SimCommands.politics_support(0, 9)), "soutien officiel : courant inconnu refusé")
	var off := _new(7, "vael", false)
	_ok(SimCommands.validate(off, SimCommands.politics_support(0, 0)) != "", "soutien officiel : refusé sans politique")


func _test_ai() -> void:
	var st := GameState.create(11, 150, 1800.0, "vael", {"ai_level": "normale", "politics": "active"})
	var sim := Simulation.new(st)
	sim.advance(1085)
	var elected := 0
	var picks := 0
	for e in st.empires:
		if Politics.applies(st, e.id) and Politics.mode(st, e.id) != "continuous":
			if int(Politics.emp(st, e.id).get("n", 0)) >= 1:
				elected += 1
			if int(Politics.emp(st, e.id).get("pick", -1)) >= 0 or int(Politics.emp(st, e.id).get("n", 0)) >= 1:
				picks += 1
	_ok(elected >= 3, "IA : les empires ont tenu leur première élection (%d)" % elected)
	var has_part := false
	for e in st.empires:
		for sid in Stability.systems_of(st, e.id):
			if not Politics.stability_part(st, sid, e.id).is_empty():
				has_part = true
	_ok(has_part, "IA : la représentation pèse sur la stabilité après l'élection")


func _test_save() -> void:
	var st := _new()
	_plant(st, 0, 4)
	Politics.run_election(st, 0)
	Politics.support(st, 0, 2)
	var d := st.to_dict()
	_ok(int(d["version"]) == 29, "sauvegarde : format 29")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and back.politics_on and JSON.stringify(Politics.to_dict(back), "", true) == JSON.stringify(Politics.to_dict(st), "", true), "sauvegarde : la politique survit au rechargement")
	_ok(back != null and back.checksum() == st.checksum(), "sauvegarde : même empreinte après rechargement")
	var old := d.duplicate(true)
	old["version"] = 27
	old.erase("politics")
	var b27 := GameState.from_dict(JSON.parse_string(JSON.stringify(old)))
	_ok(b27 != null and not b27.politics_on, "sauvegarde : une partie 27 se charge sans politique")


func _test_determinism() -> void:
	var a := GameState.create(5, 150, 1800.0, "vael", {"ai_level": "normale", "politics": "active"})
	var b := GameState.create(5, 150, 1800.0, "vael", {"ai_level": "normale", "politics": "active"})
	var sa := Simulation.new(a)
	var sb := Simulation.new(b)
	sa.advance(1100)
	var mid := GameState.from_dict(JSON.parse_string(JSON.stringify(b.to_dict())))
	sb = Simulation.new(mid)
	sb.advance(1100)
	_ok(a.checksum() == mid.checksum(), "déterminisme : même partie avec la politique, même reprise depuis une sauvegarde")
