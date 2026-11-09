extends RefCounted
## Tests de l'économie et de la colonisation, appelés par smoke_test.gd.

const TEST_SAVE := "user://saves/test_economy.json"

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Économie et colonisation…")
	_test_data()
	_test_planets()
	_test_start()
	_test_monthly_income()
	_test_faction_modifiers()
	_test_colonize()
	_test_colonize_refusals()
	_test_outpost_upgrade()
	_test_build()
	_test_growth()
	_test_famine_and_blackout()
	_test_determinism_and_save()
	_test_long_run()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _test_data() -> void:
	_ok(Array(GameData.faction_ids()) == ["ossarane", "choeur", "vael", "khthari"], "les 4 factions de la V1 sont chargées")
	_ok(GameData.resource_ids().size() == 5, "4 ressources communes + cristaux de saut")
	for f: Dictionary in GameData.factions():
		for t in f["preferred"]:
			_ok(not GameData.planet_type(t).is_empty(), "%s : type préféré %s connu" % [f["id"], t])
			_ok(not GameData.planet_type(t)["pop_yields"].is_empty(), "%s : type préféré %s habitable" % [f["id"], t])
	for bid in GameData.rules()["homeworld"]["buildings"]:
		_ok(not GameData.building(bid).is_empty(), "bâtiment de départ %s connu" % bid)
	_ok(GameData.rules()["start_resources"]["materials"] is int, "les nombres des données sont des entiers")


func _test_planets() -> void:
	for seed_value in [0, 42, 1337]:
		var g := GalaxyGenerator.generate(seed_value)
		var g2 := GalaxyGenerator.generate(seed_value)
		var total := 0
		var same := true
		var coherent := true
		for s in g.systems:
			total += s.planet_count
			if s.planet_ids.size() != s.planet_count:
				coherent = false
			for k in s.planet_ids.size():
				var p := g.get_planet(s.planet_ids[k])
				if p.system_id != s.id or p.index != k or p.size < 1 or p.size > 5 or GameData.planet_type(p.type).is_empty():
					coherent = false
		for i in g.planets.size():
			var a := g.planets[i]
			var b := g2.planets[i]
			if a.type != b.type or a.size != b.size or a.deposits != b.deposits:
				same = false
		_ok(g.planets.size() == total, "graine %d : une planète par emplacement (%d)" % [seed_value, total])
		_ok(coherent, "graine %d : planètes cohérentes avec leur système" % seed_value)
		_ok(same and g.planets.size() == g2.planets.size(), "graine %d : planètes déterministes" % seed_value)
	var g := GalaxyGenerator.generate(42)
	var p := g.planets[0]
	_ok(p.display_name(g).begins_with(g.systems[p.system_id].system_name), "le nom d'une planète suit son système")


func _test_start() -> void:
	var st := GameState.create(42)
	_ok(st.empires.size() == 4, "4 empires au départ")
	var homes := {}
	for e in st.empires:
		var c: Colony = st.colonies.get(e.capital_planet)
		var p := st.galaxy.get_planet(e.capital_planet)
		homes[p.system_id] = true
		_ok(c != null and c.owner == e.id and c.is_colony() and c.is_established(), "%s : monde d'origine colonisé" % e.faction_id)
		_ok(c.population == 8 and c.buildings.has("capitale"), "%s : 8 pop et une capitale" % e.faction_id)
		_ok(p.type == e.faction()["preferred"][0] and p.size == 4, "%s : monde d'origine à son goût" % e.faction_id)
		_ok(Economy.habitability(p.type, e.faction()) == 100, "%s : habitabilité 100 %% chez soi" % e.faction_id)
		_ok(st.system_owner(p.system_id) == e.id, "%s : système d'origine revendiqué" % e.faction_id)
		var income: Dictionary = Economy.empire_income(st, e.id)["net"]
		_ok(income["food"] >= 0 and income["energy"] > 0 and income["materials"] > 0 and income["influence"] > 0,
				"%s : économie de départ viable (%s)" % [e.faction_id, GameData.format_amounts(income, true)])
	_ok(homes.size() == 4, "4 systèmes d'origine distincts")
	var osso := st.empires[0]
	var has_crystals := false
	for pid in st.galaxy.systems[st.galaxy.get_planet(osso.capital_planet).system_id].planet_ids:
		has_crystals = has_crystals or st.galaxy.get_planet(pid).deposits.has("crystals")
	_ok(has_crystals, "Ossarane : gisement de cristaux garanti chez soi")
	var vael_first := GameState.create(42, 150, 1800.0, "vael")
	_ok(vael_first.empires[0].faction_id == "vael", "la faction du joueur devient l'empire 0")


