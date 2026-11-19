extends RefCounted
## Tests des peuples insolites, lot 1 (étude « Les 15 peuples insolites et le 9e peuple », prop. 1 à 34,
## 106 à 111 pour leur part) : fiches et briques, tirage des rivaux, population portée, Flotte-Exode,
## Cirque Zambalù (Grand Spectacle, Grand Numéro), Orbe-Monde Halcyre (Allumage), Hardes de Kraal,
## choc des tons Zambalù / Chœur, partie de 10 ans jouée par l'IA, déterminisme, sauvegarde 101.

const ODD := ["exode", "zambalu", "halcyre", "kraal"]

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Peuples insolites (lot 1)…")
	_test_data()
	_test_rivals()
	_test_found()
	_test_exode()
	_test_zambalu()
	_test_halcyre()
	_test_kraal()
	_test_tones()
	_test_commands()
	_test_ai_game()


func _ok(cond: bool, what: String) -> void:
	print("  ", "ok " if cond else "KO ", what)
	_check.call(cond, what)


func _game(seed_value := 11, player := "ossarane", rivals: Array = ODD) -> GameState:
	var r: Array = rivals.duplicate()
	return GameState.create(seed_value, 150, 1800.0, player, {"ai_level": "", "rivals": r})


func _eid(st: GameState, faction: String) -> int:
	for e in st.empires:
		if e.faction_id == faction:
			return e.id
	return -1


func _contact(st: GameState, a: int, b: int) -> void:
	for p in [[a, b], [b, a]]:
		if not st.get_empire(p[0]).contacts.has(p[1]):
			st.get_empire(p[0]).contacts.append(p[1])


func _test_data() -> void:
	_ok(GameData.classic_faction_ids().size() == 8, "les huit peuples classiques restent à part")
	var odd := GameData.insolite_faction_ids()
	var all_ok := true
	for fid in ODD:
		var f := GameData.faction(fid)
		all_ok = all_ok and odd.has(fid) and bool(f.get("insolite", false)) and String(f.get("broken_rule", "")) != "" \
				and Insolites.kind_of_faction(f) == fid and not FactionTraits.species(f).is_empty()
	_ok(all_ok, "quatre peuples sans monde : fiche insolite, règle cassée, sorte nomade, espèce construite")
	var spawn_ok := true
	for sid in ["nef_cite", "cite_chapiteau", "orbe_monde", "kraal_petit", "kraal_ancien"]:
		spawn_ok = spawn_ok and bool(GameData.ship(sid).get("spawn_only", false))
	_ok(spawn_ok and not bool(GameData.ship("troupe_cirque").get("spawn_only", false)), "cités mobiles et Kraal ne se construisent pas ; la Troupe si")
	_ok(not Victory.info("allumage").is_empty() and (Victory.info("allumage").get("requires", {}).get("archetype", []) as Array).has("planete_etre"), "victoire de peuple : l'Allumage (Orbe-Monde)")
	_ok(FaithWars.nature_def("grand_spectacle").get("label", "") == "Grand Spectacle", "nature de foi « le Grand Spectacle » au catalogue ouvert")


func _test_rivals() -> void:
	var m := MainMenu.new()
	m.slots = MainMenu.random_slots()
	m.insolites_mode = "aucun"
	var s0 := m.empire_setup("ossarane", 3)
	var none := true
	for fid in s0["rivals"]:
		none = none and not GameData.insolite_faction_ids().has(fid)
	_ok(none, "réglage Aucun : seuls des peuples classiques sont tirés")
	m.insolites_mode = "quelques"
	var n_odd := 0
	for seed_value in 12:
		var s := m.empire_setup("ossarane", seed_value)
		var k := 0
		for fid in s["rivals"]:
			if GameData.insolite_faction_ids().has(fid):
				k += 1
		n_odd = maxi(n_odd, k)
	_ok(n_odd >= 1 and n_odd <= 2, "réglage Quelques-uns : un tiers des places tirées au plus (vu %d)" % n_odd)
	m.insolites_mode = "tous"
	var s2 := m.empire_setup("ossarane", 5)
	var k2 := 0
	for fid in s2["rivals"]:
		if GameData.insolite_faction_ids().has(fid):
			k2 += 1
	_ok(k2 == mini((s2["rivals"] as Array).size(), GameData.insolite_faction_ids().size()), "réglage Tous : les insolites d'abord (%d)" % k2)
	_ok(MainMenu.insolites_default() == "quelques", "Quelques-uns par défaut")
	m.free()
	var st := GameState.create(3, 150, 1800.0, "ossarane", {"ai_level": ""})
	var classic := true
	for e in st.empires:
		classic = classic and not Insolites.is_nomad(st, e.id)
	_ok(classic and st.insolites.is_empty(), "partie par défaut : aucun insolite, aucun état (référence de déterminisme intacte)")


