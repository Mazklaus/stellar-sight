extends RefCounted
## Tests de l'espionnage, lot 1 (Espionage) : cellules, croissance des réseaux, chiffrement,
## contre-espionnage, paliers (relevés, dossiers), chronique filtrée, sondes, ordres, IA,
## sauvegarde 17, reprise des sauvegardes 16 et déterminisme. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Espionnage…")
	_test_cells()
	_test_growth()
	_test_counter()
	_test_tiers()
	_test_chronicle()
	_test_probes()
	_test_ai()
	_test_save()
	_test_old_save()
	_test_determinism()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


## Partie sans IA où les empires 0 et 1 se sont rencontrés.
func _met(seed_value: int) -> GameState:
	var st := GameState.create(seed_value, 150, 1800.0, "", {"ai_level": ""})
	for pair in [[0, 1], [1, 0]]:
		var e := st.get_empire(pair[0])
		if not e.contacts.has(pair[1]):
			e.contacts.append(pair[1])
			e.contacts.sort()
	return st


func _part(st: GameState, a: int, b: int, prefix: String) -> int:
	for p in Espionage.growth_parts(st, a, b):
		if String(p[0]).begins_with(prefix):
			return int(p[1])
	return 0


func _test_cells() -> void:
	var st := _met(31)
	_ok(Espionage.cells_total(st, 0) == 2 and Espionage.cells_free(st, 0) == 2, "2 cellules au départ")
	_ok(st.get_empire(0).probes == 2, "2 sondes au départ")
	_ok(Espionage.check_cells(st, 0, 2, 1) != "" or st.get_empire(0).contacts.has(2), "pas de cellule chez un empire jamais rencontré")
	_ok(Espionage.check_cells(st, 0, 1, 3) != "", "pas plus de cellules qu'on n'en a")
	var cmd := SimCommands.spy_cells(0, 1, 2)
	_ok(SimCommands.validate(st, cmd) == "", "ordre : 2 cellules chez le voisin")
	SimCommands.apply(st, cmd)
	_ok(Espionage.cells_on(st, 0, 1) == 2 and Espionage.cells_free(st, 0) == 0, "cellules affectées")
	_ok(SimCommands.validate(st, SimCommands.spy_cells(0, 0, 1)) != "", "plus de cellule libre pour le contre-espionnage")
	SimCommands.apply(st, SimCommands.spy_cells(0, 1, 1))
	_ok(SimCommands.validate(st, SimCommands.spy_cells(0, 0, 1)) == "", "une cellule rappelée se réaffecte chez soi")
	SimCommands.apply(st, SimCommands.spy_cells(0, 1, 0))
	_ok(not st.networks.has(Espionage.key(0, 1)), "réseau vide et sans cellule : effacé")


func _test_growth() -> void:
	var st := _met(32)
	Espionage.set_cells(st, 0, 1, 2)
	var era_gap := Espionage.decryption(st, 0) - Espionage.encryption(st, 1)
	_ok(era_gap == 0 and Espionage.crypto_pct(st, 0, 1) == 100, "même ère, pas de contre-espionnage : 100 %")
	_ok(_part(st, 0, 1, "2 cellules") == 8, "2 cellules × 4 par mois")
	var g := Espionage.growth(st, 0, 1)
	Espionage.monthly(st)
	_ok(Espionage.infiltration(st, 0, 1) == g, "l'infiltration monte de la croissance du mois (%d)" % g)
	Diplomacy._rel_w(st, 0, 1)["trade"] = 1
	_ok(_part(st, 0, 1, "Accord commercial") == 2, "le commerce aide le réseau")
	Diplomacy._rel_w(st, 0, 1)["trade"] = 0
	# Écart d'ère : la table de chiffrement.
	var era_before := Espionage.decryption(st, 0)
	var saved: Dictionary = st.get_empire(0).techs.duplicate()
	var all_techs: Dictionary = Research.data()["technologies"]
	for tid in all_techs:
		if int(all_techs[tid].get("era", 1)) <= 3:
			st.get_empire(0).techs[String(tid)] = true
	_ok(Espionage.decryption(st, 0) >= era_before + 2, "déchiffrement = ère atteinte (%d)" % Espionage.decryption(st, 0))
	_ok(Espionage.crypto_pct(st, 0, 1) == 200, "deux ères d'avance : 200 %")
	st.get_empire(0).techs = saved
	# Sans cellule, le réseau s'étiole.
	Espionage.set_cells(st, 0, 1, 0)
	var before := Espionage.infiltration(st, 0, 1)
	Espionage.monthly(st)
	_ok(Espionage.infiltration(st, 0, 1) == maxi(0, before - 3), "sans cellule : -3 par mois")


