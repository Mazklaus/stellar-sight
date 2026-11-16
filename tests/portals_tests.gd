extends RefCounted
## Tests des portails de saut (étude du 2026-11-16, 38 propositions) : données et réglages, trous de ver
## (génération, technologie, découverte, transit, dérive, ancre, méga-vaisseaux), relais hyperspatiaux
## (corridor, accès, entretien), portails de saut (portée, recharge, cristaux, accès, guerre, blocus,
## choc de transit, péage, inhibiteur, raser), ruines, ponts, talents, IA et sauvegarde.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Portails de saut…")
	print("  - data")
	_test_data()
	print("  - modes")
	_test_modes()
	print("  - wormholes")
	_test_wormholes()
	print("  - relays")
	_test_relays()
	print("  - gates")
	_test_gates()
	print("  - save")
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(mode := "complets", seed_value := 41) -> GameState:
	var st := GameState.create(seed_value, 120, 1600.0, "vael", {"ai_level": "", "portals": mode})
	st.fleets.clear()
	return st


static func cap_sys(st: GameState, eid: int) -> int:
	return st.galaxy.get_planet(st.get_empire(eid).capital_planet).system_id


static func colonize(st: GameState, eid: int, sid: int, outpost := true) -> Colony:
	var pid := -1
	for p in st.galaxy.systems[sid].planet_ids:
		if not st.colonies.has(p):
			pid = p
			break
	if pid < 0:
		return null
	var c := Colony.new()
	c.planet_id = pid
	c.owner = eid
	c.population = 0 if outpost else 6
	if outpost:
		c.kind = Colony.KIND_OUTPOST
	st.add_colony(c)
	st.rebuild_ownership()
	return c


## Système libre (sans propriétaire, avec une planète) à exactement d sauts de from.
static func free_at(st: GameState, from: int, d: int, skip: Array = []) -> int:
	var j := FactionTraits.jumps_from(st.galaxy, from)
	var ids := j.keys()
	ids.sort()
	for k in ids:
		var s := int(k)
		if int(j[k]) == d and st.system_owner(s) < 0 and not skip.has(s) and not st.galaxy.systems[s].planet_ids.is_empty() \
				and Portals.wormhole_at(st, s) < 0:
			return s
	return -1


static func reveal(st: GameState, eid: int) -> void:
	var e := st.get_empire(eid)
	for s in st.galaxy.systems:
		e.explored[s.id] = true
	e.path_cache.clear()
	e.path_cache_explored = -1


static func build(st: GameState, sid: int, bid: String) -> void:
	for pid in st.galaxy.systems[sid].planet_ids:
		var c: Colony = st.colonies.get(pid)
		if c != null:
			c.buildings.append(bid)
			break
	Portals.refresh(st)


static func war(st: GameState, a: int, b: int) -> void:
	for p in [[a, b], [b, a]]:
		var e := st.get_empire(p[0])
		if not e.contacts.has(p[1]):
			e.contacts.append(p[1])
	Combat.start_war(st, a, b)


static func run_days(st: GameState, n: int) -> void:
	for i in n:
		st.tick += 1
		FleetSystem.process(st)
		Portals.daily(st)


func _test_data() -> void:
	var d := GameData.portals()
	_ok((d["modes"] as Array).size() == 3 and Portals.default_mode() == "complets", "trois réglages, Complets par défaut")
	for b in ["relais_hyper", "portail_saut", "grand_portail", "portail_ancien", "ancre_ver"]:
		var bd := GameData.building(b)
		_ok(String(bd.get("portals", "")) != "" and not Economy.takes_slot(b), "%s : bâtiment de portail sans emplacement" % b)
		for t in bd.get("requires_tech", []):
			_ok(not Research.tech(String(t)).is_empty(), "%s : la technologie %s existe" % [b, t])
	for t in ["stabilisation_ver", "relais_hyperspatiaux", "portails_saut", "grands_portails"]:
		_ok(not Research.tech(t).is_empty(), "technologie %s" % t)
	_ok(int(Research.tech("stabilisation_ver")["era"]) == 2 and int(Research.tech("portails_saut")["era"]) == 3 and int(Research.tech("grands_portails")["era"]) == 4, "ères 2, 3, 4")
	_ok(String(GameData.building("grand_portail")["upgrades"]) == "portail_saut", "le Grand portail remplace le Portail de saut")


