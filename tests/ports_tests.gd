extends RefCounted
## Tests des spatioports et du réseau de distribution (étude « Spatioports », 2026-11-16) : données,
## réglages (Désactivée = économie d'avant, Simple sans fret ni guerre), Spatioport de la capitale,
## desserte selon la distance, plancher, enclaves et balises, fret, blocus, réserve et pillage, flux
## (chantiers, nourriture des enclaves), chantier spatial, dépôt de flotte, commerce, droits de port,
## espionnage, événements, talents, IA, bâtiments refusés sans le pilier et sauvegarde.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Spatioports…")
	_test_data()
	_test_modes()
	_test_service()
	_test_enclave_and_beacon()
	_test_freight()
	_test_blockade()
	_test_flows()
	_test_bridges()
	_test_events_and_talents()
	_test_ai_and_build()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(mode := "complet", seed_value := 41, extra := {}) -> GameState:
	var o := {"ai_level": "", "ports": mode}
	o.merge(extra, true)
	return GameState.create(seed_value, 120, 1600.0, "vael", o)


static func cap_sys(st: GameState, eid: int) -> int:
	return st.galaxy.get_planet(st.get_empire(eid).capital_planet).system_id


## Système libre (sans propriétaire, avec une planète) à exactement d sauts de la capitale.
static func free_at(st: GameState, eid: int, d: int, skip: Array = []) -> int:
	var j := FactionTraits.jumps_from(st.galaxy, cap_sys(st, eid))
	var ids := j.keys()
	ids.sort()
	for k in ids:
		var s := int(k)
		if int(j[k]) == d and st.system_owner(s) < 0 and not skip.has(s) and not st.galaxy.systems[s].planet_ids.is_empty():
			return s
	return -1


static func colonize(st: GameState, eid: int, sid: int, pop := 6, outpost := false) -> Colony:
	var c := Colony.new()
	c.planet_id = st.galaxy.systems[sid].planet_ids[0]
	c.owner = eid
	c.population = 0 if outpost else pop
	if outpost:
		c.kind = Colony.KIND_OUTPOST
	st.add_colony(c)
	st.rebuild_ownership()
	return c


func _test_data() -> void:
	var d := GameData.ports()
	_ok((d["modes"] as Array).size() == 3, "trois réglages")
	_ok(Ports.default_mode() == "complet", "Complet par défaut")
	for b in ["spatioport", "grand_port", "balise_fret"]:
		_ok(bool(GameData.building(b).get("ports", false)), "bâtiment %s marqué spatioports" % b)
	_ok(Ports.building_level("comptoir") == 1 and Ports.building_level("spatioport") == 2 and Ports.building_level("grand_port") == 3, "niveaux des ports")
	_ok(Ports.building_level("balise_fret") == 0 and Ports.building_level("forum") == -1, "balise niveau 0, forum n'est pas un port")
	_ok(String(GameData.building("spatioport").get("upgrades", "")) == "comptoir", "le Spatioport remplace le Comptoir")
	_ok(int(GameData.building("spatioport").get("trade_routes", 0)) == 1, "le Spatioport garde sa route commerciale")
	_ok(int(Research.tech("lignes_ravitaillement")["effects"].get("port_range", 0)) == 1, "Lignes de ravitaillement : portée +1")
	_ok(int(Research.tech("bourses")["effects"].get("freight_pct", 0)) == 25, "Bourses : fret +25 %")
	_ok(int(Research.tech("spatioports")["effects"].get("warehouse_pct", 0)) == 100, "Spatioports de transit : entrepôts doublés")


func _test_modes() -> void:
	var off := new_game("desactivee")
	_ok(off.ports.is_empty() and not Ports.enabled(off), "Désactivée : rien ne tourne")
	var any: Colony = off.colonies[off.get_empire(0).capital_planet]
	_ok(Ports.service_pct(off, any) == 100, "Désactivée : desserte 100 %")
	_ok(not any.buildings.has("spatioport"), "Désactivée : pas de Spatioport offert")
	var none := GameState.create(41, 120, 1600.0, "vael", {"ai_level": ""})
	_ok(none.ports.is_empty(), "sans l'option (tests, bancs) : désactivée")
	var simple := new_game("simple")
	_ok(Ports.enabled(simple) and not Ports.full(simple), "Simple : en jeu, pas complet")
	var st := new_game()
	_ok(Ports.full(st), "Complet")
	for e in st.empires:
		if e.capital_planet >= 0:
			_ok((st.colonies[e.capital_planet] as Colony).buildings.has("spatioport"), "%s : la capitale naît avec un Spatioport" % e.short_name())
	_ok(Ports.port_level_at(st, 0, cap_sys(st, 0)) == 2, "la capitale est un port de niveau 2")
	_ok(Ports.linked(st, 0, cap_sys(st, 0)), "le port de la capitale est relié")
	var cap: Colony = st.colonies[st.get_empire(0).capital_planet]
	_ok(Ports.service_pct(st, cap) == 100 and Ports.colony_state(st, cap.planet_id) == Ports.OK, "la capitale est desservie à 100 %")