func _test_found() -> void:
	var st := _game()
	var ok := true
	for fid in ODD:
		var eid := _eid(st, fid)
		ok = ok and eid >= 0 and Insolites.kind(st, eid) == fid and Stability.colony_systems(st, eid) == 0 \
				and Insolites.carried_pop(st, eid) > 0 and Insolites.keeps_alive(st, eid)
	_ok(ok, "chaque peuple sans monde démarre sans colonie, avec sa population portée")
	var ps := Victory.population_share(st, _eid(st, "zambalu"))
	_ok(ps[1] > 0 and ps[0] > ps[1], "la population portée compte dans la part galactique")
	_ok(FactionTraits.city_fleet(st, _eid(st, "exode")) != null and FactionTraits.city_fleet(st, _eid(st, "exode")).count("nef_cite") == 4, "l'Exode part avec quatre Nefs-cités")
	_ok(InsHalcyre.orbe(st, _eid(st, "halcyre")) != null and InsHalcyre.mass(st, _eid(st, "halcyre")) == Insolites.c_int("halcyre", "start_mass"), "Halcyre : l'Orbe et sa Masse de départ")
	_ok(InsKraal.herd_pop(st, _eid(st, "kraal")) > 0, "Kraal : la harde est la population")


func _test_exode() -> void:
	var st := _game(21)
	var eid := _eid(st, "exode")
	var ed := Insolites.emp(st, eid)
	var inc := Insolites.income(st, eid)
	_ok(int(inc.get("food", 0)) > 0 or int(inc.get("knowledge", 0)) > 0, "les nefs au mouillage produisent")
	# Traqueurs : deux ans au même mouillage.
	var cf := FactionTraits.city_fleet(st, eid)
	ed["anc"] = {"s": cf.system_id, "t": st.tick - Insolites.c_int("exode", "stalk_days")}
	var added: Array[Dictionary] = []
	var hope := int(ed["hope"])
	InsExode.daily(st, eid, ed, false, added)
	_ok((ed["hunters"] as Array).size() == 1 and int(ed["hope"]) < hope, "deux ans au même mouillage : les Traqueurs frappent, l'Espoir baisse")
	var hf: Fleet = st.fleets[int(ed["hunters"][0]["f"])]
	_ok(hf.owner == GameState.NPC_ID and hf.system_id == cf.system_id, "les Traqueurs surgissent dans le système du mouillage")
	# Nef perdue.
	var pop := int(ed["pop"])
	cf.remove_at(cf.ships.find("nef_cite"))
	InsExode.daily(st, eid, ed, false, added)
	_ok(int(ed["pop"]) < pop and int(ed["nefs"]) == 3, "une Nef-cité perdue emporte sa population")
	# L'Arrivée.
	_ok(InsExode.check_settle(st, eid) != "", "pas d'Arrivée sans les Chants de la route")
	st.get_empire(eid).techs["terre_promise"] = true
	var pid := Victory.promised_planet(st, eid)
	_ok(pid >= 0, "l'Exode a une Terre promise")
	if pid < 0:
		return
	var sid := st.galaxy.get_planet(pid).system_id
	cf.system_id = sid
	cf.path.clear()
	if st.colonies.has(pid):
		st.colonies.erase(pid)
	st.rebuild_ownership()
	var why := InsExode.check_settle(st, eid)
	_ok(why == "", "nefs au-dessus de la Terre promise : l'Arrivée est possible (%s)" % why)
	if why != "":
		return
	InsExode.settle(st, eid, added)
	var c: Colony = st.colonies.get(pid)
	_ok(InsExode.arrived(st, eid) and c != null and c.owner == eid and st.get_empire(eid).capital_planet == pid, "l'Arrivée : une capitale sur la Terre promise")
	_ok(not Insolites.yard_allowed(st, eid), "posé, l'Exode perd le chantier embarqué")
	var pr := Victory.progress(st, eid, "terre_promise")
	_ok(not (pr["lines"] as Array).is_empty(), "la victoire de la Terre promise suit l'Exode")


