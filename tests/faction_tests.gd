extends RefCounted
## Tests des traits de faction (FactionTraits), appelés par smoke_test.gd.
## Chaque faction est jouée comme empire 0 (GameState.create(..., faction)).

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Traits de faction…")
	_test_data()
	_test_ossarane()
	_test_choeur()
	_test_vael()
	_test_khthari()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _game(faction: String, seed_value := 21) -> Simulation:
	return Simulation.new(GameState.create(seed_value, 150, 1800.0, faction))


## Planète d'un autre système que la capitale, à exactement `jumps` sauts (ou au plus près au-dessus).
func _planet_at_jumps(st: GameState, empire_id: int, jumps: int) -> int:
	var cap_sys := st.galaxy.get_planet(st.get_empire(empire_id).capital_planet).system_id
	var d := FactionTraits.jumps_from(st.galaxy, cap_sys)
	for want in range(jumps, jumps + 6):
		for s in st.galaxy.systems:
			if int(d.get(s.id, -1)) == want and not s.planet_ids.is_empty() and st.system_owner(s.id) == -1:
				return s.planet_ids[0]
	return -1


## Pose directement une revendication établie (pour tester les rendements sans attendre la fondation).
func _plant(st: GameState, empire_id: int, planet_id: int, kind := Colony.KIND_COLONY, pop := 1) -> Colony:
	var c := Colony.new()
	c.planet_id = planet_id
	c.owner = empire_id
	c.kind = kind
	c.population = pop if kind == Colony.KIND_COLONY else 0
	st.add_colony(c)
	return c


func _test_data() -> void:
	var ok := true
	for f: Dictionary in GameData.factions():
		var traits: Array = f.get("traits", [])
		if traits.size() < 3:
			ok = false
		for t: Dictionary in traits:
			if String(t.get("name", "")) == "" or String(t.get("text", "")) == "":
				ok = false
	_ok(ok, "chaque faction a au moins trois traits nommés et décrits")
	_ok(EmpireBar.trait_summary(GameData.faction("vael")).contains("Vote d'urgence"), "résumé des traits lisible")


func _test_ossarane() -> void:
	var sim := _game("ossarane")
	var st := sim.state
	var e := st.empires[0]
	var scout: Fleet = null
	for f in Fleets.empire_fleets(st, 0):
		if f.count("scout") > 0:
			scout = f
	_ok(Fleets.speed(scout, st) == int(GameData.ship("scout")["speed"]) * 130 / 100, "Ossarane : flottes 30 % plus rapides")
	var rival_scout: Fleet = null
	for f in Fleets.empire_fleets(st, 1):
		if f.count("scout") > 0:
			rival_scout = f
	_ok(Fleets.speed(rival_scout, st) == int(GameData.ship("scout")["speed"]), "les autres peuples gardent la vitesse de base")

	var near := _planet_at_jumps(st, 0, 1)
	var far := _planet_at_jumps(st, 0, 5)
	_ok(near != -1 and far != -1, "planètes de test trouvées")
	if near == -1 or far == -1:
		return
	var inf_before := int(Economy.empire_income(st, 0)["gross"]["influence"])
	var c_near := _plant(st, 0, near)
	_ok(FactionTraits.is_fief(st, c_near) and not FactionTraits.is_far_fief(st, c_near), "colonie voisine = fief proche")
	var y_near: Dictionary = Economy.colony_yields(st, c_near)
	_ok(int(y_near["gross"]["influence"]) >= 1 and int(y_near["upkeep"]["crystals"]) == 0, "un fief peuplé verse 1 influence, sans cristal")
	_ok(int(Economy.empire_income(st, 0)["gross"]["influence"]) > inf_before, "le tribut s'ajoute à l'influence de l'empire")
	var c_far := _plant(st, 0, far)
	_ok(FactionTraits.is_far_fief(st, c_far), "colonie à 5 sauts ou plus = fief lointain")
	var y_far: Dictionary = Economy.colony_yields(st, c_far)
	_ok(int(y_far["upkeep"]["crystals"]) == 1, "un fief lointain réclame 1 cristal par mois")
	_ok(FactionTraits.fief_counts(st, 0) == {"fiefs": 2, "far": 1}, "décompte des fiefs")
	_ok(String(FactionTraits.gauge(st, 0).get("value", "")) == "2 (1 loin)", "jauge des fiefs dans le panneau d'empire")

	# Pas de cristaux : dissidence au bilan, et le fief lointain produit moitié moins.
	e.resources["crystals"] = 0
	var events := []
	sim.chronicle_added.connect(func(entry: Dictionary) -> void:
		if entry["text"].contains("Dissidence"):
			events.append(entry))
	sim.advance(30)
	_ok(e.dissent and events.size() == 1, "sans cristaux, les fiefs lointains entrent en dissidence")
	var y_dissent: Dictionary = Economy.colony_yields(st, c_far)
	var halved := true
	for r in y_far["gross"]:
		if int(y_dissent["gross"][r]) != int(y_far["gross"][r]) * 50 / 100:
			halved = false
	_ok(halved, "en dissidence, un fief lointain produit moitié moins")
	_ok(int(Economy.colony_yields(st, c_near)["gross"]["influence"]) == int(y_near["gross"]["influence"]), "les fiefs proches restent loyaux")
	e.resources["crystals"] = 50
	sim.advance(30)
	_ok(not e.dissent, "les cristaux revenus, le serment est renouvelé")

	# Les autres peuples n'ont pas de fiefs.
	var other := _game("vael").state
	var oc := _plant(other, 0, _planet_at_jumps(other, 0, 5))
	_ok(not FactionTraits.is_fief(other, oc) and int(Economy.colony_yields(other, oc)["upkeep"]["crystals"]) == 0, "pas de fiefs hors d'Ossarane")


