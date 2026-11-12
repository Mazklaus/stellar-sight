extends RefCounted
## Tests des pirates (Pirates, PirateSystem, AiPirates) : placement des repaires, choix de la cible,
## raid complet (pillage, stabilité, retour), tribut, contrat, prime, démantèlement, garde qui se
## reforme et grossit, peuple voilé, talents des couches d'espèce, ordre Patrouille, IA ; lot 3 :
## opérations d'espionnage (dissidence, partisans, pirates incités), réseau intérieur, rançon des
## héros, ralliement de la Horde, port franc ; sauvegarde 24 et déterminisme. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Pirates…")
	_test_setup()
	_test_target()
	_test_raid()
	_test_actions()
	_test_dismantle()
	_test_guard()
	_test_talents()
	_test_patrol()
	_test_ai()
	_test_spy_ops()
	_test_ransom()
	_test_rally()
	_test_port()
	_test_save()
	_test_determinism()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 11, faction := "vael", density := "normaux") -> GameState:
	return GameState.create(seed_value, 150, 1800.0, faction, {"ai_level": "", "pirates": density})


func _home(st: GameState, empire_id := 0) -> int:
	return FactionTraits.capital_system(st, empire_id)


## Fonde une colonie établie de l'empire dans un système libre à portée (1 à max_jumps sauts) du repaire.
func _plant_near(st: GameState, empire_id: int, lair: int, max_jumps := 3, pop := 4) -> int:
	var jumps := FactionTraits.jumps_from(st.galaxy, lair)
	var ids := []
	for s in st.galaxy.systems:
		var j := int(jumps.get(s.id, 999))
		if j >= 1 and j <= max_jumps and st.system_owner(s.id) < 0 and not s.planet_ids.is_empty() and not Pirates.is_lair(st, s.id):
			ids.append([j, s.id])
	ids.sort()
	if ids.is_empty():
		return -1
	var sid := int(ids[0][1])
	var c := Colony.new()
	c.planet_id = st.galaxy.systems[sid].planet_ids[0]
	c.owner = empire_id
	c.kind = Colony.KIND_COLONY
	c.population = pop
	st.add_colony(c)
	return sid


## Rend un empire seul pillable : ses rivaux n'ont que leur capitale, jamais visée.
func _lair(st: GameState) -> int:
	return Pirates.lair_ids(st)[0]


func _test_setup() -> void:
	var none := _new(11, "vael", "aucun")
	_ok(none.lairs.is_empty() and none.pirate_density == "aucun", "réglage Aucun : pas de repaire")
	var st := _new()
	var ids := Pirates.lair_ids(st)
	_ok(ids.size() == 6, "réglage Normaux : un repaire pour 25 systèmes (%d)" % ids.size())
	var far := true
	for e in st.empires:
		var d := FactionTraits.jumps_from(st.galaxy, _home(st, e.id))
		for sid in ids:
			if int(d.get(sid, 999)) < int(Pirates.data()["min_jumps_from_start"]):
				far = false
	_ok(far, "repaires à 4 sauts au moins de tout départ")
	var apart := true
	for a in ids:
		var d := FactionTraits.jumps_from(st.galaxy, a)
		for b in ids:
			if a != b and int(d.get(b, 999)) < int(Pirates.data()["min_jumps_between"]):
				apart = false
	_ok(apart, "repaires à 3 sauts au moins les uns des autres")
	var g := Pirates.guard_fleet(st, ids[0])
	_ok(g != null and g.owner == GameState.PIRATE_ID and g.system_id == ids[0] and g.ships.size() == 3, "chaque repaire a sa garde de trois vaisseaux")
	_ok(Combat.at_war(st, 0, GameState.PIRATE_ID) and Combat.at_war(st, GameState.NPC_ID, GameState.PIRATE_ID), "les pirates sont hostiles à tous")
	_ok(st.get_empire(GameState.PIRATE_ID).short_name() == "Pirates", "faction des Pirates, hors de la liste des empires")
	var inf := _new(11, "vael", "infestes")
	_ok(inf.lairs.size() > st.lairs.size(), "réglage Infestés : plus de repaires (%d)" % inf.lairs.size())


