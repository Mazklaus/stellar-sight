extends RefCounted
## Tests des ères IV et V d'Économie et de Société : bâtiments de 2e rang, projets de terraformation
## (second monde préféré, monde-jardin, écuménopole), mondes creusés, avant-postes productifs,
## Préfectures, mégastructures et merveilles, migration, technologies ultimes et IA qui s'en sert.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Ères IV et V : Économie et Société…")
	_test_data()
	_test_ultimate()
	_test_upgrades()
	_test_terraform()
	_test_ecumenopolis()
	_test_habitats_and_outposts()
	_test_prefecture()
	_test_wonders()
	_test_migration()
	_test_upkeep_and_trade()
	_test_ai_late_game()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _sim(faction := "vael", seed_value := 77) -> Simulation:
	var sim := Simulation.new(GameState.create(seed_value, 150, 1800.0, faction, {"ai_level": ""}))
	var e := sim.state.empires[0]
	for r in ["materials", "energy", "influence", "crystals", "food"]:
		e.resources[r] = 50000
	return sim


## Pose directement une colonie établie (rendements et chantiers testés sans attendre la fondation).
func _plant(st: GameState, empire_id: int, planet_id: int, pop := 1, kind := Colony.KIND_COLONY) -> Colony:
	var c := Colony.new()
	c.planet_id = planet_id
	c.owner = empire_id
	c.kind = kind
	c.population = pop if kind == Colony.KIND_COLONY else 0
	st.add_colony(c)
	return c


## Une planète libre de ce type, dans un système que personne ne tient (taille minimale au besoin).
func _free_planet(st: GameState, ptype: String, min_size := 1) -> Planet:
	for p in st.galaxy.planets:
		if p.type == ptype and p.size >= min_size and not st.colonies.has(p.id) and st.system_owner(p.system_id) == -1:
			return p
	return null


func _build(sim: Simulation, planet_id: int, bid: String) -> String:
	var cmd := SimCommands.build(0, planet_id, bid)
	var why := SimCommands.validate(sim.state, cmd)
	if why == "":
		sim.submit(cmd)
		sim.flush_commands()
	return why


func _finish(sim: Simulation, planet_id: int) -> void:
	var c: Colony = sim.state.colonies[planet_id]
	sim.advance(maxi(1, c.construction_days))


func _test_data() -> void:
	var techs: Dictionary = Research.data()["technologies"]
	var counts := {}
	for tid in techs:
		var t: Dictionary = techs[tid]
		if t.has("requires"):
			continue
		var key := "%s%d" % [String(t["domain"]), int(t["era"])]
		counts[key] = int(counts.get(key, 0)) + 1
	_ok(int(counts.get("economie4", 0)) >= 5 and int(counts.get("economie5", 0)) >= 4, "Économie : ères IV et V remplies (%d, %d)" % [int(counts.get("economie4", 0)), int(counts.get("economie5", 0))])
	_ok(int(counts.get("societe4", 0)) >= 4 and int(counts.get("societe5", 0)) >= 4, "Société : ères IV et V remplies (%d, %d)" % [int(counts.get("societe4", 0)), int(counts.get("societe5", 0))])
	# Chaque peuple peut ouvrir l'ère V des deux domaines (assez de technologies d'ère IV pour son arbre).
	for fid in ["ossarane", "choeur", "vael", "khthari"]:
		var f := GameData.faction(fid)
		var have := {}
		for tid in Research.visible_ids(f):
			have[tid] = true
		for d in ["economie", "societe"]:
			_ok(Research.era_open(have, d, 5), "%s peut ouvrir l'ère V en %s" % [fid, d])
	# Les nouveaux bâtiments et types de planète sont cohérents.
	for bid in GameData.buildings():
		var b := GameData.building(bid)
		if b.has("upgrades"):
			_ok(not GameData.building(String(b["upgrades"])).is_empty(), "%s remplace un bâtiment qui existe" % bid)
		if b.has("terraform") and String(b["terraform"]) != "preferred2":
			_ok(not GameData.planet_type(String(b["terraform"])).is_empty(), "%s vise un type de planète qui existe" % bid)
	for t in ["gaia", "ecumenopole"]:
		var g := GalaxyGenerator.generate(3, 150, 1800.0)
		var found := false
		for p in g.planets:
			if p.type == t:
				found = true
		_ok(not found, "%s n'apparaît jamais à la génération" % t)


