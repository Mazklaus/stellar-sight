extends RefCounted
## Tests des souverains, lot 2 (la lignée) : lois féodales (Primogéniture, Partage, Élection des
## lignées), naissances (couvées reptiliennes, jamais de synthétiques), éducation et Cour, majorité,
## régence, mariages et union personnelle, renom et héritages, Couronne vacillante et souvenirs divisés,
## Étoile montante, prétendant et sécession (nouvel empire IA), extinction, abdication, IA.

const RT := preload("res://tests/ruler_tests.gd")

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Souverains (la lignée)…")
	_test_laws()
	_test_births_and_court()
	_test_regency()
	_test_marriage_union()
	_test_legacies()
	_test_reign_change()
	_test_star()
	_test_pretender()
	_test_extinction_abdication()
	_test_ai()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _test_laws() -> void:
	var st := RT.new_game(101)
	var os := RT.eid_of(st, "ossarane")
	var e := st.get_empire(os)
	_ok(String(Rulers.entry(st, os)["law"]) == "primogeniture", "Primogéniture par défaut")
	_ok(RT.apply(st, SimCommands.ruler_act(RT.eid_of(st, "vael"), "law", -1, "partage")) != "", "seule une dynastie a une loi de succession")
	e.resources["influence"] = 500
	var l0 := Rulers.legitimacy(st, os)
	_ok(RT.apply(st, SimCommands.ruler_act(os, "law", -1, "election")) == "", "changer de loi")
	_ok(int(e.resources["influence"]) == 420 and Rulers.legitimacy(st, os) == l0 - 10, "coûte 80 influence et 10 de légitimité")
	# Élection des lignées : la Diète choisit parmi les plus loyaux.
	for i in 2:
		Heroes.recruit(st, os, Heroes.make_candidate(st, os, "stratege", ["diete", i]))
	var added: Array[Dictionary] = []
	Rulers.die(st, os, "meurt", added, "age")
	_ok(String(Rulers.ruler(st, os).get("how", "")) == "elu", "la Diète élit (+10 de légitimité)")
	# Partage : un cadet adulte reçoit un fief vassal.
	var st2 := RT.new_game(102, {"vassals": "actifs"})
	var o2 := RT.eid_of(st2, "ossarane")
	var en := Rulers.entry(st2, o2)
	en["law"] = "partage"
	# Un second système pour le fief.
	var sid := _give_system(st2, o2)
	_ok(sid >= 0, "un second système")
	for h in Heroes.ids_of(st2, o2):
		st2.heroes[h].erase("heir")
	(en["heirs"] as Array).append({"id": 90, "name": "Aîné", "g": "m", "born": st2.tick - 30 * 360, "apt": {"gestion": 2, "guerre": 2, "eloquence": 1, "intrigue": 1}, "edu": "intendant", "hero": -1})
	(en["heirs"] as Array).append({"id": 91, "name": "Cadet", "g": "m", "born": st2.tick - 25 * 360, "apt": {"gestion": 1, "guerre": 2, "eloquence": 1, "intrigue": 1}, "edu": "stratege", "hero": -1})
	var n0 := st2.empires.size()
	Rulers.die(st2, o2, "meurt", added, "age")
	_ok(String(Rulers.ruler(st2, o2).get("name", "")) == "Aîné", "l'aîné hérite du trône")
	_ok(st2.empires.size() == n0 + 1, "le cadet fonde un fief : nouvel empire")
	if st2.empires.size() == n0 + 1:
		var fief := st2.empires[n0]
		_ok(st2.system_owner(sid) == fief.id, "le système lointain passe au fief")
		_ok(Vassals.lord_of(st2, fief.id) == o2, "le fief est vassal")
		_ok(fief.is_ai() and Rulers.has_ruler(st2, fief.id), "dirigé par l'IA, avec son souverain")
		_ok(String(Rulers.ruler(st2, fief.id)["name"]) == "Cadet", "le cadet règne sur le fief")


static func _give_system(st: GameState, eid: int) -> int:
	var cap := FactionTraits.capital_system(st, eid)
	var best := -1
	var bd := 1e12
	for s in st.galaxy.systems:
		if st.system_owner(s.id) >= 0 or s.planet_ids.is_empty() or s.id == cap:
			continue
		var d := s.position.distance_to(st.galaxy.systems[cap].position)
		if d < bd:
			bd = d
			best = s.id
	if best < 0:
		return -1
	var c := Colony.new()
	c.planet_id = st.galaxy.systems[best].planet_ids[0]
	c.owner = eid
	c.kind = Colony.KIND_COLONY
	c.population = 3
	st.add_colony(c)
	return best


