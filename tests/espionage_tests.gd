extends RefCounted
## Tests de l'espionnage, lot 1 (Espionage) : cellules, croissance des réseaux, chiffrement,
## contre-espionnage, paliers (relevés, dossiers), chronique filtrée, sondes, ordres, IA,
## sauvegarde 17, reprise des sauvegardes 16 et déterminisme ; lot 2 : opérations et découverte ;
## lot 3 : talents de peuple, intrigue, réseau retourné. Appelés par smoke_test.gd.

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
	_test_ai_reads_network()
	_test_save()
	_test_old_save()
	_test_determinism()
	_test_operations()
	_test_larcin_sabotage()
	_test_discovery()
	_test_ally_caught()
	_test_ai_ops()
	_test_save_ops()
	_test_talents()
	_test_intrigue()
	_test_turned()


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
	_ok(_part(st, 0, 1, "Contre-espionnage") == -4, "contre-espionnage : -2 par cellule, compté double par l'Inquisition du Chœur")
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
	_ok(int(d["version"]) == GameState.FORMAT_VERSION, "format de sauvegarde à jour")
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


## Les relevés d'un réseau Cartographes nourrissent la mémoire, donc le jugement de l'IA (Intel.owner_in) :
## un système pris en douce hors de vue devient connu de l'espion.
func _test_ai_reads_network() -> void:
	var sim := Simulation.new(_met(41))
	var st := sim.state
	var spy := st.get_empire(0)
	var target := -1
	var vis := Fleets.visible_systems(st, 0)
	for s in st.galaxy.systems:
		if s.planet_count > 0 and st.system_owner(s.id) == -1 and not vis.has(s.id):
			target = s.id
			break
	_ok(target >= 0, "réseau et IA : un système libre hors de vue")
	if target < 0:
		return
	var c := Colony.new()
	c.planet_id = st.galaxy.get_system(target).planet_ids[0]
	c.owner = 1
	c.kind = Colony.KIND_OUTPOST
	st.add_colony(c)
	_ok(Intel.owner_in(st, spy, Intel.seen(st, 0), target) == -1, "réseau et IA : sans réseau, l'espion croit le système libre")
	Espionage.set_cells(st, 0, 1, 1)
	st.networks[Espionage.key(0, 1)]["inf"] = 25
	Espionage.monthly(st)
	_ok(Intel.owner_in(st, spy, Intel.seen(st, 0), target) == 1, "réseau et IA : les Cartographes lui apprennent qui tient le système")


# --- Lot 2 : opérations -------------------------------------------------------------------------

## Réseau de 0 chez 1 au niveau voulu, avec de l'influence pour opérer.
func _ready_net(seed_value: int, inf: int) -> GameState:
	var st := _met(seed_value)
	Espionage.set_cells(st, 0, 1, 1)
	st.networks[Espionage.key(0, 1)]["inf"] = inf
	st.get_empire(0).resources["influence"] = 500
	return st