func _test_counter() -> void:
	var st := _met(33)
	Espionage.set_cells(st, 0, 1, 2)
	Espionage.set_cells(st, 1, 1, 1)
	_ok(Espionage.encryption(st, 1) == Espionage.decryption(st, 1) + 1, "une cellule chez soi : chiffrement +1")
	_ok(Espionage.crypto_pct(st, 0, 1) == 50, "chiffrement d'avance : 50 %")
	_ok(_part(st, 0, 1, "Contre-espionnage") == -2, "contre-espionnage : -2 par cellule")
	_ok(Espionage.suspected(st, 1).is_empty(), "réseau trop faible : pas soupçonné")
	st.networks[Espionage.key(0, 1)]["inf"] = 25
	_ok(Array(Espionage.suspected(st, 1)) == [0], "réseau au 1er palier : soupçonné")
	Espionage.set_cells(st, 1, 1, 0)
	_ok(Espionage.suspected(st, 1).is_empty(), "sans cellule chez soi : on ne soupçonne rien")


func _test_tiers() -> void:
	var sim := Simulation.new(_met(34))
	var st := sim.state
	sim.advance(3)
	var spy := st.get_empire(0)
	var home1 := st.galaxy.get_planet(st.get_empire(1).capital_planet).system_id
	var pid: int = -1
	for p in st.galaxy.get_system(home1).planet_ids:
		if not st.colonies.has(p):
			pid = p
			break
	Espionage.set_cells(st, 0, 1, 2)
	st.networks[Espionage.key(0, 1)]["inf"] = 10
	Espionage.monthly(st)
	_ok(Espionage.tier(st, 0, 1) == 0 and not spy.dossiers.has(1), "sous 20 : rien")
	st.networks[Espionage.key(0, 1)]["inf"] = 30
	sim.advance(2)
	if pid >= 0:
		var c := Colony.new()
		c.planet_id = pid
		c.owner = 1
		c.kind = Colony.KIND_OUTPOST
		st.add_colony(c)
	Espionage.monthly(st)
	_ok(Espionage.tier(st, 0, 1) == 1, "palier 1 : Cartographes")
	_ok(spy.intel.has(home1) and int(spy.intel[home1]["day"]) == st.tick, "Cartographes : relevé à jour du système d'origine du rival")
	if pid >= 0 and not Intel.is_live(st, 0, home1):
		_ok(Intel.colony_of(st, 0, pid) != null, "Cartographes : la nouvelle revendication apparaît hors de vue")
	_ok(not spy.dossiers.has(1), "palier 1 : pas encore de dossier")
	st.networks[Espionage.key(0, 1)]["inf"] = 45
	Espionage.monthly(st)
	var d: Dictionary = spy.dossiers.get(1, {})
	_ok(int(d.get("tier", 0)) == 2 and d.has("res") and d.has("techs") and not d.has("fleets"), "palier 2 : dossier Comptables, sans les flottes")
	st.networks[Espionage.key(0, 1)]["inf"] = 65
	Espionage.monthly(st)
	d = spy.dossiers.get(1, {})
	_ok(d.has("fleets") and int(d["ships"]) > 0 and not d.has("opinions"), "palier 3 : Amirauté, les flottes")
	st.networks[Espionage.key(0, 1)]["inf"] = 90
	Espionage.monthly(st)
	d = spy.dossiers.get(1, {})
	_ok(d.has("opinions") and d.has("wars"), "palier 4 : Conseil, guerres et opinions")
	_ok(Espionage.infiltration(st, 0, 1) <= 100, "infiltration plafonnée à 100")


func _test_chronicle() -> void:
	var st := GameState.create(35, 150, 1800.0, "", {"ai_level": ""})
	var stranger := -1
	for e in st.empires:
		if e.id != 0 and not st.get_empire(0).contacts.has(e.id) and not st.get_empire(1).contacts.has(e.id) and e.id != 1:
			stranger = e.id
			break
	var entry := st.add_chronicle("Secret de 1", Espionage.private_to(st, [1]))
	_ok(Espionage.can_read(entry, 1) and not Espionage.can_read(entry, 0), "nouvelle intérieure : connue du seul concerné")
	_ok(Espionage.can_read(entry, -1), "le spectateur sans brouillard lit tout")
	st.get_empire(0).contacts.append(1)
	Espionage.set_cells(st, 0, 1, 1)
	st.networks[Espionage.key(0, 1)]["inf"] = 40
	entry = st.add_chronicle("Secret de 1, bis", Espionage.private_to(st, [1]))
	_ok(Espionage.can_read(entry, 0), "réseau Comptables : on lit sa chronique intérieure")
	var pub := st.add_chronicle("Guerre", Espionage.public_to(st, [1, 2]))
	_ok(Espionage.can_read(pub, 0), "nouvelle publique : connue de ceux qui ont rencontré un concerné")
	if stranger >= 0 and stranger != 2:
		_ok(not Espionage.can_read(pub, stranger), "nouvelle publique : inconnue de qui n'a rencontré personne")
	var all := st.add_chronicle("Comète")
	_ok(Espionage.can_read(all, stranger if stranger >= 0 else 3), "événement cosmique : visible de tous")
	var r := Espionage.readable(st, 1, 10)
	_ok(not r.is_empty() and String(r[0]["text"]) == "Comète", "dernières nouvelles lisibles, de la plus récente à la plus ancienne")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	_ok(back != null and back.chronicle.back().get("who", null) == null and (back.chronicle[back.chronicle.size() - 2]["who"] as Array) == pub["who"],
			"destinataires de la chronique sauvegardés")