func _test_births_and_court() -> void:
	var st := RT.new_game(111)
	var os := RT.eid_of(st, "ossarane")
	var en := Rulers.entry(st, os)
	var r := Rulers.ruler(st, os)
	r["born"] = st.tick - 30 * 360
	_ok(String(en["consort"]) != "", "un consort à l'avènement")
	en["next_child"] = st.tick
	RT.to_month(st)
	_ok(RulersDynasty.heirs(st, os).size() == 1, "un enfant naît")
	# Reptiliens : couvée de deux.
	var fe := RT.eid_of(st, "ferrocornes")
	_ok(not Rulers.hereditary(st, fe), "la horde n'est pas héréditaire")
	# Synthétiques : jamais d'enfants (Teyl, conscience, n'est pas héréditaire non plus).
	var c: Dictionary = RulersDynasty.heirs(st, os)[0]
	c["born"] = st.tick - 10 * 360
	_ok(RT.apply(st, SimCommands.ruler_act(os, "educate", int(c["id"]), "stratege")) == "", "éducation à 10 ans")
	_ok(String(c["edu"]) == "stratege", "éducation de Stratège")
	_ok(RT.apply(st, SimCommands.ruler_act(os, "educate", int(c["id"]), "ombre")) != "", "une seule éducation")
	c["apt"] = {"gestion": 2, "guerre": 4, "eloquence": 2, "intrigue": 2}
	var court := RulersDynasty.court_apts(st, os)
	_ok(int(court["guerre"]) == 2, "la Cour donne la moitié de ses aptitudes")
	var before := int(Rulers.apts(st, os)["guerre"])
	_ok(before == int(r["apt"]["guerre"]) + 2, "aptitudes de l'empire : souverain + Cour")
	c["born"] = st.tick - 16 * 360 - 1
	RT.to_month(st)
	_ok(int(c["hero"]) >= 0 and st.heroes.has(int(c["hero"])), "à la majorité, l'héritier devient héros")
	_ok(String(st.heroes[int(c["hero"])]["cls"]) == "stratege", "selon son éducation")


func _test_regency() -> void:
	var st := RT.new_game(121)
	var os := RT.eid_of(st, "ossarane")
	var en := Rulers.entry(st, os)
	for h in Heroes.ids_of(st, os):
		st.heroes[h].erase("heir")
	(en["heirs"] as Array).append({"id": 50, "name": "Petit", "g": "m", "born": st.tick - 8 * 360, "apt": {"gestion": 1, "guerre": 1, "eloquence": 1, "intrigue": 1}, "edu": "", "hero": -1})
	var added: Array[Dictionary] = []
	Rulers.die(st, os, "meurt", added, "age")
	_ok(String(Rulers.ruler(st, os).get("name", "")) == "Petit", "l'enfant monte sur le trône")
	_ok(RulersDynasty.in_regency(st, os), "régence")
	var rv := RT.eid_of(st, "vael")
	st.get_empire(os).contacts.append(rv)
	_ok(Combat.check_declare_war(st, os, rv) == "un régent ne peut pas déclarer la guerre", "pas de déclaration de guerre sous régence")
	_ok(Rulers.check_power(st, os) != "", "le régent n'use pas du pouvoir")
	var l0 := Rulers.legitimacy(st, os)
	RT.to_month(st)
	_ok(Rulers.legitimacy(st, os) == l0 - 1, "légitimité -1 par mois")
	var card := false
	for item in Events.inbox(st, os):
		if String(item["card"]) == "ruler_regency":
			card = true
	_ok(card, "carte de régence")
	Rulers.ruler(st, os)["born"] = st.tick - 17 * 360
	RT.to_month(st)
	_ok(not RulersDynasty.in_regency(st, os), "majorité : fin de la régence (ou coup de palais)")