func _test_service() -> void:
	var st := new_game("simple")
	var near := free_at(st, 0, 2)
	var mid := free_at(st, 0, 4)
	var far := free_at(st, 0, 7)
	_ok(near >= 0 and mid >= 0, "systèmes libres trouvés")
	var cn := colonize(st, 0, near)
	var cm := colonize(st, 0, mid)
	Ports.refresh(st)
	_ok(Ports.service_pct(st, cn) == 100, "à 2 sauts (portée du Spatioport) : 100 %")
	_ok(Ports.service_pct(st, cm) <= 85 and Ports.service_pct(st, cm) >= 50, "à 4 sauts : desserte réduite (%d %%)" % Ports.service_pct(st, cm))
	if far >= 0:
		var cf := colonize(st, 0, far)
		Ports.refresh(st)
		_ok(Ports.service_pct(st, cf) == 50, "loin de tout port : plancher 50 %")
		_ok(Ports.colony_state(st, cf.planet_id) == Ports.ISOLATED, "loin de tout port : Isolée")
	# La production matérielle est réduite, pas le Savoir.
	var y := Economy.colony_yields(st, cm)
	var saved := st.ports
	st.ports = {}
	var y0 := Economy.colony_yields(st, cm)
	st.ports = saved
	var pct := Ports.service_pct(st, cm)
	for r in ["energy", "materials", "food"]:
		if int(y0["gross"].get(r, 0)) > 0:
			_ok(int(y["gross"][r]) == int(y0["gross"][r]) * pct / 100, "%s réduit à la desserte" % r)
	_ok(int(y["gross"].get("knowledge", 0)) == int(y0["gross"].get("knowledge", 0)), "le Savoir ne passe pas par les ports")
	_ok(not Ports.service_parts(st, cm.planet_id).is_empty(), "causes de la desserte affichables")


func _test_enclave_and_beacon() -> void:
	var st := new_game("simple")
	var far := free_at(st, 0, 6)
	if far < 0:
		_ok(true, "(pas de système à 6 sauts : test des enclaves sauté)")
		return
	var cf := colonize(st, 0, far)
	cf.buildings.append("comptoir")
	Ports.refresh(st)
	_ok(Ports.port_level_at(st, 0, far) == 1, "le Comptoir lointain est un port")
	_ok(not Ports.linked(st, 0, far), "trop loin du réseau : port non relié")
	_ok(Ports.colony_state(st, cf.planet_id) == Ports.ENCLAVE, "sa colonie est en enclave")
	_ok(Ports.service_pct(st, cf) == 50, "enclave : plancher")
	# Une chaîne de balises sur le chemin relie le port.
	var j := FactionTraits.jumps_from(st.galaxy, far)
	var used: Array = [far]
	for d in [2, 4]:
		var best := -1
		var ids := j.keys()
		ids.sort()
		var jc := FactionTraits.jumps_from(st.galaxy, cap_sys(st, 0))
		for k in ids:
			var s := int(k)
			if int(jc.get(s, 99)) == d and int(j[k]) == 6 - d and st.system_owner(s) < 0 and not st.galaxy.systems[s].planet_ids.is_empty():
				best = s
				break
		if best >= 0:
			var b := colonize(st, 0, best, 0, true)
			b.buildings.append("comptoir")
			used.append(best)
	Ports.refresh(st)
	if used.size() == 3:
		_ok(Ports.linked(st, 0, far), "relais posés sur le chemin : le port est relié")
		_ok(Ports.service_pct(st, cf) == 100, "port relié : sa colonie est desservie à 100 %")
	else:
		_ok(true, "(chemin sans systèmes libres : relais non testés)")