func _test_probes() -> void:
	var sim := Simulation.new(GameState.create(36, 150, 1800.0, "", {"ai_level": ""}))
	var st := sim.state
	var e := st.get_empire(0)
	var target := -1
	for sid in e.sorted_explored():
		if not Intel.is_live(st, 0, sid):
			target = sid
			break
	if target < 0:
		# Un système aperçu puis perdu de vue.
		for s in st.galaxy.systems:
			if not Fleets.visible_systems(st, 0).has(s.id):
				var f := st.spawn_ship(0, "scout", s.id)
				sim.step()
				st.fleets.erase(f.id)
				sim.step()
				target = s.id
				break
	_ok(target >= 0, "un système connu hors de vue pour la sonde")
	if target < 0:
		return
	var home := st.galaxy.get_planet(e.capital_planet).system_id
	_ok(Espionage.check_probe(st, 0, home) != "", "pas de sonde vers un système en vue")
	var energy := int(e.resources["energy"])
	sim.advance(5)
	energy = int(e.resources["energy"])
	var cmd := SimCommands.probe(0, target)
	_ok(SimCommands.validate(st, cmd) == "", "sonde : ordre valide (%s)" % SimCommands.validate(st, cmd))
	SimCommands.apply(st, cmd)
	_ok(e.probes == 1 and int(e.resources["energy"]) == energy - 10, "sonde : une de moins, 10 énergie payées")
	_ok(int(e.intel[target]["day"]) == st.tick, "sonde : relevé daté d'aujourd'hui")
	SimCommands.apply(st, SimCommands.probe(0, target))
	_ok(e.probes == 0 and SimCommands.validate(st, cmd) != "", "plus de sonde : ordre refusé")
	sim.advance(95)
	_ok(e.probes == 1, "une sonde revient en 90 jours")


func _test_ai() -> void:
	var st := _met(37)
	_ok(AiEspionage.plan(st, st.get_empire(1), 0) == {0: 2}, "Recrue : tout chez le premier empire rencontré")
	var p := AiEspionage.plan(st, st.get_empire(1), 1)
	_ok(int(p.get(1, 0)) == 1 and int(p.get(0, 0)) == 1, "IA : une cellule chez soi, une chez le voisin")
	var none := GameState.create(37, 150, 1800.0, "", {"ai_level": ""})
	none.get_empire(1).contacts.clear()
	_ok(AiEspionage.plan(none, none.get_empire(1), 2).is_empty(), "IA sans contact : aucune cellule")


func _test_save() -> void:
	var sim := Simulation.new(_met(38))
	var st := sim.state
	Espionage.set_cells(st, 0, 1, 2)
	st.networks[Espionage.key(0, 1)]["inf"] = 61
	sim.advance(31)
	_ok(st.get_empire(0).dossiers.has(1), "dossier tenu avant sauvegarde")
	var d := st.to_dict()
	_ok(int(d["version"]) == 17, "format de sauvegarde 17")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null, "sauvegarde 17 relue (%s)" % GameState.last_error)
	if back == null:
		return
	_ok(back.checksum() == st.checksum(), "même empreinte après aller-retour (réseaux, dossiers, sondes)")
	_ok(Espionage.infiltration(back, 0, 1) == Espionage.infiltration(st, 0, 1) and back.get_empire(0).dossiers.has(1), "réseau et dossier relus")
	var b := Simulation.new(back)
	sim.advance(60)
	b.advance(60)
	_ok(sim.state.checksum() == b.state.checksum(), "la partie rechargée continue à l'identique")


func _test_old_save() -> void:
	var st := GameState.create(39)
	Simulation.new(st).advance(10)
	var d := st.to_dict()
	d["version"] = 16
	d.erase("networks")
	for e: Dictionary in d["empires"]:
		e.erase("probes")
		e.erase("probe_day")
		e.erase("dossiers")
	for c: Dictionary in d["chronicle"]:
		c.erase("who")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null, "sauvegarde 16 toujours lisible (%s)" % GameState.last_error)
	if back == null:
		return
	_ok(back.networks.is_empty() and back.get_empire(0).probes == 2, "sauvegarde 16 : aucun réseau, sondes de départ")
	_ok(Espionage.readable(back, 0, 3).size() == mini(3, back.chronicle.size()), "sauvegarde 16 : la vieille chronique reste lisible de tous")


func _test_determinism() -> void:
	var a := Simulation.new(GameState.create(40))
	var b := Simulation.new(GameState.create(40))
	a.advance(240)
	b.advance(240)
	_ok(a.state.checksum() == b.state.checksum(), "espionnage : deux parties de même graine identiques")
	var used := false
	for e in a.state.empires:
		if e.is_ai() and Espionage.cells_used(a.state, e.id) > 0:
			used = true
	_ok(used, "les IA affectent leurs cellules")