func _test_ultimate() -> void:
	var sim := _sim()
	var st := sim.state
	Research.grant(st, 0, ["hydroponie", "fusion_compacte", "extraction", "academies", "logistique", "recyclage", "raffinage",
			"automatisation", "nanofabrication", "bourses", "cristallographie",
			"arcologies_productives", "ecopes", "fabriques_autonomes", "forage_manteau"])
	_ok(Research.era_open(st.get_empire(0).techs, "economie", 5), "ère V d'Économie ouverte avec 4 technologies d'ère IV")
	_ok(Research.check_queue(st, 0, "abondance").contains("ultime"), "Économie d'abondance refusée sans 3 technologies d'ère V")
	Research.grant(st, 0, ["arcologie_planetaire", "collecteur_stellaire"])
	_ok(not Research.is_available(st, 0, "abondance"), "toujours refusée avec 2 technologies d'ère V")
	Research.apply_queue(st, 0, "nexus_savoir", false)
	_ok(Research.check_queue(st, 0, "abondance") == "",
			"planifiable dès que la 3e technologie d'ère V est en file")
	Research.complete(st, 0, "nexus_savoir")
	_ok(Research.is_available(st, 0, "abondance"), "Économie d'abondance disponible avec 3 technologies d'ère V")


func _test_upgrades() -> void:
	var sim := _sim()
	var st := sim.state
	var home := st.empires[0].capital_planet
	var c: Colony = st.colonies[home]
	_ok(_build(sim, home, "mine_profonde").contains("technologie"), "Mine profonde : il faut la technologie")
	Research.grant(st, 0, ["arcologies_productives"])
	_ok(_build(sim, home, "centrale_confinement").contains("1er rang"), "2e rang refusé sans le bâtiment de 1er rang")
	var used := Economy.building_slots_used(c)
	var mat0: int = Economy.empire_income(st, 0)["gross"]["materials"]
	_ok(_build(sim, home, "mine_profonde") == "", "Mine profonde lancée sur le Complexe minier")
	_finish(sim, home)
	_ok(c.buildings.has("mine_profonde") and not c.buildings.has("complexe_minier"), "la Mine profonde remplace le Complexe minier")
	_ok(Economy.building_slots_used(c) == used, "aucun emplacement de plus")
	_ok(int(Economy.empire_income(st, 0)["gross"]["materials"]) > mat0, "plus de matériaux")
	# Une planète pleine peut encore passer au 2e rang.
	while Economy.building_slots_used(c) < Economy.building_slots(st, c):
		c.buildings.append("centrale_fusion")
	_ok(_build(sim, home, "forum").contains("emplacement"), "planète pleine")
	_ok(_build(sim, home, "centrale_confinement") == "", "le 2e rang passe sur une planète pleine")


func _test_terraform() -> void:
	var sim := _sim("vael")  # préférés : océan puis continental
	var st := sim.state
	var desert := _free_planet(st, "desert", 2)
	var c := _plant(st, 0, desert.id, 3)
	_ok(_build(sim, desert.id, "terraformeur").contains("technologie"), "Terraformation : il faut la technologie")
	Research.grant(st, 0, ["terraformation"])
	var home := st.empires[0].capital_planet
	_ok(_build(sim, home, "terraformeur").contains("impossible"), "pas de terraformation du monde d'origine (déjà préféré)")
	var hab0 := Economy.habitability_for(st, 0, "desert")
	var cap0 := Economy.max_pop(st, desert, 0, c.buildings)
	var used := Economy.building_slots_used(c)
	_ok(_build(sim, desert.id, "terraformeur") == "", "Terraformation lancée sur un désert")
	_finish(sim, desert.id)
	_ok(desert.type == "continental", "le désert devient continental (second monde préféré des Vael)")
	_ok(Economy.habitability_for(st, 0, desert.type) == 80 and 80 > hab0, "habitabilité 80 %")
	_ok(Economy.max_pop(st, desert, 0, c.buildings) > cap0, "plus de population possible")
	_ok(Economy.building_slots_used(c) == used and not c.buildings.has("terraformeur"), "le projet ne laisse pas de bâtiment")
	_ok(st.planet_overrides.get(desert.id, {}).get("type", "") == "continental", "la terraformation est retenue (sauvegarde)")
	var st2 := GameState.from_dict(st.to_dict())
	_ok(st2.galaxy.get_planet(desert.id).type == "continental", "la terraformation survit au chargement")
	# Monde-jardin : 100 % pour tous, y compris un peuple d'un autre milieu.
	Research.grant(st, 0, ["mondes_jardins"])
	_ok(_build(sim, desert.id, "monde_jardin") == "", "Monde-jardin lancé")
	_finish(sim, desert.id)
	_ok(desert.type == "gaia", "monde-jardin achevé")
	for fid in ["ossarane", "choeur", "vael", "khthari"]:
		_ok(Economy.habitability(desert.type, GameData.faction(fid)) == 100, "monde-jardin à 100 %% pour %s" % fid)