func _test_modes() -> void:
	var off := GameState.create(41, 120, 1600.0, "vael", {"ai_level": ""})
	_ok(not Portals.enabled(off) and off.galaxy.wormholes.is_empty(), "sans le réglage : désactivés, aucun trou de ver")
	_ok(not Portals.building_allowed(off, "portail_saut") and Portals.building_allowed(off, "forum"), "désactivés : pas de bâtiment de portail")
	var simple := new_game("simples")
	_ok(Portals.enabled(simple) and not Portals.full(simple), "Simples")
	_ok(Portals.building_allowed(simple, "relais_hyper") and Portals.building_allowed(simple, "portail_saut") and not Portals.building_allowed(simple, "ancre_ver"), "Simples : relais et portails, pas d'ancre")
	_ok((simple.portals["ruins"] as Dictionary).is_empty(), "Simples : pas de ruines")
	var unstable := 0
	for pr in simple.portals["wh"]:
		unstable += int(pr[2])
	_ok(unstable == 0, "Simples : aucun trou de ver instable")
	var st := new_game()
	_ok(Portals.full(st) and not (st.portals["ruins"] as Dictionary).is_empty(), "Complets : portails anciens en ruine")


func _test_wormholes() -> void:
	var st := new_game()
	var wh: Array = st.portals["wh"]
	_ok(wh.size() == 10, "une paire pour 12 systèmes (%d)" % wh.size())
	var starts := Portals._starts(st)
	var ok_far := true
	var ok_start := true
	for pr in wh:
		var a := int(pr[0])
		var b := int(pr[1])
		if int(FactionTraits.jumps_from(st.galaxy, a).get(b, 0)) < 6:
			ok_far = false
		if starts.has(a) or starts.has(b):
			ok_start = false
	_ok(ok_far, "extrémités à 6 sauts ou plus")
	_ok(ok_start, "jamais sur un système de départ")
	var a0 := int(wh[0][0])
	var b0 := int(wh[0][1])
	_ok(Fleets.lane_length(st.galaxy, a0, b0) == 1 and Portals.is_shortcut(st.galaxy, a0, b0), "un trou de ver : un jour de transit")
	var e := st.get_empire(0)
	reveal(st, 0)
	e.explored.erase(b0)
	_ok(Fleets.find_path(st, 0, a0, b0).size() != 1, "sans la technologie : pas de passage")
	e.techs["stabilisation_ver"] = true
	var out: Array[Dictionary] = []
	Portals._discover(st, out)
	_ok(Portals.known_pair(st, 0, 0) and e.explored.has(b0) and not out.is_empty(), "avec la technologie : la sonde révèle l'autre bout")
	_ok(Fleets.find_path(st, 0, a0, b0) == [b0], "le trajet emprunte le trou de ver")
	var f := st.spawn_ship(0, "scout", a0)
	SimCommands.apply(st, SimCommands.move_fleet(0, f.id, b0))
	run_days(st, 1)
	_ok(f.system_id == b0, "la flotte traverse en un jour")
	_ok(not Portals.wormhole_ok(st, 1, a0), "un empire sans la technologie ne passe pas")
	_ok(Portals.wormhole_ok(st, GameState.FAUNA_ID, a0) and not Portals.gate_ok(st, GameState.FAUNA_ID, a0, b0), "les créatures passent les trous de ver, jamais les portails")
	# Dérive d'un trou de ver instable.
	var pr0: Array = wh[0]
	pr0[2] = 1
	pr0[3] = st.tick + 10
	pr0[4] = 0
	var added: Array[Dictionary] = []
	Portals._drift(st, added)
	_ok(int(pr0[4]) == 1 and not added.is_empty(), "instable : annoncé un an avant")
	st.tick += 11
	Portals._drift(st, added)
	_ok((int(pr0[0]) != a0 or int(pr0[1]) != b0) and not Portals.known_pair(st, 0, 0), "il se referme et se rouvre ailleurs : destination à redécouvrir")
	_ok(int(st.galaxy.wormholes.get(a0, -1)) != b0, "l'ancien passage n'existe plus")


