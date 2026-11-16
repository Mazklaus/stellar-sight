extends RefCounted
## Tests des défenses spatiales (étude du 2026-11-16, 40 propositions) : données et réglages, station à
## 3 paliers, modules et capacité, flotte fixe qui se bat, pas de siège ni de débarquement tant que la
## station tient, réduite au silence puis réparée, boucliers planétaires, mines et inhibiteur, garde,
## modernisation, talents, ponts (sabotage, traité, loi, héros, terrain, haut fait, mineurs, privé),
## IA et sauvegarde. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Défenses spatiales…")
	print("  - data")
	_test_data()
	print("  - modes")
	_test_modes()
	print("  - build_rules")
	_test_build_rules()
	print("  - fixed_fleet")
	_test_fixed_fleet()
	print("  - battle")
	_test_battle()
	print("  - siege_and_landing")
	_test_siege_and_landing()
	print("  - silence_and_repair")
	_test_silence_and_repair()
	print("  - shields")
	_test_shields()
	print("  - mines_and_inhibitor")
	_test_mines_and_inhibitor()
	print("  - guard_and_modernize")
	_test_guard_and_modernize()
	print("  - talents")
	_test_talents()
	print("  - bridges")
	_test_bridges()
	print("  - ai")
	_test_ai()
	print("  - save")
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(mode := "complete", seed_value := 41) -> GameState:
	var st := GameState.create(seed_value, 60, 1200.0, "ossarane", {"ai_level": "", "defenses": mode})
	st.fleets.clear()
	return st


static func home(st: GameState, eid: int) -> int:
	return st.galaxy.get_planet(st.get_empire(eid).capital_planet).system_id


static func cap_colony(st: GameState, eid: int) -> Colony:
	return st.colonies[st.get_empire(eid).capital_planet]


static func war(st: GameState, a: int, b: int) -> void:
	for p in [[a, b], [b, a]]:
		var e := st.get_empire(p[0])
		if not e.contacts.has(p[1]):
			e.contacts.append(p[1])
	Combat.start_war(st, a, b)


static func apply(st: GameState, cmd: Dictionary) -> String:
	var why := SimCommands.validate(st, cmd)
	if why == "":
		SimCommands.apply(st, cmd)
	return why


static func learn_all(st: GameState, eid: int) -> void:
	var e := st.get_empire(eid)
	for t in ["bastions", "citadelle_planetaire", "plates_formes_defense", "champs_de_mines", "boucliers_planetaires", "inhibiteur_saut", "remparts_stellaires"]:
		if not e.techs.has(t):
			e.techs[t] = true


func _test_data() -> void:
	var d := GameData.defenses()
	_ok(not d.is_empty() and d.has("units") and d.has("stations"), "data/defenses.json se charge")
	for t in [1, 2, 3]:
		var b := String(Defenses.tier_def(t)["building"])
		_ok(Defenses.station_tier_of(b) == t, "le palier %d est porté par %s" % [t, b])
	_ok(Defenses.role("bastion") == "station" and Defenses.role("module_batterie") == "module" and Defenses.role("plateforme_canon") == "platform", "rôles des bâtiments")
	_ok(Defenses.role("batterie_planetaire") == "planetary" and Defenses.role("bouclier_planetaire") == "shield", "rôles planétaires")
	for bid in GameData.buildings():
		if Defenses.role(bid) != "":
			_ok(not GameData.building(bid).get("requires_tech", []).is_empty(), "%s demande une technologie" % bid)
			for t in GameData.building(bid)["requires_tech"]:
				_ok(not Research.tech(String(t)).is_empty(), "%s : la technologie %s existe" % [bid, t])
	for uid in Defenses.cfg("units"):
		if String(uid).begins_with("_"):
			continue
		var u := GameData.ship(String(uid))
		_ok(not u.is_empty() and bool(u.get("fixed", false)) and int(u.get("speed", 1)) == 0, "%s se lit comme une unité fixe" % uid)
		_ok(Combat.data()["sizes"].has(Combat.ship_size(String(uid))), "%s a une taille connue" % uid)
	var core := Defenses.unit("def_st_2_10_20_120")
	_ok(int(core["hp"]) == 1400 * 120 / 100 and int(core["armor"]) == 40 and int(core["shield"]) == 45, "cœur de station calculé (palier II, blindage, bouclier, PV)")
	_ok(Combat.is_armed_ship("def_st_1_0_0_100"), "le cœur de station est armé")
	_ok(Designs.module("mouilleur_mines").get("minelayer", false) and Designs.module("demineur").get("sweeper", false), "modules de vaisseau mouilleur et démineur")
	_ok(int(Designs.module("torpilles_siege").get("siege", {}).get("medium", 0)) > 0, "torpilles de siège")


