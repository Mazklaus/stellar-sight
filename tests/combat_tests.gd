extends RefCounted
## Tests du combat spatial : règles (Combat), batailles, blocus, sièges, invasions, traits de peuple,
## sauvegarde et déterminisme. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Combat spatial…")
	_test_data()
	_test_damage_rules()
	_test_declare_war()
	_test_battle_basic()
	_test_battle_odds()
	_test_battle_determinism_and_save()
	_test_blockade()
	_test_retreat()
	_test_siege_and_invasion()
	_test_elimination()
	_test_khthari()
	_test_faction_bonuses()
	_test_merge_split_repair()
	_test_ai_war()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


## Partie sans IA (les rivaux restent inertes), seule la faction du joueur est choisie.
func _state(seed_value := 4242, faction := "ossarane") -> GameState:
	return GameState.create(seed_value, 150, 1800.0, faction, {"ai_level": ""})


func _home(st: GameState, empire_id: int) -> int:
	return st.galaxy.get_planet(st.get_empire(empire_id).capital_planet).system_id


## Un système sans propriétaire, loin des capitales.
func _empty_system(st: GameState) -> int:
	for s in st.galaxy.systems:
		if st.system_owner(s.id) == -1 and s.neighbors.size() >= 2:
			var near := false
			for e in st.empires:
				if e.capital_planet >= 0 and _home(st, e.id) == s.id:
					near = true
			if not near:
				return s.id
	return -1


## Retire toutes les flottes de départ (éclaireurs, vaisseaux colons) pour des tests propres.
func _clear_fleets(st: GameState) -> void:
	st.fleets.clear()


func _meet_and_war(st: GameState, a: int, b: int) -> void:
	var ea := st.get_empire(a)
	var eb := st.get_empire(b)
	if not ea.contacts.has(b):
		ea.contacts.append(b)
	if not eb.contacts.has(a):
		eb.contacts.append(a)
	Combat.start_war(st, a, b)


func _spawn(st: GameState, owner: int, ship: String, sid: int, n := 1) -> Fleet:
	var f := st.spawn_ship(owner, ship, sid)
	for i in n - 1:
		f.add_ship(ship)
	f.troops = Combat.max_troops(f)
	return f


func _test_data() -> void:
	var mil := 0
	for sid in GameData.ship_ids():
		if Combat.is_military(sid):
			mil += 1
			_ok(Combat.is_armed_ship(sid), "%s est armé" % sid)
	_ok(mil == 3, "trois classes de vaisseaux de guerre (obtenu %d)" % mil)
	_ok(Combat.ship_strength("corvette") < Combat.ship_strength("fregate") and Combat.ship_strength("fregate") < Combat.ship_strength("croiseur"),
			"puissance croissante : corvette < frégate < croiseur")
	_ok(Combat.tactic_ids().size() >= 3 and Combat.tactic_ids().has(Combat.default_tactic()), "tactiques présentes, avec une tactique par défaut")
	_ok(Combat.battle_days() == 6, "une bataille dure 6 jours (2 par phase)")
	_ok(Combat.phase_index(1) == 0 and Combat.phase_index(3) == 1 and Combat.phase_index(6) == 2, "phases longue, moyenne puis courte portée")
	for f in GameData.factions():
		_ok(f.has("combat"), "%s a des traits de combat" % f["id"])
	_ok(not Combat.is_armed_ship("scout") and not Combat.is_armed_ship("colony_ship"), "éclaireurs et vaisseaux colons ne sont pas armés")