func _test_ecumenopolis() -> void:
	var sim := _sim("vael")
	var st := sim.state
	var home := st.empires[0].capital_planet
	var p := st.galaxy.get_planet(home)
	var c: Colony = st.colonies[home]
	Research.grant(st, 0, ["arcologie_planetaire"])
	c.population = 6
	_ok(_build(sim, home, "ecumenopole").contains("population"), "Écuménopole : il faut 12 population")
	c.population = 14
	var cap0 := Economy.max_pop(st, p, 0, c.buildings)
	var y0: Dictionary = Economy.colony_yields(st, c)["gross"]
	_ok(_build(sim, home, "ecumenopole") == "", "Écuménopole lancée sur la capitale")
	_finish(sim, home)
	var y1: Dictionary = Economy.colony_yields(st, c)["gross"]
	_ok(p.type == "ecumenopole", "la capitale devient une écuménopole")
	_ok(Economy.max_pop(st, p, 0, c.buildings) >= cap0 * 2 - 4, "deux fois plus de population (%d -> %d)" % [cap0, Economy.max_pop(st, p, 0, c.buildings)])
	_ok(int(y1["food"]) < int(y0["food"]) and int(y1["materials"]) > int(y0["materials"]) and int(y1["knowledge"]) > int(y0["knowledge"]),
			"la ville produit matériaux et Savoir, plus de nourriture")


func _test_habitats_and_outposts() -> void:
	var sim := _sim("ossarane")
	var st := sim.state
	var barren := _free_planet(st, "barren")
	var rock := _free_planet(st, "asteroids")
	_ok(Economy.max_pop(st, barren, 0) == 0, "monde stérile inhabitable sans technologie")
	Research.grant(st, 0, ["cites_creusees"])
	_ok(Economy.max_pop(st, barren, 0) > 0 and Economy.max_pop(st, rock, 0) > 0, "Cités creusées : stériles et astéroïdes habitables")
	var c := _plant(st, 0, barren.id, 1)
	_ok(int(Economy.colony_yields(st, c)["gross"]["materials"]) >= 2, "les habitants d'un monde creusé extraient des matériaux")
	var gas := _free_planet(st, "gas_giant")
	var o := _plant(st, 0, gas.id, 0, Colony.KIND_OUTPOST)
	var g0: Dictionary = Economy.colony_yields(st, o)["gross"]
	var slots0 := Economy.building_slots(st, o)
	Research.grant(st, 0, ["ecopes", "fabriques_autonomes"])
	var g1: Dictionary = Economy.colony_yields(st, o)["gross"]
	_ok(int(g1["crystals"]) == int(g0["crystals"]) + 1 and int(g1["energy"]) == int(g0["energy"]) + 2, "Écopes : avant-poste de géante gazeuse +2 énergie, +1 cristal")
	_ok(Economy.building_slots(st, o) == slots0 + 1, "Fabriques autonomes : 2e emplacement sur les avant-postes")
	var home: Colony = st.colonies[st.empires[0].capital_planet]
	_ok(Economy.building_slots(st, home) == st.galaxy.get_planet(home.planet_id).size + 1, "Fabriques autonomes : +1 emplacement sur les colonies")
	# Forage du manteau : gisements doublés.
	var dep_planet: Planet = null
	for p in st.galaxy.planets:
		if p.deposits.has("minerals") and not st.colonies.has(p.id) and st.system_owner(p.system_id) == -1:
			dep_planet = p
			break
	var od := _plant(st, 0, dep_planet.id, 0, Colony.KIND_OUTPOST)
	var m0 := int(Economy.colony_yields(st, od)["gross"]["materials"])
	Research.grant(st, 0, ["forage_manteau"])
	_ok(int(Economy.colony_yields(st, od)["gross"]["materials"]) == m0 + 2, "Forage du manteau : un filon riche rapporte le double")


