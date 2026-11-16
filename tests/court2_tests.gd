extends RefCounted
## Tests de la cour, lot 2 : missions des grands offices (présent, pacification, emprisonnement, secret et
## levier, ambassade, intercession), exil, courtisan élevé au rang de héros, mariage, Étoile montante,
## Fronde, ultimatum, guerre civile par sécession, maisons des vaincus, opérations d'espionnage.
## Appelés par smoke_test.gd.

const CT := preload("res://tests/court_tests.gd")

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Cour et Grandes Maisons (intrigues)…")
	_test_missions()
	_test_members()
	_test_star()
	_test_fronde()
	_test_civil_war()
	_test_peaceful()
	_test_conquered()
	_test_spy()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func ready_game(seed_value := 31, extra := {}) -> GameState:
	var st := CT.new_game(seed_value, extra)
	var v := CT.eid_of(st, "vael")
	CT.to_month(st)
	CT.answer(st, v, "court_houses", 0)
	var e := st.get_empire(v)
	e.resources["influence"] = 2000
	e.resources["energy"] = 5000
	return st


func _test_missions() -> void:
	var st := ready_game()
	var v := CT.eid_of(st, "vael")
	var hs := Court.houses(st, v)
	var h: Dictionary = hs[0]
	var hid := int(h["id"])
	_ok(CT.apply(st, SimCommands.court_act(v, "gift", hid)) != "", "pas de présent sans Grand Intendant")
	var m: Dictionary = (hs[1] as Dictionary)["members"][0]
	CT.apply(st, SimCommands.court_act(v, "appoint", int(m["id"]), 0, "intendant"))
	var adj := int(h["adj"])
	_ok(CT.apply(st, SimCommands.court_act(v, "gift", hid)) == "", "un présent")
	_ok(int(h["adj"]) > adj, "la maison apprécie (%d → %d)" % [adj, int(h["adj"])])
	_ok(CT.apply(st, SimCommands.court_act(v, "gift", hid)) != "", "pas deux présents de suite")
	# Pacifier un fief.
	var s := CT.give_system(st, v)
	Court.reconcile(st, v)
	if s >= 0:
		_ok(CT.apply(st, SimCommands.court_act(v, "pacify", s)) == "", "pacifier un fief")
		var found := false
		for p in Court.stability_parts(st, s, v):
			if String(p[0]).begins_with("Pacifié"):
				found = true
		_ok(found, "le fief pacifié gagne de la stabilité")
	# Maître des Murmures : secret, levier, emprisonnement.
	var m2: Dictionary = (hs[2] as Dictionary)["members"][0]
	CT.apply(st, SimCommands.court_act(v, "appoint", int(m2["id"]), 0, "murmures"))
	_ok(CourtIntrigue.chance(st, v, "secret") >= Court.r_int("secret_base"), "chance d'un secret selon l'Intrigue")
	var en := Court.entry(st, v)
	var got := false
	for i in 12:
		(en["cd"] as Dictionary).erase("secret")
		st.tick += 1
		CT.apply(st, SimCommands.court_act(v, "secret", hid))
		if (en["levers"] as Dictionary).has(str(hid)):
			got = true
			break
	_ok(got, "un secret finit par tomber")
	_ok(CT.apply(st, SimCommands.court_act(v, "secret", hid)) != "", "un seul secret à la fois")
	var adj2 := int(h["adj"])
	_ok(CT.apply(st, SimCommands.court_act(v, "lever", hid)) == "", "utiliser le levier")
	_ok(int(h["adj"]) > adj2 and not (en["levers"] as Dictionary).has(str(hid)), "le levier force la faveur, puis s'use")
	var victim: Dictionary = h["members"][(h["members"] as Array).size() - 1]
	var n0 := 0
	for o: Dictionary in hs:
		n0 += (o["members"] as Array).size()
	var jailed := false
	for i in 12:
		(en["cd"] as Dictionary).erase("imprison")
		st.tick += 1
		if Court.member(st, v, int(victim["id"])).is_empty():
			jailed = true
			break
		CT.apply(st, SimCommands.court_act(v, "imprison", int(victim["id"])))
	_ok(jailed or Court.member(st, v, int(victim["id"])).is_empty(), "un courtisan finit en prison")
	# Ambassade.
	var e := st.get_empire(v)
	var m3: Dictionary = (hs[0] as Dictionary)["members"][0]
	CT.apply(st, SimCommands.court_act(v, "appoint", int(m3["id"]), 0, "heraut"))
	var other := -1
	for o in st.empires:
		if o.id != v and not o.is_npc():
			other = o.id
			if not e.contacts.has(o.id):
				e.contacts.append(o.id)
			break
	_ok(CT.apply(st, SimCommands.court_act(v, "embassy", other)) == "", "ambassade du Grand Héraut")
	var mem := false
	for mm in st.memories:
		if String(mm["kind"]) == "court_embassy" and int(mm["who"]) == other:
			mem = true
	_ok(mem, "l'autre empire s'en souvient")
	# Intercession.
	var best := Court.house(st, v, int(hs[1]["id"]))
	best["adj"] = 60
	best["scorn"] = 0
	Court.refresh(st, v)
	if Court.favor(best) >= Court.r_int("intercede_min"):
		var t := -1
		for o: Dictionary in hs:
			if int(o["id"]) != int(best["id"]) and not (best["rivals"] as Array).has(int(o["id"])):
				t = int(o["id"])
		if t >= 0:
			_ok(CT.apply(st, SimCommands.court_act(v, "intercede", t, int(best["id"]))) == "", "une maison dévouée intercède")
	# Mariage.
	_ok(CT.apply(st, SimCommands.court_act(v, "wed", hid)) == "", "un mariage avec une maison")
	_ok(int(h["kin"]) == 1, "la maison est liée au trône")
	_ok(CT.apply(st, SimCommands.court_act(v, "wed", int(hs[1]["id"]))) != "", "pas deux mariages de suite")
	# Grande fête, train.
	var f0 := int(en["faste"])
	_ok(CT.apply(st, SimCommands.court_act(v, "fete")) == "", "une grande fête")
	_ok(int(en["faste"]) == f0 + Court.r_int("fete_faste"), "le faste monte")
	_ok(CT.apply(st, SimCommands.court_act(v, "train", 2, -1, "table")) == "", "train de la cour")
	_ok(CourtBridges.train_upkeep(st, v) > 0, "le train coûte")