func _test_damage_rules() -> void:
	var near := Combat.shot_damage("kinetic", 24, 2, "equilibre", 100, "fregate", "equilibre")
	var far := Combat.shot_damage("kinetic", 24, 0, "equilibre", 100, "fregate", "equilibre")
	_ok(near > far * 3, "les canons cinétiques frappent bien plus fort à courte portée (%d contre %d)" % [near, far])
	_ok(Combat.shot_damage("missile", 36, 0, "equilibre", 100, "", "equilibre") > Combat.shot_damage("missile", 36, 2, "equilibre", 100, "", "equilibre"),
			"les missiles frappent plus fort de loin")
	_ok(Combat.shot_damage("beam", 30, 1, "equilibre", 100, "corvette", "equilibre") > Combat.shot_damage("beam", 30, 1, "equilibre", 100, "fregate", "equilibre"),
			"les boucliers des frégates réduisent les rayons")
	_ok(Combat.shot_damage("kinetic", 24, 2, "equilibre", 100, "corvette", "equilibre") > Combat.shot_damage("kinetic", 24, 2, "equilibre", 100, "croiseur", "equilibre"),
			"le blindage des croiseurs réduit les canons")
	_ok(Combat.shot_damage("kinetic", 24, 2, "assaut", 100, "corvette", "equilibre") > near, "l'assaut renforce le tir à courte portée")
	_ok(Combat.shot_damage("kinetic", 24, 2, "equilibre", 100, "fregate", "rempart") < near, "le rempart réduit les dégâts reçus")
	_ok(Combat.shot_damage("kinetic", 24, 2, "equilibre", 130, "fregate", "equilibre") > near, "un bonus de peuple augmente les dégâts")


func _test_declare_war() -> void:
	var st := _state()
	var sim := Simulation.new(st)
	_ok(SimCommands.validate(st, SimCommands.declare_war(0, 1)) != "", "pas de guerre contre un empire jamais rencontré")
	st.get_empire(0).contacts.append(1)
	st.get_empire(1).contacts.append(0)
	_ok(SimCommands.validate(st, SimCommands.declare_war(0, 0)) != "", "pas de guerre contre soi-même")
	_ok(sim.submit(SimCommands.declare_war(0, 1)), "déclaration de guerre acceptée après le contact")
	sim.flush_commands()
	_ok(Combat.at_war(st, 0, 1) and Combat.at_war(st, 1, 0), "la guerre vaut dans les deux sens")
	_ok(SimCommands.validate(st, SimCommands.declare_war(0, 1)) != "", "pas de seconde déclaration")
	_ok(not Combat.at_war(st, 0, 2), "la guerre ne concerne que les deux empires")


func _test_battle_basic() -> void:
	var st := _state()
	_clear_fleets(st)
	var sid := _empty_system(st)
	_meet_and_war(st, 0, 1)
	var a := _spawn(st, 0, "corvette", sid, 3)
	var b := _spawn(st, 1, "corvette", sid, 3)
	var sim := Simulation.new(st)
	var events: Array = []
	sim.combat_event.connect(func(ev: Dictionary) -> void: events.append(ev))
	sim.step()
	_ok(st.battles.has(sid), "une bataille s'engage entre flottes en guerre dans le même système")
	_ok(not events.is_empty() and events[0]["type"] == "battle_started", "événement « bataille engagée » pour l'interface")
	_ok(a.total_hp() < a.total_max_hp() or not st.fleets.has(a.id), "les vaisseaux subissent des dégâts")
	for i in 5:
		sim.step()
	_ok(not st.battles.has(sid) or int(st.battles[sid]["day"]) < 6, "une bataille s'arrête après 6 jours")
	_ok(not st.battle_reports.is_empty(), "un rapport de bataille est rédigé")
	var rep: Dictionary = st.battle_reports[0]
	_ok(rep["sides"].size() == 2 and Combat.count_ships(rep["sides"][0]["engaged"]) == 3, "le rapport compte les vaisseaux engagés de chaque camp")
	_ok(int(rep["sides"][0]["dealt"]) > 0 and int(rep["sides"][1]["dealt"]) > 0, "le rapport compte les dégâts infligés")
	var ended := false
	for ev in events:
		ended = ended or ev["type"] == "battle_ended"
	_ok(ended, "événement « bataille terminée »")
	# Sans guerre, pas de bataille.
	var st2 := _state()
	_clear_fleets(st2)
	_spawn(st2, 0, "corvette", sid, 2)
	_spawn(st2, 1, "corvette", sid, 2)
	var sim2 := Simulation.new(st2)
	sim2.advance(3)
	_ok(st2.battles.is_empty(), "pas de bataille entre empires en paix")
	# Des éclaireurs ennemis ne se battent pas : personne n'est armé.
	var st3 := _state()
	_clear_fleets(st3)
	_meet_and_war(st3, 0, 1)
	_spawn(st3, 0, "scout", sid)
	_spawn(st3, 1, "scout", sid)
	Simulation.new(st3).advance(3)
	_ok(st3.battles.is_empty() and st3.fleets.size() == 2, "deux éclaireurs ennemis se regardent sans se battre")


