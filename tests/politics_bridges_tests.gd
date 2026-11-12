extends RefCounted
## Tests des ponts de la politique (lot 3) : doléances tenues et ignorées, crise de régime et
## interrègne, opérations d'espionnage (élection truquée, opposition financée, coup d'État),
## proximité idéologique, mondes conquis, talents de peuple (Échos, réputation, vote d'urgence,
## héritier déloyal), sauvegarde. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Ponts de la politique…")
	_test_grievances()
	_test_crisis()
	_test_espionage()
	_test_diplomacy()
	_test_conquest()
	_test_talents()
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


func _rule(st: GameState, eid: int, current: String) -> int:
	var i := Politics.index_of(current)
	var en := Laws._w(st, eid)
	en["ruling"] = [i]
	st.relic_rev += 1
	return i


## Opinion de tous les systèmes : pmille pour le courant donné, le reste au courant en tête.
func _lean(st: GameState, eid: int, current: String, pmille: int) -> void:
	var c := Politics.index_of(current)
	var l := Politics.lead(st, eid)
	for sid in Stability.systems_of(st, eid):
		var op := [0, 0, 0, 0, 0, 0]
		op[c] = pmille
		op[l] += 1000 - pmille
		Politics._sys_w(st, sid, eid)["op"] = op


func _part(st: GameState, sid: int, prefix: String) -> int:
	for p in Stability.parts(st, sid):
		if String(p[0]).begins_with(prefix):
			return int(p[1])
	return 0


func _test_grievances() -> void:
	var st := _new()
	_rule(st, 0, "forge")
	var cap := FactionTraits.capital_system(st, 0)
	_lean(st, 0, "academie", 600)
	var ac := Politics.index_of("academie")
	_ok(Grievances.opposition(st, 0) == ac, "doléances : le plus grand courant d'opposition")
	st.tick = 390
	var added: Array[Dictionary] = []
	Grievances.monthly(st, 0, Politics.emp(st, 0), added)
	var g: Dictionary = Politics.emp(st, 0).get("grv", {})
	_ok(not g.is_empty() and int(g["c"]) == ac and int(g["need"]) == 2, "doléances : l'Académie demande 2 technologies")
	_ok(not added.is_empty() and String(added[0]["text"]).find("doléance") >= 0, "doléances : la chronique l'annonce")
	Politics.on_act(st, 0, "tech")
	Politics.on_act(st, 0, "battles_won")
	_ok(int(Politics.emp(st, 0)["grv"]["got"]) == 1, "doléances : seuls les actes du courant comptent")
	Politics.on_act(st, 0, "tech")
	st.tick = 420
	Grievances.monthly(st, 0, Politics.emp(st, 0), added)
	_ok(not Politics.emp(st, 0).has("grv"), "doléances : satisfaite, elle se referme")
	_ok(_part(st, cap, "Doléance de") == 5, "doléances : +5 stabilité là où l'on penche pour lui")
	# La suivante, ignorée.
	st.tick = 420 + 180
	Grievances.monthly(st, 0, Politics.emp(st, 0), added)
	_ok(Politics.emp(st, 0).has("grv"), "doléances : une nouvelle après le délai")
	st.tick = int(Politics.emp(st, 0)["grv"]["end"])
	Grievances.monthly(st, 0, Politics.emp(st, 0), added)
	var neg := false
	for f in Politics.emp(st, 0)["gfx"]:
		if int(f["v"]) < 0:
			neg = true
	_ok(neg, "doléances : ignorée, ses systèmes perdent de la stabilité")
	# Sous 20 % : pas de doléance.
	var st2 := _new()
	_rule(st2, 0, "forge")
	_lean(st2, 0, "academie", 100)
	_ok(Grievances.opposition(st2, 0) == -1, "doléances : une opposition trop faible se tait")


func _test_crisis() -> void:
	var st := _new()
	var fo := _rule(st, 0, "forge")
	Laws._w(st, 0)["xp"][fo] = 2
	st.get_empire(0).resources["influence"] = 500
	Laws.adopt(st, 0, "cadences")
	Laws.adopt(st, 0, "pain_jeux")
	for sid in Stability.systems_of(st, 0):
		Stability._entry_w(st, sid)["v"] = 10
	var en := Politics.emp(st, 0)
	en["low"] = 11
	var added: Array[Dictionary] = []
	Grievances._crisis_check(st, 0, en, added)
	_ok(Politics.ruling(st, 0) == [Politics.opposite(fo)], "crise : le courant opposé prend seul le pouvoir")
	_ok(Laws.used(st, 0) == 0, "crise : toutes les lois sont révoquées")
	_ok(Grievances.interregnum(st, 0) and Laws.power_active(st, 0) == "", "crise : interrègne, pas de loi de pouvoir")
	_ok(Laws.check_adopt(st, 0, "pain_jeux").begins_with("interrègne"), "crise : aucune loi pendant l'interrègne")
	_ok(not added.is_empty() and String(added[0]["text"]).begins_with("Crise de régime"), "crise : la chronique la raconte")
	st.tick += 200
	_ok(not Grievances.interregnum(st, 0) and Laws.check_adopt(st, 0, "pain_jeux") == "", "crise : l'interrègne finit")
	var kh := _emp(st, "khthari")
	_ok(Grievances.crisis(st, kh, "test").is_empty(), "crise : la ruche y échappe")