func _test_target() -> void:
	var st := _new()
	var lair := _lair(st)
	_ok(Pirates.pick_target(st, lair) == -1, "rien à piller sans colonie à portée (les capitales ne sont jamais visées)")
	var a := _plant_near(st, 0, lair, 3)
	_ok(a >= 0 and Pirates.pick_target(st, lair) == a, "la colonie à portée devient la cible")
	var b := _plant_near(st, 0, lair, 4)
	var fl := st.spawn_ship(0, "fregate", a)
	_ok(Pirates.pick_target(st, lair) == b, "un système gardé par une flotte armée n'est pas une cible prioritaire")
	st.fleets.erase(fl.id)
	st.lairs[lair]["tribute"][0] = st.tick + 360
	_ok(Pirates.pick_target(st, lair) == -1, "tribut payé : ce repaire ne vise plus l'empire")
	_ok(Pirates.pick_target(st, lair, 0) >= 0, "un contrat passe outre le tribut")
	st.lairs[lair]["tribute"].clear()
	# Prime : un rival plus mis à prix attire les raids.
	var c := _plant_near(st, 1, lair, 4)
	if c >= 0:
		st.pirate_meta["bounty"] = [{"by": 0, "on": 1, "until": st.tick + 100}]
		_ok(st.system_owner(Pirates.pick_target(st, lair)) == 1, "la prime oriente les raids vers l'empire mis à prix")
		st.pirate_meta["bounty"] = []


func _test_raid() -> void:
	var sim := Simulation.new(_new())
	var st := sim.state
	var lair := _lair(st)
	var sid := _plant_near(st, 0, lair, 3)
	var e := st.get_empire(0)
	e.resources["energy"] = 1000
	e.resources["materials"] = 1000
	st.stability[sid] = {"v": 50}
	st.lairs[lair]["next"] = st.tick + 1
	sim.advance(1)
	var raid: Dictionary = st.lairs[lair]["raid"]
	_ok(not raid.is_empty() and int(raid["target"]) == sid, "le repaire lance un raid vers la colonie")
	var fid := int(raid.get("fleet", -1))
	var done := false
	for _i in 200:
		sim.advance(1)
		if bool((st.lairs[lair]["raid"] as Dictionary).get("back", false)):
			done = true
			break
	_ok(done, "le raid arrive et pille")
	_ok(int(e.resources["energy"]) <= 850 and int(e.resources["materials"]) <= 850, "le raid vole énergie et matériaux (150 au plus chacun)")
	_ok(Stability.value(st, sid) <= 40, "le raid coûte 10 de stabilité (%d)" % Stability.value(st, sid))
	_ok(st.system_owner(sid) == 0, "un raid ne conquiert jamais")
	_ok(int((st.lairs[lair]["hits"] as Dictionary).get(0, -1)) >= 0, "le repaire se souvient de qui il a pillé")
	for _i in 200:
		sim.advance(1)
		if (st.lairs[lair]["raid"] as Dictionary).is_empty():
			break
	_ok((st.lairs[lair]["raid"] as Dictionary).is_empty() and not st.fleets.has(fid), "les pillards rentrent au repaire et s'y dissolvent")
	_ok(int(st.lairs[lair]["next"]) > st.tick, "le prochain raid est programmé")