func _test_choeur() -> void:
	var sim := _game("choeur")
	var st := sim.state
	var e := st.empires[0]
	var fv: Dictionary = e.faction()["fervor"]
	_ok(e.fervor == int(fv["start"]), "Chœur : ferveur de départ (%d)" % e.fervor)
	_ok(FactionTraits.fervor_delta(st, 0) == 1 - 5, "ferveur : +1 par colonie, -5 par mois")
	sim.advance(30)
	_ok(e.fervor == int(fv["start"]) - 4, "la ferveur baisse au bilan mensuel (%d)" % e.fervor)

	var cap: Colony = st.colonies[e.capital_planet]
	var pop := cap.population
	var base_mat := int(Economy.empire_income(st, 0)["gross"]["materials"])
	_ok(sim.submit(SimCommands.sacrifice(0, e.capital_planet)), "offrande acceptée")
	sim.flush_commands()
	_ok(cap.population == pop - 1 and e.fervor == int(fv["start"]) - 4 + 20, "offrande : -1 population, +20 ferveur")
	_ok(FactionTraits.fervor_pct(st, 0) == 125, "ferveur à 60 ou plus : Exaltation")
	var exalted := int(Economy.empire_income(st, 0)["gross"]["materials"])
	_ok(exalted > base_mat, "l'Exaltation augmente la production (%d -> %d matériaux)" % [base_mat, exalted])
	e.fervor = 0
	_ok(FactionTraits.fervor_pct(st, 0) == 75, "ferveur à 0 : le dieu se tait (-25 %)")
	_ok(int(Economy.empire_income(st, 0)["gross"]["materials"]) < base_mat, "le silence du dieu réduit la production")
	e.fervor = 100
	_ok(not sim.submit(SimCommands.sacrifice(0, e.capital_planet)), "refus : ferveur déjà à son comble")
	e.fervor = 10
	cap.population = 1
	_ok(not sim.submit(SimCommands.sacrifice(0, e.capital_planet)), "refus : le dernier fidèle reste")
	_ok(not sim.submit(SimCommands.sacrifice(1, st.empires[1].capital_planet)), "refus : les autres peuples ne sacrifient pas")
	_ok(FactionTraits.gauge(st, 0).get("label", "") == "Ferveur", "jauge de ferveur dans le panneau d'empire")

	# Pèlerins zélés : une colonie fondée démarre à 2 population.
	var pid := _planet_at_jumps(st, 0, 1)
	var c := _plant(st, 0, pid, Colony.KIND_COLONY, 0)
	c.days_left = 1
	sim.step()
	_ok(c.is_established() and c.population == 2, "Chœur : nouvelle colonie à 2 population")


func _test_vael() -> void:
	var sim := _game("vael")
	var st := sim.state
	var e := st.empires[0]
	_ok(Economy.habitability("arctic", e.faction()) == 60, "Vael : un monde glaciaire habitable à 60 %")
	_ok(Economy.habitability("arctic", GameData.faction("khthari")) == 40, "les autres gardent l'habitabilité de base (40 %)")
	_ok(Economy.habitability("barren", e.faction()) == 0, "le plancher ne rend pas un monde stérile habitable")

	# Vote d'urgence sur un bâtiment.
	e.resources["materials"] = 1000
	e.resources["influence"] = 100
	_ok(not sim.submit(SimCommands.rush(0, e.capital_planet, "building")), "refus : aucun chantier à presser")
	sim.submit(SimCommands.build(0, e.capital_planet, "centrale_fusion"))
	sim.flush_commands()
	var cost := FactionTraits.rush_cost(st, 0, e.capital_planet, "building")
	_ok(cost == 30, "vote d'urgence : 1 influence pour 2 jours (60 j -> %d)" % cost)
	_ok(sim.submit(SimCommands.rush(0, e.capital_planet, "building")), "vote d'urgence accepté")
	sim.flush_commands()
	_ok(e.resources["influence"] == 100 - cost, "l'influence est dépensée")
	sim.step()
	_ok(st.colonies[e.capital_planet].buildings.has("centrale_fusion"), "le bâtiment est achevé dès le lendemain")
	# Et sur un vaisseau.
	sim.submit(SimCommands.build_ship(0, e.capital_planet, "scout"))
	sim.flush_commands()
	_ok(sim.submit(SimCommands.rush(0, e.capital_planet, "ship")), "vote d'urgence sur un vaisseau")
	var n := Fleets.empire_fleets(st, 0).size()
	sim.flush_commands()
	sim.step()
	_ok(Fleets.empire_fleets(st, 0).size() == n + 1, "le vaisseau sort des chantiers le lendemain")
	e.resources["influence"] = 0
	sim.submit(SimCommands.build(0, e.capital_planet, "forum"))
	sim.flush_commands()
	_ok(not sim.submit(SimCommands.rush(0, e.capital_planet, "building")), "refus : influence insuffisante")
	_ok(FactionTraits.check_rush(st, 1, st.empires[1].capital_planet, "building") != "", "refus : seuls les Vael votent l'urgence")

	# Ambassades : +2 influence par empire rencontré (avant le bonus de 50 %).
	var before := int(Economy.empire_income(st, 0)["gross"]["influence"])
	e.contacts.assign([1, 2])
	var after := int(Economy.empire_income(st, 0)["gross"]["influence"])
	_ok(after - before == 4 * 150 / 100, "ambassades : +2 influence par contact (%+d)" % (after - before))