func _test_espionage() -> void:
	var st := _new()
	var os := _emp(st, "ossarane")
	var te := _emp(st, "teyl")
	var vael_lead := Politics.lead(st, 0)
	Espionage._apply(st, 0, os, Espionage.op_def("truquer"))
	_ok(int(Politics.emp(st, os).get("rig", {}).get("c", -1)) == vael_lead, "espionnage : élection truquée pour notre courant en tête")
	_ok(int(Laws.vote_weights(st, os)[vael_lead]) >= 200, "espionnage : poids en plus au vote de la cible")
	_ok(Espionage.check_op(st, 0, te, "truquer") != "", "espionnage : pas de vote à truquer au Consensus")
	st.tick = int(Politics.emp(st, os)["next"])
	Politics.run_election(st, os)
	_ok(Politics.emp(st, os).get("rig", {}).is_empty(), "espionnage : la fraude ne vaut que pour un vote")
	var txt := Espionage._apply(st, 0, os, Espionage.op_def("financer_opposition"))
	var g: Dictionary = Politics.emp(st, os).get("grv2", {})
	_ok(not g.is_empty() and bool(g["f"]), "espionnage : opposition financée, doléance de plus (%s)" % txt)
	var base_need := int(Grievances.cfg()["by_current"][Politics.current_id(int(g["c"]))]["need"]) if not g.is_empty() else 0
	_ok(not g.is_empty() and int(g["need"]) == base_need * 2, "espionnage : doléance financée deux fois plus exigeante")
	var before := Politics.ruling(st, os)
	Espionage._apply(st, 0, os, Espionage.op_def("coup"))
	_ok(Politics.ruling(st, os) == before, "espionnage : un régime stable résiste au coup d'État")
	for sid in Stability.systems_of(st, os):
		Stability._entry_w(st, sid)["v"] = 20
	Espionage._apply(st, 0, os, Espionage.op_def("coup"))
	_ok(Grievances.interregnum(st, os), "espionnage : coup d'État réussi, crise de régime")


func _test_diplomacy() -> void:
	var st := _new()
	var os := _emp(st, "ossarane")
	_rule(st, 0, "forge")
	_rule(st, os, "forge")
	var parts := Politics.opinion_parts(st, 0, os)
	_ok(parts.size() == 1 and int(parts[0][1]) == 10, "diplomatie : même courant en tête, +10")
	_rule(st, os, "seve")
	parts = Politics.opinion_parts(st, 0, os)
	_ok(parts.size() == 1 and int(parts[0][1]) == -10, "diplomatie : courants opposés, -10")
	_rule(st, os, "glaive")
	var v := 0
	for p in Politics.opinion_parts(st, 0, os):
		v += int(p[1])
	_ok(v == -5, "diplomatie : Glaive au pouvoir chez lui, méfiance")
	var found := false
	for p in Diplomacy.opinion_parts(st, 0, os):
		if String(p["label"]).find("méfiance") >= 0:
			found = true
	_ok(found, "diplomatie : la ligne apparaît dans l'opinion")
	_rule(st, os, "concorde")
	var ev := AiDiplomacy.evaluate(st, 0, os, Diplomacy.PEACE)
	var cc := false
	for p in ev["parts"]:
		if String(p["label"]).find("Concorde") >= 0:
			cc = true
	_ok(cc, "diplomatie : la Concorde au pouvoir fait mieux passer la paix")