func _test_zambalu() -> void:
	var st := _game(31)
	var z := _eid(st, "zambalu")
	var host := _eid(st, "ossarane")
	var ed := Insolites.emp(st, z)
	_contact(st, z, host)
	var hc := st.get_empire(host).capital_planet
	var sid := st.galaxy.get_planet(hc).system_id
	var tr := st.spawn_ship(z, "troupe_cirque", sid)
	_ok(InsZambalu.is_troupe(tr) and InsZambalu.host_of(st, z, sid) == host, "une Troupe chez un hôte en paix")
	st.get_empire(host).resources["energy"] = 500
	var e_before := int(st.get_empire(z).resources.get("energy", 0))
	var added: Array[Dictionary] = []
	for _d in Insolites.c_int("zambalu", "show_days") + 1:
		InsZambalu._show_day(st, z, ed, tr, host, added)
	_ok(int(st.get_empire(z).resources.get("energy", 0)) == e_before + Insolites.c_int("zambalu", "show_ticket"), "représentation de 60 jours : la billetterie est payée par l'hôte")
	_ok(int((st.insolites.get("stage", {}) as Dictionary).get(str(sid), 0)) > st.tick, "la scène reste : stabilité chez l'hôte")
	# Grand Spectacle : l'hôte suit une foi de cette nature.
	st.faith_on = true
	if not st.faiths.has("list"):
		st.faiths = {"list": {}, "state": {}, "next": 1}
	st.faiths["list"]["f9"] = {"name": "Liturgie des Lumières", "founder": host, "holy": hc, "founded": 0, "via": "origine", "precepts": [], "slots": 1,
			"color": "#ffffff", "zeal": 50, "nature": "grand_spectacle", "doctrines": {}, "offer": [], "pending": 0, "excom": {}, "council_next": 0}
	st.faiths["state"][str(host)] = "f9"
	var cap: Colony = st.colonies[hc]
	cap.faith = {Faiths.NATIVE: cap.population}
	st.insolites["stage"] = {}
	e_before = int(st.get_empire(z).resources.get("energy", 0))
	for _d in Insolites.c_int("zambalu", "show_days") + 1:
		InsZambalu._show_day(st, z, ed, tr, host, added)
	_ok(int(cap.faith.get("f9", 0)) == 1, "Grand Spectacle : la représentation convertit un habitant")
	_ok(int(st.get_empire(z).resources.get("energy", 0)) == e_before + 2 * Insolites.c_int("zambalu", "show_ticket"), "Grand Spectacle : billetterie doublée par les fidèles")
	_ok(FaithNatures.source_x(st, cap, "f9") >= 2, "Grand Spectacle : la scène prêche comme un monde saint")
	# Tournée triomphale.
	var war := _game(32)
	var z2 := _eid(war, "zambalu")
	var foe := _eid(war, "ossarane")
	_contact(war, z2, foe)
	Combat.start_war(war, z2, foe)
	var fsid := war.galaxy.get_planet(war.get_empire(foe).capital_planet).system_id
	var tour := war.spawn_ship(z2, "troupe_cirque", fsid)
	tour.add_ship("corvette")
	var ed2 := Insolites.emp(war, z2)
	for _d in Insolites.c_int("zambalu", "tour_days") + 1:
		InsZambalu._tour_day(war, z2, ed2, tour, foe, added)
	var fan := Insolites.implants_of(war, z2)
	_ok(fan.size() == 1 and (war.colonies[fan[0]] as Colony).owner == foe, "Tournée triomphale : un Fan-club, la colonie reste à son maître")
	var inc_before := int(war.get_empire(z2).resources.get("energy", 0))
	Insolites._implant_month(war, added)
	_ok(int(war.get_empire(z2).resources.get("energy", 0)) > inc_before, "le Fan-club verse sa dîme")
	war.get_empire(foe).resources["influence"] = 500
	_ok(Insolites.check_purge(war, foe, fan[0]) == "", "l'hôte peut purger le Fan-club")
	Insolites.purge(war, foe, fan[0], added)
	_ok(Insolites.implants_of(war, z2).is_empty(), "purgé, le Fan-club disparaît")
	# Grand Numéro.
	var num: Dictionary = ed["num"]
	num["call"] = st.tick + 30
	_ok(InsZambalu.open_call(st) == z and InsZambalu.check_delegate(st, host) == "", "le Grand Numéro est annoncé : un délégué peut partir")
	InsZambalu.delegate(st, host)
	_ok(InsZambalu.check_delegate(st, host) != "", "un seul délégué par empire")