func _test_operations() -> void:
	var st := _ready_net(50, 25)
	_ok(Espionage.check_op(st, 0, 1, "rapport") == "", "rapport possible au palier Cartographes")
	_ok(Espionage.check_op(st, 0, 1, "siphon") != "", "larcin refusé sous le palier Comptables")
	var ch := Espionage.chances(st, 0, 1, "rapport")
	_ok(int(ch["success"]) == 85 and int(ch["discovery"]) == 10, "briefing : chances de base sans modificateur (%d / %d)" % [ch["success"], ch["discovery"]])
	Espionage.set_cells(st, 1, 1, 2)
	ch = Espionage.chances(st, 0, 1, "rapport")
	_ok(int(ch["discovery"]) == 50 and int(ch["success"]) == 75, "contre-espionnage : +20 découverte par cellule (Inquisition du Chœur), chiffrement : -10 succès (%d / %d)" % [ch["success"], ch["discovery"]])
	Espionage.set_cells(st, 1, 1, 0)
	var cmd := SimCommands.spy_op(0, 1, "rapport")
	_ok(SimCommands.validate(st, cmd) == "", "ordre : lancer un rapport")
	SimCommands.apply(st, cmd)
	_ok(int(st.get_empire(0).resources["influence"]) == 480 and not Espionage.running(st, 0, 1).is_empty(), "rapport lancé, 20 influence payées")
	_ok(SimCommands.validate(st, cmd) != "", "une seule opération à la fois par réseau")
	SimCommands.apply(st, SimCommands.spy_cancel(0, 1))
	_ok(Espionage.running(st, 0, 1).is_empty(), "opération annulée")
	# Résolution : on force les chances pour tester chaque issue.
	var sim := Simulation.new(st)
	SimCommands.apply(st, SimCommands.spy_op(0, 1, "rapport"))
	var op: Dictionary = Espionage.running(st, 0, 1)
	op["success"] = 100
	op["discovery"] = 0
	var before_inf := Espionage.infiltration(st, 0, 1)
	sim.advance(31)
	_ok(Espionage.running(st, 0, 1).is_empty(), "opération terminée à son terme")
	_ok(int(st.get_empire(0).dossiers.get(1, {}).get("tier", 0)) == 4, "rapport réussi : dossier complet")
	_ok(Espionage.infiltration(st, 0, 1) < before_inf + 10, "une réussite consomme de l'infiltration")
	_ok(not Espionage.can_read(st.chronicle.back(), 1) or not String(st.chronicle.back()["text"]).contains("Rapport"), "réussite discrète : la victime n'en sait rien")


func _test_larcin_sabotage() -> void:
	var st := _ready_net(51, 70)
	var e0 := st.get_empire(0)
	var e1 := st.get_empire(1)
	e1.resources["energy"] = 400
	var energy0 := int(e0.resources["energy"])
	SimCommands.apply(st, SimCommands.spy_op(0, 1, "siphon"))
	var op: Dictionary = Espionage.running(st, 0, 1)
	op["success"] = 100
	op["discovery"] = 0
	op["end"] = st.tick
	Espionage.daily(st)
	_ok(int(e1.resources["energy"]) == 320 and int(e0.resources["energy"]) == energy0 + 80, "siphon : 20 % de son énergie passe chez nous")
	# Sabotage d'un chantier.
	var cap: Colony = st.colonies[e1.capital_planet]
	cap.construction = "forum" if GameData.building("forum").size() > 0 else GameData.buildings().keys()[0]
	cap.construction_days = 10
	_ok(Espionage.check_op(st, 0, 1, "sabotage_chantier") == "", "sabotage possible au palier Amirauté (%s)" % Espionage.check_op(st, 0, 1, "sabotage_chantier"))
	SimCommands.apply(st, SimCommands.spy_op(0, 1, "sabotage_chantier"))
	op = Espionage.running(st, 0, 1)
	op["success"] = 100
	op["discovery"] = 0
	op["end"] = st.tick
	Espionage.daily(st)
	_ok(cap.construction_days == 70, "sabotage : 60 jours de retard (%d)" % cap.construction_days)
	# Archives.
	e1.research_progress = 100
	SimCommands.apply(st, SimCommands.spy_op(0, 1, "archives"))
	op = Espionage.running(st, 0, 1)
	op["success"] = 100
	op["discovery"] = 0
	op["end"] = st.tick
	Espionage.daily(st)
	_ok(e1.research_progress == 50, "archives : la moitié du Savoir en cours brûle")