func _test_relays() -> void:
	var st := new_game()
	var e := st.get_empire(0)
	reveal(st, 0)
	var home := cap_sys(st, 0)
	var n1 := -1
	for n in st.galaxy.systems[home].neighbors:
		if st.system_owner(n) < 0 and not st.galaxy.systems[n].planet_ids.is_empty():
			n1 = n
			break
	_ok(n1 >= 0, "un voisin libre")
	colonize(st, 0, n1)
	var plain := Fleets.lane_length(st.galaxy, home, n1)
	var d0 := int(Fleets._dijkstra_raw(st, 0, home)["dist"][n1])
	build(st, home, "relais_hyper")
	build(st, n1, "relais_hyper")
	_ok(Portals.relay_ok(st, 0, home, n1), "corridor entre deux relais")
	var d1 := int(Fleets._dijkstra_raw(st, 0, home)["dist"][n1])
	_ok(d1 == maxi(1, plain / 3) and d1 < d0, "la route compte trois fois moins (%d -> %d)" % [d0, d1])
	_ok(Fleets.lane_length(st.galaxy, home, n1) == plain, "la route elle-même ne change pas")
	var f := st.spawn_ship(0, "scout", home)
	SimCommands.apply(st, SimCommands.move_fleet(0, f.id, n1))
	var slow := Fleets.speed(f, st)
	var days_plain := (plain + slow - 1) / slow
	var days := 0
	while f.system_id != n1 and days < 60:
		run_days(st, 1)
		days += 1
	_ok(days <= maxi(1, (days_plain + 2) / 3), "la flotte va trois fois plus vite (%d jours au lieu de %d)" % [days, days_plain])
	_ok(not Portals.relay_ok(st, 1, home, n1), "un empire sans droit de passage n'en profite pas")
	_ok(Portals.lane_mult(st, 1, home, n1) == 1, "ni vitesse")
	# Entretien : sans cristaux, les relais s'éteignent.
	e.resources["crystals"] = 0
	var added: Array[Dictionary] = []
	Portals._monthly(st, added)
	_ok(not Portals.relay_ok(st, 0, home, n1) and not added.is_empty(), "sans cristaux : relais éteints")
	e.resources["crystals"] = 10
	Portals._monthly(st, added)
	_ok(Portals.relay_ok(st, 0, home, n1) and int(e.resources["crystals"]) == 9, "avec cristaux : un cristal pour deux relais")
	# Tempête gravitationnelle : corridor coupé.
	Portals._sub(st, "cut")[str(n1)] = st.tick + 5
	_ok(not Portals.relay_ok(st, 0, home, n1), "relais coupé (sabotage, résonance, tempête)")


static func gate_pair(st: GameState, eid: int, jumps: int) -> Array:
	var home := cap_sys(st, eid)
	var far := free_at(st, home, jumps)
	if far < 0:
		return []
	colonize(st, eid, far)
	build(st, home, "portail_saut")
	build(st, far, "portail_saut")
	return [home, far]