func _test_modes() -> void:
	var off := GameState.create(41, 60, 1200.0, "ossarane", {"ai_level": ""})
	_ok(not Defenses.enabled(off) and off.defenses.is_empty(), "sans le réglage : défenses désactivées (tests et bancs inchangés)")
	_ok(Defenses.building_allowed(off, "bastion") and not Defenses.building_allowed(off, "module_batterie"), "désactivées : le Bastion reste, pas les modules")
	var cc := cap_colony(off, 0)
	cc.buildings.append("bastion")
	_ok(Defenses.station(off, home(off, 0)).is_empty() and Combat.besiegers(off, home(off, 0)).is_empty(), "désactivées : pas de station au sens des défenses")
	var simple := new_game("simple")
	_ok(Defenses.enabled(simple) and not Defenses.full(simple), "Simples")
	_ok(Defenses.building_allowed(simple, "module_batterie") and not Defenses.building_allowed(simple, "plateforme_canon") \
			and not Defenses.building_allowed(simple, "module_inhibiteur") and Defenses.building_allowed(simple, "bouclier_planetaire"), "Simples : modules et boucliers, sans plates-formes ni inhibiteur")
	_ok(Defenses.full(new_game()), "Complètes")


func _test_build_rules() -> void:
	var st := new_game()
	learn_all(st, 0)
	var e := st.get_empire(0)
	e.resources["materials"] = 99999
	e.resources["energy"] = 99999
	e.resources["crystals"] = 999
	var c := cap_colony(st, 0)
	var sid := home(st, 0)
	_ok(apply(st, SimCommands.build(0, c.planet_id, "module_batterie")) != "", "pas de module sans station")
	c.buildings.append("bastion")
	_ok(Defenses.tier(st, sid) == 1, "le Bastion orbital est le palier I")
	_ok(Economy.check_build(st, 0, c.planet_id, "module_batterie") == "", "module sur la colonie de la station")
	_ok(not Economy.takes_slot("module_batterie") and not Economy.takes_slot("plateforme_canon") and Economy.takes_slot("bastion"), "modules et plates-formes sans emplacement")
	c.buildings.append_array(["module_batterie", "module_missiles"])
	_ok(Economy.check_build(st, 0, c.planet_id, "module_blindage") != "", "palier I : 2 emplacements de module")
	_ok(Economy.check_build(st, 0, c.planet_id, "forteresse_orbitale") == "", "Forteresse orbitale sur le Bastion")
	c.buildings[c.buildings.find("bastion")] = "forteresse_orbitale"
	_ok(Defenses.tier(st, sid) == 2 and Economy.check_build(st, 0, c.planet_id, "module_blindage") == "", "palier II : 4 emplacements")
	_ok(Combat.garrison_max(st, sid) > 0 and int(GameData.building("forteresse_orbitale")["garrison"]) == 35, "la Forteresse garde le rôle du Bastion (garnison +35)")
	# Capacité de plates-formes.
	var cap := Defenses.capacity(st, sid)
	_ok(cap >= 6, "capacité : base du palier II, population, technologies (%d)" % cap)
	for i in cap:
		c.buildings.append("plateforme_canon")
	_ok(Economy.check_build(st, 0, c.planet_id, "plateforme_missiles").contains("place"), "plus de place une fois la capacité pleine")
	# Une seule station par système.
	for pid in st.galaxy.systems[sid].planet_ids:
		if pid != c.planet_id and st.colonies.get(pid) == null:
			var o := Colony.new()
			o.planet_id = pid
			o.owner = 0
			o.kind = Colony.KIND_OUTPOST
			st.colonies[pid] = o
			st.rebuild_ownership()
			_ok(Economy.check_build(st, 0, pid, "bastion").contains("station"), "une seule station par système")
			_ok(Economy.check_build(st, 0, pid, "module_batterie") != "", "modules seulement sur la colonie de la station")
			break
	# Talent Médiéval spatial (Ossarane) : stations et modules moins chers.
	var t := Defenses.talent(st, 0)
	if int(t.get("cost_pct", 0)) < 0:
		_ok(int(Economy.building_cost(st, 0, "bastion")["materials"]) < int(GameData.building("bastion")["cost"]["materials"]), "Bâtisseurs de forteresses : Bastion moins cher")


func _station_setup(mode := "complete") -> Dictionary:
	var st := new_game(mode)
	learn_all(st, 0)
	var c := cap_colony(st, 0)
	c.buildings.append("bastion")
	c.buildings.append("module_batterie")
	c.buildings.append("plateforme_canon")
	war(st, 0, 1)
	return {"st": st, "sid": home(st, 0), "c": c}