func _test_discovery() -> void:
	var st := _ready_net(52, 45)
	SimCommands.apply(st, SimCommands.spy_op(0, 1, "rapport"))
	var op: Dictionary = Espionage.running(st, 0, 1)
	op["success"] = 0
	op["discovery"] = 100
	op["end"] = st.tick
	Espionage.daily(st)
	_ok(Espionage.infiltration(st, 0, 1) == 15, "démasqué : le réseau perd 30")
	var labels := PackedStringArray()
	for p in Diplomacy.opinion_parts(st, 1, 0):
		labels.append(String(p["label"]))
	_ok(" ".join(labels).contains("pris chez nous"), "la victime s'en souvient")
	_ok(Espionage.has_grief(st, 1, 0), "grief d'un an")
	var cases := Espionage.cases_for(st, 1)
	_ok(cases.size() == 1, "un dossier attend la réponse de la victime (humaine dans ce test)")
	_ok(Espionage.can_read(st.chronicle.back(), 1), "la victime lit la découverte dans sa chronique")
	# Réparation payée.
	var inf0 := int(st.get_empire(0).resources["influence"])
	SimCommands.apply(st, SimCommands.spy_answer(1, int(cases[0]["id"]), "reparation"))
	_ok(int(st.get_empire(0).resources["influence"]) == inf0 - 80, "réparation : 80 influence payées")
	_ok(Espionage.cases_for(st, 1).is_empty(), "dossier clos")
	# Expulsion faute de réponse.
	SimCommands.apply(st, SimCommands.spy_op(0, 1, "rapport"))
	op = Espionage.running(st, 0, 1)
	op["success"] = 0
	op["discovery"] = 100
	op["end"] = st.tick
	Espionage.daily(st)
	st.tick += 30
	Espionage.daily(st)
	_ok(Espionage.cases_for(st, 1).is_empty() and Espionage.infiltration(st, 0, 1) == 0 and Espionage.cells_on(st, 0, 1) == 0, "sans réponse en 30 jours : expulsion")
	# Grief : déclarer la guerre à l'espion pendant une paix n'est pas un parjure.
	Diplomacy._rel_w(st, 0, 1)["pact"] = Diplomacy.PEACE
	Combat.start_war(st, 1, 0)
	var parjure := false
	for m in st.memories:
		if int(m["about"]) == 1 and (String(m["kind"]) == "oathbreaker" or String(m["kind"]) == "broke_treaty"):
			parjure = true
	_ok(not parjure, "grief : rompre la paix avec l'espion n'est pas un parjure")


func _test_ally_caught() -> void:
	var st := _ready_net(53, 45)
	Diplomacy._rel_w(st, 0, 1)["pact"] = Diplomacy.ALLIANCE
	SimCommands.apply(st, SimCommands.spy_op(0, 1, "rapport"))
	var op: Dictionary = Espionage.running(st, 0, 1)
	op["discovery"] = 100
	op["end"] = st.tick
	Espionage.daily(st)
	_ok(not Diplomacy.allied(st, 0, 1), "un allié pris à espionner : l'alliance est rompue")


func _test_ai_ops() -> void:
	var st := _ready_net(54, 50)
	st.get_empire(1).ai_level = "normal"
	st.get_empire(0).ai_level = "normal"
	st.get_empire(0).resources["influence"] = 300
	var ctx := {"state": st, "e": st.get_empire(0), "lv": AiLevels.level("normal"), "ai": AiLevels.personality(st.get_empire(0)), "salt": 0, "intent": ""}
	ctx["lv"] = (ctx["lv"] as Dictionary).duplicate()
	ctx["lv"]["mistake_pct"] = 0
	AiEspionage._operation(ctx)
	_ok(not Espionage.running(st, 0, 1).is_empty(), "l'IA lance une opération quand elle a de quoi (%s)" % str(Espionage.running(st, 0, 1).get("op", "")))
	_ok(AiEspionage.response(st, 1, 0) in ["expel", "reparation"], "l'IA répond à une découverte")
	Combat.start_war(st, 1, 0)
	_ok(AiEspionage.response(st, 1, 0) == "expel", "en guerre, l'IA expulse")


func _test_save_ops() -> void:
	var st := _ready_net(55, 45)
	SimCommands.apply(st, SimCommands.spy_op(0, 1, "rapport"))
	st.spy_cases.append({"id": 99, "victim": 0, "spy": 1, "op": "siphon", "tick": st.tick})
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	_ok(back != null and back.checksum() == st.checksum(), "opérations et dossiers sauvegardés (version %d)" % GameState.FORMAT_VERSION)
	_ok(back != null and back.operations.size() == 1 and String(back.operations[0]["op"]) == "rapport" and back.spy_cases.size() == 1, "opérations relues")


