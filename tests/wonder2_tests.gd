extends RefCounted
## Tests des merveilles galactiques, lot 2 : catalogue codé (péage, Œil du Démiurge, Collège
## universel, Ménagerie, Rade franche, Académie d'amirauté, Calculateur de Raison, Brise-tempêtes),
## ruines à restaurer, Monde-anneau, Portes stellaires, lieux saints, trait Architecte, Tribunal.
## Appelés par smoke_test.gd.

const T := preload("res://tests/wonder_tests.gd")

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Merveilles galactiques (catalogue)…")
	_test_ruins()
	_test_toll()
	_test_sight()
	_test_known_tech()
	_test_flags()
	_test_free_tech()
	_test_gates()
	_test_misc()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


## Achève d'un coup une merveille sur une planète (comme un chantier terminé).
static func finish(st: GameState, eid: int, pid: int, wid: String) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	var b: Dictionary = Wonders._m(st, "build")
	if not b.has(wid):
		b[wid] = {}
	b[wid][str(eid)] = {"p": pid, "pts": 0, "need": Wonders.need_pts(wid), "paid": {}, "total": {}, "ok": 1, "since": st.tick, "st": 0}
	Wonders.complete(st, wid, eid, added)
	st.relic_rev += 1
	return added


static func plant(st: GameState, eid: int, pid: int) -> Colony:
	var c := Colony.new()
	c.planet_id = pid
	c.owner = eid
	c.kind = Colony.KIND_COLONY
	c.population = 4
	st.add_colony(c)
	return c


func _test_ruins() -> void:
	var st := T.new_game()
	var ruins: Dictionary = st.wonders.get("ruins", {})
	_ok(ruins.size() >= 1, "des ruines de merveilles gisent dans la galaxie (%d)" % ruins.size())
	if ruins.is_empty():
		return
	var wid := String(ruins.keys()[0])
	var pid := int(ruins[wid])
	_ok(not st.colonies.has(pid), "sur un monde inhabité")
	T.rich(st, 0)
	Research.grant_all(st, 0)
	_ok(Wonders.check_start(st, 0, st.get_empire(0).capital_planet, wid).contains("ruine"), "on ne la bâtit pas ailleurs : il faut la restaurer")
	_ok(SimCommands.validate(st, SimCommands.won_act(0, "restore", wid)).contains("tenir"), "il faut tenir la planète")
	plant(st, 0, pid)
	var why := T.apply(st, SimCommands.won_act(0, "restore", wid))
	_ok(why == "", "restauration lancée (%s)" % why)
	var e := Wonders.build_of(st, 0, wid)
	_ok(not e.is_empty() and int(e["need"]) < Wonders.need_pts(wid), "restaurer est plus court")
	_ok(Wonders.active_count(st, 0) == 0, "hors de la limite des grands chantiers")
	T.days(st, int(Wonders.def(wid)["days"]) + 40)
	_ok(st.colonies[pid].buildings.has(wid) and WondersCatalog.ruin_of(st, wid) < 0, "la merveille est relevée")


func _test_toll() -> void:
	var st := T.new_game()
	var host := st.get_empire(2).capital_planet if st.empires.size() > 2 else st.get_empire(1).capital_planet
	var owner: int = (st.colonies[host] as Colony).owner
	st.colonies[host].buildings.append("grand_caravanserail")
	var sid := st.galaxy.get_planet(host).system_id
	var income := {}
	var routes := [{"kind": "ext", "from": 0, "to": 99, "path": [0, sid, 5], "blocked": false}]
	WondersCatalog.tolls(st, routes, income)
	_ok(int(income.get(owner, {}).get("influence", 0)) == Wonders.r_int("toll_influence"), "le Grand Caravansérail lève un péage sur les routes étrangères")
	income = {}
	routes = [{"kind": "ext", "from": owner, "to": 99, "path": [0, sid, 5], "blocked": false}]
	WondersCatalog.tolls(st, routes, income)
	_ok(income.is_empty(), "pas de péage sur ses propres routes")


func _test_sight() -> void:
	var st := T.new_game()
	var n0 := Fleets.visible_systems(st, 0).size()
	finish(st, 0, st.get_empire(0).capital_planet, "oeil_demiurge")
	_ok(Fleets.visible_systems(st, 0).size() == st.galaxy.systems.size() and n0 < st.galaxy.systems.size(), "l'Œil du Démiurge voit toute la galaxie")
	_ok(Fleets.visible_all(st)[0].size() == st.galaxy.systems.size(), "même résultat par le calcul groupé")
	var st2 := T.new_game()
	finish(st2, 0, st2.get_empire(0).capital_planet, "toile_silence")
	_ok(WondersCatalog.sees_all(st2, 0), "la Toile du Silence voit tous les chantiers")