func _test_actions() -> void:
	var sim := Simulation.new(_new())
	var st := sim.state
	var lair := _lair(st)
	var e := st.get_empire(0)
	e.resources["energy"] = 2000
	e.resources["influence"] = 500
	_ok(Pirates.check_tribute(st, 0, lair) != "", "on ne paie pas tribut à un repaire inconnu")
	e.explored[lair] = true
	_ok(Pirates.known_lairs(st, 0).has(lair), "repaire connu une fois le système exploré")
	var cost := int(Pirates.tribute_cost(st, 0)["energy"])
	_ok(sim.submit(SimCommands.pirate_tribute(0, lair)), "tribut accepté")
	sim.flush_commands()
	_ok(Pirates.pays_tribute(st, lair, 0) and int(e.resources["energy"]) == 2000 - cost, "tribut payé en énergie (%d), un an de paix" % cost)
	_ok(not sim.submit(SimCommands.pirate_tribute(0, lair)), "pas deux tributs au même repaire")
	# Contrat : il faut connaître la cible et qu'elle ait un système à portée.
	_ok(Pirates.check_hire(st, 0, lair, 1) != "", "pas de contrat contre un empire jamais rencontré")
	e.contacts.append(1)
	var target := _plant_near(st, 1, lair, 6)
	_ok(target >= 0 and sim.submit(SimCommands.pirate_hire(0, lair, 1)), "contrat contre un rival accepté")
	sim.flush_commands()
	_ok(int(st.lairs[lair]["contract"].get("victim", -1)) == 1, "le contrat attend son raid")
	sim.advance(1)
	var raid: Dictionary = st.lairs[lair]["raid"]
	_ok(int(raid.get("by", -1)) == 0 and st.system_owner(int(raid.get("target", -1))) == 1, "le raid commandité part contre le rival")
	_ok(not sim.submit(SimCommands.pirate_hire(0, lair, 1)), "un seul contrat à la fois par repaire")
	# Prime.
	_ok(sim.submit(SimCommands.pirate_bounty(0, 1)), "prime acceptée")
	sim.flush_commands()
	_ok(Pirates.bounty_weight(st, 1) == 1, "la prime pèse sur le rival")
	_ok(not sim.submit(SimCommands.pirate_bounty(0, 1)), "une seule prime à la fois sur le même empire")
	sim.advance(int(Pirates.data()["bounty"]["days"]) + 31)
	_ok(Pirates.bounty_weight(st, 1) == 0 and (st.pirate_meta.get("bounty", []) as Array).is_empty(), "la prime expire et s'efface")


func _test_dismantle() -> void:
	var sim := Simulation.new(_new(11, "choeur"))
	var st := sim.state
	var lair := _lair(st)
	var e := st.get_empire(0)
	var fervor := e.fervor
	var mat := int(e.resources.get("materials", 0))
	var g := Pirates.guard_fleet(st, lair)
	st.fleets.erase(g.id)
	var fl := st.spawn_ship(0, "fregate", lair)
	sim.advance(1)
	_ok(not Pirates.is_lair(st, lair), "garde détruite et flotte armée sur place : le repaire est démantelé")
	_ok(int(e.resources.get("materials", 0)) >= mat + 150, "butin du démantèlement")
	_ok(e.fervor >= fervor + 15, "Croisade (théocratie) : +15 ferveur")
	_ok(st.fleets.has(fl.id), "la flotte reste en place")


func _test_guard() -> void:
	var sim := Simulation.new(_new())
	var st := sim.state
	var lair := _lair(st)
	st.fleets.erase(Pirates.guard_fleet(st, lair).id)
	sim.advance(1)
	_ok(Pirates.is_lair(st, lair) and Pirates.guard_fleet(st, lair) == null and int(st.lairs[lair]["lost"]) >= 0, "garde détruite sans flotte sur place : le repaire tient")
	sim.advance(int(Pirates.data()["guard"]["respawn_days"]))
	_ok(Pirates.guard_fleet(st, lair) != null, "la garde se reforme au bout d'un an")
	var n := Pirates.guard_fleet(st, lair).ships.size()
	var born := int(st.lairs[lair]["born"])
	var grow := int(Pirates.data()["guard"]["grow_every_days"])
	@warning_ignore("integer_division")
	sim.advance(born + (st.tick / grow + 1) * grow - st.tick)
	_ok(Pirates.guard_fleet(st, lair).ships.size() == n + 1, "la garde grossit d'un navire tous les deux ans")