# --- Lot 3 : talents de peuple, intrigue, réseau retourné ------------------------------------------

func _empire_of(st: GameState, faction_id: String) -> int:
	for e in st.empires:
		if e.faction_id == faction_id:
			return e.id
	return -1


func _meet(st: GameState, a: int, b: int) -> void:
	for pair in [[a, b], [b, a]]:
		var e := st.get_empire(pair[0])
		if not e.contacts.has(pair[1]):
			e.contacts.append(pair[1])
			e.contacts.sort()


## Lance une opération de a chez b et la tranche tout de suite, chances forcées.
func _force_op(st: GameState, a: int, b: int, op_id: String, success: int, discovery: int) -> void:
	SimCommands.apply(st, SimCommands.spy_op(a, b, op_id))
	var op: Dictionary = Espionage.running(st, a, b)
	op["success"] = success
	op["discovery"] = discovery
	op["end"] = st.tick
	Espionage.daily(st)


func _count_memories(st: GameState, who: int, about: int, kind: String) -> int:
	var n := 0
	for m in st.memories:
		if int(m["who"]) == who and int(m["about"]) == about and String(m["kind"]) == kind:
			n += int(m["count"])
	return n


func _test_talents() -> void:
	var st := _met(60)
	var oss := _empire_of(st, "ossarane")
	var choeur := _empire_of(st, "choeur")
	var vael := _empire_of(st, "vael")
	var kh := _empire_of(st, "khthari")
	var teyl := _empire_of(st, "teyl")
	_ok(oss >= 0 and choeur >= 0 and vael >= 0 and kh >= 0 and teyl >= 0, "les cinq peuples officiels sont en jeu")
	var era := Research.current_era(st, oss)
	_ok(Espionage.encryption(st, oss) == era + 1, "féodalité : maisons méfiantes, chiffrement +1")
	_ok(Espionage.encryption(st, vael) == Research.current_era(st, vael) - 1, "république : assemblées ouvertes, chiffrement -1")
	_ok(Espionage.decryption(st, teyl) == Research.current_era(st, teyl) + 2 and Espionage.encryption(st, teyl) == Research.current_era(st, teyl) + 2,
			"synthétiques : déchiffrement et chiffrement +2")
	var names := PackedStringArray()
	for tl in Espionage.talent_labels(st, oss):
		names.append(String(tl[0]))
	_ok(names.has("Maisons méfiantes"), "les talents s'affichent par leur nom")
	# Inquisition du Chœur : le contre-espionnage compte double.
	_meet(st, oss, choeur)
	Espionage.set_cells(st, oss, choeur, 2)
	Espionage.set_cells(st, choeur, choeur, 1)
	_ok(_part(st, oss, choeur, "Contre-espionnage") == -4, "foi : une cellule de contre-espionnage compte double (%d)" % _part(st, oss, choeur, "Contre-espionnage"))
	# Conscience distribuée : ses nœuds sont ouverts.
	_meet(st, oss, teyl)
	Espionage.set_cells(st, oss, choeur, 0)
	Espionage.set_cells(st, oss, teyl, 1)
	_ok(_part(st, oss, teyl, "Conscience partagée") == 2, "conscience distribuée : +2 par mois aux réseaux chez elle")
	# La ruche : pas d'intrigue, ni chez elle ni par elle ; les espions pris sont dévorés.
	_meet(st, oss, kh)
	Espionage.set_cells(st, oss, teyl, 0)
	Espionage.set_cells(st, oss, kh, 1)
	st.networks[Espionage.key(oss, kh)]["inf"] = 70
	st.get_empire(oss).resources["influence"] = 900
	_ok(Espionage.check_op(st, oss, kh, "discorde").contains("ruche"), "aucune intrigue ne prend sur une ruche")
	_meet(st, kh, oss)
	Espionage.set_cells(st, kh, oss, 1)
	st.networks[Espionage.key(kh, oss)]["inf"] = 70
	st.get_empire(kh).resources["influence"] = 900
	_ok(Espionage.check_op(st, kh, oss, "heritier").contains("ruche"), "une ruche ne complote pas")
	Espionage.set_cells(st, kh, oss, 0)
	_force_op(st, oss, kh, "rapport", 0, 100)
	_ok(Espionage.cases_for(st, kh).is_empty() and Espionage.infiltration(st, oss, kh) == 0 and Espionage.cells_on(st, oss, kh) == 0,
			"ruche : les espions pris sont dévorés sur-le-champ, sans dossier")
	# République : un espion pris fait scandale (souvenir double).
	_meet(st, oss, vael)
	Espionage.set_cells(st, oss, kh, 0)
	Espionage.set_cells(st, oss, vael, 1)
	st.networks[Espionage.key(oss, vael)]["inf"] = 40
	_force_op(st, oss, vael, "rapport", 0, 100)
	_ok(_count_memories(st, vael, oss, "spy_caught") == 2, "république : le scandale compte double (%d)" % _count_memories(st, vael, oss, "spy_caught"))
	# Foi : un espion infidèle démasqué rallume la ferveur.
	st.get_empire(choeur).fervor = 0
	Espionage.set_cells(st, oss, vael, 0)
	Espionage.set_cells(st, oss, choeur, 1)
	st.networks[Espionage.key(oss, choeur)]["inf"] = 40
	_force_op(st, oss, choeur, "rapport", 0, 100)
	_ok(st.get_empire(choeur).fervor == 10, "foi : un espion infidèle démasqué donne +10 de ferveur (%d)" % st.get_empire(choeur).fervor)