func _test_monthly_income() -> void:
	var sim := Simulation.new(GameState.create(7))
	var e := sim.state.empires[0]
	var before := e.resources.duplicate()
	sim.advance(29)
	_ok(e.resources == before, "pas de revenu avant la fin du mois")
	var net: Dictionary = Economy.empire_income(sim.state, 0)["net"]
	sim.step()
	var ok := true
	for r in net:
		if e.resources[r] != maxi(0, before[r] + net[r]):
			ok = false
	_ok(ok, "bilan du mois appliqué exactement (%s)" % GameData.format_amounts(net, true))


func _test_faction_modifiers() -> void:
	var st := GameState.create(3)
	var vael := _empire(st, "vael")
	var y := Economy.colony_yields(st, st.colonies[vael.capital_planet])
	var inc := Economy.empire_income(st, vael.id)
	_ok(inc["gross"]["influence"] == int(y["gross"]["influence"]) * 150 / 100, "Vael : +50 % d'influence")
	var kh := _empire(st, "khthari")
	var c: Colony = st.colonies[kh.capital_planet]
	_ok(Economy.growth_per_day(st, c) == 2 * Economy.growth_per_day(st, st.colonies[vael.capital_planet]), "Kh'thari : croissance doublée")
	_ok(Economy.colony_yields(st, c)["upkeep"]["food"] == c.population * 3 / 2, "Kh'thari : chaque pop mange 50 % de plus")
	var choeur := _empire(st, "choeur")
	var g: Dictionary = Economy.colony_yields(st, st.colonies[choeur.capital_planet])["gross"]
	_ok(Economy.empire_income(st, choeur.id)["gross"]["materials"] == int(g["materials"]) * 125 / 100, "Chœur Éternel : +25 % de matériaux")


func _test_colonize() -> void:
	var sim := Simulation.new(GameState.create(42))
	var st := sim.state
	var target := _find_target(st, 0, Colony.KIND_COLONY)
	_ok(target != -1, "une planète colonisable à portée existe")
	if target == -1:
		return
	var e := st.empires[0]
	var mat: int = e.resources["materials"]
	_ok(sim.submit(SimCommands.colonize(0, target, Colony.KIND_COLONY)), "ordre de colonisation accepté")
	sim.flush_commands()
	var c: Colony = st.colonies.get(target)
	_ok(c != null and not c.is_established() and c.population == 0, "colonie en fondation, sans population")
	_ok(e.resources["materials"] == mat - 150, "coût payé à l'application de l'ordre")
	_ok(st.system_owner(st.galaxy.get_planet(target).system_id) == 0, "le système est revendiqué dès le lancement")
	var founded := []
	sim.chronicle_added.connect(func(entry: Dictionary) -> void:
		if entry["text"].contains("fonde une colonie"):
			founded.append(entry))
	sim.advance(Economy.claim_days(Colony.KIND_COLONY) - 1)
	_ok(not c.is_established(), "pas encore fondée la veille")
	sim.step()
	_ok(c.is_established() and c.population == 1, "colonie fondée avec 1 pop au bout de %d jours" % Economy.claim_days(Colony.KIND_COLONY))
	_ok(founded.size() == 1, "le chroniqueur annonce la fondation")