func _test_conquest() -> void:
	var st := _new()
	var os := _emp(st, "ossarane")
	var sid := -1
	for s in Stability.systems_of(st, 0):
		if s != FactionTraits.capital_system(st, 0):
			sid = s
	if sid < 0:
		var c0 := Colony.new()
		var jumps := FactionTraits.jumps_from(st.galaxy, FactionTraits.capital_system(st, 0))
		for s in st.galaxy.systems:
			if int(jumps.get(s.id, 99)) == 1 and st.system_owner(s.id) < 0 and not s.planet_ids.is_empty():
				c0.planet_id = s.planet_ids[0]
				sid = s.id
				break
		c0.owner = 0
		c0.kind = Colony.KIND_COLONY
		c0.population = 3
		st.add_colony(c0)
	var op := [0, 0, 700, 300, 0, 0]
	Politics._sys_w(st, sid, 0)["op"] = op.duplicate()
	for pid in st.galaxy.systems[sid].planet_ids:
		var c: Colony = st.colonies.get(pid)
		if c != null:
			c.owner = os
	st.rebuild_ownership()
	Politics.prune(st)
	var en := Politics.sys_entry(st, sid)
	_ok(int(en.get("o", -1)) == os and Politics.opinion(st, sid) == op, "conquête : le monde garde l'opinion de son ancien maître")
	_ok(int(en.get("cqe", -1)) == st.tick + int(Politics.data()["conquered_days"]), "conquête : pendant 10 ans")
	_ok(Politics.target_nature(st, sid, os) == Politics.nature(st, 0), "conquête : il revient vers le penchant de l'ancien maître")
	st.tick += 3700
	_ok(Politics.target_nature(st, sid, os) == Politics.nature(st, os), "conquête : puis vers celui du nouveau")


func _test_talents() -> void:
	var st := _new()
	# Échos (Cosmique) : la prévision est le résultat du vote.
	var mu := _emp(st, "murmurants")
	_ok(mu >= 0 and Politics.sees_forecast(st, mu) and not Politics.sees_forecast(st, 0), "talents : les Échos annoncent le vote (Cosmique)")
	var fc := Politics.forecast(st, 0)
	st.tick = int(Politics.emp(st, 0)["next"])
	Politics.run_election(st, 0)
	_ok(fc["ruling"] == Politics.ruling(st, 0) and fc["votes"] == Politics.emp(st, 0)["votes"], "talents : la prévision est exacte si rien ne change")
	# Réputation (Picaresque) : la campagne pèse plus.
	var br := _emp(st, "brisecomete")
	var be := st.get_empire(br)
	be.resources["influence"] = 200
	Politics.support(st, br, 0)
	Laws.do_action(st, br, "campagne")
	var w0 := int(Laws.vote_weights(st, br)[0])
	be.reputation = 100
	_ok(int(Laws.vote_weights(st, br)[0]) == w0 + 100, "talents : la réputation fait campagne (Picaresque)")
	# Vote d'urgence de Vael, moins cher quand la Concorde gouverne.
	var cap := FactionTraits.capital_system(st, 0)
	var pid := -1
	for p in st.galaxy.systems[cap].planet_ids:
		var c: Colony = st.colonies.get(p)
		if c != null and c.owner == 0:
			pid = p
			c.construction = "forum"
			c.construction_days = 200
	_rule(st, 0, "forge")
	var full := FactionTraits.rush_cost(st, 0, pid, FactionTraits.RUSH_BUILDING)
	_rule(st, 0, "concorde")
	var cheap := FactionTraits.rush_cost(st, 0, pid, FactionTraits.RUSH_BUILDING)
	_ok(full > 0 and cheap < full, "talents : vote d'urgence moins cher sous la Concorde (%d → %d)" % [full, cheap])
	# Héritier déloyal (féodalité) : il soutient l'opposition.
	var os := _emp(st, "ossarane")
	var oe := st.get_empire(os)
	if Diplomacy.has_heir(st, os):
		oe.heir_loyalty = 80
		var opp := Grievances.opposition(st, os, true)
		var before := int(Laws.vote_weights(st, os)[opp])
		oe.heir_loyalty = 10
		_ok(int(Laws.vote_weights(st, os)[opp]) == before + 150, "talents : l'héritier déloyal soutient l'opposition à la Diète")
	else:
		_ok(true, "talents : pas d'héritier dans cette partie")


func _test_save() -> void:
	var st := _new()
	_rule(st, 0, "forge")
	_lean(st, 0, "academie", 600)
	st.tick = 390
	var added: Array[Dictionary] = []
	Grievances.monthly(st, 0, Politics.emp(st, 0), added)
	Grievances._fx(Politics.emp(st, 0), 1, 5, 900)
	Grievances.fund(st, 0)
	Politics._emp_w(st, 0)["rig"] = {"c": 2, "n": 0}
	Grievances.crisis(st, 0, "test")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	_ok(back != null and back.checksum() == st.checksum(), "ponts : même empreinte après rechargement")
	_ok(back != null and Grievances.current(back, 0).size() == Grievances.current(st, 0).size() and Grievances.interregnum(back, 0), "ponts : doléances et interrègne rechargés")