func _test_talents() -> void:
	# Syndicat (Brisecomète) : tribut et contrats à moitié prix ; profit : primes à moitié prix.
	var st := _new(11, "brisecomete")
	var base := _new(11, "vael")
	_ok(int(Pirates.hire_cost(st, 0)["energy"]) * 2 == int(Pirates.hire_cost(base, 0)["energy"]), "Syndicat : contrats à moitié prix")
	_ok(int(Pirates.bounty_cost(st, 0)["energy"]) * 2 == int(Pirates.bounty_cost(base, 0)["energy"]), "Profit : primes à moitié prix")
	# République (Vael) : le tribut fait scandale.
	var sim := Simulation.new(_new(11, "vael"))
	var vs := sim.state
	var lair := _lair(vs)
	vs.get_empire(0).explored[lair] = true
	vs.get_empire(0).resources["energy"] = 2000
	Pirates.tribute(vs, 0, lair)
	var found := false
	for p in Stability.parts(vs, _home(vs)):
		if String(p[0]) == "Scandale du tribut" and int(p[1]) == -5:
			found = true
	_ok(found, "République : le tribut coûte 5 de stabilité partout")
	# Honneur (Ossarane) : la honte du tribut, et +20 % de dégâts contre les pirates.
	var os := _new(11, "ossarane")
	var ol := _lair(os)
	os.get_empire(0).explored[ol] = true
	os.get_empire(0).resources["energy"] = 2000
	Pirates.tribute(os, 0, ol)
	found = false
	for p in Stability.parts(os, _home(os)):
		if String(p[0]) == "Tribut payé aux forbans" and int(p[1]) == -10:
			found = true
	_ok(found, "Honneur : payer un tribut coûte 10 de stabilité partout")
	var f := os.spawn_ship(0, "fregate", ol)
	_ok(Pirates.hunt_pct(os, f, [f, Pirates.guard_fleet(os, ol)]) == 20, "Honneur : +20 % de dégâts contre les pirates")
	# Voile (Murmurants) : les pirates ne voient pas les mondes voilés jamais repérés.
	var ms := _new(11, "murmurants")
	var ml := _lair(ms)
	var sid := _plant_near(ms, 0, ml, 3)
	_ok(sid >= 0 and Pirates.pick_target(ms, ml) == -1, "Voile : les pirates ignorent un monde voilé jamais repéré")
	ms.get_empire(0).spotted_tick = ms.tick
	_ok(Pirates.pick_target(ms, ml) == sid, "Voile : repéré depuis moins d'un an, il redevient une proie")
	# Esprit de ruche : le repaire démantelé est dévoré.
	var ks := _new(11, "khthari")
	var kl := _lair(ks)
	var mat := int(ks.get_empire(0).resources.get("materials", 0))
	Pirates.dismantle(ks, kl, 0, [])
	var bio := int(FactionTraits.biomass_gain(ks, 0).get("materials", 0)) * 3
	_ok(bio > 0 and int(ks.get_empire(0).resources["materials"]) == mat + 150 + bio, "Ruche : le repaire dévoré vaut trois digestions")
	_ok(not Pirates.talent_labels(st, 0).is_empty(), "talents pirates affichés pour le Syndicat")


func _test_patrol() -> void:
	var sim := Simulation.new(_new(11, "vael", "aucun"))
	var st := sim.state
	var home := _home(st)
	var n := int(st.galaxy.systems[home].neighbors[0])
	var f := st.spawn_ship(0, "fregate", home)
	_ok(not sim.submit(SimCommands.set_fleet_order(0, f.id, Fleet.ORDER_PATROL)), "la patrouille se donne avec une destination")
	_ok(not sim.submit(SimCommands.patrol_fleet(0, f.id, home)), "pas de patrouille sur place")
	_ok(sim.submit(SimCommands.patrol_fleet(0, f.id, n)), "ordre Patrouille accepté")
	sim.flush_commands()
	_ok(f.is_patrolling() and f.patrol == [home, n] and f.destination() == n, "la flotte part vers le bout de sa patrouille")
	var reached := false
	var back := false
	for _i in 300:
		sim.advance(1)
		# Arrivée et nouveau départ se font le même jour : on la voit repartir de n vers home.
		if f.system_id == n:
			reached = true
			back = f.is_moving() and f.destination() == home
			break
	_ok(reached and back, "arrivée au bout, elle repart vers son point de départ")
	_ok(sim.submit(SimCommands.set_fleet_order(0, f.id, "")), "on peut interrompre la patrouille")
	sim.flush_commands()
	_ok(not f.is_patrolling(), "patrouille interrompue")
	var d := Fleet.from_dict(JSON.parse_string(JSON.stringify(f.to_dict())))
	f.standing_order = Fleet.ORDER_PATROL
	var d2 := Fleet.from_dict(JSON.parse_string(JSON.stringify(f.to_dict())))
	_ok(not d.is_patrolling() and d2.is_patrolling() and d2.patrol == f.patrol, "la patrouille se sauvegarde")


