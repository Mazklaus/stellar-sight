extends RefCounted
## Tests des peuples mineurs, lot 3 (MinorsBridges) : Amphictyonie (famille du Nomos, infractions, voix
## de Tisseterre) ; religion (prêcher, même foi) ; espionnage (Ingérence, Infiltrer, Pousser au raid) ;
## comptoir ; frontières ; Conservatoire ; Préscience de Quellis ; héros offert ; talents par couche ;
## domination ; nouveaux effets (technologies, espionnage) ; sauvegarde 71. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Peuples mineurs, ponts…")
	_test_amphictyony()
	_test_faith()
	_test_spy()
	_test_route_borders()
	_test_ancients()
	_test_presage()
	_test_hero_talents()
	_test_domination()
	_test_fx()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	if what.contains("sauté"):
		print("  (%s)" % what)
	_check.call(cond, what)


func _new(seed_value := 11, extra := {}) -> GameState:
	var o := {"ai_level": "", "minors": "normal"}
	o.merge(extra, true)
	return GameState.create(seed_value, 120, 1600.0, "vael", o)


func _days(st: GameState, n: int) -> void:
	for i in n:
		st.tick += 1
		Minors.daily(st)


func _first(st: GameState, fam: String) -> int:
	for id in Minors.ids(st):
		if String(Minors.get_m(st, id)["fam"]) == fam:
			return id
	return -1


func _of_kind(st: GameState, kind: String) -> int:
	for id in Minors.ids(st):
		if Minors.kind_of(st, id) == kind:
			return id
	return -1


func _met(st: GameState, id: int, eids: Array) -> void:
	var added: Array[Dictionary] = []
	for eid in eids:
		Minors.meet(st, id, int(eid), added)
		if Minors.is_pre(st, id):
			(Minors.get_m(st, id)["post"] as Dictionary)[int(eid)] = "discret"


func _founded(st: GameState) -> void:
	for e in st.empires:
		for o in st.empires:
			if o.id != e.id and not e.contacts.has(o.id):
				e.contacts.append(o.id)
		e.resources["influence"] = 2000
	st.tick = int(Amphictyony.data()["found"]["min_day"])
	var added: Array[Dictionary] = []
	Amphictyony.monthly(st, added)
	var el: Array[int] = []
	for e in st.empires:
		if Amphictyony.eligible(st, e.id):
			el.append(e.id)
	for i in mini(3, el.size()):
		Amphictyony.found_sign(st, el[i])
	for e in st.empires:
		if not Amphictyony.is_member(st, e.id) and Amphictyony.check_join(st, e.id) == "":
			Amphictyony.join(st, e.id)


func _test_amphictyony() -> void:
	var st := _new(11, {"amphictyony": "active"})
	_ok(Amphictyony.family_available(st, "mineurs"), "famille « Peuples mineurs » au Nomos quand ils sont en jeu")
	_ok(not Amphictyony.family_available(_new(11, {"amphictyony": "active", "minors": "aucun"}), "mineurs"), "absente sans mineurs")
	_founded(st)
	_ok(Amphictyony.founded(st), "Amphictyonie fondée")
	st.amph["fam"]["mineurs"] = 1
	_ok(Amphictyony.banned(st, "minor_open_post") and Amphictyony.banned(st, "minor_tech"), "Non-ingérence : poste ouvert et transfert interdits")
	var pre := _first(st, "pre")
	_met(st, pre, [0])
	st.empires[0].resources["materials"] = 1000
	_ok(Minors.check_act(st, 0, "post", pre, "ouvert", -1).contains("Amphictyonie"), "poste ouvert refusé")
	var mem := -1
	for e in st.empires:
		if Amphictyony.is_member(st, e.id):
			mem = e.id
			break
	if mem >= 0:
		_met(st, pre, [mem])
		Minors.act(st, mem, "war", pre, "", -1, [])
		Combat.capture_system(st, Minors.system_of(st, pre), mem)
		_ok(Amphictyony.outlaw(st, mem), "conquérir un pré-spatial : hors-la-loi")
	st.amph["fam"]["mineurs"] = -1
	_ok(MinorsBridges.post_pct(st) == 50, "Exploitation : observation +50 %")
	st.amph["fam"]["mineurs"] = -2
	_ok(MinorsBridges.tech_x(st, 0) >= 2 and MinorsBridges.trade_x(st, 0) >= 2, "Égalité des échanges : transfert et commerce doublés")
	# Tisseterre prête des voix.
	var ts := _of_kind(st, "tisseterre")
	if ts >= 0 and mem >= 0:
		var w0 := Amphictyony.voix_pct(st, mem)
		_met(st, ts, [mem])
		(Minors.get_m(st, ts)["fav"] as Dictionary)[mem] = 90
		_days(st, 30)
		_ok(Amphictyony.voix_pct(st, mem) == w0 + 3, "Sénat de Tisseterre : +3 % des voix à son suzerain")


