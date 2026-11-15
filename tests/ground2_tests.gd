extends RefCounted
## Tests du pilier combat au sol, lot 2 : spécialistes (forces spéciales, génie, tir au débarquement),
## terrain, tactiques, vétérance, siège en deux temps (fortifications), postures de bombardement,
## dévastation, Citadelle, reddition, sortie, technologies, sauvegarde 60, IA.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Combat au sol, lot 2…")
	_test_specialists()
	_test_terrain_veterancy()
	_test_tactics()
	_test_siege()
	_test_bombard_devastation()
	_test_surrender()
	_test_sortie()
	_test_save()
	_test_ai()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 21, faction := "ossarane") -> GameState:
	var st := GameState.create(seed_value, 120, 1600.0, faction, {"ai_level": "", "ground": "complet"})
	for e in st.empires:
		e.resources["materials"] = 5000
		e.resources["energy"] = 5000
		e.resources["food"] = 5000
		st.ground["rec"][str(e.id)] = 40
	return st


func _home(st: GameState, eid: int) -> int:
	return FactionTraits.capital_system(st, eid)


func _war(st: GameState, a: int, b: int) -> void:
	for pair in [[a, b], [b, a]]:
		var e := st.get_empire(pair[0])
		if not e.contacts.has(pair[1]):
			e.contacts.append(pair[1])
	Combat.start_war(st, a, b)


func _learn(st: GameState, eid: int, techs: Array) -> void:
	var e := st.get_empire(eid)
	for t in techs:
		e.techs[String(t)] = true
	e.tech_fx_n = -1