func _test_freight() -> void:
	var st := new_game()
	var got: Array = []
	for d in [3, 3, 4, 4, 5]:
		var s := free_at(st, 0, d, got)
		if s >= 0:
			colonize(st, 0, s)
			got.append(s)
	Ports.refresh(st)
	var fr := Ports.freight(st, 0)
	_ok(int(fr[0]) > 0, "colonies lointaines : du fret est demandé (%d)" % int(fr[0]))
	_ok(int(fr[1]) >= 8, "le Spatioport de la capitale fournit du fret (%d)" % int(fr[1]))
	_ok(int(fr[2]) == mini(100, int(fr[1]) * 100 / maxi(1, int(fr[0]))), "ratio du fret")
	var simple := new_game("simple")
	_ok(int(Ports.freight(simple, 0)[2]) == 100, "Simple : pas de limite de fret")


func _test_blockade() -> void:
	var st := new_game()
	var cs := cap_sys(st, 0)
	var foe := -1
	for e in st.empires:
		if e.id != 0 and not e.is_npc():
			foe = e.id
			break
	Combat.start_war(st, 0, foe, true)
	var f := st.spawn_ship(foe, "corvette", cs)
	_ok(Combat.is_armed(f), "flotte ennemie armée")
	Ports.refresh(st)
	var n := Ports.node(st, 0, cs)
	_ok(int(n["bk"]) == 1, "flotte ennemie en guerre dans le système : port bloqué")
	_ok(int(n["res"]) > 0 and Ports.linked(st, 0, cs), "le port bloqué vit sur sa réserve")
	var before := int(n["res"])
	st.get_empire(0).resources["energy"] = 500
	var foe_en := int(st.get_empire(foe).resources.get("energy", 0))
	st.tick += 30 - posmod(st.tick, 30)
	var added := Ports.daily(st)
	n = Ports.node(st, 0, cs)
	_ok(int(n["res"]) == before - 30, "un mois de blocus : 30 jours de réserve en moins")
	_ok(int(st.get_empire(foe).resources.get("energy", 0)) > foe_en, "le bloqueur pille le port")
	_ok(added.any(func(a: Dictionary) -> bool: return String(a.get("text", "")).begins_with("Blocus")), "le blocus est annoncé")
	n["res"] = 0
	Ports.refresh(st)
	_ok(not Ports.linked(st, 0, cs), "réserve vide : le port bloqué ne dessert plus")
	var simple := new_game("simple")
	Combat.start_war(simple, 0, foe, true)
	simple.spawn_ship(foe, "corvette", cap_sys(simple, 0))
	Ports.refresh(simple)
	_ok(int(Ports.node(simple, 0, cap_sys(simple, 0))["bk"]) == 0, "Simple : pas de blocus")


func _test_flows() -> void:
	var st := new_game()
	var far := free_at(st, 0, 7)
	if far < 0:
		far = free_at(st, 0, 6)
	var cf := colonize(st, 0, far)
	Ports.refresh(st)
	var cs := Ports.colony_state(st, cf.planet_id)
	_ok(cs != Ports.OK, "colonie lointaine mal desservie")
	var skipped := 0
	for t in 8:
		st.tick = 1200 + t
		if Ports.skip_build(st, cf):
			skipped += 1
	_ok(skipped >= 2, "chantier de bâtiment ralenti (%d jours perdus sur 8)" % skipped)
	var cap: Colony = st.colonies[st.get_empire(0).capital_planet]
	st.tick = 1200
	_ok(not Ports.skip_build(st, cap), "la capitale n'est pas ralentie")
	_ok(Ports.ship_bonus(st, 0, cap_sys(st, 0)) == 1, "Spatioport : un jour de chantier spatial gagné tous les 4 jours")
	st.tick = 1201
	_ok(Ports.ship_bonus(st, 0, cap_sys(st, 0)) == 0, "pas tous les jours")
	# Enclave affamée : colonie en enclave qui ne produit pas sa nourriture.
	cf.buildings.append("comptoir")
	Ports.refresh(st)
	if Ports.colony_state(st, cf.planet_id) == Ports.ENCLAVE:
		cf.population = 40
		Ports._hunger(st)
		var y := Economy.colony_yields(st, cf)
		var diet := FactionTraits.diet(st.get_empire(0).faction())
		_ok(Ports.hungry(st, cf) == (int(y["gross"].get(diet, 0)) < int(y["upkeep"].get(diet, 0))), "enclave : croissance arrêtée si elle ne se nourrit pas")
	_ok(Ports.system_stability_parts(st, cap_sys(st, 0)).is_empty(), "capitale : aucun malus de luxe")