## Résultat d'une bataille jusqu'à ce qu'un camp disparaisse (au plus 60 jours).
func _fight(seed_value: int, ships_a: Dictionary, ships_b: Dictionary, tac_a := "", tac_b := "") -> Dictionary:
	var st := _state(seed_value)
	_clear_fleets(st)
	var sid := _empty_system(st)
	_meet_and_war(st, 0, 1)
	var fa: Fleet = null
	var fb: Fleet = null
	for s in ships_a:
		if fa == null:
			fa = _spawn(st, 0, s, sid, int(ships_a[s]))
		else:
			for i in int(ships_a[s]):
				fa.add_ship(s)
	for s in ships_b:
		if fb == null:
			fb = _spawn(st, 1, s, sid, int(ships_b[s]))
		else:
			for i in int(ships_b[s]):
				fb.add_ship(s)
	fa.tactic = tac_a
	fb.tactic = tac_b
	var sim := Simulation.new(st)
	var days := 0
	while days < 60 and st.fleets.has(fa.id) and st.fleets.has(fb.id):
		sim.step()
		days += 1
	return {"a": st.fleets.has(fa.id), "b": st.fleets.has(fb.id), "days": days, "state": st}


func _test_battle_odds() -> void:
	var r := _fight(1, {"fregate": 4}, {"corvette": 2})
	_ok(r["a"] and not r["b"], "4 frégates écrasent 2 corvettes")
	var wins := 0
	for seed_value in [11, 12, 13, 14, 15]:
		var x := _fight(seed_value, {"croiseur": 2}, {"corvette": 2})
		if x["a"] and not x["b"]:
			wins += 1
	_ok(wins == 5, "2 croiseurs battent toujours 2 corvettes (%d/5)" % wins)
	# La tactique compte : des corvettes en assaut font mieux qu'en tir à distance contre la même flotte.
	var hp_assault := 0
	var hp_distance := 0
	for seed_value in [21, 22, 23, 24]:
		var s1 := _fight(seed_value, {"corvette": 4}, {"fregate": 2}, "assaut", "")
		var s2 := _fight(seed_value, {"corvette": 4}, {"fregate": 2}, "distance", "")
		hp_assault += _side_hp(s1["state"], 1)
		hp_distance += _side_hp(s2["state"], 1)
	_ok(hp_assault < hp_distance, "des corvettes en assaut abîment plus l'ennemi qu'en tir à distance (%d contre %d points restants)" % [hp_assault, hp_distance])


func _side_hp(st: GameState, owner: int) -> int:
	var n := 0
	for f in Fleets.empire_fleets(st, owner):
		n += f.total_hp()
	return n


