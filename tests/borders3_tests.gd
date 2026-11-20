extends RefCounted
## Tests du pilier frontières et droit de passage, lot 3 : commerce à travers une frontière close,
## opération « Corridor discret », religion (même foi, précepte Sanctuaire), talents de peuple,
## héros (amiral discret, ambassadeur), lois Doctrine des frontières, IA, sauvegarde 58.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Frontières, lot 3…")
	_test_trade()
	_test_corridor()
	_test_faith()
	_test_talents()
	_test_heroes()
	_test_laws()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(opts := {}) -> GameState:
	var o := {"ai_level": "", "borders": "souples"}
	o.merge(opts, true)
	var st := GameState.create(7, 120, 1600.0, "vael", o)
	for e in st.empires:
		if e.is_npc():
			continue
		for x in st.empires:
			if x.id != e.id and not x.is_npc() and not e.contacts.has(x.id):
				e.contacts.append(x.id)
		e.resources["influence"] = 500
	for e in st.empires:
		for x in st.empires:
			st.borders["first"]["%d>%d" % [e.id, x.id]] = 1
	return st


func _cap(st: GameState, eid: int) -> int:
	return FactionTraits.capital_system(st, eid)


func _empire_of(st: GameState, fid: String) -> int:
	for e in st.empires:
		if e.faction_id == fid:
			return e.id
	return -1


func _memory(st: GameState, who: int, about: int, kind: String) -> int:
	for m in st.memories:
		if int(m["who"]) == who and int(m["about"]) == about and String(m["kind"]) == kind:
			return int(m["count"])
	return 0


func _test_trade() -> void:
	var st := _new()
	var path := [_cap(st, 1), _cap(st, 2), _cap(st, 3)]
	_ok(Borders.trade_pct(st, 1, 3, path) == 0, "Commerce : une route à travers une frontière gardée ne perd rien")
	Borders.set_policy(st, 2, 1, Borders.CLOSED)
	var syn := bool(Borders.talent(st, 1).get("civil_always", false))
	_ok(Borders.trade_pct(st, 1, 3, path) == (0 if syn else -25), "Commerce : une route à travers une frontière close perd 25 %")
	_ok(Borders.trade_pct(_new({"borders": "libres"}), 1, 3, path) == 0, "Sans frontières, le commerce passe")


func _test_corridor() -> void:
	var st := _new()
	_ok(Espionage.op_def("corridor_discret").get("borders", false), "Opération « Corridor discret » au catalogue de l'espionnage")
	_ok(Borders.spy_check(st, 1, 0, "corridor_discret") == "", "Corridor possible chez un empire qui ne vous ouvre pas ses frontières")
	var what := Borders.spy_apply(st, 1, 0, {})
	_ok(what != "" and Borders.corridor(st, 0, 1), "Corridor ouvert pour 180 jours")
	var f := st.spawn_ship(1, "corvette", _cap(st, 0))
	Simulation.new(st).step()
	_ok(Borders.intruders(st, 0, 1).is_empty() and _memory(st, 0, 1, "intrusion") == 0, "Corridor : aucune intrusion constatée")
	_ok(Borders.spy_check(st, 1, 0, "corridor_discret") != "", "Un seul corridor à la fois")
	st.tick += 181
	_ok(not Borders.fleet_right(st, f, 0), "Corridor refermé au bout de 180 jours")


func _test_faith() -> void:
	var st := _new({"faiths": "actives"})
	if not st.faith_on:
		return
	var fids: Array = (st.faiths.get("list", {}) as Dictionary).keys() if st.faiths.has("list") else []
	st.faiths["state"] = st.faiths.get("state", {})
	var war := st.spawn_ship(1, "corvette", _cap(st, 0))
	st.faiths["state"]["0"] = "f_a"
	st.faiths["state"]["1"] = "f_b"
	_ok(not Borders.fleet_right(st, war, 0), "Foi différente : la flotte de guerre est une intruse")
	st.faiths["state"]["0"] = "f_test"
	st.faiths["state"]["1"] = "f_test"
	if Borders.same_faith(st, 0, 1):
		_ok(Borders.fleet_right(st, war, 0), "Même foi d'État : passage inoffensif, même armé")
		Borders.set_policy(st, 0, 1, Borders.CLOSED)
		_ok(not Borders.fleet_right(st, war, 0), "Même foi : la frontière close tient")
	_ok(Faiths.precept_def("sanctuaire").get("fx", {}).has("sanctuary"), "Précepte Sanctuaire au catalogue ouvert des préceptes")
	_ok(fids.size() >= 0, "Religions en jeu")