func _test_colonize_refusals() -> void:
	var sim := Simulation.new(GameState.create(42))
	var st := sim.state
	var e := st.empires[0]
	var reasons := []
	sim.command_rejected.connect(func(_c: Dictionary, r: String) -> void: reasons.append(r))
	_ok(not sim.submit(SimCommands.colonize(0, 999999)), "refus : planète inconnue")
	_ok(not sim.submit(SimCommands.colonize(9, 0)), "refus : empire inconnu")
	_ok(not sim.submit(SimCommands.colonize(0, e.capital_planet)), "refus : planète déjà revendiquée")
	var rival := st.empires[1]
	var rival_sys := st.galaxy.get_planet(rival.capital_planet).system_id
	for pid in st.galaxy.systems[rival_sys].planet_ids:
		if pid != rival.capital_planet:
			_ok(not sim.submit(SimCommands.colonize(0, pid, Colony.KIND_OUTPOST)), "refus : système d'un autre empire")
			_ok(reasons.back().contains(rival.display_name()), "le refus nomme l'empire rival")
			break
	var far := _find_far_planet(st, 0)
	_ok(far != -1 and not sim.submit(SimCommands.colonize(0, far, Colony.KIND_OUTPOST)), "refus : hors de portée")
	var hostile := _find_target(st, 0, Colony.KIND_OUTPOST, true)
	if hostile != -1:
		_ok(not sim.submit(SimCommands.colonize(0, hostile, Colony.KIND_COLONY)), "refus : colonie sur une planète inhabitable")
		_ok(reasons.back().contains("inhabitable"), "raison : inhabitable")
	_ok(not sim.submit(SimCommands.colonize(0, 0, "station")), "refus : type de colonisation inconnu")

	var saved := e.resources.duplicate()
	var target := _find_target(st, 0, Colony.KIND_OUTPOST)
	e.resources["materials"] = 10
	_ok(not sim.submit(SimCommands.colonize(0, target, Colony.KIND_OUTPOST)), "refus : ressources insuffisantes")
	_ok(reasons.back().contains("ressources insuffisantes"), "raison : ressources insuffisantes")
	e.resources = saved
	e.resources["materials"] = 10000
	e.resources["influence"] = 10000
	var launched := 0
	for i in 3:
		var t := _find_target(st, 0, Colony.KIND_OUTPOST)
		if t != -1 and sim.submit(SimCommands.colonize(0, t, Colony.KIND_OUTPOST)):
			sim.flush_commands()
			launched += 1
	_ok(launched == int(GameData.rules()["max_projects"]), "au plus %d colonisations simultanées (lancées : %d)" % [GameData.rules()["max_projects"], launched])

	# Deux ordres valides à la soumission, mais un seul payable : le second est refusé à l'application.
	var sim2 := Simulation.new(GameState.create(42))
	var e2 := sim2.state.empires[0]
	e2.resources["materials"] = 100
	var t1 := _find_target(sim2.state, 0, Colony.KIND_OUTPOST)
	var t2 := -1
	for pid in sim2.state.galaxy.planets.size():
		if pid != t1 and Economy.check_colonize(sim2.state, 0, pid, Colony.KIND_OUTPOST) == "":
			t2 = pid
			break
	_ok(sim2.submit(SimCommands.colonize(0, t1, Colony.KIND_OUTPOST)) and sim2.submit(SimCommands.colonize(0, t2, Colony.KIND_OUTPOST)), "deux ordres acceptés à la soumission")
	sim2.flush_commands()
	_ok(sim2.state.colonies.has(t1) and not sim2.state.colonies.has(t2), "revalidation : le second ordre, impayable, est refusé")
	_ok(e2.resources["materials"] == 40, "un seul coût payé")