func _test_battle_determinism_and_save() -> void:
	var make := func() -> Simulation:
		var st := _state(77)
		_clear_fleets(st)
		var sid := _empty_system(st)
		_meet_and_war(st, 0, 1)
		_spawn(st, 0, "fregate", sid, 3)
		_spawn(st, 1, "corvette", sid, 4)
		return Simulation.new(st)
	var s1: Simulation = make.call()
	var s2: Simulation = make.call()
	s1.advance(3)
	s2.advance(3)
	_ok(s1.state.checksum() == s2.state.checksum(), "bataille déterministe : même empreinte au même jour")
	# Sauvegarde en pleine bataille, puis on continue des deux côtés.
	var d := s1.state.to_dict()
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(loaded != null, "une partie en pleine bataille se recharge (%s)" % GameState.last_error)
	if loaded == null:
		return
	_ok(loaded.checksum() == s1.state.checksum(), "même empreinte après rechargement en pleine bataille")
	var s3 := Simulation.new(loaded)
	s1.advance(10)
	s3.advance(10)
	_ok(s1.state.checksum() == s3.state.checksum(), "la bataille rechargée se termine à l'identique")
	_ok(not loaded.battle_reports.is_empty(), "les rapports de bataille sont sauvegardés")


func _test_blockade() -> void:
	var st := _state(5)
	_clear_fleets(st)
	_meet_and_war(st, 0, 1)
	var home := _home(st, 0)
	# Un chemin d'au moins deux sauts, et un ennemi armé posté sur le premier.
	var mid: int = st.galaxy.systems[home].neighbors[0]
	var far := -1
	for n in st.galaxy.systems[mid].neighbors:
		if n != home:
			far = n
	for s in [home, mid, far]:
		st.get_empire(0).explored[s] = true
	var f := _spawn(st, 0, "scout", home)
	_spawn(st, 1, "corvette", mid)
	var sim := Simulation.new(st)
	_ok(sim.submit(SimCommands.move_fleet(0, f.id, far)), "ordre de traverser le système tenu par l'ennemi")
	sim.flush_commands()
	_ok(f.path.size() == 2, "le trajet passe par le système bloqué")
	var days := 0
	while days < 80 and st.fleets.has(f.id) and (f.is_moving() or f.system_id == home):
		sim.step()
		days += 1
	_ok(not st.fleets.has(f.id) or f.system_id == mid, "blocus : la flotte est arrêtée au système tenu par l'ennemi")


func _test_retreat() -> void:
	var st := _state(9)
	_clear_fleets(st)
	_meet_and_war(st, 0, 1)
	var home := _home(st, 0)
	var sid: int = st.galaxy.systems[home].neighbors[0]
	st.get_empire(0).explored[sid] = true
	var mine := _spawn(st, 0, "croiseur", sid)
	_spawn(st, 1, "corvette", sid, 2)
	var sim := Simulation.new(st)
	sim.step()
	_ok(st.battles.has(sid), "bataille engagée")
	_ok(sim.submit(SimCommands.move_fleet(0, mine.id, home)), "ordre de retraite pendant la bataille")
	sim.step()
	_ok(st.fleets.has(mine.id) and mine.is_moving(), "la flotte quitte le système")
	sim.step()
	_ok(not st.battles.has(sid), "la bataille prend fin quand un camp s'en va")


