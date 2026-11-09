extends RefCounted
## Tests du catalogue de vaisseaux : classes communes, classes de peuple liées aux couches d'espèce,
## rangs de bataille (écran, ligne, arrière), défense ponctuelle, bonus de taille, titan unique,
## Martyr, tactique Adaptative, Coursier de saut, et IA qui se sert du catalogue. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Catalogue de vaisseaux…")
	_test_catalogue_per_people()
	_test_species_rules()
	_test_requirements()
	_test_damage_rules()
	_test_lines()
	_test_martyr()
	_test_adaptive()
	_test_blockade_runner()
	_test_titan_launch()
	_test_ai_uses_catalogue()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _state(seed_value := 4242, faction := "ossarane") -> GameState:
	return GameState.create(seed_value, 150, 1800.0, faction, {"ai_level": ""})


func _empire_of(st: GameState, faction: String) -> int:
	for e in st.empires:
		if e.faction_id == faction:
			return e.id
	return -1


func _home(st: GameState, empire_id: int) -> int:
	return st.galaxy.get_planet(st.get_empire(empire_id).capital_planet).system_id


func _empty_system(st: GameState) -> int:
	for s in st.galaxy.systems:
		if st.system_owner(s.id) == -1 and s.neighbors.size() >= 2:
			return s.id
	return -1


func _war(st: GameState, a: int, b: int) -> void:
	for p in [[a, b], [b, a]]:
		if not st.get_empire(p[0]).contacts.has(p[1]):
			st.get_empire(p[0]).contacts.append(p[1])
	Combat.start_war(st, a, b)


func _spawn(st: GameState, owner: int, ships: Array, sid: int) -> Fleet:
	var f := st.spawn_ship(owner, String(ships[0]), sid)
	for i in range(1, ships.size()):
		f.add_ship(String(ships[i]))
	f.troops = Combat.max_troops(f)
	return f


func _rich(e: Empire) -> void:
	for r in GameData.resource_ids():
		e.resources[r] = 5000


func _test_catalogue_per_people() -> void:
	var common := ["escorteur", "torpilleur", "transport", "bombarde", "cuirasse", "titan"]
	for fid in GameData.faction_ids():
		var ids := FactionTraits.ship_ids_for(fid)
		for c in common:
			_ok(ids.has(c), "%s peut construire : %s" % [fid, c])
	var oss := FactionTraits.ship_ids_for("ossarane")
	_ok(oss.has("coursier") and not oss.has("corvette"), "Ossarane : le Coursier de saut remplace la corvette")
	var ch := FactionTraits.ship_ids_for("choeur")
	_ok(ch.has("martyr") and ch.has("corvette"), "Chœur : le Martyr s'ajoute au catalogue")
	var va := FactionTraits.ship_ids_for("vael")
	_ok(va.has("fregate_quarante") and not va.has("fregate"), "Vael : la Frégate des Quarante remplace la frégate")
	var kh := FactionTraits.ship_ids_for("khthari")
	_ok(kh.has("ruche_mere") and not kh.has("porte_vaisseaux") and kh.has("spore_ship"), "Kh'thari : la Ruche-mère remplace le porte-vaisseaux")
	_ok(not oss.has("martyr") and not ch.has("ruche_mere") and not kh.has("coursier"), "les classes de peuple restent chez leur peuple")


func _test_species_rules() -> void:
	# Une espèce de l'éditeur (pas une faction officielle) obtient les classes de sa combinaison.
	var custom := {"registre": "Grimdark", "species": {"archetype": "ruche", "gouvernement": "horde", "credo": "foi", "traits": ["pluriel"]}}
	_ok(FactionTraits.species_matches(custom, {"archetype": ["ruche"]}), "espèce personnalisée : archétype ruche reconnu")
	_ok(FactionTraits.species_matches(custom, {"credo": ["foi"]}), "espèce personnalisée : credo foi reconnu")
	_ok(FactionTraits.species_matches(custom, {"traits": ["navigateurs", "pluriel"]}), "il suffit d'un des traits demandés")
	_ok(not FactionTraits.species_matches(custom, {"traits": ["navigateurs"]}), "trait absent : condition non remplie")
	_ok(FactionTraits.species_matches(custom, {"registre": ["Grimdark"]}), "le registre compte aussi")
	_ok(FactionTraits.species_matches(custom, {}), "aucune condition : toujours rempli")