func _test_ai() -> void:
	var st := GameState.create(11, 150, 1800.0, "vael", {"ai_level": "veteran", "pirates": "normaux"})
	var e := st.get_empire(1)
	var lair := -1
	var home := _home(st, 1)
	var jumps := FactionTraits.jumps_from(st.galaxy, home)
	for sid in Pirates.lair_ids(st):
		if int(jumps.get(sid, 99)) <= 6 and (lair < 0 or int(jumps[sid]) < int(jumps[lair])):
			lair = sid
	if lair < 0:
		_ok(true, "IA : aucun repaire à 6 sauts, chasse non testée")
		return
	e.explored[lair] = true
	var f := st.spawn_ship(1, "fregate", home)
	for _i in 6:
		f.add_ship("fregate", -1, 1)
	var ctx := {"state": st, "e": e, "lv": AiLevels.level("veteran"), "ai": AiLevels.personality(e), "salt": 0, "intent": ""}
	_ok(AiPirates.lair_target(ctx, f, home) == lair, "IA Vétéran : une flotte assez forte vise le repaire connu le plus proche")
	var weak := st.spawn_ship(1, "corvette", home)
	_ok(AiPirates.lair_target(ctx, weak, home) == -1, "IA Vétéran : une flotte trop faible n'y va pas")
	var ctx_n := {"state": st, "e": e, "lv": AiLevels.level("normal"), "ai": AiLevels.personality(e), "salt": 0, "intent": ""}
	_ok(AiPirates.lair_target(ctx_n, f, home) == -1, "IA Normale : pas de chasse aux repaires")
	# Tribut : une IA mesurée, pillée dans l'année et riche, paie.
	st.lairs[lair]["hits"][1] = st.tick
	e.resources["energy"] = 5000
	e.ai_temperament = "pacifique" if AiLevels.is_valid_temperament("pacifique") else e.ai_temperament
	if AiLevels.aggression(e) <= 0 and int(Pirates.talent(st, 1).get("tribute_shame", 0)) == 0:
		var t := 0
		while posmod(st.tick + e.id * 11, 30) >= 5 and t < 40:
			st.tick += 1
			t += 1
		AiPirates.think(ctx)
		_ok(Pirates.pays_tribute(st, lair, 1), "IA mesurée pillée dans l'année : elle paie tribut")
	else:
		_ok(true, "IA : peuple trop fier ou agressif pour le tribut, non testé")


## Empire qui espionne b avec un réseau au palier 3 (Amirauté).
func _spy(st: GameState, a: int, b: int) -> void:
	for pair in [[a, b], [b, a]]:
		if not st.get_empire(pair[0]).contacts.has(pair[1]):
			st.get_empire(pair[0]).contacts.append(pair[1])
	Espionage.set_cells(st, a, b, 2)
	st.networks[Espionage.key(a, b)]["inf"] = 65
	st.get_empire(a).resources["influence"] = 500


func _has_part(st: GameState, sid: int, label: String, v: int) -> bool:
	for p in Stability.parts(st, sid):
		if String(p[0]) == label and int(p[1]) == v:
			return true
	return false