func _test_siege_and_invasion() -> void:
	var st := _state(31)
	_clear_fleets(st)
	_meet_and_war(st, 0, 1)
	var target := _home(st, 1)
	var full := Combat.garrison_max(st, target)
	_ok(full > 0, "le système d'origine a une garnison (%d)" % full)
	var income_before: Dictionary = Economy.empire_income(st, 1)["gross"]
	var f := _spawn(st, 0, "croiseur", target, 2)
	var sim := Simulation.new(st)
	sim.step()
	_ok(Combat.is_besieged(st, target), "flotte armée sans défenseur : le système est assiégé")
	_ok(Combat.garrison(st, target) < full, "le siège use la garnison")
	var income_during: Dictionary = Economy.empire_income(st, 1)["gross"]
	_ok(int(income_during["materials"]) < int(income_before["materials"]), "un système assiégé produit moins")
	# Le chantier spatial est bloqué.
	var cap: Colony = st.colonies[st.get_empire(1).capital_planet]
	cap.ship_build = "corvette"
	cap.ship_days = 1
	sim.step()
	_ok(cap.ship_build == "corvette", "chantier spatial bloqué pendant le siège")
	cap.ship_build = ""
	f.troops = 1
	_ok(SimCommands.validate(st, SimCommands.invade(0, f.id)) != "", "invasion refusée tant que la garnison dépasse les troupes")
	var days := 0
	while Combat.garrison(st, target) > 0 and days < 200:
		sim.step()
		days += 1
	_ok(Combat.garrison(st, target) == 0, "la garnison finit par tomber (%d jours)" % days)
	f.troops = Combat.max_troops(f)
	var cmd := SimCommands.invade(0, f.id)
	_ok(SimCommands.validate(st, cmd) == "", "invasion possible une fois la garnison usée (%s)" % SimCommands.validate(st, cmd))
	var planets_before := 0
	for pid in st.galaxy.systems[target].planet_ids:
		if st.colonies.has(pid) and st.colonies[pid].owner == 1:
			planets_before += 1
	sim.submit(cmd)
	sim.flush_commands()
	_ok(st.system_owner(target) == 0, "le système conquis change de mains")
	var mine := 0
	for pid in st.galaxy.systems[target].planet_ids:
		if st.colonies.has(pid) and st.colonies[pid].owner == 0:
			mine += 1
	_ok(mine == planets_before, "toutes les revendications du système passent au conquérant")
	_ok(st.get_empire(1).capital_planet != cap.planet_id, "l'empire vaincu perd sa capitale")
	_ok(not Combat.is_besieged(st, target), "le siège s'arrête avec la conquête")
	_ok(SimCommands.validate(st, SimCommands.invade(0, f.id)) != "", "on n'envahit pas son propre système")


func _test_elimination() -> void:
	var st := _state(32)
	_clear_fleets(st)
	_meet_and_war(st, 0, 2)
	var target := _home(st, 2)
	_spawn(st, 2, "scout", _home(st, 2))
	var f := _spawn(st, 0, "croiseur", target, 3)
	var sim := Simulation.new(st)
	var guard := 0
	while Combat.garrison(st, target) > 0 and guard < 300:
		sim.step()
		guard += 1
	f.troops = Combat.max_troops(f)
	sim.submit(SimCommands.invade(0, f.id))
	sim.step()
	var e := st.get_empire(2)
	_ok(e.eliminated, "un empire sans revendication disparaît")
	_ok(Fleets.empire_fleets(st, 2).is_empty(), "ses flottes disparaissent avec lui")
	_ok(not Combat.at_war(st, 0, 2), "plus de guerre contre un empire disparu")
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	_ok(loaded != null and loaded.get_empire(2).eliminated, "la disparition est sauvegardée")


func _test_khthari() -> void:
	var st := _state(41, "khthari")
	var kh := st.get_empire(0)
	_ok(kh.faction_id == "khthari", "le joueur joue l'Essaim")
	var other := st.get_empire(1)
	var added: Array[Dictionary] = []
	FleetSystem._meet(st, kh, other, added)
	_ok(Combat.at_war(st, 0, 1), "l'Essaim est en guerre avec tout empire rencontré")
	# Rencontre entre deux autres peuples : pas de guerre automatique.
	FleetSystem._meet(st, st.get_empire(1), st.get_empire(2), added)
	_ok(not Combat.at_war(st, 1, 2), "les autres peuples ne partent pas en guerre au premier contact")
	# Digestion des colonies conquises.
	var target := _home(st, 1)
	var c: Colony = st.colonies[other.capital_planet]
	var pop := c.population
	var mat := int(kh.resources["materials"])
	Combat.capture_system(st, target, 0)
	_ok(c.owner == 0 and c.population == 1, "colonie conquise par l'Essaim : il n'y reste qu'une population (avant : %d)" % pop)
	_ok(int(kh.resources["materials"]) == mat + (pop - 1) * 15, "le reste est digéré en biomasse (15 matériaux par population)")
	# Coques vivantes : réparation partout.
	_clear_fleets(st)
	var sid := _empty_system(st)
	var f := _spawn(st, 0, "fregate", sid)
	f.hp[0] = 50
	var f1 := _spawn(st, 1, "fregate", sid)
	f1.hp[0] = 50
	st.get_empire(1).wars.clear()
	kh.wars.clear()
	CombatSystem._repairs(st, {})
	_ok(f.hp[0] > f1.hp[0], "les coques vivantes de l'Essaim se réparent plus vite hors de chez elles")