func _test_outpost_upgrade() -> void:
	var sim := Simulation.new(GameState.create(42, 150, 1800.0, "", {"ai_level": ""}))  # aucune IA : on compte les colonies
	var st := sim.state
	var target := _find_target(st, 0, Colony.KIND_COLONY)
	sim.submit(SimCommands.colonize(0, target, Colony.KIND_OUTPOST))
	sim.flush_commands()
	_ok(not sim.submit(SimCommands.colonize(0, target, Colony.KIND_COLONY)), "refus : améliorer un avant-poste pas encore établi")
	sim.advance(Economy.claim_days(Colony.KIND_OUTPOST))
	var c: Colony = st.colonies[target]
	_ok(c.is_established() and not c.is_colony() and c.population == 0, "avant-poste établi, sans population")
	var y := Economy.colony_yields(st, c)
	_ok(y["upkeep"]["food"] == 0, "un avant-poste ne mange pas")
	_ok(sim.submit(SimCommands.colonize(0, target, Colony.KIND_COLONY)), "un avant-poste peut devenir une colonie")
	sim.flush_commands()
	sim.advance(Economy.claim_days(Colony.KIND_COLONY))
	_ok(c.is_colony() and c.is_established() and c.population == 1, "avant-poste transformé en colonie")
	_ok(st.colonies.size() == 5, "pas de colonie en double")


func _test_build() -> void:
	var sim := Simulation.new(GameState.create(42))
	var st := sim.state
	var e := st.empires[0]
	e.resources["materials"] = 5000
	e.resources["energy"] = 5000
	var home := e.capital_planet
	var reasons := []
	sim.command_rejected.connect(func(_c: Dictionary, r: String) -> void: reasons.append(r))
	_ok(not sim.submit(SimCommands.build(0, home, "capitale")), "refus : la capitale ne se construit pas")
	_ok(not sim.submit(SimCommands.build(0, home, "tour_de_babel")), "refus : bâtiment inconnu")
	_ok(not sim.submit(SimCommands.build(1, home, "forum")), "refus : construire chez un autre empire")
	var rival_home := st.empires[1].capital_planet
	_ok(not sim.submit(SimCommands.build(0, rival_home, "forum")), "refus : planète d'un rival")
	if not st.galaxy.get_planet(home).deposits.has("crystals"):
		_ok(not sim.submit(SimCommands.build(0, home, "raffinerie")) and reasons.back().contains("gisement"), "refus : raffinerie sans gisement")

	var food_before: int = Economy.empire_income(st, 0)["net"]["food"]
	_ok(sim.submit(SimCommands.build(0, home, "ferme_hydroponique")), "chantier accepté")
	sim.flush_commands()
	_ok(e.resources["materials"] == 5000 - 80, "coût du bâtiment payé")
	_ok(not sim.submit(SimCommands.build(0, home, "forum")), "refus : un seul chantier à la fois par planète")
	sim.advance(59)
	_ok(st.colonies[home].construction == "ferme_hydroponique", "chantier toujours en cours au jour 59")
	sim.advance(1)
	var c: Colony = st.colonies[home]
	_ok(c.construction == "" and c.buildings.count("ferme_hydroponique") == 2, "bâtiment achevé au bout de 60 jours")
	var food_after: int = Economy.empire_income(st, 0)["net"]["food"]
	_ok(food_after - food_before >= 6 - 2, "la nouvelle ferme nourrit l'empire (%+d)" % (food_after - food_before))

	# Emplacements : taille 4, 2 déjà occupés (la capitale ne compte pas) + la ferme = 3.
	_ok(sim.submit(SimCommands.build(0, home, "habitats")), "habitats acceptés")
	sim.flush_commands()
	sim.advance(120)
	_ok(c.buildings.has("habitats"), "habitats achevés")
	var p := st.galaxy.get_planet(home)
	_ok(Economy.max_pop(st, p, 0, c.buildings) == Economy.max_pop(st, p, 0) + 4, "les habitats ajoutent 4 pop max")
	_ok(not sim.submit(SimCommands.build(0, home, "centrale_fusion")) and reasons.back().contains("emplacement"), "refus : plus d'emplacement libre")

	# Pénurie d'énergie : les chantiers s'arrêtent.
	var sim2 := Simulation.new(GameState.create(42))
	var e2 := sim2.state.empires[0]
	sim2.submit(SimCommands.build(0, e2.capital_planet, "ferme_hydroponique"))
	sim2.flush_commands()
	e2.blackout = true
	sim2.advance(10)
	_ok(sim2.state.colonies[e2.capital_planet].construction_days == 60, "pas d'avancement en pénurie d'énergie")