func _test_halcyre() -> void:
	var st := _game(41)
	var h := _eid(st, "halcyre")
	var ed := Insolites.emp(st, h)
	var o := InsHalcyre.orbe(st, h)
	_ok(InsHalcyre.damage_pct(st, o) > 0, "la Masse frappe : bonus de dégâts de l'Orbe")
	# Lune-sentinelle sur un corps libre du système.
	var free := -1
	for pid in st.galaxy.systems[o.system_id].planet_ids:
		if not st.colonies.has(pid) and not Insolites.is_eaten(st, pid):
			free = pid
			break
	if free >= 0:
		var m0 := InsHalcyre.mass(st, h)
		var why := InsHalcyre.check_sentinel(st, h, free)
		_ok(why == "", "Lune-sentinelle possible sur un corps libre (%s)" % why)
		if why == "":
			var added: Array[Dictionary] = []
			InsHalcyre.sentinel(st, h, free, added)
			_ok((st.colonies[free] as Colony).owner == h and InsHalcyre.mass(st, h) == m0 - Insolites.c_int("halcyre", "sentinel_mass"), "la Lune-sentinelle coûte de la Masse et tient le système")
	# Allumage fabriqué.
	_ok(not Victory.progress(st, h, "allumage")["cond"], "pas d'Allumage au départ")
	st.get_empire(h).techs["allumage"] = true
	ed["pop"] = Insolites.c_int("halcyre", "ignition_mass")
	ed["sp"] = {st.get_empire(h).faction_id: int(ed["pop"])}
	var pr := Victory.progress(st, h, "allumage")
	_ok(bool(pr["cond"]), "Allumage : Masse atteinte, sans siège, le compte à rebours tourne")
	var foe := _eid(st, "ossarane")
	_contact(st, h, foe)
	Combat.start_war(st, h, foe)
	var siege := st.spawn_ship(foe, "croiseur", o.system_id)
	for _i in 30:
		siege.add_ship("croiseur")
	_ok(InsHalcyre.besieged(st, h) and not Victory.progress(st, h, "allumage")["cond"], "assiégé, l'Orbe ne peut pas s'allumer")


func _test_kraal() -> void:
	var st := _game(51)
	var k := _eid(st, "kraal")
	var herd: Fleet = null
	for f in Fleets.empire_fleets(st, k):
		if InsKraal.kraal_count(f) > 0:
			herd = f
	_ok(herd != null and InsKraal.breeders(herd) >= 2, "la harde a ses reproducteurs")
	var pop := InsKraal.herd_pop(st, k)
	herd.add_ship("kraal_ancien")
	_ok(InsKraal.herd_pop(st, k) == pop + int(Insolites.cfg("kraal")["age_pop"]["kraal_ancien"]), "un Kraal de plus, c'est de la population en plus")
	var ok_explore := false
	for s in st.galaxy.systems:
		if s.id != herd.system_id and st.get_empire(k).explored.has(s.id):
			ok_explore = true
			break
	_ok(ok_explore, "mémoire ancestrale : la harde connaît les routes alentour")
	# Carcasse : un Kraal tué laisse des matériaux.
	_ok(int(GameData.ship("kraal_adulte").get("carcass", {}).get("materials", 0)) > 0, "un Kraal mort laisse une carcasse")
	_ok(bool(GameData.ship("kraal_adulte").get("unboardable", false)), "un Kraal ne s'aborde pas")
	_ok(InsKraal.check_pilot(st, k, herd.id) != "", "pas de Pilote sans colonie ennemie dans le système")
	# Moisson fabriquée : Kraal se nourrissent des populations prises.
	st.get_empire(k).techs["grande_moisson"] = true
	st.get_empire(k).stats["digested"] = 9999
	for _i in 200:
		herd.add_ship("kraal_ancien")
	var pr := Victory.progress(st, k, "moisson")
	_ok(bool(pr["cond"]), "Moisson des Kraal : la harde compte comme part de population galactique")


