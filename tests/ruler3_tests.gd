extends RefCounted
## Tests des souverains, lot 3 (les ponts) : courant de l'archétype, coup d'État et crise de régime,
## sacre, Ancêtres, opérations d'espionnage (assassiner, prétendant, bâtardise), guerre de succession et
## but « Imposer un héritier », titre de haut fait devenu surnom, frise des règnes.

const RT := preload("res://tests/ruler_tests.gd")

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Souverains (les ponts)…")
	_test_politics()
	_test_faith()
	_test_espionage()
	_test_war()
	_test_deeds()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _test_politics() -> void:
	var st := RT.new_game(201, {"politics": "active"})
	var va := RT.eid_of(st, "vael")
	_ok(Rulers.arch_def("conquerant")["current"] == "glaive" and Rulers.arch_def("savant")["current"] == "academie", "chaque archétype penche vers un courant")
	if Politics.applies(st, va):
		Rulers.ruler(st, va)["arch"] = "savant"
		var cap := FactionTraits.capital_system(st, va)
		var i := Politics.index_of("academie")
		var before := int(Politics.opinion(st, cap)[i]) if Politics.opinion(st, cap).size() > i else 0
		RulersBridges.monthly(st, va)
		var after := int(Politics.opinion(st, cap)[i]) if Politics.opinion(st, cap).size() > i else 0
		_ok(after >= before, "le Savant pousse l'Académie à la capitale")
		var r0 := Rulers.ruler(st, va)
		Grievances.crisis(st, va, "coup d'État")
		_ok(Rulers.ruler(st, va) != r0 and String(Rulers.ruler(st, va)["how"]) == "usurpateur", "le coup d'État installe un usurpateur")
		_ok(Rulers.legitimacy(st, va) <= 30, "légitimité d'usurpateur")
		_ok((Rulers.ruler(st, va)["cogs"] as Array).has("usurpateur"), "surnom « l'Usurpateur »")
		Rulers.entry(st, va)["adj"] = 40
		Rulers.entry(st, va)["wobbly"] = 0
		Rulers.ruler(st, va)["cogs"] = []
		var r1 := Rulers.ruler(st, va)
		Grievances.crisis(st, va, "crise")
		_ok(Rulers.ruler(st, va) == r1, "un souverain légitime survit à la crise de régime")
	else:
		_ok(true, "politique inactive dans ce tirage")


func _test_faith() -> void:
	var st := RT.new_game(211, {"faiths": "actives"})
	var ch := RT.eid_of(st, "choeur")
	_ok(RulersBridges.legit_bonus(st, ch) == (10 if RulersBridges.crowned_by_faith(st, ch) else 0), "sacre : +10 si la foi d'État tient un monde saint")
	_ok(RulersBridges.heads_faith(st, ch) == (st.faith_on and Faiths.state_faith(st, ch) != ""), "le Pontife est le chef de sa foi")
	# Funérailles : souvenirs prolongés.
	var m := Heroes.meta(st, ch)
	m["memorials"] = [{"name": "X", "until": st.tick + 100, "credo": "foi"}]
	RulersBridges.on_funeral(st, ch)
	_ok(int(m["memorials"][0]["until"]) == st.tick + 460, "les funérailles prolongent les souvenirs des héros")


func _test_espionage() -> void:
	var st := RT.new_game(221)
	var va := RT.eid_of(st, "vael")
	var os := RT.eid_of(st, "ossarane")
	var ops := {}
	for o: Dictionary in Espionage.data()["operations"]:
		ops[String(o["id"])] = o
	for id in ["assassiner_souverain", "soutenir_pretendant", "reveler_batardise"]:
		_ok(ops.has(id) and bool(ops[id].get("rulers", false)), "opération %s" % id)
	_ok(RulersBridges.spy_check(st, va, os, "reveler_batardise") != "", "pas de bâtardise sans héritier")
	(Rulers.entry(st, os)["heirs"] as Array).append({"id": 1, "name": "Fils", "g": "m", "born": st.tick - 5 * 360, "apt": {"gestion": 1, "guerre": 1, "eloquence": 1, "intrigue": 1}, "edu": "", "hero": -1})
	_ok(RulersBridges.spy_check(st, va, os, "reveler_batardise") == "", "bâtardise possible")
	RulersBridges.spy_apply(st, va, os, ops["reveler_batardise"])
	_ok(int(RulersDynasty.heirs(st, os)[0].get("bastard", 0)) == 1, "l'héritier est déclaré bâtard")
	var l0 := Rulers.legitimacy(st, os)
	RulersBridges.spy_apply(st, va, os, ops["soutenir_pretendant"])
	_ok(Rulers.legitimacy(st, os) == maxi(0, l0 - 15), "soutenir un prétendant : -15 de légitimité")
	var r0 := Rulers.ruler(st, os)
	RulersBridges.spy_apply(st, va, os, ops["assassiner_souverain"])
	var rg: Array = Rulers.entry(st, os)["reigns"]
	_ok(Rulers.ruler(st, os) != r0 and String(rg[rg.size() - 1]["end"]) == "murdered", "le souverain est assassiné")
	_ok((rg[rg.size() - 1]["cogs"] as Array).has("assassine"), "surnom posthume « l'Assassiné »")
	_ok(RulersBridges.spy_check(st, va, RT.eid_of(st, "khthari"), "assassiner_souverain") != "", "la Reine-mère ne s'assassine pas")
	RulersBridges.spy_exposed(st, va, os, "assassiner_souverain", true)
	var found := false
	for mm in st.memories:
		if int(mm["who"]) == os and int(mm["about"]) == va and String(mm["kind"]) == "war_crime":
			found = true
	_ok(found, "découvert : incident diplomatique")


func _test_war() -> void:
	var st := RT.new_game(231, {"wargoals": "actifs"})
	var va := RT.eid_of(st, "vael")
	var os := RT.eid_of(st, "ossarane")
	_ok(not Wars.casus_def("succession").is_empty() and not Wars.goal_def("heritier").is_empty(), "motif et but de succession en données")
	Rulers.ruler(st, va)["how"] = "usurpateur"
	_ok(RulersBridges.succession_casus(st, os, va), "un trône usurpé donne un motif à une dynastie")
	_ok(not RulersBridges.succession_casus(st, va, os), "mais pas l'inverse")
	RulersBridges.impose_heir(st, os, va)
	_ok(String(Rulers.ruler(st, va)["house"]) == String(Rulers.entry(st, os)["house"]), "imposer un héritier : candidat de la maison du vainqueur")
	_ok(int(Rulers.entry(st, va)["parent"]) == os, "lien de maison retenu")


func _test_deeds() -> void:
	var st := RT.new_game(241, {"deeds": "tous"})
	var va := RT.eid_of(st, "vael")
	Rulers.give_cognomen(st, va, "deed:cartographe")
	_ok(Rulers.full_name(st, va).contains("Cartographe"), "un titre de haut fait devient un surnom : %s" % Rulers.full_name(st, va))
	var added: Array[Dictionary] = []
	Rulers.die(st, va, "meurt", added, "age")
	var rg: Array = Rulers.entry(st, va)["reigns"]
	_ok(rg.size() == 1 and int(rg[0]["to"]) == st.tick and String(rg[0]["name"]) != "", "frise des règnes : dates, nom, surnoms, fin")