func _test_members() -> void:
	var st := ready_game()
	var v := CT.eid_of(st, "vael")
	var h: Dictionary = Court.houses(st, v)[0]
	var m: Dictionary = h["members"][0]
	var nh := Heroes.ids_of(st, v).size()
	var ok := CT.apply(st, SimCommands.court_act(v, "raise", int(m["id"])))
	if Heroes.ids_of(st, v).size() < Heroes.cap(st, v) or ok == "":
		_ok(ok == "", "élever un courtisan au rang de héros (%s)" % ok)
		_ok(Heroes.ids_of(st, v).size() == nh + 1, "un héros de plus")
		var hh: Dictionary = st.heroes[Heroes.ids_of(st, v)[-1]]
		_ok(int(hh.get("house", -1)) == int(h["id"]), "le héros garde sa maison")
		h["adj"] = 60
		Court.refresh(st, v)
		var l1 := Heroes.loyalty(st, hh)
		h["adj"] = -60
		h["scorn"] = -30
		Court.refresh(st, v)
		_ok(Heroes.loyalty(st, hh) < l1, "sa loyauté suit la faveur de sa maison")
	var m2: Dictionary = h["members"][0]
	h["adj"] = 0
	var adj := int(h["adj"])
	_ok(CT.apply(st, SimCommands.court_act(v, "exile", int(m2["id"]))) == "", "exiler un courtisan")
	_ok(Court.member(st, v, int(m2["id"])).is_empty() and int(h["adj"]) < adj, "il part, sa maison s'offense")
	_ok(not (h["members"] as Array).is_empty() and not Court.head(h).is_empty(), "la maison garde un chef")
	# Vieillesse : un chef très vieux finit par mourir, un autre lui succède.
	var oldest: Dictionary = Court.head(h)
	oldest["born"] = st.tick - 120 * 360
	oldest["life"] = 75
	for i in 24:
		CT.to_month(st)
		if Court.member(st, v, int(oldest["id"])).is_empty():
			break
	_ok(Court.member(st, v, int(oldest["id"])).is_empty(), "un chef centenaire s'éteint")
	_ok(not Court.head(h).is_empty(), "un successeur à la tête de la maison")