func _test_spy_ops() -> void:
	var sim := Simulation.new(_new(11, "vael"))
	var st := sim.state
	var b := -1
	for e in st.empires:
		if e.id != 0 and Stability.applies(st, e.id):
			b = e.id
			break
	_ok(b > 0, "un rival connaît la stabilité")
	var lair := _lair(st)
	_spy(st, 0, b)
	_ok(Espionage.check_op(st, 0, b, "dissidence") != "", "dissidence : il faut un système hors de la capitale")
	var sid := _plant_near(st, b, lair, 6)
	_ok(sid >= 0 and Espionage.check_op(st, 0, b, "dissidence") == "", "dissidence possible contre une colonie (%s)" % Espionage.check_op(st, 0, b, "dissidence"))
	Espionage._apply(st, 0, b, Espionage.op_def("dissidence"))
	_ok(_has_part(st, sid, "Agitateurs étrangers", -15), "dissidence : -15 de stabilité dans son système le moins stable")
	st.stability[sid]["agit"] = st.tick - 1
	_ok(not _has_part(st, sid, "Agitateurs étrangers", -15), "l'agitation s'éteint au bout d'un an")
	# Partisans : seulement en Agitation ou en Révolte.
	st.stability[sid]["v"] = 50
	_ok(Espionage.check_op(st, 0, b, "partisans") != "", "partisans : rien à soulever dans un système calme")
	st.stability[sid]["v"] = 20
	_ok(Espionage.check_op(st, 0, b, "partisans") == "", "partisans possibles en Agitation")
	var before := Fleets.fleets_at(st, sid, GameState.NPC_ID).size()
	Espionage._apply(st, 0, b, Espionage.op_def("partisans"))
	_ok(Fleets.fleets_at(st, sid, GameState.NPC_ID).size() == before + 1, "partisans : des rebelles se lèvent")
	# Inciter les pirates : un repaire connu, un système de la cible à portée.
	_ok(Espionage.check_op(st, 0, b, "inciter") != "", "inciter : il faut connaître un repaire")
	st.get_empire(0).explored[lair] = true
	_ok(Espionage.check_op(st, 0, b, "inciter") == "", "inciter possible (%s)" % Espionage.check_op(st, 0, b, "inciter"))
	Espionage._apply(st, 0, b, Espionage.op_def("inciter"))
	_ok(int(st.lairs[lair]["contract"].get("victim", -1)) == b and int(st.lairs[lair]["contract"].get("by", 0)) == -1, "inciter : contrat anonyme contre la cible")
	_ok(Espionage.check_op(st, 0, b, "inciter") != "", "un seul contrat à la fois")
	sim.advance(1)
	var raid: Dictionary = st.lairs[lair]["raid"]
	_ok(int(raid.get("victim", -1)) == b and st.system_owner(int(raid.get("target", -1))) == b, "le raid incité part contre la cible")
	# Réseau intérieur : +5 de stabilité.
	var cap := _home(st, b)
	_ok(not _has_part(st, cap, "Réseau intérieur (contre-espionnage)", 5), "sans cellule chez soi : pas de bonus")
	Espionage.set_cells(st, b, b, 1)
	_ok(_has_part(st, cap, "Réseau intérieur (contre-espionnage)", 5), "une cellule chez soi : +5 de stabilité")
	_ok(AiEspionage.WAR_OPS.has("inciter") and AiEspionage.WAR_OPS.has("partisans"), "l'IA en guerre connaît les nouvelles opérations")