func _test_faction_bonuses() -> void:
	var st := _state(51, "ossarane")
	_clear_fleets(st)
	var home := _home(st, 0)
	var sid := _empty_system(st)
	var b := {"fleets": [], "sides": []}
	var at_home := _spawn(st, 0, "corvette", home)
	var away := _spawn(st, 0, "corvette", sid)
	_ok(CombatSystem._damage_bonus(st, b, at_home, home) > CombatSystem._damage_bonus(st, b, away, sid), "Ossarane frappe plus fort chez elle")
	var ossa_g := Combat.garrison_max(st, home)
	# Même système tenu par un autre peuple : garnison plus faible.
	var st2 := _state(51, "vael")
	_ok(Combat.garrison_max(st2, _home(st2, 0)) < ossa_g, "les fiefs d'Ossarane ont des garnisons plus nombreuses")
	# Vael : renforts arrivés en cours de bataille.
	_clear_fleets(st2)
	var sid2 := _empty_system(st2)
	var early := _spawn(st2, 0, "corvette", sid2)
	var late := _spawn(st2, 0, "corvette", sid2)
	var b2 := {"fleets": [[early.id, 1], [late.id, 3]], "sides": []}
	_ok(CombatSystem._damage_bonus(st2, b2, late, sid2) > CombatSystem._damage_bonus(st2, b2, early, sid2), "Vael : une flotte qui arrive en renfort frappe plus fort")
	# Chœur : chaque vaisseau ennemi détruit nourrit la ferveur.
	var st3 := _state(52, "choeur")
	_clear_fleets(st3)
	_meet_and_war(st3, 0, 1)
	var sid3 := _empty_system(st3)
	_spawn(st3, 0, "croiseur", sid3, 3)
	_spawn(st3, 1, "scout", sid3, 3)
	var choeur := st3.get_empire(0)
	choeur.fervor = 10
	Simulation.new(st3).advance(6)
	_ok(choeur.fervor > 10, "Chœur : la croisade nourrit la ferveur (%d)" % choeur.fervor)


func _test_merge_split_repair() -> void:
	var st := _state(61)
	_clear_fleets(st)
	var home := _home(st, 0)
	var a := _spawn(st, 0, "fregate", home)
	var b := _spawn(st, 0, "croiseur", home)
	a.hp[0] = 40
	b.troops = 5
	var sim := Simulation.new(st)
	sim.submit(SimCommands.merge_fleets(0, a.id, b.id))
	sim.flush_commands()
	_ok(b.ships.size() == 2 and b.total_hp() == 40 + 300, "la fusion garde les dégâts de chaque vaisseau")
	_ok(b.troops == 5 + 4, "la fusion additionne les troupes")
	sim.submit(SimCommands.split_fleet(0, b.id, "fregate"))
	sim.flush_commands()
	var nf: Fleet = null
	for f in Fleets.empire_fleets(st, 0):
		if f.id != b.id:
			nf = f
	_ok(nf != null and nf.hp[0] == 40, "le vaisseau détaché garde ses dégâts")
	_ok(nf != null and nf.troops + b.troops == 9, "les troupes se partagent au détachement")
	if nf:
		var before := nf.hp[0]
		sim.step()
		_ok(nf.hp[0] > before, "une flotte se répare dans ses propres systèmes")
	var tactic := SimCommands.set_tactic(0, b.id, "distance")
	_ok(sim.submit(tactic), "changer de tactique")
	sim.flush_commands()
	_ok(Combat.fleet_tactic(b) == "distance", "la tactique est appliquée")
	_ok(SimCommands.validate(st, SimCommands.set_tactic(0, b.id, "n'importe")) != "", "tactique inconnue refusée")