func _test_star() -> void:
	var st := ready_game()
	var v := CT.eid_of(st, "vael")
	var h: Dictionary = Court.houses(st, v)[0]
	var m: Dictionary = h["members"][0]
	m["traits"] = ["ambitieux"]
	m["apt"] = {"gestion": 4, "guerre": 3, "eloquence": 3, "intrigue": 3}
	CT.to_month(st)
	_ok(CT.has_card(st, v, "court_star"), "une étoile montante se fait remarquer")
	_ok(CT.answer(st, v, "court_star", 1), "acheter sa fidélité")
	_ok((m["traits"] as Array).has("loyal") and not (m["traits"] as Array).has("ambitieux"), "il devient loyal")


func _test_fronde() -> void:
	var st := ready_game()
	var v := CT.eid_of(st, "vael")
	for i in 4:
		CT.give_system(st, v)
	Court.reconcile(st, v)
	var h: Dictionary = Court.houses(st, v)[0]
	var hid := int(h["id"])
	h["adj"] = -60
	h["scorn"] = -30
	Court.refresh(st, v)
	var en := Court.entry(st, v)
	var started := false
	for i in 60:
		h["adj"] = -60
		CT.to_month(st)
		if (en["fronde"] as Dictionary).has(str(hid)):
			started = true
			break
	_ok(started, "une maison furieuse entre en Fronde")
	if started:
		var fs := Court.fiefs_of(st, v, hid)
		if not fs.is_empty():
			var found := false
			for p in Court.stability_parts(st, fs[0], v):
				if int(p[1]) == Court.r_int("fronde_stab"):
					found = true
			_ok(found, "ses fiefs grondent (stabilité %d)" % Court.r_int("fronde_stab"))
		en["fronde"][str(hid)] = st.tick + 1
		CT.to_month(st)
		_ok(CT.has_card(st, v, "court_ultimatum"), "fin de Fronde, toujours furieuse : ultimatum")
		_ok(CT.answer(st, v, "court_ultimatum", 0), "céder")
		_ok((en["ult"] as Dictionary).is_empty() and int(en["ult_cd"]) > st.tick, "l'ultimatum est réglé")
	# Un levier empêche la Fronde.
	var st2 := ready_game()
	var h2: Dictionary = Court.houses(st2, v)[0]
	var en2 := Court.entry(st2, v)
	(en2["levers"] as Dictionary)[str(int(h2["id"]))] = st2.tick + 9999
	var any := false
	for i in 40:
		h2["adj"] = -60
		h2["scorn"] = -30
		CT.to_month(st2)
		if (en2["fronde"] as Dictionary).has(str(int(h2["id"]))):
			any = true
	_ok(not any, "un secret tient la maison : pas de Fronde")


func _test_civil_war() -> void:
	var st := ready_game(31, {"rulers": "mortels"})
	var v := CT.eid_of(st, "vael")
	var sids: Array = []
	for i in 6:
		var s := CT.give_system(st, v, sids)
		if s >= 0:
			sids.append(s)
	Court.reconcile(st, v)
	var h: Dictionary = Court.houses(st, v)[0]
	var hid := int(h["id"])
	var fs := Court.fiefs_of(st, v, hid)
	var n0 := st.empires.size()
	var added: Array[Dictionary] = []
	var nid := CourtIntrigue.civil_war(st, v, hid, added)
	_ok(nid >= 0 and st.empires.size() == n0 + 1, "guerre civile : un nouvel empire naît")
	if nid >= 0:
		for s in fs:
			_ok(st.system_owner(s) == nid, "le fief %d suit la maison rebelle" % s)
		_ok(Combat.at_war(st, v, nid), "et c'est la guerre")
		_ok(Court.house(st, v, hid).is_empty(), "la maison a quitté la cour")
		_ok(Rulers.has_ruler(st, nid), "le chef rebelle monte sur un trône")
		CT.to_month(st)
		_ok(Court.applies(st, nid), "l'empire rebelle a sa propre cour")
	# Sans souverains : la sécession marche aussi.
	var st2 := ready_game()
	var v2 := CT.eid_of(st2, "vael")
	var sids2: Array = []
	for i in 6:
		var s2 := CT.give_system(st2, v2, sids2)
		if s2 >= 0:
			sids2.append(s2)
	Court.reconcile(st2, v2)
	var h2: Dictionary = Court.houses(st2, v2)[0]
	var nid2 := CourtIntrigue.civil_war(st2, v2, int(h2["id"]), added)
	_ok(nid2 >= 0 and st2.rulers.is_empty(), "sécession sans souverains en jeu")
	# Une maison sans fiefs est brisée.
	var st3 := ready_game()
	var h3: Dictionary = Court.houses(st3, v2)[0]
	var n3 := st3.empires.size()
	_ok(CourtIntrigue.civil_war(st3, v2, int(h3["id"]), added) < 0 and st3.empires.size() == n3, "sans fiefs, pas de sécession")
	_ok(Court.house(st3, v2, int(h3["id"])).is_empty(), "la maison est brisée")