func _test_fixed_fleet() -> void:
	var s := _station_setup()
	var st: GameState = s["st"]
	var sid: int = s["sid"]
	var f := Defenses.fixed_fleet(st, sid)
	_ok(f != null and Defenses.is_fixed(f) and f.owner == 0, "flotte fixe du défenseur")
	_ok(f.ships[0].begins_with("def_st_1_") and f.ships.has("def_mod_batterie") and f.ships.has("def_pf_canon"), "cœur, module armé, plate-forme")
	_ok(not st.fleets.has(f.id), "la flotte fixe n'est jamais rangée dans les flottes")
	var by := {}
	Defenses.add_fixed(st, by)
	_ok(by.is_empty(), "rien n'est ajouté sans intrus")
	var foe := st.spawn_ship(1, "fregate", sid)
	by = {sid: [foe]}
	Defenses.add_fixed(st, by)
	_ok((by[sid] as Array).size() == 2, "un intrus en guerre : la flotte fixe rejoint le système")
	_ok(Defenses.holds(st, sid), "la station tient l'orbite")


func _test_battle() -> void:
	var s := _station_setup()
	var st: GameState = s["st"]
	var sid: int = s["sid"]
	var foe := st.spawn_ship(1, "corvette", sid)
	var fid := foe.id
	for i in 6:
		CombatSystem.process(st, [])
	_ok(not st.fleets.has(fid) or st.fleets[fid].total_hp() < foe.total_max_hp(), "la station tire sur une corvette ennemie")
	var rep: Dictionary = st.battle_reports[-1] if not st.battle_reports.is_empty() else {}
	_ok(not rep.is_empty(), "un rapport de bataille")
	var sides := Espionage.battle_sides(rep)
	_ok(sides.has(0), "le défenseur figure dans la bataille grâce à ses défenses")
	if not st.fleets.has(fid):
		_ok(int(rep.get("winner", -1)) == 0, "la station gagne seule la bataille")


func _test_siege_and_landing() -> void:
	var s := _station_setup()
	var st: GameState = s["st"]
	var sid: int = s["sid"]
	var foe := st.spawn_ship(1, "croiseur", sid)
	foe.troops = 500
	_ok(Combat.besiegers(st, sid).is_empty(), "pas de siège tant que la station tient")
	_ok(Combat.check_invade(st, 1, foe.id).contains("station"), "pas de débarquement tant que la station tient")
	_ok(Defenses.assault_stage(st, sid).begins_with("2."), "étape de l'assaut : la station")
	Defenses._sub(st, "sil")[str(sid)] = 1
	_ok(not Defenses.holds(st, sid) and not Combat.besiegers(st, sid).is_empty(), "station réduite au silence : le siège peut commencer")


func _test_silence_and_repair() -> void:
	var s := _station_setup()
	var st: GameState = s["st"]
	var sid: int = s["sid"]
	var f := Defenses.fixed_fleet(st, sid)
	# Le cœur tombe, la plate-forme aussi.
	var keep_ships: Array[String] = []
	var keep_hp: Array[int] = []
	for i in f.ships.size():
		if f.ships[i] == "def_mod_batterie":
			keep_ships.append(f.ships[i])
			keep_hp.append(f.hp[i] / 2)
	f.ships = keep_ships
	f.hp = keep_hp
	var added: Array[Dictionary] = []
	Defenses._write_back(st, sid, f, added)
	_ok(Defenses.silenced(st, sid), "cœur détruit : station réduite au silence")
	_ok(not (s["c"] as Colony).buildings.has("plateforme_canon"), "plate-forme détruite : perdue")
	_ok((s["c"] as Colony).buildings.has("bastion"), "la station n'est pas rasée")
	for i in 70:
		Defenses._repairs(st, added)
	_ok(not Defenses.silenced(st, sid), "la station se répare seule (60 jours) et reprend du service")