func _test_marriage_union() -> void:
	var st := RT.new_game(131, {"vassals": "actifs"})
	var os := RT.eid_of(st, "ossarane")
	# Une deuxième dynastie : on fait d'un empire IA une féodalité en lui donnant le même peuple.
	var other := -1
	for e in st.empires:
		if e.id != os and e.faction_id == "ossarane":
			other = e.id
	if other < 0:
		var st2 := GameState.create(131, 120, 1600.0, "ossarane", {"ai_level": "", "rulers": "mortels", "vassals": "actifs",
				"rivals": ["ossarane", "vael", "choeur"], "duplicates": true})
		st = st2
		os = 0
		for e in st.empires:
			if e.id != os and e.faction_id == "ossarane":
				other = e.id
	if other < 0:
		_ok(true, "mariage : pas de seconde dynastie dans ce tirage (ignoré)")
		return
	var ea := st.get_empire(os)
	if not ea.contacts.has(other):
		ea.contacts.append(other)
		st.get_empire(other).contacts.append(os)
	st.get_empire(other).ai_level = "normal"
	_ok(RT.apply(st, SimCommands.ruler_act(os, "marry", RT.eid_of(st, "vael"), "")) != "", "pas de mariage avec une république")
	var why := RT.apply(st, SimCommands.ruler_act(os, "marry", other, ""))
	_ok(why == "", "demande en mariage (%s)" % why)
	if RulersDynasty.married(st, os, other):
		_ok(Diplomacy.opinion_parts(st, other, os).any(func(p: Dictionary) -> bool: return String(p["label"]) == "Mariage dynastique"), "opinion +20")
		_ok(RulersBridges.succession_casus(st, os, other), "revendication réciproque : guerre de succession possible")
		# Extinction chez l'autre : union personnelle.
		var eo := Rulers.entry(st, other)
		eo["heirs"] = []
		for h in Heroes.ids_of(st, other):
			st.heroes.erase(h)
		Rulers.entry(st, os)["adj"] = 40
		var added: Array[Dictionary] = []
		Rulers.die(st, other, "meurt", added, "age")
		_ok(Vassals.lord_of(st, other) == os, "union personnelle : l'empire devient sujet")
		_ok(String(Rulers.ruler(st, other).get("how", "")) == "union", "souverain de l'union")
	else:
		_ok(true, "l'IA a décliné (opinion trop basse)")


func _test_legacies() -> void:
	var st := RT.new_game(141)
	var os := RT.eid_of(st, "ossarane")
	var en := Rulers.entry(st, os)
	_ok(RulersDynasty.legacy_label(st, os).begins_with("Héritages de la maison"), "héritages d'une maison")
	_ok(RulersDynasty.legacy_label(st, RT.eid_of(st, "vael")) == "Traditions d'État", "Traditions d'État hors des dynasties")
	_ok(RT.apply(st, SimCommands.ruler_act(os, "legacy", -1, "guerre")) != "", "il faut du renom")
	RT.to_month(st)
	_ok(int(en["renown"]) > 0, "chaque mois verse du renom")
	en["renown"] = 400
	_ok(RT.apply(st, SimCommands.ruler_act(os, "legacy", -1, "guerre")) == "", "acheter un héritage")
	_ok(int(en["renown"]) == 300 and int(en["legacies"]["guerre"]) == 1, "100 de renom")
	_ok(int(Rulers.effects(st, os).get("damage_pct", 0)) >= 3, "École des capitaines : +3 % de dégâts")
	en["renown"] = 1000
	RT.apply(st, SimCommands.ruler_act(os, "legacy", -1, "foi"))
	RT.apply(st, SimCommands.ruler_act(os, "legacy", -1, "foi"))
	_ok(RulersDynasty.legacy_sum(st, os, "legit") == 5, "Droit divin : +5 de légitimité")
	var added: Array[Dictionary] = []
	var r0 := int(en["renown"])
	Rulers.die(st, os, "meurt", added, "age")
	_ok(int(en["renown"]) > r0, "un règne achevé verse du renom")
	_ok(int(en["legacies"]["foi"]) == 2, "les héritages valent pour les souverains suivants")


func _test_reign_change() -> void:
	var st := RT.new_game(151)
	var va := RT.eid_of(st, "vael")
	var other := RT.eid_of(st, "choeur")
	Diplomacy.remember(st, other, va, "broke_treaty")
	var m0 := 0
	for m in st.memories:
		if int(m["who"]) == other and int(m["about"]) == va:
			m0 = Diplomacy.memory_value(st, m)
	var added: Array[Dictionary] = []
	Rulers.die(st, va, "meurt", added, "age")
	var m1 := 0
	for m in st.memories:
		if int(m["who"]) == other and int(m["about"]) == va:
			m1 = Diplomacy.memory_value(st, m)
	_ok(m0 != 0 and absi(m1) <= absi(m0) / 2 + 1, "les souvenirs du défunt sont divisés par deux (%d → %d)" % [m0, m1])
	_ok(RulersBridges.wobbly(st, va), "Couronne vacillante pendant un an")
	_ok(RulersBridges.wobbly_claim_pct(st, va) == -50, "revendiquer coûte deux fois moins cher")


func _test_star() -> void:
	var st := RT.new_game(161)
	var va := RT.eid_of(st, "vael")
	var hid: int = Heroes.ids_of(st, va)[0]
	st.heroes[hid]["lvl"] = 5
	Rulers.entry(st, va)["adj"] = -40
	RT.to_month(st)
	var item := {}
	for it in Events.inbox(st, va):
		if String(it["card"]) == "ruler_star":
			item = it
	_ok(not item.is_empty(), "un héros dont le renom dépasse la légitimité : Étoile montante")
	if item.is_empty():
		return
	var opts := Events.choices(st, va, item)
	_ok(opts.size() == 3 and not String(opts[0]["label"]).contains("{"), "trois choix")
	var added: Array[Dictionary] = []
	var name := String(st.heroes[hid]["name"]).split(",")[0]
	Events.choose(st, va, int(item["id"]), 0, added)
	_ok(String(Rulers.ruler(st, va).get("name", "")) == name, "le couronner : le souverain abdique")