func _test_peaceful() -> void:
	var st := ready_game(31, {"court": "apaisees"})
	var v := CT.eid_of(st, "vael")
	var h: Dictionary = Court.houses(st, v)[0]
	var en := Court.entry(st, v)
	var any := false
	for i in 40:
		h["adj"] = -60
		h["scorn"] = -30
		CT.to_month(st)
		if not (en["fronde"] as Dictionary).is_empty() or CT.has_card(st, v, "court_ultimatum"):
			any = true
	_ok(not any, "Apaisées : ni Fronde ni ultimatum")


func _test_conquered() -> void:
	var st := ready_game()
	var v := CT.eid_of(st, "vael")
	var o := -1
	for e in st.empires:
		if e.id != v and not e.is_npc() and Court.applies(st, e.id):
			o = e.id
			break
	if o < 0:
		return
	CT.answer(st, o, "court_houses", 0)
	var s := CT.give_system(st, o)
	Court.reconcile(st, o)
	var h := Court.fief_house(st, s, o)
	_ok(not h.is_empty(), "un fief chez le rival")
	# On prend toute la terre de cette maison.
	var hid := int(h["id"])
	for sid in Court.fiefs_of(st, o, hid):
		for pid in st.galaxy.systems[sid].planet_ids:
			if st.colonies.has(pid):
				(st.colonies[pid] as Colony).owner = v
	st.rebuild_ownership()
	CT.to_month(st)
	_ok(CT.has_card(st, v, "court_conquered"), "les vaincus de %s attendent notre décision" % h["name"])
	var n := Court.houses(st, v).size()
	_ok(CT.answer(st, v, "court_conquered", 0), "l'intégrer")
	_ok(Court.houses(st, v).size() == n + 1, "elle rejoint nos maisons")
	_ok(Court.house(st, o, hid).is_empty(), "elle a quitté son ancienne cour")


func _test_spy() -> void:
	var st := ready_game()
	var v := CT.eid_of(st, "vael")
	var o := -1
	for e in st.empires:
		if e.id != v and not e.is_npc() and Court.applies(st, e.id):
			o = e.id
			break
	if o < 0:
		return
	var op := Espionage.op_def("attiser_maison")
	_ok(not op.is_empty() and bool(op.get("court", false)), "opération « Attiser une Grande Maison »")
	_ok(CourtIntrigue.spy_check(st, v, o, "attiser_maison") == "", "possible contre une cour")
	var sore := CourtIntrigue._sorest(st, o)
	var f0 := Court.favor(sore)
	CourtIntrigue.spy_apply(st, v, o, op)
	_ok(Court.favor(Court.house(st, o, int(sore["id"]))) < f0, "sa maison la plus fâchée perd de la faveur")
	_ok(CourtIntrigue.spy_check(st, v, o, "debaucher_maison") != "" or Court.favor(CourtIntrigue._sorest(st, o)) <= -20, "débaucher seulement une maison fâchée")
	var st2 := CT.new_game(31, {"court": "aucune"})
	_ok(CourtIntrigue.spy_check(st2, v, o, "attiser_maison") != "", "sans cour, pas d'opération de cour")