func _test_tones() -> void:
	var st := _game(61, "choeur", ["zambalu", "vael"])
	var z := _eid(st, "zambalu")
	var c := _eid(st, "choeur")
	var labels := []
	for p in Diplomacy.opinion_parts(st, c, z):
		labels.append(String(p["label"]))
	_ok(labels.has("Le Cirque a mis l'Hymne éternel en comédie musicale"), "choc des tons Chœur / Zambalù dans l'opinion")
	var added: Array[Dictionary] = []
	Events.on_contact(st, st.get_empire(c), st.get_empire(z), added)
	var got := false
	for it in Events.meta(st, c).get("inbox", []):
		if String(it.get("card", "")) == "t_hymne_chapiteau":
			got = true
	_ok(not Events.enabled(st) or got, "premier contact : la carte « l'Hymne et le Chapiteau », avant celle des registres")


func _test_commands() -> void:
	var st := _game(71)
	var z := _eid(st, "zambalu")
	var cmd := SimCommands.ins_act(z, "build", {"ship": "troupe_cirque"})
	st.get_empire(z).resources["materials"] = 500
	st.get_empire(z).resources["energy"] = 500
	_ok(SimCommands.validate(st, cmd) == "", "le Chapiteau construit une Troupe")
	SimCommands.apply(st, cmd)
	_ok(SimCommands.validate(st, cmd) != "", "un vaisseau à la fois dans le chantier embarqué")
	_ok(SimCommands.validate(st, SimCommands.ins_act(z, "build", {"ship": "nef_cite"})) != "", "une cité mobile ne se construit pas")
	_ok(SimCommands.validate(st, SimCommands.ins_act(_eid(st, "kraal"), "build", {"ship": "corvette"})) != "", "les Kraal ne construisent rien")
	var col := -1
	for pid in st.colonies:
		if (st.colonies[pid] as Colony).owner == _eid(st, "ossarane"):
			col = pid
			break
	_ok(Fleets.check_build_ship(st, _eid(st, "ossarane"), col, "orbe_monde") != "", "les vaisseaux d'apparition ne passent pas par un chantier planétaire")


func _test_ai_game() -> void:
	var opts := {"spectator": true, "ai_level": "normal", "rivals": ["exode", "zambalu", "halcyre", "kraal", "ossarane", "vael"]}
	var st := GameState.create(7, 150, 1800.0, "", opts.duplicate(true))
	var sim := Simulation.new(st)
	var start_sid := FactionTraits.city_fleet(st, _eid(st, "exode")).system_id
	var m0 := InsHalcyre.mass(st, _eid(st, "halcyre"))
	var alive5 := true
	var early_win := false
	var exode_moved := false
	for d in 3600:
		sim.step()
		if not exode_moved:
			var cf := FactionTraits.city_fleet(st, _eid(st, "exode"))
			exode_moved = cf != null and cf.system_id != start_sid
		if d == 1799:
			for fid in ODD:
				alive5 = alive5 and not st.get_empire(_eid(st, fid)).eliminated
		if not st.winner.is_empty():
			early_win = true
	_ok(alive5, "les quatre peuples sans monde survivent jusqu'à l'an 5")
	_ok(not early_win, "aucune victoire en 10 ans")
	_ok(exode_moved, "IA : l'Exode lève l'ancre")
	_ok(int(st.get_empire(_eid(st, "zambalu")).stats.get("shows", 0)) > 0, "IA : le Cirque donne des représentations")
	_ok(InsHalcyre.mass(st, _eid(st, "halcyre")) > m0, "IA : l'Orbe-Monde mange et grossit")
	_ok(not (Insolites.emp(st, _eid(st, "kraal"))["known"] as Dictionary).is_empty() and InsKraal.herd_pop(st, _eid(st, "kraal")) > 0, "IA : la harde connaît des pâturages et vit")
	var d1 := st.to_dict()
	var st2 := GameState.from_dict(JSON.parse_string(JSON.stringify(d1)))
	_ok(st2 != null and int(d1.get("version", 0)) == 101 and JSON.stringify(st2.to_dict()) == JSON.stringify(d1), "sauvegarde 101 relue à l'identique")
	# Déterminisme : deux parties identiques de 2 ans.
	var a := GameState.create(9, 120, 1600.0, "", opts.duplicate(true))
	var b := GameState.create(9, 120, 1600.0, "", opts.duplicate(true))
	var sa := Simulation.new(a)
	var sb := Simulation.new(b)
	for _d in 720:
		sa.step()
		sb.step()
	_ok(JSON.stringify(a.to_dict()) == JSON.stringify(b.to_dict()), "déterminisme : deux parties identiques restent identiques")