func _test_intrigue() -> void:
	var st := _met(61)
	var oss := _empire_of(st, "ossarane")
	var choeur := _empire_of(st, "choeur")
	var vael := _empire_of(st, "vael")
	_meet(st, choeur, oss)
	_meet(st, oss, vael)
	# Discorde : le Chœur accuse Vael auprès d'Ossarane.
	Espionage.set_cells(st, choeur, oss, 1)
	st.networks[Espionage.key(choeur, oss)]["inf"] = 70
	st.get_empire(choeur).resources["influence"] = 900
	_ok(Espionage.check_op(st, choeur, oss, "discorde") == "", "discorde possible au palier Amirauté (%s)" % Espionage.check_op(st, choeur, oss, "discorde"))
	_ok(Espionage._framed(st, choeur, oss) == vael, "la discorde vise l'ami de la cible, pas l'espion")
	var before := Diplomacy.opinion(st, oss, vael)
	_force_op(st, choeur, oss, "discorde", 100, 0)
	_ok(_count_memories(st, oss, vael, "framed") == 1 and Diplomacy.opinion(st, oss, vael) < before, "discorde : la cible croit que son ami l'espionne")
	_ok(_count_memories(st, oss, choeur, "spy_caught") == 0, "discorde réussie sans être prise : personne ne soupçonne l'espion")
	# Héritier : en secret, et c'est à l'espion qu'il pensera.
	_ok(Diplomacy.has_heir(st, oss), "Ossarane a un héritier")
	var loyalty := st.get_empire(oss).heir_loyalty
	st.networks[Espionage.key(choeur, oss)]["inf"] = 70
	_force_op(st, choeur, oss, "heritier", 100, 0)
	_ok(st.get_empire(oss).heir_loyalty == maxi(0, loyalty - 30) and st.get_empire(oss).heir_suitor == choeur, "héritier corrompu : -30 de loyauté, prétendant = l'espion")
	_ok(_count_memories(st, oss, choeur, "bribed_heir") == 0, "corrompre par le réseau ne laisse pas de souvenir (contrairement à la bourse diplomatique)")
	st.networks[Espionage.key(choeur, oss)]["inf"] = 70
	_ok(Espionage.check_op(st, choeur, vael, "heritier") != "", "pas d'héritier chez une république")