func _test_requirements() -> void:
	var st := _state()
	var e := st.get_empire(0)
	_rich(e)
	var cap := e.capital_planet
	var c: Colony = st.colonies[cap]
	_ok(Fleets.check_build_ship(st, 0, cap, "cuirasse").contains("Arsenal"), "cuirassé refusé sans arsenal")
	_ok(Fleets.check_build_ship(st, 0, cap, "escorteur") == "", "l'escorteur se construit partout")
	_ok(Economy.check_build(st, 0, cap, "chantier_titanesque").contains("Arsenal"), "le chantier titanesque demande d'abord un arsenal")
	c.buildings.append("arsenal")
	_ok(Fleets.check_build_ship(st, 0, cap, "cuirasse") == "", "cuirassé possible avec un arsenal")
	_ok(Fleets.check_build_ship(st, 0, cap, "titan") != "", "titan refusé sans chantier titanesque")
	c.buildings.append("chantier_titanesque")
	_ok(Fleets.check_build_ship(st, 0, cap, "titan") == "", "titan possible avec son chantier")
	_spawn(st, 0, ["titan"], _home(st, 0))
	_ok(Fleets.check_build_ship(st, 0, cap, "titan").contains("un seul"), "un seul titan par empire")


func _test_damage_rules() -> void:
	var big := Combat.shot_damage("torpedo", 34, 1, "equilibre", 100, "croiseur", "equilibre")
	var small := Combat.shot_damage("torpedo", 34, 1, "equilibre", 100, "corvette", "equilibre")
	_ok(big > small, "les torpilles frappent plus fort les grosses coques (%d contre %d)" % [big, small])
	_ok(Combat.shot_damage("artillery", 70, 2, "equilibre", 100, "croiseur", "equilibre") == 0, "l'artillerie lourde ne tire pas à courte portée")
	_ok(Combat.shot_damage("artillery", 70, 0, "equilibre", 100, "croiseur", "equilibre") > Combat.shot_damage("artillery", 70, 0, "equilibre", 100, "corvette", "equilibre") / 2,
			"l'artillerie écrase les grosses coques de loin")
	var bare := Combat.shot_damage("missile", 36, 0, "equilibre", 100, "croiseur", "equilibre")
	var covered := Combat.shot_damage("missile", 36, 0, "equilibre", 100, "croiseur", "equilibre", 15)
	_ok(covered < bare, "les escorteurs de la flotte abattent une partie des missiles (%d contre %d)" % [covered, bare])
	_ok(Combat.shot_damage("missile", 36, 0, "equilibre", 100, "escorteur", "equilibre") < Combat.shot_damage("missile", 36, 0, "equilibre", 100, "corvette", "equilibre"),
			"la défense ponctuelle de l'escorteur le protège des missiles")
	_ok(Combat.shot_damage("kinetic", 24, 2, "equilibre", 100, "croiseur", "equilibre", 60) == Combat.shot_damage("kinetic", 24, 2, "equilibre", 100, "croiseur", "equilibre"),
			"la défense ponctuelle n'arrête pas les canons")
	var f := Fleet.new()
	for i in 10:
		f.add_ship("escorteur")
	_ok(Combat.fleet_pd(f) == int(Combat.data()["pd_cap"]), "défense ponctuelle de flotte plafonnée")


func _test_lines() -> void:
	# Des frégates contre un écran de corvettes qui couvre un transport : le transport n'est pas visé.
	var st := _state(77)
	st.fleets.clear()
	var sid := _empty_system(st)
	_war(st, 0, 1)
	var a := _spawn(st, 0, ["fregate", "fregate", "fregate"], sid)
	var b := _spawn(st, 1, ["corvette", "corvette", "corvette", "transport"], sid)
	var sim := Simulation.new(st)
	sim.step()
	sim.step()
	var ti := b.ships.find("transport")
	_ok(ti >= 0 and b.hp[ti] == Fleet.max_hp_of("transport"), "l'arrière est hors d'atteinte tant que l'écran tient")
	# Des chasseurs vont chercher l'arrière.
	var st2 := _state(77)
	st2.fleets.clear()
	_war(st2, 0, 1)
	_spawn(st2, 0, ["porte_vaisseaux", "porte_vaisseaux"], sid)
	var b2 := _spawn(st2, 1, ["corvette", "corvette", "corvette", "transport"], sid)
	var sim2 := Simulation.new(st2)
	for i in 4:
		sim2.step()
	var t2 := b2.ships.find("transport")
	_ok(not st2.fleets.has(b2.id) or t2 < 0 or b2.hp[t2] < Fleet.max_hp_of("transport"), "les chasseurs frappent derrière les lignes")
	# Une flotte sans front : l'arrière devient la cible.
	var st3 := _state(77)
	st3.fleets.clear()
	_war(st3, 0, 1)
	_spawn(st3, 0, ["corvette", "corvette"], sid)
	var b3 := _spawn(st3, 1, ["transport"], sid)
	var sim3 := Simulation.new(st3)
	for i in 6:
		sim3.step()
	_ok(not st3.fleets.has(b3.id) or b3.hp[0] < Fleet.max_hp_of("transport"), "sans écran ni ligne, l'arrière encaisse")