func _test_ransom() -> void:
	var sim := Simulation.new(_new())
	var st := sim.state
	var id := Heroes.ids_of(st, 0)[0]
	var h: Dictionary = st.heroes[id]
	h["jailer"] = GameState.PIRATE_ID
	h["ransom"] = st.tick + int(Heroes.data()["capture"]["ransom"]["days"])
	_ok(Heroes.held_for_ransom(st, 0) == [id], "héros retenu par les pirates")
	_ok(HeroScreen.status_text(st, h).contains("rançon"), "la fiche du héros dit la rançon et l'échéance")
	var cost := int(Heroes.ransom_cost(h)["energy"])
	_ok(cost == 60 + 40 * int(h["lvl"]), "rançon : 60 + 40 par niveau (%d)" % cost)
	st.get_empire(0).resources["energy"] = 0
	_ok(Heroes.check_ransom(st, 0, id) != "", "rançon refusée sans énergie")
	_ok(Heroes.check_ransom(st, 1, id) != "", "seul son empire paie la rançon")
	st.get_empire(0).resources["energy"] = 1000
	_ok(sim.submit(SimCommands.hero_ransom(0, id)), "rançon acceptée")
	sim.flush_commands()
	_ok(not Heroes.is_prisoner(st.heroes[id]) and int(st.get_empire(0).resources["energy"]) == 1000 - cost and not st.heroes[id].has("ransom"), "rançon payée : le héros rentre")
	# Sans rançon dans les temps, il est exécuté ; jamais converti.
	h["jailer"] = GameState.NPC_ID
	h["ransom"] = st.tick + 60
	var out: Array[Dictionary] = []
	Heroes._prison_month(st, h, out)
	_ok(st.heroes.has(id) and int(h["owner"]) == 0, "les rebelles ne convertissent pas : ils attendent")
	h["ransom"] = st.tick
	Heroes._prison_month(st, h, out)
	_ok(not st.heroes.has(id), "rançon jamais payée : le héros est exécuté")
	# Démanteler le repaire libère les héros que les pirates retenaient.
	var st2 := _new()
	var id2 := Heroes.ids_of(st2, 0)[0]
	st2.heroes[id2]["jailer"] = GameState.PIRATE_ID
	st2.heroes[id2]["ransom"] = st2.tick + 700
	Pirates.dismantle(st2, _lair(st2), 0, [])
	_ok(not Heroes.is_prisoner(st2.heroes[id2]), "démanteler un repaire libère ses prisonniers")
	# IA : paie la rançon quand l'énergie le permet.
	var st3 := GameState.create(11, 150, 1800.0, "vael", {"ai_level": "normale", "pirates": "normaux"})
	var e1 := st3.get_empire(1)
	var id3 := Heroes.ids_of(st3, 1)[0]
	st3.heroes[id3]["jailer"] = GameState.PIRATE_ID
	st3.heroes[id3]["ransom"] = st3.tick + 700
	e1.resources["energy"] = 5000
	var sim3 := Simulation.new(st3)
	sim3.advance(31)
	_ok(not Heroes.is_prisoner(st3.heroes[id3]), "IA : rançon payée")


func _test_rally() -> void:
	var sim := Simulation.new(_new(11, "ferrocornes"))
	var st := sim.state
	var lair := _lair(st)
	st.fleets.erase(Pirates.guard_fleet(st, lair).id)
	var fl := st.spawn_ship(0, "fregate", lair)
	sim.advance(1)
	_ok(not Pirates.is_lair(st, lair), "Horde : repaire démantelé")
	_ok(fl.ships.size() == 1 + (Pirates.data()["guard"]["ships"] as Array).size(), "Horde : les équipages rallient la flotte (%d vaisseaux)" % fl.ships.size())
	_ok(_has_part(st, _home(st), "Butin récent", 10), "Horde : le ralliement compte comme un pillage")