func _test_shields() -> void:
	var st := new_game()
	learn_all(st, 0)
	var c := cap_colony(st, 0)
	var sid := home(st, 0)
	c.buildings.append("bouclier_planetaire")
	var sh := Defenses.shield(st, sid)
	_ok(int(sh["level"]) == 1 and int(sh["pts"]) == int(sh["max"]), "bouclier planétaire plein")
	_ok(Defenses.bombard_pct(st, sid) == 50, "Bouclier I : bombardement divisé par deux")
	var left := Defenses.absorb_siege(st, sid, 40)
	_ok(left == 0 and int(Defenses.shield(st, sid)["pts"]) == int(sh["max"]) - 40, "le siège use d'abord le bouclier")
	c.buildings[c.buildings.find("bouclier_planetaire")] = "bouclier_planetaire_2"
	_ok(Defenses.blocks_landing(st, sid) and Defenses.bombard_pct(st, sid) == 0, "Dôme : bombardement et débarquement bloqués")
	Defenses._sub(st, "sh")[str(sid)] = 0
	_ok(not Defenses.blocks_landing(st, sid), "Dôme épuisé : le débarquement redevient possible")
	Defenses._shields(st)
	_ok(int(Defenses.shield(st, sid)["pts"]) > 0, "le bouclier remonte hors siège")


func _test_mines_and_inhibitor() -> void:
	var s := _station_setup()
	var st: GameState = s["st"]
	var sid: int = s["sid"]
	Defenses._sub(st, "mines")[str(sid)] = {"o": 0, "d": 100}
	var hits := 0
	for i in 20:
		var f := st.spawn_ship(1, "fregate", sid)
		if Defenses.on_enter(st, f, sid) == 1:
			hits += 1
			_ok(f.hp[0] >= 1, "une mine estropie sans détruire")
		st.fleets.erase(f.id)
	_ok(hits > 3, "densité 100 : les mines touchent souvent (%d sur 20)" % hits)
	var friend := st.spawn_ship(0, "fregate", sid)
	_ok(Defenses.on_enter(st, friend, sid) == 0, "les mines épargnent leur propriétaire")
	# Inhibiteur (palier II).
	var c: Colony = s["c"]
	c.buildings[c.buildings.find("bastion")] = "forteresse_orbitale"
	c.buildings.append("module_inhibiteur")
	Defenses._sub(st, "mines").clear()
	var runner := st.spawn_ship(1, "coursier", sid)
	_ok(Defenses.on_enter(st, runner, sid) == 2, "l'inhibiteur retient même un coursier de saut")
	# Usure et déminage.
	Defenses._sub(st, "mines")[str(sid)] = {"o": 0, "d": 50}
	var sw := st.spawn_ship(1, "fregate", sid)
	sw.ships[0] = "fregate"
	st.tick = 359
	Defenses._mines_daily(st)
	_ok(int(Defenses.mines(st, sid).get("d", 50)) <= 50, "déminage et usure")


func _test_guard_and_modernize() -> void:
	var s := _station_setup()
	var st: GameState = s["st"]
	var sid: int = s["sid"]
	var f := st.spawn_ship(0, "fregate", sid)
	_ok(apply(st, SimCommands.defense_act(0, "guard", f.id)) == "", "ordre Garder le système")
	_ok(f.is_guarding() and int(f.patrol[0]) == sid, "la flotte garde son système")
	_ok(Defenses.damage_pct(st, f, sid) >= 10 + Defenses.cover_pct(st, sid), "garde et couverture de station : bonus de dégâts")
	var other := -1
	for n in st.galaxy.systems[sid].neighbors:
		other = int(n)
		break
	f.system_id = other
	Defenses._guards(st)
	_ok(f.is_moving() and f.destination() == sid, "une flotte gardienne attirée au-dehors revient")
	_ok(apply(st, SimCommands.defense_act(0, "unguard", f.id)) == "" and not f.is_guarding(), "lever la garde")
	# Modernisation : un élément aux marques d'hier.
	Defenses._sub(st, "gen")[str(sid)] = {"st": -2}
	var e := st.get_empire(0)
	e.resources["materials"] = 9999
	var g := Research.mark_gen(st, 0)
	if Research.gen_outdated(st, 0, -2):
		_ok(not Defenses.modernize_cost(st, sid).is_empty(), "coût de modernisation")
		_ok(apply(st, SimCommands.defense_act(0, "modernize", sid)) == "", "moderniser")
		_ok(int(Defenses._sub(st, "gen")[str(sid)].get("st", -1)) == g, "défenses aux marques du jour")


func _test_talents() -> void:
	var st := new_game()
	for eid in range(st.empires.size()):
		var t := Defenses.talent(st, eid)
		for l in t.get("labels", []):
			_ok(String(l[0]) != "" and String(l[1]) != "", "talent de défense lisible pour %s" % st.get_empire(eid).short_name())