func _test_martyr() -> void:
	var st := _state(91, "choeur")
	st.fleets.clear()
	var me := _empire_of(st, "choeur")
	var foe := (me + 1) % st.empires.size()
	var sid := _empty_system(st)
	_war(st, me, foe)
	var m := _spawn(st, me, ["martyr", "martyr", "martyr"], sid)
	var target := _spawn(st, foe, ["croiseur"], sid)
	var e := st.get_empire(me)
	var sim := Simulation.new(st)
	for i in 4:
		sim.step()
	var alive_before := m.ships.size() if st.fleets.has(m.id) else 0
	var hp_before := target.hp[0] if st.fleets.has(target.id) else 0
	var fervor_before := e.fervor
	sim.step()  # jour 5 : courte portée, les martyrs chargent
	_ok(not st.fleets.has(m.id) or m.ships.size() < alive_before, "les martyrs disparaissent dans leur charge")
	_ok(not st.fleets.has(target.id) or target.hp[0] < hp_before, "la charge sacrée frappe fort")
	_ok(e.fervor > fervor_before or alive_before == 0, "l'offrande nourrit la ferveur")
	_ok(alive_before > 0, "les martyrs ne chargent pas avant la courte portée")


func _test_adaptive() -> void:
	var st := _state(5, "vael")
	st.fleets.clear()
	var me := _empire_of(st, "vael")
	var f := _spawn(st, me, ["fregate_quarante", "corvette"], _home(st, me))
	_ok(Combat.tactic_ids_for(f).has("adaptatif"), "une flotte avec une Frégate des Quarante peut suivre l'Adaptative")
	_ok(Combat.check_tactic(st, me, f.id, "adaptatif") == "", "ordre de tactique Adaptative accepté")
	var other := (me + 1) % st.empires.size()
	var g := _spawn(st, other, ["corvette"], _home(st, other))
	_ok(Combat.check_tactic(st, other, g.id, "adaptatif") != "", "sans Frégate des Quarante, pas d'Adaptative")
	g.tactic = "adaptatif"
	_ok(Combat.fleet_tactic(g) == Combat.default_tactic(), "une tactique interdite retombe sur la tactique par défaut")


func _test_blockade_runner() -> void:
	var st := _state(5, "ossarane")
	st.fleets.clear()
	var me := _empire_of(st, "ossarane")
	var foe := (me + 1) % st.empires.size()
	_war(st, me, foe)
	var home := _home(st, me)
	var mid: int = st.galaxy.systems[home].neighbors[0]
	var far := -1
	for n in st.galaxy.systems[mid].neighbors:
		if n != home:
			far = n
	for s in [home, mid, far]:
		st.get_empire(me).explored[s] = true
	var f := _spawn(st, me, ["coursier", "coursier"], home)
	_spawn(st, foe, ["corvette"], mid)
	_ok(Combat.runs_blockades(f), "une flotte de coursiers force les blocus")
	var sim := Simulation.new(st)
	sim.submit(SimCommands.move_fleet(me, f.id, far))
	sim.flush_commands()
	var days := 0
	while days < 80 and st.fleets.has(f.id) and f.system_id != far:
		sim.step()
		days += 1
	_ok(st.fleets.has(f.id) and f.system_id == far, "les coursiers traversent le système bloqué")
	f.add_ship("fregate")
	_ok(not Combat.runs_blockades(f), "une frégate dans la flotte et le blocus s'applique de nouveau")


func _test_titan_launch() -> void:
	var st := _state(8)
	var e := st.get_empire(0)
	var c: Colony = st.colonies[e.capital_planet]
	c.ship_build = "titan"
	c.ship_days = 1
	var sim := Simulation.new(st)
	var before := st.chronicle.size()
	sim.step()
	var found := false
	for i in range(before, st.chronicle.size()):
		found = found or String(st.chronicle[i].get("text", "")).contains("Titan")
	_ok(found, "la chronique annonce le lancement d'un titan")
	_ok(Fleets.count_owned_or_building(st, 0, "titan") == 1, "le titan est compté pour la limite d'un par empire")


func _test_ai_uses_catalogue() -> void:
	var built := {}
	for seed_value in [17, 23]:
		var st := GameState.create(seed_value, 150, 1800.0, "", {"spectator": true, "ai_level": "veteran", "temperament": "belliqueux"})
		var sim := Simulation.new(st)
		for i in 360 * 3:
			sim.step()
		for e in st.empires:
			for sid in e.ships_built:
				built[sid] = int(built.get(sid, 0)) + int(e.ships_built[sid])
	var fresh := 0
	for sid in ["escorteur", "torpilleur", "transport", "bombarde", "cuirasse", "porte_vaisseaux", "titan", "coursier", "martyr", "fregate_quarante", "ruche_mere"]:
		if int(built.get(sid, 0)) > 0:
			fresh += 1
	print("  IA Vétéran, 3 ans x2 : ", built)
	_ok(fresh >= 3, "les IA Vétéran construisent plusieurs classes du nouveau catalogue (%d)" % fresh)