func _test_ai_war() -> void:
	# Tempérament belliqueux : les IA arment, déclarent la guerre et se battent.
	var st := GameState.create(17, 150, 1800.0, "", {"spectator": true, "ai_level": "normal", "temperament": "belliqueux"})
	var sim := Simulation.new(st)
	var n := {"battles": 0, "declared": 0}
	sim.combat_event.connect(func(ev: Dictionary) -> void:
		if ev["type"] == "battle_ended":
			n["battles"] += 1)
	sim.chronicle_added.connect(func(entry: Dictionary) -> void:
		if String(entry["text"]).contains("déclare la guerre"):
			n["declared"] += 1)
	sim.advance(360 * 3)
	var warships := 0
	for f in st.fleets.values():
		if Combat.is_warfleet(f):
			warships += f.ships.size()
	_ok(warships > 0, "les IA construisent des vaisseaux de guerre (%d)" % warships)
	_ok(int(n["declared"]) > 0, "des IA belliqueuses déclarent la guerre (%d)" % n["declared"])
	_ok(int(n["battles"]) > 0, "des batailles ont lieu entre IA (%d)" % n["battles"])
	# Tempérament pacifique : aucune déclaration (seul l'Essaim est en guerre, par nature).
	var st2 := GameState.create(17, 150, 1800.0, "", {"spectator": true, "ai_level": "normal", "temperament": "pacifique"})
	var sim2 := Simulation.new(st2)
	var declared := [0]
	sim2.chronicle_added.connect(func(entry: Dictionary) -> void:
		if String(entry["text"]).contains("déclare la guerre"):
			declared[0] += 1)
	sim2.advance(360 * 2)
	_ok(declared[0] == 0, "des IA pacifiques ne déclarent jamais la guerre")
	for e in st2.empires:
		for w in e.wars:
			_ok(Combat.always_war(st2, e.id) or Combat.always_war(st2, w), "seul l'Essaim est en guerre chez les pacifiques")
	# Tactiques selon le niveau : la Recrue charge toujours, le Vétéran adapte aux armes.
	var st3 := _state(5)
	_clear_fleets(st3)
	var home := _home(st3, 1)
	var cru := _spawn(st3, 1, "croiseur", home, 2)
	var ctx := {"state": st3, "e": st3.get_empire(1), "lv": AiLevels.level("recrue"), "ai": {}, "salt": 0, "intent": ""}
	_ok(AiPlayer.tactic_for(ctx, cru) == "assaut", "la Recrue charge, même avec des croiseurs lance-missiles")
	ctx["lv"] = AiLevels.level("veteran")
	_ok(AiPlayer.tactic_for(ctx, cru) == "distance", "le Vétéran garde ses croiseurs à distance")
	var cor := _spawn(st3, 1, "corvette", home, 3)
	_ok(AiPlayer.tactic_for(ctx, cor) == "assaut", "le Vétéran envoie ses corvettes au contact")
	ctx["lv"] = AiLevels.level("normal")
	_ok(AiPlayer.tactic_for(ctx, cru) == Combat.default_tactic(), "le Normal reste en Équilibre")
	# Le niveau et le tempérament règlent la taille de l'armée.
	var e1 := st3.get_empire(1)
	e1.ai_level = "legende"
	e1.ai_temperament = "belliqueux"
	ctx["lv"] = AiLevels.level("legende")
	var big := AiPlayer.wanted_warships(ctx)
	e1.ai_temperament = "pacifique"
	ctx["lv"] = AiLevels.level("recrue")
	_ok(AiPlayer.wanted_warships(ctx) < big, "une Recrue pacifique arme moins qu'une Légende belliqueuse")