func _test_growth() -> void:
	var sim := Simulation.new(GameState.create(5))
	var st := sim.state
	var c: Colony = st.colonies[st.empires[0].capital_planet]
	var start := c.population
	sim.advance(Economy.growth_threshold(start) / Economy.growth_per_day(st, c) + 1)
	_ok(c.population == start + 1, "la population grandit (%d -> %d)" % [start, c.population])
	sim.advance(360 * 5)
	var cap := Economy.max_pop(st, st.galaxy.get_planet(c.planet_id), c.owner, c.buildings)
	_ok(c.population <= cap, "la population ne dépasse pas le maximum (%d/%d)" % [c.population, cap])
	var kh := _empire(st, "khthari")
	_ok(st.colonies[kh.capital_planet].population > 8, "l'Essaim Kh'thari a grandi")


func _test_famine_and_blackout() -> void:
	var sim := Simulation.new(GameState.create(9))
	var st := sim.state
	# L'Essaim mange 50 % de plus : 30 pop, c'est bien plus que ce que son monde nourrit.
	var e := _empire(st, "khthari")
	var c: Colony = st.colonies[e.capital_planet]
	c.population = 30
	e.resources["food"] = 0
	var famine := []
	sim.chronicle_added.connect(func(entry: Dictionary) -> void:
		if entry["text"].contains("Famine"):
			famine.append(entry))
	sim.advance(30)
	_ok(e.starving, "famine déclarée")
	_ok(c.population == 29, "la famine coûte une population")
	_ok(e.resources["food"] == 0, "les stocks ne passent jamais sous zéro")
	sim.advance(30)
	_ok(famine.size() == 1, "la famine n'est annoncée qu'une fois")
	var g := c.growth
	sim.advance(5)
	_ok(c.growth == 0 and g == 0, "pas de croissance pendant une famine")

	var sim2 := Simulation.new(GameState.create(9))
	var e2 := sim2.state.empires[0]
	var home: Colony = sim2.state.colonies[e2.capital_planet]
	home.buildings.append_array(["forum", "habitats", "raffinerie", "forum"])  # entretien énorme
	for i in 12:
		home.buildings.append("forum")
	e2.resources["energy"] = 0
	sim2.advance(30)
	_ok(e2.blackout and e2.resources["energy"] == 0, "pénurie d'énergie déclarée, stock à zéro")