func _test_turned() -> void:
	var st := _ready_net(62, 60)
	Espionage.set_cells(st, 1, 1, 1)
	_force_op(st, 0, 1, "rapport", 0, 100)
	var cases := Espionage.cases_for(st, 1)
	_ok(cases.size() == 1, "un dossier de découverte")
	var cmd := SimCommands.spy_answer(1, int(cases[0]["id"]), "turn")
	_ok(SimCommands.validate(st, cmd) == "", "retourner le réseau : possible avec une cellule chez soi (%s)" % SimCommands.validate(st, cmd))
	SimCommands.apply(st, cmd)
	_ok(Espionage.is_turned(st, 0, 1) and Array(Espionage.turned_by(st, 1)) == [0], "réseau retourné")
	_ok(not Espionage.can_read(st.chronicle.back(), 0), "l'espion n'apprend pas que son réseau est retourné")
	st.networks[Espionage.key(0, 1)]["inf"] = 70
	_ok(not Espionage.private_to(st, [1]).has(0), "un réseau retourné ne lit plus la chronique intérieure")
	var e1 := st.get_empire(1)
	e1.resources["energy"] = 400
	var d := Espionage._report(st, 0, 1, 3)
	_ok(int(d["res"]["energy"]) == 200 and (d["fleets"] as Array).is_empty() and int(d["warships"]) == 0, "dossier arrangé : réserves divisées par deux, aucune flotte")
	_force_op(st, 0, 1, "siphon", 100, 100)
	_ok(int(e1.resources["energy"]) == 400 and Espionage.cases_for(st, 1).is_empty(), "opération par un réseau retourné : rien ne se passe, personne n'est pris")
	var cfg: Dictionary = Espionage.data()["turned"]
	cfg["false_pct"] = 100
	Espionage._record(st, 0, 1)
	var fake := 0
	for sid in EmpireReport.owned_systems(st, 1):
		if int(st.get_empire(0).intel[sid]["info"]["owner"]) == -1:
			fake += 1
	_ok(fake == EmpireReport.owned_systems(st, 1).size() and fake > 0, "relevés faux : ses systèmes paraissent libres")
	cfg["false_pct"] = 50
	# Sauvegarde : le réseau retourné survit.
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	_ok(back != null and Espionage.is_turned(back, 0, 1) and back.checksum() == st.checksum(), "réseau retourné sauvegardé (version %d)" % GameState.FORMAT_VERSION)
	# L'IA Vétéran retourne quand elle le peut.
	e1.ai_level = "veteran"
	_ok(AiEspionage.response(st, 1, 0) == "turn", "l'IA Vétéran retourne le réseau")
	e1.ai_level = "normal"
	_ok(AiEspionage.response(st, 1, 0) != "turn", "l'IA Normale ne retourne pas")
	e1.ai_level = ""
	# L'espion finit par comprendre.
	var keep := [int(cfg["spot_min"]), int(cfg["spot_max"])]
	cfg["spot_min"] = 100
	cfg["spot_max"] = 100
	Espionage.monthly(st)
	cfg["spot_min"] = keep[0]
	cfg["spot_max"] = keep[1]
	_ok(not Espionage.is_turned(st, 0, 1) and Espionage.infiltration(st, 0, 1) == 0 and _count_memories(st, 0, 1, "turned_us") == 1,
			"l'espion découvre la ruse : réseau à zéro, rancune")
	# Sans cellule chez soi, on ne retourne personne.
	var st2 := _ready_net(63, 60)
	_force_op(st2, 0, 1, "rapport", 0, 100)
	_ok(SimCommands.validate(st2, SimCommands.spy_answer(1, int(Espionage.cases_for(st2, 1)[0]["id"]), "turn")) != "", "sans contre-espionnage, pas d'agents doubles")