func _test_khthari() -> void:
	var sim := _game("khthari")
	var st := sim.state
	var e := st.empires[0]
	var ships := FactionTraits.ship_ids_for("khthari")
	_ok(ships.has("spore_ship") and not ships.has("colony_ship"), "Kh'thari : vaisseaux-spores à la place des vaisseaux colons")
	_ok(not FactionTraits.ship_ids_for("vael").has("spore_ship"), "les autres peuples n'ont pas de vaisseau-spore")
	_ok(not sim.submit(SimCommands.build_ship(0, e.capital_planet, "colony_ship")), "refus : l'Essaim ne construit pas de vaisseau colon")
	_ok(not sim.submit(SimCommands.build_ship(1, st.empires[1].capital_planet, "spore_ship")), "refus : vaisseau-spore réservé à l'Essaim")

	var cap: Colony = st.colonies[e.capital_planet]
	var pop := cap.population
	_ok(sim.submit(SimCommands.build_ship(0, e.capital_planet, "spore_ship")), "vaisseau-spore accepté")
	sim.flush_commands()
	_ok(cap.population == pop - 2, "le vaisseau-spore emporte 2 population")
	cap.ship_build = ""
	cap.population = 2
	_ok(not sim.submit(SimCommands.build_ship(0, e.capital_planet, "spore_ship")), "refus : pas assez de population")

	# Coloniser sans influence, avec le vaisseau-spore de départ.
	var spore: Fleet = null
	for f in Fleets.empire_fleets(st, 0):
		if f.count("spore_ship") > 0:
			spore = f
	_ok(spore != null and Fleets.colonizer_ship(spore) == "spore_ship", "le vaisseau-spore sert de vaisseau colon")
	var pid := _planet_at_jumps(st, 0, 1)
	_ok(not Economy.claim_cost_for(st, 0, pid, Colony.KIND_OUTPOST).has("influence"), "coloniser ne coûte pas d'influence à l'Essaim")
	_ok(Economy.claim_cost_for(st, 0, e.capital_planet, Colony.KIND_COLONY).get("materials", 0) > 0, "les matériaux restent dus")

	# Biomasse : une colonie pleine digère sa croissance en matériaux.
	cap.population = Economy.max_pop(st, st.galaxy.get_planet(cap.planet_id), 0, cap.buildings)
	cap.growth = Economy.growth_threshold(cap.population) - 1
	var mat: int = e.resources["materials"]
	sim.step()
	var bio := int(e.faction()["biomass"]["materials"])
	_ok(e.resources["materials"] == mat + bio and e.biomass == bio, "biomasse : +%d matériaux pour une population en trop" % bio)
	_ok(cap.population == Economy.max_pop(st, st.galaxy.get_planet(cap.planet_id), 0, cap.buildings), "la population ne dépasse pas le maximum")
	var other := _game("vael")
	var oc: Colony = other.state.colonies[other.state.empires[0].capital_planet]
	oc.population = Economy.max_pop(other.state, other.state.galaxy.get_planet(oc.planet_id), 0, oc.buildings)
	oc.growth = 50
	other.step()
	_ok(oc.growth == 0 and other.state.empires[0].biomass == 0, "pas de biomasse hors de l'Essaim")


func _test_save() -> void:
	var st := GameState.create(5, 150, 1800.0, "choeur")
	st.empires[0].fervor = 37
	st.empires[1].dissent = true
	st.empires[2].biomass = 45
	var back := GameState.from_dict(st.to_dict())
	_ok(back != null and back.empires[0].fervor == 37 and back.empires[1].dissent and back.empires[2].biomass == 45,
			"ferveur, dissidence et biomasse survivent à la sauvegarde")
	_ok(back != null and back.checksum() == st.checksum(), "même empreinte après rechargement")