func _test_faith() -> void:
	var st := _new(11, {"faiths": "actives"})
	if not st.faith_on:
		_ok(true, "religions absentes : test sauté")
		return
	var id := _first(st, "space")
	_met(st, id, [0])
	_ok(MinorsBridges.minor_faith(st, id) == Faiths.NATIVE, "foi native au départ")
	var f := Faiths.state_faith(st, 0)
	if f == "":
		_ok(MinorsBridges.check_preach(st, 0, id).contains("foi d'État"), "prêcher : il faut une foi d'État")
		return
	st.empires[0].resources["influence"] = 500
	for i in 6:
		if MinorsBridges.check_preach(st, 0, id) == "":
			Minors.act(st, 0, "preach", id, "", -1, [])
	_ok(MinorsBridges.minor_faith(st, id) == f, "prêcher : ils adoptent votre foi")
	var f0 := Minors.fav(st, id, 0)
	_days(st, 30)
	_ok(Minors.fav(st, id, 0) >= f0, "même foi : la faveur monte chaque mois")


func _test_spy() -> void:
	var st := _new()
	var id := _first(st, "space")
	_met(st, id, [0, 1])
	var m := Minors.get_m(st, id)
	(m["fav"] as Dictionary)[1] = 80
	(m["fav"] as Dictionary)[0] = 30
	_days(st, 30)
	st.empires[0].resources["influence"] = 500
	st.empires[0].resources["knowledge"] = 500
	_ok(Minors.check_act(st, 0, "meddle", id, "", -1) == "", "Ingérence possible contre un suzerain")
	Minors.act(st, 0, "meddle", id, "", -1, [])
	_ok(Minors.fav(st, id, 1) <= 65 and Minors.fav(st, id, 0) >= 44, "Ingérence : 15 de faveur volés au suzerain")
	_ok(Minors.check_act(st, 0, "meddle", id, "", -1) != "", "pas deux fois dans l'année")
	var pre := _first(st, "pre")
	var added: Array[Dictionary] = []
	Minors.meet(st, pre, 0, added)
	_ok(not Minors.can_talk(st, pre, 0), "sans poste, pas de dialogue")
	Minors.act(st, 0, "infiltrate", pre, "", -1, [])
	_ok(Minors.can_talk(st, pre, 0) and Minors.check_act(st, 0, "accord", pre, "trade", -1) == "", "Infiltrer : accords sans se révéler")
	# Pousser au raid.
	m["att"] = "hostile"
	(m["fav"] as Dictionary)[0] = 30
	var target := -1
	for e in st.empires:
		if e.id != 0 and MinorsBridges.check_op(st, 0, id, "incite", e.id) == "":
			target = e.id
			break
	if target >= 0:
		Minors.act(st, 0, "incite", id, "", target, [])
		_ok(not (m.get("raid", {}) as Dictionary).is_empty(), "Pousser au raid : leur flotte part harceler le rival")
	else:
		_ok(true, "aucun rival à portée : test sauté")


func _test_route_borders() -> void:
	var st := _new()
	var id := _first(st, "space")
	_met(st, id, [0])
	var m := Minors.get_m(st, id)
	(m["fav"] as Dictionary)[0] = 25
	st.empires[0].resources["influence"] = 100
	_ok(Minors.check_act(st, 0, "route", id, "", -1) == "", "comptoir possible au palier de contact")
	Minors.act(st, 0, "route", id, "", -1, [])
	var e0 := int(st.empires[0].resources.get("energy", 0))
	var f0 := Minors.fav(st, id, 0)
	_days(st, 30)
	_ok(int(st.empires[0].resources.get("energy", 0)) > e0 and Minors.fav(st, id, 0) > f0 - 1, "comptoir : énergie et faveur")
	_ok(Borders.policy(st, id, 0) == Borders.OPEN, "frontière d'un peuple neutre : ouverte")
	m["att"] = "hostile"
	(m["fav"] as Dictionary)[1] = 0
	_ok(Borders.policy(st, id, 1) == Borders.CLOSED, "hostile : close")


func _test_ancients() -> void:
	var st := _new(11, {"ancients": "beaucoup"})
	var y := Ancients.id_of_kind(st, "conservatoire")
	if y < 0:
		_ok(true, "pas de Conservatoire dans cette galaxie : test sauté")
		return
	var pre := _first(st, "pre")
	_met(st, pre, [0])
	Ancients.meet(st, y, 0, [])
	var op0 := Ancients.opinion(st, y, 0)
	Minors.act(st, 0, "war", pre, "", -1, [])
	Combat.capture_system(st, Minors.system_of(st, pre), 0)
	_ok(Ancients.opinion(st, y, 0) <= op0 - 40, "le Conservatoire punit les conquérants de pré-spatiaux")