func _test_port() -> void:
	var sim := Simulation.new(_new())
	var st := sim.state
	var lair := _lair(st)
	var years := int(Pirates.data()["port"]["untouched_years"])
	st.lairs[lair]["calm"] = st.tick - years * 360 + 2
	sim.advance(1)
	_ok(Pirates.is_lair(st, lair), "pas encore quinze ans de calme : toujours un repaire")
	var g := Pirates.guard_fleet(st, lair)
	sim.advance(1)
	_ok(Pirates.is_port(st, lair) and not Pirates.is_lair(st, lair), "quinze ans sans être attaqué : le repaire devient port franc")
	_ok(not st.fleets.has(g.id) and not Pirates.lair_ids(st).has(lair) and Pirates.port_ids(st) == [lair], "plus de garde, plus dans la liste des repaires")
	st.lairs[lair]["next"] = st.tick + 1
	_plant_near(st, 0, lair, 3)
	sim.advance(3)
	_ok((st.lairs[lair]["raid"] as Dictionary).is_empty(), "un port franc ne pille plus")
	var e := st.get_empire(0)
	e.resources["energy"] = 2000
	e.resources["influence"] = 500
	e.explored.erase(lair)
	_ok(Pirates.check_port(st, 0, lair, "fleet") != "", "il faut connaître le port")
	e.explored[lair] = true
	_ok(Pirates.known_ports(st, 0) == [lair] and Pirates.known_lairs(st, 0).is_empty(), "port connu, et ce n'est plus un repaire")
	var n := Fleets.empire_fleets(st, 0).size()
	_ok(sim.submit(SimCommands.port_deal(0, lair, "fleet")), "mercenaires loués")
	sim.flush_commands()
	var merc := Fleets.fleets_at(st, lair, 0)
	_ok(Fleets.empire_fleets(st, 0).size() == n + 1 and not merc.is_empty() and merc[0].ships.size() == 3, "la flotte de mercenaires apparaît au port")
	_ok(not sim.submit(SimCommands.port_deal(0, lair, "fleet")), "un seul marché de mercenaires par an")
	var h := Heroes.ids_of(st, 0).size()
	if h < Heroes.cap(st, 0):
		_ok(sim.submit(SimCommands.port_deal(0, lair, "hero")), "héros recruté au port")
		sim.flush_commands()
		_ok(Heroes.ids_of(st, 0).size() == h + 1, "le héros rejoint l'empire")
	var p := st.galaxy.systems[lair]
	if not p.planet_ids.is_empty():
		_ok(Economy.check_colonize(st, 0, int(p.planet_ids[0]), Colony.KIND_COLONY).contains("port franc"), "on ne colonise pas un port franc")


func _test_save() -> void:
	var sim := Simulation.new(_new(13))
	var st := sim.state
	var lair := _lair(st)
	_plant_near(st, 0, lair, 3)
	st.lairs[lair]["next"] = st.tick + 1
	st.get_empire(0).explored[lair] = true
	st.get_empire(0).resources["energy"] = 3000
	sim.advance(3)
	st.pirate_meta["bounty"] = [{"by": 0, "on": 1, "until": st.tick + 50}]
	Pirates._shame(st, 0, "Scandale du tribut", -5, 100)
	var other := Pirates.lair_ids(st)[1]
	st.get_empire(0).explored[other] = true
	Pirates.make_port(st, other, [])
	Pirates.port_deal(st, 0, other, "fleet")
	var hid := Heroes.ids_of(st, 0)[0]
	st.heroes[hid]["jailer"] = GameState.PIRATE_ID
	st.heroes[hid]["ransom"] = st.tick + 300
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_snapshot())))
	_ok(back != null, "sauvegarde 24 relue")
	if back == null:
		return
	_ok(back.checksum() == st.checksum(), "même empreinte après sauvegarde (repaires, raid en cours, primes)")
	_ok(back.lairs.size() == st.lairs.size() and not (back.lairs[lair]["raid"] as Dictionary).is_empty() and back.pirate_density == "normaux", "repaires et raid relus")
	_ok(Pirates.is_port(back, other) and Pirates.port_next(back, other, "fleet") > back.tick, "port franc et ses marchés relus")
	_ok(int(back.heroes[hid].get("ransom", 0)) == st.tick + 300, "échéance de la rançon relue")
	var a := Simulation.new(st)
	var b := Simulation.new(back)
	a.advance(120)
	b.advance(120)
	_ok(a.state.checksum() == b.state.checksum(), "la partie reprise continue à l'identique")
	var old := st.to_snapshot()
	old["version"] = 22
	old.erase("lairs")
	old.erase("pirate_meta")
	old.erase("pirate_density")
	var o := GameState.from_dict(JSON.parse_string(JSON.stringify(old)))
	_ok(o != null and o.lairs.is_empty(), "une sauvegarde 22 se relit (sans pirates)")


func _test_determinism() -> void:
	var a := Simulation.new(GameState.create(53, 150, 1800.0, "", {"pirates": "infestes"}))
	var b := Simulation.new(GameState.create(53, 150, 1800.0, "", {"pirates": "infestes"}))
	a.advance(900)
	b.advance(900)
	_ok(a.state.checksum() == b.state.checksum() and not a.state.lairs.is_empty(), "même graine, mêmes pirates après 900 jours")