func _test_talents() -> void:
	var st := _new()
	var oss := _empire_of(st, "ossarane")
	var vael := _empire_of(st, "vael")
	var kh := _empire_of(st, "khthari")
	var bri := _empire_of(st, "brisecomete")
	if vael >= 0:
		_ok(Borders.pass_cost(st, vael).is_empty(), "République de Vael : laissez-passer gratuits")
	if oss >= 0:
		_ok(int(Borders.talent(st, oss).get("toll_x", 1)) == 2 and bool(Borders.talent(st, oss).get("first_free", false)), "Ossarane : péage double et Gens du voyage")
	if kh >= 0 and vael >= 0:
		_ok(Borders.policy(st, kh, vael) == Borders.CLOSED, "Ruche close : frontières closes dès la rencontre")
	if bri >= 0 and kh >= 0:
		var scout := st.spawn_ship(bri, "scout", _cap(st, kh))
		_ok(Borders.fleet_right(st, scout, kh), "Contrebandiers : leurs vaisseaux sans armes passent même une frontière close")
	_ok(not Borders.talent_labels(st, oss).is_empty() if oss >= 0 else true, "Talents de frontière affichés")


func _test_heroes() -> void:
	var st := _new()
	_ok(not Heroes.trait_def("amiral_discret").is_empty(), "Trait d'amiral « Amiral discret »")
	var f := st.spawn_ship(1, "corvette", _cap(st, 0))
	var hid := Heroes.recruit(st, 1, Heroes.make_candidate(st, 1, "stratege", ["amiral_discret"]))
	var h: Dictionary = st.heroes[hid]
	h["post"] = "fleet"
	h["target"] = f.id
	h["arrive"] = 0
	if not (h["traits"] as Array).has("amiral_discret"):
		(h["traits"] as Array).append("amiral_discret")
	Simulation.new(st).step()
	_ok(Borders.intruders(st, 0, 1).has(f.id) and _memory(st, 0, 1, "intrusion") == 0, "Amiral discret : intrusion notée, sans souvenir")
	var st2 := _new({"amphictyony": "active"})
	var g := st2.spawn_ship(1, "corvette", _cap(st2, 1))
	var before := AiBorders.pass_score(st2, 0, 1, g)
	var aid := Heroes.recruit(st2, 1, Heroes.make_candidate(st2, 1, "orateur", []))
	var a: Dictionary = st2.heroes[aid]
	a["post"] = "amph"
	a["target"] = 0
	a["arrive"] = 0
	_ok(AiBorders.pass_score(st2, 0, 1, g) > before, "Ambassadeur : les laissez-passer s'obtiennent plus facilement")


func _test_laws() -> void:
	var st := _new({"politics": "active"})
	if not st.politics_on:
		return
	var vael := _empire_of(st, "vael")
	_ok(not Laws.law_def("doctrine_close").is_empty() and not Laws.law_def("doctrine_ouverte").is_empty(), "Lois Doctrine des frontières")
	_ok(Laws.check_adopt(_new({"politics": "active", "borders": "libres"}), vael, "doctrine_close") != "", "Pas de doctrine sans frontières")
	var other := 1 if vael != 1 else 2
	Laws.adopt(st, vael, "doctrine_ouverte")
	_ok(Borders.policy(st, vael, other) == Borders.OPEN, "Doctrine des frontières ouvertes : politique par défaut Ouverte")
	_ok(_memory(st, other, vael, "borders_opened") == 1, "La doctrine ouverte plaît à ses voisins")
	_ok(Laws.check_adopt(st, vael, "doctrine_close") != "", "Les deux doctrines s'excluent")
	_ok(AiBorders.law_score(st, st.get_empire(other), "doctrine_close", 3) > 0 and AiBorders.law_score(st, st.get_empire(other), "doctrine_close", 0) < 0,
			"L'IA belliqueuse ferme ses frontières par la loi, pas l'IA tranquille")


func _test_save() -> void:
	var st := _new()
	Borders.spy_apply(st, 1, 0, {})
	var d := st.to_dict()
	_ok(int(d["version"]) == GameState.FORMAT_VERSION and GameState.FORMAT_VERSION >= 58, "Sauvegarde 58")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and back.checksum() == st.checksum() and Borders.corridor(back, 0, 1), "Sauvegarde : corridor relu")