func _regs(st: GameState, eid: int, sid: int, t: String, n: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in n:
		out.append(Ground._new_regiment(st, eid, t, Peoples.founder_of(st, eid), sid))
	return out


## Flotte de transports de l'empire 0 au-dessus de la capitale de 1, avec n régiments de type t à bord.
func _landing(st: GameState, n: int, t := "infanterie") -> Array:
	var sim := Simulation.new(st)
	_war(st, 0, 1)
	var target := _home(st, 1)
	for g in Fleets.fleets_at(st, target, 1):
		st.fleets.erase(g.id)
	var f := st.spawn_ship(0, "transport", target)
	for i in (n * Ground.size_of(t) + 15) / 16:
		f.add_ship("transport")
	for r in _regs(st, 0, target, t, n):
		r["f"] = f.id
	Ground.sync_fleet(st, f)
	return [sim, target, f]


func _add_building(st: GameState, sid: int, owner: int, bid: String) -> void:
	for pid in st.galaxy.systems[sid].planet_ids:
		var c: Colony = st.colonies.get(pid)
		if c != null and c.owner == owner and c.is_established():
			c.buildings.append(bid)
			return


func _test_specialists() -> void:
	var st := _new()
	_ok(Ground.type_ids().has("commandos") and Ground.type_ids().has("genie"), "deux spécialistes au catalogue : forces spéciales et génie")
	_ok(not Ground.type_allowed(st, 0, "commandos"), "les forces spéciales demandent une technologie")
	_learn(st, 0, ["forces_speciales", "genie_siege"])
	_ok(Ground.type_allowed(st, 0, "commandos") and Ground.type_allowed(st, 0, "genie"), "technologies apprises : spécialistes ouverts")
	# Génie : puissance de siège à bord.
	var home := _home(st, 0)
	var f := st.spawn_ship(0, "transport", home)
	f.add_ship("transport")
	for r in _regs(st, 0, home, "genie", 2):
		r["f"] = f.id
	Ground.sync_fleet(st, f)
	_ok(GroundSiege.engineer_power(st, f) == 8, "deux génies à bord : +8 puissance de siège")
	# Tir au débarquement : Bastion (10 %), annulé en partie par les commandos.
	var st2 := _new(22)
	var target := _home(st2, 1)
	_add_building(st2, target, 1, "bastion")
	var inf := _regs(st2, 0, target, "infanterie", 1)
	_ok(Ground.landing_fire_pct(st2, target, 0, inf) == 10, "un Bastion tire sur les péniches (10 %)")
	_learn(st2, 1, ["defense_planetaire"])
	_ok(Ground.landing_fire_pct(st2, target, 0, inf) == 20, "Défense planétaire : +10 %")
	var com := _regs(st2, 0, target, "commandos", 1)
	_ok(Ground.landing_fire_pct(st2, target, 0, com) == 0, "un commando sabote les batteries")
	for r in inf + com:
		st2.ground["r"].erase(str(int(r["id"])))
	var x := _landing(st2, 4)
	(x[0] as Simulation).submit(SimCommands.invade(0, (x[2] as Fleet).id))
	(x[0] as Simulation).flush_commands()
	var hurt := 0
	for r in Ground.on_ground(st2, target, 0):
		if int(r["hp"]) < Ground.max_hp(r):
			hurt += 1
	_ok(hurt == 4, "les régiments qui débarquent sous le feu sont touchés")
	# Génie au sol : démolit la milice.
	_ok(int(Ground.type_def("genie")["vs"].get("milice", 100)) == 150, "le génie frappe la milice à 150 %")


func _test_terrain_veterancy() -> void:
	var st := _new(23)
	var x := _landing(st, 3)
	(x[0] as Simulation).submit(SimCommands.invade(0, (x[2] as Fleet).id))
	(x[0] as Simulation).flush_commands()
	var b := Ground.battle(st, int(x[1]))
	var ter := String(b.get("ter", ""))
	_ok(ter != "" and not Ground.terrain_def(ter).is_empty(), "la bataille connaît son terrain (%s)" % ter)
	_ok(int(Ground.terrain_def("ocean")["mods"]["aerien"]) > 100 and int(Ground.terrain_def("ocean")["mods"]["blindes"]) < 100, "océan : l'aérien domine, les blindés s'embourbent")
	_ok(int(Ground.terrain_def("ecumenopole").get("defender", 100)) > 100, "écuménopole : le défenseur est avantagé")
	# Vétérance.
	var r: Dictionary = Ground.on_ground(st, int(x[1]), 0)[0]
	var m0 := Ground.max_morale(r, st)
	r["xp"] = 80
	_ok(String(Ground.rank(r)["id"]) == "veteran", "80 d'expérience : Vétéran")
	_ok(Ground.label(st, r).contains("vétéran"), "le rang paraît dans le nom (%s)" % Ground.label(st, r))
	_ok(Ground.max_morale(r, st) == m0 * 120 / 100, "un Vétéran a 20 % de moral en plus")
	r["xp"] = 200
	_ok(String(Ground.rank(r)["id"]) == "elite", "200 : Élite")


func _test_tactics() -> void:
	# Blitz : un jour de débarquement.
	var st := _new(24)
	Ground.set_default_tactic(st, 0, "attack", "blitz")
	var x := _landing(st, 3)
	(x[0] as Simulation).submit(SimCommands.invade(0, (x[2] as Fleet).id))
	(x[0] as Simulation).flush_commands()
	var b := Ground.battle(st, int(x[1]))
	_ok(String(b["ta"]) == "blitz" and int(b["land"]) - st.tick == 1, "Blitz : bataille dès le lendemain")
	_ok(SimCommands.validate(st, SimCommands.ground_act(0, "tactic", int(x[1]), "infiltration")) == "", "on peut changer de tactique pendant le débarquement")
	(x[0] as Simulation).submit(SimCommands.ground_act(0, "tactic", int(x[1]), "infiltration"))
	(x[0] as Simulation).flush_commands()
	_ok(String(b["ta"]) == "infiltration" and int(b["land"]) - st.tick == 5, "Infiltration : débarquement de 5 jours")
	_ok(SimCommands.validate(st, SimCommands.ground_act(1, "tactic", int(x[1]), "blitz")) != "", "le défenseur choisit parmi les tactiques de défense")
	# Résistance locale et bombardement préventif, au premier jour.
	var st2 := _new(25)
	Ground.set_default_tactic(st2, 1, "defense", "resistance")
	Ground.set_default_tactic(st2, 0, "attack", "bombardement")
	var y := _landing(st2, 3)
	(y[0] as Simulation).submit(SimCommands.invade(0, (y[2] as Fleet).id))
	(y[0] as Simulation).flush_commands()
	var b2 := Ground.battle(st2, int(y[1]))
	var n0 := (b2["mil"] as Array).size()
	Ground._open(st2, b2)
	_ok((b2["mil"] as Array).size() > n0, "Résistance locale : plus de miliciens (%d → %d)" % [n0, (b2["mil"] as Array).size()])
	_ok(int(b2["mil"][0][0]) < int(Ground.type_def("milice")["hp"]), "Bombardement préventif : la milice commence blessée")
	_ok(GroundSiege.dev(st2, int(y[1])) >= 10, "et le système est dévasté")
	# Capitulation : sans régiment, le monde se rend au débarquement.
	var st3 := _new(26)
	Ground.set_default_tactic(st3, 1, "defense", "capitulation")
	var z := _landing(st3, 1)
	(z[0] as Simulation).submit(SimCommands.invade(0, (z[2] as Fleet).id))
	(z[0] as Simulation).flush_commands()
	_ok(st3.system_owner(int(z[1])) == 0 and Ground.battle(st3, int(z[1])).is_empty(), "Capitulation : pris sans combat")


func _besiege(st: GameState) -> Array:
	var sim := Simulation.new(st)
	_war(st, 0, 1)
	var target := _home(st, 1)
	for g in Fleets.fleets_at(st, target, 1):
		st.fleets.erase(g.id)
	var f := st.spawn_ship(0, "croiseur", target)
	for i in 3:
		f.add_ship("croiseur")
	return [sim, target, f]


func _test_siege() -> void:
	var st := _new(27)
	var x := _besiege(st)
	var sim: Simulation = x[0]
	var sid: int = x[1]
	var fmax := GroundSiege.fort_max(st, sid)
	_ok(fmax > 0, "la capitale a des fortifications (%d)" % fmax)
	var g0 := Combat.garrison(st, sid)
	sim.step()
	_ok(Combat.is_besieged(st, sid), "siège en cours")
	_ok(GroundSiege.fort(st, sid) < fmax and Combat.garrison(st, sid) == g0, "le siège use d'abord les fortifications, la milice tient")
	var guard := 0
	while GroundSiege.fort(st, sid) > 0 and guard < 300:
		sim.step()
		guard += 1
	sim.step()
	sim.step()
	_ok(Combat.garrison(st, sid) < g0, "fortifications tombées : la milice fond")
	# Bastion : plus de fortifications.
	var st2 := _new(27)
	var before := GroundSiege.fort_max(st2, _home(st2, 1))
	_add_building(st2, _home(st2, 1), 1, "bastion")
	_ok(GroundSiege.fort_max(st2, _home(st2, 1)) == before + 60, "un Bastion ajoute 60 fortifications")
	# Hors siège, elles se relèvent.
	for f in Fleets.fleets_at(st, sid, 0):
		st.fleets.erase(f.id)
	var low := GroundSiege.fort(st, sid)
	sim.step()
	sim.step()
	_ok(GroundSiege.fort(st, sid) > low, "siège levé : les fortifications se relèvent")


func _test_bombard_devastation() -> void:
	var st := _new(28)
	var x := _besiege(st)
	var sim: Simulation = x[0]
	var sid: int = x[1]
	var f: Fleet = x[2]
	_ok(SimCommands.validate(st, SimCommands.ground_act(0, "bomb", f.id, "rasant")) != "", "Ossarane ne rase pas les mondes")
	var kh := _new(28, "khthari")
	var kf := kh.spawn_ship(0, "croiseur", _home(kh, 0))
	_ok(SimCommands.validate(kh, SimCommands.ground_act(0, "bomb", kf.id, "rasant")) == "", "l'Essaim peut raser (couche orbital_raze)")
	sim.submit(SimCommands.ground_act(0, "bomb", f.id, "indiscrimine"))
	sim.flush_commands()
	_ok(GroundSiege.posture(st, f.id) == "indiscrimine", "posture Indiscriminé")
	var pop0 := 0
	for pid in st.galaxy.systems[sid].planet_ids:
		var c: Colony = st.colonies.get(pid)
		if c != null and c.owner == 1:
			pop0 += c.population
	for i in 40:
		sim.step()
	_ok(GroundSiege.dev(st, sid) > 0, "le bombardement Indiscriminé dévaste (%d)" % GroundSiege.dev(st, sid))
	var pop1 := 0
	for pid in st.galaxy.systems[sid].planet_ids:
		var c: Colony = st.colonies.get(pid)
		if c != null and c.owner == 1:
			pop1 += c.population
	_ok(pop1 < pop0, "et tue des habitants (%d → %d)" % [pop0, pop1])
	GroundSiege._sub(st, "dev")[str(sid)] = 40
	_ok(GroundSiege.production_pct(st, sid) == 80, "40 de dévastation : production à 80 %")
	_ok(GroundSiege.stability_malus(st, sid) == -8, "et -8 de stabilité")
	var found := false
	for p: Array in Stability.parts(st, sid):
		if String(p[0]) == "Dévastation":
			found = true
	_ok(found, "la dévastation paraît dans la stabilité du système")
	# Décroissance mensuelle hors siège.
	for g in Fleets.fleets_at(st, sid, 0):
		st.fleets.erase(g.id)
	for i in 31:
		sim.step()
	_ok(GroundSiege.dev(st, sid) < 40, "la dévastation baisse chaque mois")
	# Citadelle : la population à l'abri tant qu'elle tient.
	var st3 := _new(29)
	_add_building(st3, _home(st3, 1), 1, "citadelle")
	_ok(GroundSiege.has_citadel(st3, _home(st3, 1)) and GroundSiege.shielded(st3, _home(st3, 1)), "une Citadelle debout protège le système")
	_ok(GameData.building("citadelle").get("requires_tech", []).has("citadelle_planetaire"), "la Citadelle demande sa technologie")


func _test_surrender() -> void:
	var st := _new(30)
	var x := _besiege(st)
	var sim: Simulation = x[0]
	var sid: int = x[1]
	var f: Fleet = x[2]
	sim.submit(SimCommands.ground_act(0, "bomb", f.id, "selectif"))
	sim.flush_commands()
	GroundSiege._sub(st, "fort")[str(sid)] = 0
	st.garrisons[sid] = 0
	var guard := 0
	while st.system_owner(sid) == 1 and guard < 30:
		GroundSiege._sub(st, "fort")[str(sid)] = 0
		sim.step()
		guard += 1
	_ok(st.system_owner(sid) == 0, "bombardé sans défense, le monde capitule (%d jours)" % guard)
	# Ossarane (Honneur) ne capitule jamais.
	var st2 := _new(31, "vael")
	var y := _besiege(st2)
	var sim2: Simulation = y[0]
	var never := int(st2.get_empire(1).faction().get("combat", {}).get("no_surrender", 0)) > 0
	sim2.submit(SimCommands.ground_act(0, "bomb", (y[2] as Fleet).id, "selectif"))
	sim2.flush_commands()
	for i in 15:
		GroundSiege._sub(st2, "fort")[str(int(y[1]))] = 0
		st2.garrisons[int(y[1])] = 0
		sim2.step()
	_ok((st2.system_owner(int(y[1])) == 1) == never, "les peuples qui ne se rendent jamais tiennent (%s)" % st2.get_empire(1).faction_id)
	_ok(int(GameData.faction("ossarane")["combat"].get("no_surrender", 0)) > 0, "Ossarane (Honneur) ne capitule jamais")


func _test_sortie() -> void:
	var st := _new(32)
	var x := _besiege(st)
	var sim: Simulation = x[0]
	var sid: int = x[1]
	var f: Fleet = x[2]
	f.add_ship("transport")
	for r in _regs(st, 0, sid, "infanterie", 2):
		r["f"] = f.id
	Ground.sync_fleet(st, f)
	sim.step()
	_ok(SimCommands.validate(st, SimCommands.ground_act(1, "sortie", sid)) != "", "pas de sortie sans régiment au sol")
	_regs(st, 1, sid, "infanterie", 6)
	_ok(SimCommands.validate(st, SimCommands.ground_act(1, "sortie", sid)) == "", "sortie possible")
	var hp0 := 0
	for r in Ground.aboard(st, f.id):
		hp0 += int(r["hp"])
	sim.submit(SimCommands.ground_act(1, "sortie", sid))
	sim.flush_commands()
	var hp1 := 0
	for r in Ground.aboard(st, f.id):
		hp1 += int(r["hp"])
	_ok(hp1 < hp0, "la sortie frappe les troupes à bord (%d → %d)" % [hp0, hp1])
	_ok(SimCommands.validate(st, SimCommands.ground_act(1, "sortie", sid)).contains("remet"), "puis la garnison se remet")


func _test_save() -> void:
	var st := _new(33)
	var x := _besiege(st)
	var sim: Simulation = x[0]
	sim.submit(SimCommands.ground_act(0, "bomb", (x[2] as Fleet).id, "indiscrimine"))
	sim.flush_commands()
	Ground.set_default_tactic(st, 0, "attack", "blitz")
	for i in 5:
		sim.step()
	var d := st.to_dict()
	_ok(int(d["version"]) >= 60, "sauvegarde 60")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and GroundSiege.posture(back, (x[2] as Fleet).id) == "indiscrimine", "la posture survit à la sauvegarde")
	_ok(back != null and Ground.default_tactic(back, 0, "attack") == "blitz", "les tactiques par défaut aussi")
	_ok(back != null and GroundSiege.fort(back, int(x[1])) == GroundSiege.fort(st, int(x[1])), "et les fortifications entamées")


func _test_ai() -> void:
	var st := GameState.create(34, 120, 1600.0, "", {"spectator": true, "ai_level": "normal", "ground": "complet"})
	var x := _besiege(st)
	var sim: Simulation = x[0]
	# L'IA réfléchit par intervalles : on lui laisse quelques jours.
	for i in 15:
		sim.step()
		if GroundSiege.posture(st, (x[2] as Fleet).id) != "":
			break
	_ok(GroundSiege.posture(st, (x[2] as Fleet).id) == "selectif", "l'IA bombarde en Sélectif quand elle assiège")
	var techs: Array = []
	for t in ["forces_speciales", "genie_siege", "defense_planetaire", "pont_orbital", "conscription_planetaire", "medecine_campagne",
			"citadelle_planetaire", "doctrine_interarmes", "infanterie_antiaerienne", "propagande_front", "bombardement_precision"]:
		if not Research.tech(t).is_empty():
			techs.append(t)
	_ok(techs.size() == 11, "onze technologies au sol de plus dans l'arbre")