func _test_prefecture() -> void:
	var sim := _sim("vael")
	var st := sim.state
	var home := st.empires[0].capital_planet
	var c: Colony = st.colonies[home]
	Research.grant(st, 0, ["prefectures"])
	c.population = 5
	_ok(_build(sim, home, "prefecture").contains("population"), "Préfecture : il faut 10 population")
	c.population = 12
	# Un grand empire : des colonies fondées pour faire monter le surcoût de recherche.
	var n := 0
	for p in st.galaxy.planets:
		if n >= 14:
			break
		if p.is_habitable_type() and not st.colonies.has(p.id) and st.system_owner(p.system_id) == -1:
			_plant(st, 0, p.id, 2)
			n += 1
	var cost0 := Research.cost(st, 0, "ambassades")
	_ok(_build(sim, home, "prefecture") == "", "Préfecture lancée")
	_finish(sim, home)
	_ok(Research.cost(st, 0, "ambassades") < cost0, "la Préfecture réduit le surcoût de recherche des grands empires (%d -> %d)" % [cost0, Research.cost(st, 0, "ambassades")])
	# Une seule par système.
	var sys := st.galaxy.get_planet(home).system_id
	for pid in st.galaxy.systems[sys].planet_ids:
		if pid != home and not st.colonies.has(pid):
			var other := _plant(st, 0, pid, 12)
			other.population = 12
			_ok(_build(sim, pid, "prefecture").contains("système"), "une seule Préfecture par système")
			break


func _test_wonders() -> void:
	var sim := _sim("vael")
	var st := sim.state
	var home := st.empires[0].capital_planet
	Research.grant(st, 0, ["collecteur_stellaire", "abondance", "assemblee"])
	Research.grant(st, 1, ["assemblee"])
	var outpost := _plant(st, 0, _free_planet(st, "barren").id, 0, Colony.KIND_OUTPOST)
	_ok(_build(sim, outpost.planet_id, "collecteur_stellaire") == "", "Collecteur stellaire lancé depuis un avant-poste")
	_ok(_build(sim, home, "collecteur_stellaire").contains("une seule"), "un seul Collecteur stellaire par empire")
	var score0 := Victory.score(st, 0)
	_finish(sim, outpost.planet_id)
	_ok(Victory.score(st, 0) > score0, "la mégastructure rapporte du score")
	# Merveille unique dans la galaxie : le premier qui la lance est le seul.
	_ok(_build(sim, home, "assemblee") == "", "Assemblée interstellaire lancée")
	var rival := st.empires[1].capital_planet
	st.empires[1].resources["materials"] = 50000
	st.empires[1].resources["influence"] = 50000
	st.empires[1].resources["energy"] = 50000
	var why := SimCommands.validate(st, SimCommands.build(1, rival, "assemblee"))
	_ok(why.contains("merveille"), "un rival ne peut plus la lancer (%s)" % why)
	var op0 := Diplomacy.opinion(st, 1, 0)
	_finish(sim, home)
	_ok(Diplomacy.opinion(st, 1, 0) > op0, "l'Assemblée améliore l'opinion des autres empires (%d -> %d)" % [op0, Diplomacy.opinion(st, 1, 0)])