func _test_presage() -> void:
	var st := GameState.create(11, 120, 1600.0, "vael", {"ai_level": "", "minors": "beaucoup", "crises": "une", "crisis_kinds": ["dechirure"], "rivals": ["ossarane", "khthari", "teyl"]})
	var q := _of_kind(st, "quellis")
	if q < 0:
		_ok(true, "pas de Quellis dans cette galaxie : test sauté")
		return
	_met(st, q, [0])
	(Minors.get_m(st, q)["fav"] as Dictionary)[0] = 90
	_days(st, 30)
	_ok(Minors.suzerain(st, q) == 0, "suzerain de Quellis")
	st.tick = 10800
	var added: Array[Dictionary] = []
	Crisis.begin(st, "dechirure", added)
	var c := Crisis.cur(st)
	_ok(String(c["stage"]) == "notice" and (c.get("seers", []) as Array).has(0), "Préscience : le suzerain de Quellis sent venir la crise")


func _test_hero_talents() -> void:
	var st := _new()
	var id := _first(st, "space")
	_met(st, id, [0])
	(Minors.get_m(st, id)["fav"] as Dictionary)[0] = 55
	st.empires[0].resources["influence"] = 200
	var n0 := Heroes.ids_of(st, 0).size()
	_ok(Minors.check_act(st, 0, "hero", id, "", -1) == "", "un ami peut offrir un héros")
	Minors.act(st, 0, "hero", id, "", -1, [])
	_ok(Heroes.ids_of(st, 0).size() == n0 + 1, "héros offert, de leur espèce")
	_ok(Minors.check_act(st, 0, "hero", id, "", -1) != "", "une seule fois")
	# Talents par couche (le Chœur est une ruche ? on teste via les données).
	var st2 := GameState.create(11, 120, 1600.0, "choeur", {"ai_level": "", "minors": "normal"})
	var t := MinorsBridges.talent(st2, 0)
	var sp: Dictionary = st2.empires[0].faction().get("species", {})
	var expect := ((Minors.data()["talents"] as Dictionary).get("gouvernement", {}) as Dictionary).has(String(sp.get("gouvernement", ""))) \
			or ((Minors.data()["talents"] as Dictionary).get("credo", {}) as Dictionary).has(String(sp.get("credo", "")))
	_ok(expect == not t.is_empty(), "talents tirés des couches d'espèce (%s / %s)" % [String(sp.get("gouvernement", "")), String(sp.get("credo", ""))])


func _test_domination() -> void:
	var st := _new()
	var a := _first(st, "space")
	var b := _first(st, "pre")
	for id in [a, b]:
		_met(st, id, [0])
		(Minors.get_m(st, id)["fav"] as Dictionary)[0] = 90
	_days(st, 30)
	_ok(MinorsBridges.domination_bonus(st, 0) == 1, "deux protégés : un système de plus pour la domination")


func _test_fx() -> void:
	var st := _new()
	Minors.absorb(st, 0, "nadir")
	var cells := Espionage.cells_total(st, 0)
	Minors.absorb(st, 0, "zimzoroo")
	Minors.act(st, 0, "trait", -1, "zimzoroo", -1, [])
	st.minors["active"][0] = ["nadir", "zimzoroo"]
	Relics.touch(st)
	_ok(Research.fx_int(st, 0, "spy_discovery_pct") == -20, "Nadir : espions plus discrets")
	_ok(Research.fx_int(st, 0, "spy_cost_pct") == -15, "Zim-Zoroo : opérations moins chères")
	var nad := _of_kind(st, "nadir")
	if nad >= 0:
		_met(st, nad, [1])
		(Minors.get_m(st, nad)["fav"] as Dictionary)[1] = 90
		var c1 := Espionage.cells_total(st, 1)
		_days(st, 30)
		_ok(Espionage.cells_total(st, 1) == c1 + 1, "Oreilles de Nadir : +1 cellule pour le suzerain")
	_ok(cells >= 0, "cellules lisibles")


func _test_save() -> void:
	var sim := Simulation.new(_new(19, {"ai_level": "normal", "amphictyony": "active", "faiths": "actives"}))
	var st := sim.state
	sim.advance(1080)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_snapshot())))
	_ok(back != null and back.checksum() == st.checksum(), "sauvegarde 71 relue, même empreinte")
	if back == null:
		return
	var a := Simulation.new(st)
	var b := Simulation.new(back)
	a.advance(360)
	b.advance(360)
	_ok(a.state.checksum() == b.state.checksum(), "la partie reprise continue à l'identique")