func _test_known_tech() -> void:
	var st := T.new_game()
	var tid := ""
	for t in Research.visible_ids(st.get_empire(0).faction()):
		if not st.get_empire(0).techs.has(t) and int(Research.tech(t).get("era", 1)) == 1:
			tid = t
			break
	Research.grant(st, 1, [tid])
	if not st.get_empire(0).contacts.has(1):
		st.get_empire(0).contacts.append(1)
	var c0 := Research.cost(st, 0, tid)
	finish(st, 0, st.get_empire(0).capital_planet, "college_universel")
	_ok(Research.cost(st, 0, tid) < c0, "Collège universel : une technologie connue d'un voisin coûte moins (%d -> %d)" % [c0, Research.cost(st, 0, tid)])


func _test_flags() -> void:
	var st := T.new_game()
	var home := st.get_empire(0).capital_planet
	finish(st, 0, home, "menagerie_celeste")
	_ok(not Fauna.species_hostile(st, 0, "nuees"), "Ménagerie céleste : les créatures n'attaquent plus")
	finish(st, 0, home, "rade_franche")
	_ok(Trade.route_loss(st, {"from": 0, "to": 1, "path": [0, 1, 2]}) == 0, "Rade franche : les pirates épargnent vos routes")
	finish(st, 0, home, "academie_amiraute")
	var hid := Heroes.recruit(st, 0, {"name": "Test", "portrait": "", "cls": "stratege", "traits": []})
	_ok(int(st.heroes[hid]["lvl"]) == 2, "Académie d'amirauté : les héros commencent un niveau plus haut")
	finish(st, 0, home, "senat_etoiles")
	_ok(WondersCatalog.voix_pct(st, 0) == 10, "Sénat des étoiles : des voix en plus à l'Amphictyonie")
	_ok(WondersCatalog.check_tribunal(st, 0) != "", "sans le Tribunal, pas de saisine")
	_ok(WondersCatalog.holy_x(st, st.colonies[home], "x") == 1, "sans religions, pas de lieu saint")


func _test_free_tech() -> void:
	var st := T.new_game()
	var n := st.get_empire(0).techs.size()
	finish(st, 0, st.get_empire(0).capital_planet, "calculateur_raison")
	_ok(st.get_empire(0).techs.size() == n + 1, "Calculateur de Raison : une technologie apprise d'office")
	var st2 := T.new_game()
	var eu := st2.get_empire(0).eurekas.size()
	finish(st2, 0, st2.get_empire(0).capital_planet, "observatoire_horizon")
	_ok(st2.get_empire(0).eurekas.size() == eu + 1, "Observatoire de l'Horizon : un eurêka")


func _test_gates() -> void:
	var st := T.new_game()
	var home := st.get_empire(0).capital_planet
	var a := st.galaxy.get_planet(home).system_id
	var far := -1
	var j := FactionTraits.jumps_from(st.galaxy, a)
	for p in st.galaxy.planets:
		if int(j.get(p.system_id, 0)) >= 4 and not st.colonies.has(p.id):
			far = p.id
			break
	var b := st.galaxy.get_planet(far).system_id
	var c := plant(st, 0, far)
	c.kind = Colony.KIND_OUTPOST
	for s in st.galaxy.systems:
		st.get_empire(0).explored[s.id] = true
	finish(st, 0, home, "porte_stellaire")
	finish(st, 0, far, "porte_stellaire")
	_ok(st.galaxy.gates.size() == 2, "deux portes ouvertes")
	var path := Fleets.find_path(st, 0, a, b)
	_ok(path.size() == 1 and path[0] == b, "les flottes sautent d'une porte à l'autre (%s)" % str(path))
	_ok(Fleets.lane_length(st.galaxy, a, b) == WondersCatalog.GATE_LEN, "en un saut d'un jour")
	_ok(Fleets.find_path(st, 1, a, b).size() != 1 or Diplomacy.allied(st, 0, 1), "un étranger sans droit de passage ne les emprunte pas")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	_ok(back != null and back.galaxy.gates.size() == 2, "le réseau des portes se reconstruit au chargement")


func _test_misc() -> void:
	var st := T.new_game(11, {"heroes": true})
	var home := st.get_empire(0).capital_planet
	var sid := st.galaxy.get_planet(home).system_id
	var h := Heroes.at_post(st, "system", sid, 0)
	finish(st, 0, home, "palais_doleances")
	if not h.is_empty():
		_ok((h["traits"] as Array).has("architecte"), "le gouverneur devient Architecte")
	else:
		_ok(Heroes.trait_def("architecte").get("label", "") == "Architecte", "trait Architecte en données")
	_ok(WondersCatalog.fx(st, 0, "grievance_half") > 0, "Palais des Doléances actif")