func _test_migration() -> void:
	var sim := _sim("vael")
	var st := sim.state
	var home := st.empires[0].capital_planet
	var c: Colony = st.colonies[home]
	var p := st.galaxy.get_planet(home)
	c.population = Economy.max_pop(st, p, 0, c.buildings)
	var small := _plant(st, 0, _free_planet(st, "ocean", 3).id, 1)
	sim.advance(150)
	var gained_without := small.population
	var sim2 := _sim("vael")
	var st2 := sim2.state
	var c2: Colony = st2.colonies[home]
	c2.population = Economy.max_pop(st2, p, 0, c2.buildings)
	var small2 := _plant(st2, 0, _free_planet(st2, "ocean", 3).id, 1)
	Research.grant(st2, 0, ["spatioports"])
	sim2.advance(150)
	_ok(small2.population > gained_without, "Spatioports : les colons d'une colonie pleine peuplent une autre colonie (%d contre %d)" % [small2.population, gained_without])
	_ok(c2.population == Economy.max_pop(st2, st2.galaxy.get_planet(home), 0, c2.buildings), "la colonie d'origine reste pleine")


func _test_upkeep_and_trade() -> void:
	var sim := _sim("vael")
	var st := sim.state
	var home: Colony = st.colonies[st.empires[0].capital_planet]
	var u0: Dictionary = Economy.colony_yields(st, home)["upkeep"]
	Research.grant(st, 0, ["replicateurs"])
	var u1: Dictionary = Economy.colony_yields(st, home)["upkeep"]
	_ok(int(u1["food"]) < int(u0["food"]), "Réplicateurs : la population mange moins (%d -> %d)" % [int(u0["food"]), int(u1["food"])])
	Research.grant(st, 0, ["abondance"])
	var u2: Dictionary = Economy.colony_yields(st, home)["upkeep"]
	_ok(int(u2["energy"]) < int(u1["energy"]), "Économie d'abondance : plus d'entretien des bâtiments")
	# Compagnies marchandes : un accord commercial rapporte le double.
	var e := st.get_empire(0)
	e.contacts.append(1)
	st.get_empire(1).contacts.append(0)
	Diplomacy.sign_treaty(st, 0, 1, Diplomacy.TRADE)
	var t0: Dictionary = Diplomacy.treaty_income(st, 0)
	Research.grant(st, 0, ["compagnies"])
	var t1: Dictionary = Diplomacy.treaty_income(st, 0)
	var sum0 := 0
	var sum1 := 0
	for r in t0:
		sum0 += int(t0[r])
	for r in t1:
		sum1 += int(t1[r])
	_ok(sum0 > 0 and sum1 >= sum0 * 2 - 1, "Compagnies marchandes : le commerce rapporte le double (%d -> %d)" % [sum0, sum1])
	_ok(Diplomacy.opinion(st, 1, 0) < Diplomacy.opinion(st, 1, 0) + 1, "opinion calculée")
	var op0 := Diplomacy.opinion(st, 1, 0)
	Research.grant(st, 0, ["ambassades"])
	_ok(Diplomacy.opinion(st, 1, 0) > op0, "Ambassades permanentes : meilleure opinion des autres")


func _test_ai_late_game() -> void:
	# Des IA qui connaissent tout et nagent dans les matériaux se servent des chantiers tardifs.
	var sim := Simulation.new(GameState.create(9, 150, 1800.0, "", {"spectator": true, "ai_level": "veteran"}))
	var st := sim.state
	sim.advance(600)
	for e in st.empires:
		Research.grant_all(st, e.id)
		for r in ["materials", "energy", "influence", "crystals"]:
			e.resources[r] = int(e.resources.get(r, 0)) + 20000
	sim.advance(400)
	var seen := {}
	for pid in st.colonies:
		var c: Colony = st.colonies[pid]
		for b in c.buildings:
			seen[b] = true
		if c.construction != "":
			seen[c.construction] = true
	var terraformed := 0
	for entry in st.chronicle:
		if String(entry.get("text", "")).contains("n'est plus un monde"):
			terraformed += 1
	_ok(seen.has("mine_profonde") or seen.has("centrale_confinement") or seen.has("ferme_verticale"), "les IA bâtissent des bâtiments de 2e rang")
	_ok(seen.has("prefecture"), "les IA bâtissent des Préfectures")
	_ok(seen.has("collecteur_stellaire") or seen.has("nexus_savoir"), "les IA bâtissent des mégastructures")
	_ok(seen.has("assemblee") or seen.has("bourse_mille_soleils"), "les IA lancent des merveilles")
	_ok(terraformed > 0 or seen.has("monde_jardin") or seen.has("terraformeur") or seen.has("ecumenopole"), "les IA terraforment (%d)" % terraformed)