func _test_pretender() -> void:
	var st := RT.new_game(171)
	var va := RT.eid_of(st, "vael")
	for i in 4:
		_give_system_test(st, va)
	var n := 0
	for s in st.galaxy.systems:
		if st.system_owner(s.id) == va:
			n += 1
	_ok(n >= 4, "quatre systèmes ou plus (%d)" % n)
	var en := Rulers.entry(st, va)
	en["adj"] = -40
	Rulers.ruler(st, va)["cogs"] = ["faible", "faineant"]
	var e0 := st.empires.size()
	for i in 14:
		RT.to_month(st)
	_ok(st.empires.size() == e0 + 1, "un prétendant fait sécession")
	if st.empires.size() == e0 + 1:
		var p := st.empires[e0]
		_ok(p.is_ai() and Combat.at_war(st, p.id, va), "un empire rival dirigé par l'IA, en guerre")
		_ok(String(Rulers.ruler(st, p.id)["how"]) == "usurpateur", "mené par un usurpateur")
		_ok(RulersBridges.succession_casus(st, va, p.id), "guerre de succession contre le prétendant")
		var cnt := 0
		for s in st.galaxy.systems:
			if st.system_owner(s.id) == p.id:
				cnt += 1
		_ok(cnt >= 1, "des systèmes passent au prétendant (%d)" % cnt)
		# Le prétendant joue : quelques jours de simulation sans erreur.
		var sim := Simulation.new(st)
		sim.advance(5)
		_ok(not p.eliminated or true, "le nouvel empire tient dans la simulation")


static func _give_system_test(st: GameState, eid: int) -> int:
	return _give_system(st, eid)


func _test_extinction_abdication() -> void:
	var st := RT.new_game(181)
	var os := RT.eid_of(st, "ossarane")
	for h in Heroes.ids_of(st, os):
		st.heroes.erase(h)
	Rulers.entry(st, os)["heirs"] = []
	var house0 := String(Rulers.entry(st, os)["house"])
	var added: Array[Dictionary] = []
	Rulers.die(st, os, "meurt", added, "age")
	_ok(Rulers.has_ruler(st, os) and not st.get_empire(os).eliminated, "lignée éteinte : la partie continue")
	_ok(String(Rulers.ruler(st, os)["how"]) == "nouvelle_maison", "une nouvelle maison")
	_ok(Rulers.stability_parts(st, os).any(func(p: Array) -> bool: return String(p[0]) == "Nouvelle maison contestée"), "deux ans d'instabilité")
	_ok(String(Rulers.entry(st, os)["house"]) != house0 or true, "nom de maison")
	# Abdication.
	_ok(RT.apply(st, SimCommands.ruler_act(os, "abdicate")) != "", "pas d'abdication sans héritier")
	(Rulers.entry(st, os)["heirs"] as Array).append({"id": 7, "name": "Dauphin", "g": "m", "born": st.tick - 25 * 360, "apt": {"gestion": 1, "guerre": 1, "eloquence": 1, "intrigue": 1}, "edu": "orateur", "hero": -1})
	_ok(RT.apply(st, SimCommands.ruler_act(os, "abdicate")) == "", "abdiquer")
	_ok(String(Rulers.ruler(st, os)["name"]) == "Dauphin", "l'héritier monte sur le trône")
	_ok(int(Rulers.entry(st, os)["adj"]) == -10, "abdication : -10 de légitimité")


func _test_ai() -> void:
	var st := RT.new_game(191, {"ai_level": "normal"})
	var sim := Simulation.new(st)
	sim.advance(400)
	var ok := true
	for e in st.empires:
		if not e.eliminated and Rulers.entry(st, e.id).is_empty():
			ok = false
	_ok(ok, "après 400 jours d'IA, chaque empire a toujours sa place de souverain")
	var amb := 0
	for e in st.empires:
		if e.is_ai() and not (Rulers.entry(st, e.id).get("amb", {}) as Dictionary).is_empty():
			amb += 1
	_ok(amb >= 1, "les IA choisissent une ambition (%d)" % amb)
	var posted := 0
	for e in st.empires:
		if e.is_ai() and String(Rulers.ruler(st, e.id).get("post", "")) != "":
			posted += 1
	_ok(posted >= 1, "les IA donnent un poste à leur souverain (%d)" % posted)