func _test_gates() -> void:
	var st := new_game()
	var e := st.get_empire(0)
	e.resources["crystals"] = 100
	reveal(st, 0)
	var pr := gate_pair(st, 0, 5)
	_ok(not pr.is_empty(), "deux portails à 5 sauts")
	var home: int = pr[0]
	var far: int = pr[1]
	_ok(Portals.gate_ok(st, 0, home, far), "dans la portée : saut possible")
	_ok(Fleets.find_path(st, 0, home, far) == [far], "le trajet emprunte le portail")
	var f := st.spawn_ship(0, "corvette", home)
	f.ships.append_array(["corvette", "corvette", "corvette", "corvette", "corvette"])
	SimCommands.apply(st, SimCommands.move_fleet(0, f.id, far))
	run_days(st, 1)
	_ok(f.system_id == far, "saut de portail en un jour")
	_ok(int(e.resources["crystals"]) == 98, "6 vaisseaux de guerre : 2 cristaux")
	_ok(int(Portals._sub(st, "cd").get(str(home), 0)) > st.tick, "le portail de départ se recharge")
	_ok(Portals.shock_pct(st, f) == -25, "choc de transit à l'arrivée")
	var g2 := st.spawn_ship(0, "corvette", home)
	SimCommands.apply(st, SimCommands.move_fleet(0, g2.id, far))
	run_days(st, 1)
	_ok(g2.system_id == home and g2.is_moving(), "une autre flotte de guerre attend la recharge")
	var sc := st.spawn_ship(0, "scout", home)
	SimCommands.apply(st, SimCommands.move_fleet(0, sc.id, far))
	run_days(st, 1)
	_ok(sc.system_id == far, "un éclaireur passe sans recharge")
	# Portée.
	var st2 := new_game()
	reveal(st2, 0)
	var pr2 := gate_pair(st2, 0, 8)
	if not pr2.is_empty():
		_ok(not Portals.gate_ok(st2, 0, pr2[0], pr2[1]), "hors de portée (8 sauts pour 6)")
		var c: Colony = null
		for pid in st2.galaxy.systems[pr2[0]].planet_ids:
			if st2.colonies.has(pid):
				c = st2.colonies[pid]
		c.buildings[c.buildings.find("portail_saut")] = "grand_portail"
		var c2: Colony = null
		for pid in st2.galaxy.systems[pr2[1]].planet_ids:
			if st2.colonies.has(pid):
				c2 = st2.colonies[pid]
		c2.buildings[c2.buildings.find("portail_saut")] = "grand_portail"
		Portals.refresh(st2)
		_ok(Portals.gate_ok(st2, 0, pr2[0], pr2[1]), "Grands portails : 10 sauts")
	# Accès : un autre empire, sans droit, ne passe pas ; en guerre non plus, même allié avant.
	_ok(not Portals.gate_ok(st, 1, home, far), "un autre empire sans droit de passage ne passe pas")
	_ok(Portals.may_use(st, 0, 0) and Portals.may_use(st, -1, 1), "les siens, et les portails libres")
	war(st, 0, 1)
	_ok(not Portals.may_use(st, 0, 1), "jamais un ennemi en guerre")
	# Blocus : un ennemi armé à l'arrêt coupe le portail.
	var foe := st.spawn_ship(1, "corvette", far)
	_ok(not Portals.gate_ok(st, 0, home, far), "blocus ennemi : portail coupé")
	st.fleets.erase(foe.id)
	_ok(Portals.gate_ok(st, 0, home, far), "le blocus levé, le portail rouvre")
	# Un seul portail par système.
	var cc: Colony = st.colonies[e.capital_planet]
	e.techs["portails_saut"] = true
	_ok(Portals.check_build(st, 0, cc, "portail_saut") != "", "un seul portail par système")


func _test_save() -> void:
	var st := new_game()
	Portals._sub(st, "cd")["3"] = 99
	var d := st.to_dict()
	_ok(int(d["version"]) >= 82 and d.has("portals"), "sauvegarde 82 avec les portails")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and Portals.mode(back) == "complets", "réglage relu")
	_ok((back.portals["wh"] as Array).size() == (st.portals["wh"] as Array).size() and not back.galaxy.wormholes.is_empty(), "trous de ver relus, réseau reconstruit")
	_ok(int(back.portals["cd"]["3"]) == 99, "recharges relues")
	var off := GameState.create(41, 60, 1200.0, "vael", {"ai_level": ""})
	_ok(not off.to_dict().has("portals"), "désactivés : rien de plus dans la sauvegarde")