func _test_determinism_and_save() -> void:
	var a := _scripted_economy(2024, 900)
	var b := _scripted_economy(2024, 900)
	_ok(a.state.checksum() == b.state.checksum(), "économie déterministe : mêmes ordres = même empreinte")
	_ok(a.state.colonies.size() > 4, "la partie scénarisée a colonisé (%d revendications)" % a.state.colonies.size())
	var replayed := Simulation.replay(GameState.create(2024), a.command_log, 900)
	_ok(replayed.state.checksum() == a.state.checksum(), "rediffusion d'une partie avec colonisation et chantiers")

	var copy := GameState.from_dict(JSON.parse_string(JSON.stringify(a.state.to_dict())))
	_ok(copy != null, "état avec colonies relu (%s)" % GameState.last_error)
	if copy:
		_ok(copy.checksum() == a.state.checksum(), "colonies, empires et planètes modifiées survivent au JSON")
		_ok(copy.system_owner(copy.galaxy.get_planet(copy.empires[0].capital_planet).system_id) == 0, "propriétaires des systèmes reconstruits")
		var cp := copy.empires[0].capital_planet
		_ok(copy.galaxy.get_planet(cp).type == a.state.galaxy.get_planet(cp).type, "le monde d'origine garde son type après chargement")

	SaveGame.save_state(a.state, TEST_SAVE)
	var loaded := SaveGame.load_state(TEST_SAVE)
	_ok(loaded != null, "sauvegarde avec économie relue (%s)" % SaveGame.last_error)
	if loaded:
		var sa := Simulation.new(a.state)
		var sb := Simulation.new(loaded)
		for t in 400:
			if t == 10:
				for s in [sa, sb]:
					var target := _find_target(s.state, 0, Colony.KIND_OUTPOST)
					if target != -1:
						s.submit(SimCommands.colonize(0, target, Colony.KIND_OUTPOST))
			sa.step()
			sb.step()
		_ok(sa.state.checksum() == sb.state.checksum(), "sauvegarder puis reprendre = même économie")
	DirAccess.remove_absolute(TEST_SAVE)

	var d := a.state.to_dict()
	d["version"] = 1
	_ok(GameState.from_dict(d) == null and GameState.last_error.contains("version"), "les sauvegardes de l'ancien format sont refusées proprement")
	var bad := a.state.to_dict()
	bad["empires"][0]["faction"] = "inconnue"
	_ok(GameState.from_dict(bad) == null, "faction inconnue refusée")


func _test_long_run() -> void:
	var sim := _scripted_economy(77, 3600)
	var ok := true
	for e in sim.state.empires:
		for r in e.resources:
			if e.resources[r] < 0:
				ok = false
	_ok(ok, "10 ans d'économie sans stock négatif")
	print("  10 ans scénarisés : %d revendications, joueur %s" % [sim.state.colonies.size(),
			GameData.format_amounts(sim.state.empires[0].resources)])


## Partie scénarisée : le joueur colonise et construit dès qu'il le peut.
func _scripted_economy(seed_value: int, ticks: int) -> Simulation:
	var sim := Simulation.new(GameState.create(seed_value))
	var builds := ["complexe_minier", "ferme_hydroponique", "centrale_fusion", "forum"]
	for t in ticks:
		if t % 20 == 0:
			var target := _find_target(sim.state, 0, Colony.KIND_COLONY)
			if target == -1:
				target = _find_target(sim.state, 0, Colony.KIND_OUTPOST)
			if target != -1:
				var kind := Colony.KIND_COLONY if Economy.check_colonize(sim.state, 0, target, Colony.KIND_COLONY) == "" else Colony.KIND_OUTPOST
				sim.submit(SimCommands.colonize(0, target, kind))
			for pid in sim.state.sorted_colony_ids():
				sim.submit(SimCommands.build(0, pid, builds[(t / 20 + pid) % builds.size()]))
		sim.step()
	return sim


## Première planète que l'empire peut revendiquer de cette façon (-1 si aucune).
## hostile_only : seulement des planètes inhabitables pour lui.
func _find_target(st: GameState, empire_id: int, kind: String, hostile_only := false) -> int:
	for p in st.galaxy.planets:
		if hostile_only and Economy.max_pop(st, p, empire_id) > 0:
			continue
		if Economy.check_colonize(st, empire_id, p.id, kind) == "":
			return p.id
	return -1


func _find_far_planet(st: GameState, empire_id: int) -> int:
	for p in st.galaxy.planets:
		if st.system_owner(p.system_id) == -1 and not Economy.in_range(st, empire_id, p.system_id):
			return p.id
	return -1


func _empire(st: GameState, faction_id: String) -> Empire:
	for e in st.empires:
		if e.faction_id == faction_id:
			return e
	return null