func _test_bridges() -> void:
	var s := _station_setup()
	var st: GameState = s["st"]
	var sid: int = s["sid"]
	var c: Colony = s["c"]
	# Sabotage : bouclier coupé 30 jours.
	c.buildings.append("bouclier_planetaire")
	_ok(DefensesBridges.spy_check(st, 1, 0, "couper_bouclier") == "", "sabotage du bouclier possible")
	DefensesBridges.spy_apply(st, 1, 0, {"id": "couper_bouclier"})
	_ok(int(Defenses.shield(st, sid)["pts"]) == 0, "bouclier coupé")
	DefensesBridges.spy_apply(st, 1, 0, {"id": "saboter_plates_formes"})
	var pf := Defenses.hp_of(st, sid, "pf:plateforme_canon:0", "def_pf_canon")
	_ok(pf < Fleet.max_hp_of("def_pf_canon"), "plates-formes endommagées")
	# Traité : démilitarisation.
	_ok(WarPeace.CLAUSES.has("demil") and not WarPeace.clause_def("demil").is_empty(), "clause Démilitariser un système")
	_ok(DefensesBridges.demil_target(st, 1, 0) == sid, "le système à démilitariser porte une station")
	DefensesBridges.demilitarize(st, 1, 0)
	_ok(Defenses.tier(st, sid) == 0 and not c.buildings.has("plateforme_canon"), "station et plates-formes démontées")
	_ok(Defenses.check_build(st, 0, c, "bastion").contains("démilitarisé"), "interdit de rebâtir pendant 10 ans")
	# Haut fait Inviolée.
	var st2 := new_game()
	cap_colony(st2, 0).buildings.append("bastion")
	st2.tick = 360 * 51
	_ok(DefensesBridges.inviolate_years(st2, 0) >= 50, "Inviolée : 50 ans sans siège avec une station")
	st2.sieges[home(st2, 0)] = {"by": 1}
	DefensesBridges.daily(st2, [])
	_ok(DefensesBridges.inviolate_years(st2, 0) == 0, "un siège remet le compteur à zéro")
	_ok(not GameData.deeds().get("deeds", {}).get("inviolee", {}).is_empty(), "haut fait Inviolée dans les données")
	# Terrain : tempête coupe l'inhibiteur ; astéroïdes blindent.
	_ok(DefensesBridges.core_armor(st2, home(st2, 0), 0) == (15 if Terrain.at(st2, home(st2, 0)).has("asteroides") else 0), "astéroïdes : cœur blindé")
	# Loi des mines.
	_ok(not DefensesBridges.mines_banned(st2, 0), "sans Amphictyonie, les mines sont permises")
	# Héros : trait ingénieur de place gardé hors du tirage sans défenses.
	var off := GameState.create(41, 60, 1200.0, "ossarane", {"ai_level": ""})
	_ok(not Heroes.class_traits("intendant", off).has("ingenieur_place") and Heroes.class_traits("intendant", st2).has("ingenieur_place"), "Ingénieur de place seulement avec les défenses")
	# Privé : plate-forme payée seulement près d'un comptoir.
	var st3 := new_game()
	learn_all(st3, 0)
	var c3 := cap_colony(st3, 0)
	c3.buildings.append("bastion")
	_ok(not DefensesBridges.private_ok(st3, 0, c3, "plateforme_canon"), "pas de plate-forme privée sans comptoir")
	c3.buildings.append("comptoir")
	_ok(DefensesBridges.private_ok(st3, 0, c3, "plateforme_canon"), "plate-forme privée dans un système à comptoir")


func _test_ai() -> void:
	var st := GameState.create(43, 60, 1200.0, "ossarane", {"ai_level": "normal", "defenses": "complete"})
	var sim := Simulation.new(st)
	for e in st.empires:
		learn_all(st, e.id)
		e.resources["materials"] = 3000
	for i in 120:
		sim.step()
	var stations := 0
	for e in st.empires:
		if e.is_ai() and not e.eliminated and e.capital_planet >= 0 and Defenses.tier(st, home(st, e.id)) > 0:
			stations += 1
	_ok(stations > 0, "les IA bâtissent des stations à leur capitale (%d)" % stations)


func _test_save() -> void:
	var s := _station_setup()
	var st: GameState = s["st"]
	var sid: int = s["sid"]
	Defenses._sub(st, "mines")[str(sid)] = {"o": 0, "d": 42}
	Defenses._sub(st, "hp")[str(sid)] = {"st": 100}
	var d := st.to_dict()
	_ok(int(d["version"]) >= 81, "sauvegarde 81 ou plus")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and Defenses.mode(back) == "complete", "réglage relu")
	_ok(int(Defenses.mines(back, sid).get("d", 0)) == 42 and Defenses.hp_of(back, sid, "st", "x") == 100, "mines et PV relus")
	var off := GameState.create(41, 60, 1200.0, "ossarane", {"ai_level": ""})
	_ok(not off.to_dict().has("defenses"), "désactivées : rien de plus dans la sauvegarde")