func _test_bridges() -> void:
	var st := new_game("complet", 41, {"logistics": "simple"})
	var cs := cap_sys(st, 0)
	_ok(Ports.depot_at(st, cs, 0), "le Spatioport sert de dépôt de flotte")
	_ok(Logistics.has_depot(st, cs, 0), "la logistique voit ce dépôt")
	_ok(Ports.route_pct(st, 0) == 10, "routes commerciales +10 % (Spatioport)")
	_ok(int(Ports.income(st, 0).get("energy", 0)) >= 2, "droits de port")
	_ok(Ports.dock_fees(st, 0) == 4, "droits de quai pour le privé")
	var inc := Economy.empire_income(st, 0)
	st.ports["mode"] = "simple"
	var inc2 := Economy.empire_income(st, 0)
	st.ports["mode"] = "complet"
	_ok(int(inc["gross"]["energy"]) > int(inc2["gross"]["energy"]), "les droits de port entrent au budget")
	# Espionnage : désorganiser les docks.
	var foe := 1
	_ok(PortsBridges.spy_check(st, foe, 0, "desorganiser_docks") == "", "opération possible contre un port relié")
	PortsBridges.spy_apply(st, foe, 0, {"id": "desorganiser_docks"})
	_ok(int(st.ports["dis"].get(str(cs), 0)) > st.tick, "docks désorganisés pour 60 jours")
	_ok(not Ports.linked(st, 0, cs) or int(Ports.node(st, 0, cs)["res"]) > 0, "un port désorganisé ne compte plus que sur sa réserve")
	var simple := new_game("simple")
	_ok(PortsBridges.spy_check(simple, 1, 0, "desorganiser_docks") != "", "opération refusée sans le mode complet")
	_ok(Ports.route_pct(simple, 0) == 0 and Ports.income(simple, 0).is_empty(), "Simple : pas de ponts")


func _test_events_and_talents() -> void:
	var st := new_game()
	var ev: Dictionary = Ports.cfg("events")
	var keep := int(ev["chance_permil"])
	ev["chance_permil"] = 1000
	var added: Array[Dictionary] = []
	PortsBridges.monthly(st, added)
	ev["chance_permil"] = keep
	_ok(not added.is_empty(), "événement de port tiré (chance forcée)")
	var any := false
	for e in st.empires:
		if not Ports.talent_labels(st, e.id).is_empty():
			any = true
	_ok(any, "au moins un peuple a un talent de port")
	var t: Dictionary = Ports.data()["talents"]
	_ok(int(t["gouvernement"]["ruche"]["range"]) == 1 and bool(t["gouvernement"]["horde"]["enclave_fed"]), "talents : ruche, horde")


func _test_ai_and_build() -> void:
	var st := new_game()
	var off := new_game("desactivee")
	var c: Colony = off.colonies[off.get_empire(0).capital_planet]
	off.get_empire(0).resources["materials"] = 5000
	off.get_empire(0).resources["energy"] = 5000
	_ok(Economy.check_build(off, 0, c.planet_id, "balise_fret").contains("spatioports"), "sans le pilier : bâtiments des ports refusés")
	var near := free_at(st, 0, 3)
	var col := colonize(st, 0, near)
	col.buildings.append("comptoir")
	st.get_empire(0).techs["logistique"] = true
	_ok(Ports.ai_wish(st, 0, col) == "spatioport", "IA : améliorer le Comptoir en Spatioport")
	var far := free_at(st, 0, 7, [near])
	if far >= 0:
		var cf := colonize(st, 0, far)
		Ports.refresh(st)
		_ok(Ports.ai_wish(st, 0, cf) == "comptoir", "IA : un Comptoir pour une colonie isolée")


func _test_save() -> void:
	var st := new_game()
	var far := free_at(st, 0, 5)
	if far >= 0:
		colonize(st, 0, far)
	Ports.refresh(st)
	var d := st.to_dict()
	_ok(int(d["version"]) >= 80, "sauvegarde 80")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(Ports.full(back), "réglage relu")
	_ok(str(Ports.to_dict(back)) == str(Ports.to_dict(st)), "réseau relu à l'identique")
	var off := new_game("desactivee")
	_ok(not off.to_dict().has("ports"), "Désactivée : rien dans la sauvegarde")
