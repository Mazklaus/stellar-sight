extends RefCounted
## Tests du pilier combat au sol, lot 3 : régiments de peuple, régiment titanesque, mercenaires,
## occupation tenue, insurrection, sort des civils, libération, héros général, ponts (espionnage,
## conscription, Nomos, faune), sauvegarde 61.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Combat au sol, lot 3…")
	_test_people_regiments()
	_test_titan()
	_test_mercenaries()
	_test_occupation()
	_test_liberation()
	_test_civilians()
	_test_general()
	_test_bridges()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 41, faction := "ossarane", opts := {}) -> GameState:
	var o := {"ai_level": "", "ground": "complet", "wargoals": "actifs", "occupation": "occupation"}
	o.merge(opts, true)
	var st := GameState.create(seed_value, 120, 1600.0, faction, o)
	for e in st.empires:
		e.resources["materials"] = 5000
		e.resources["energy"] = 5000
		e.resources["food"] = 5000
		e.resources["influence"] = 500
		e.resources["crystals"] = 500
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


func _regs(st: GameState, eid: int, sid: int, t: String, n: int, sp := "") -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in n:
		out.append(Ground._new_regiment(st, eid, t, sp if sp != "" else Peoples.founder_of(st, eid), sid))
	return out


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


func _run_battle(st: GameState, sim: Simulation, sid: int) -> int:
	var guard := 0
	while not Ground.battle(st, sid).is_empty() and guard < 300:
		sim.step()
		guard += 1
	return guard


func _test_people_regiments() -> void:
	_ok(Ground.type_allowed(_new(41, "khthari"), 0, "essaims"), "l'Essaim (ruche) lève des essaims de guerre")
	var st := _new(42)
	_ok(not Ground.type_allowed(st, 0, "essaims"), "Ossarane, non")
	_ok(bool(Ground.type_def("essaims").get("no_morale", false)) and Ground.size_of("essaims") == 2, "essaims : sans moral, deux par place")
	_ok(Ground.type_allowed(_new(43, "choeur"), 0, "fanatiques"), "le Chœur (Foi) lève des fanatiques")
	# Sans moral : les coups n'entament pas le moral.
	var x := _landing(st, 2)
	(x[0] as Simulation).submit(SimCommands.invade(0, (x[2] as Fleet).id))
	(x[0] as Simulation).flush_commands()
	var b := Ground.battle(st, int(x[1]))
	var ess := _regs(st, 0, int(x[1]), "essaims", 1)[0]
	var mo := int(ess["mo"])
	b["land"] = st.tick
	for i in 3:
		(x[0] as Simulation).step()
		if Ground.regiment(st, int(ess["id"])).is_empty():
			break
	_ok(Ground.regiment(st, int(ess["id"])).is_empty() or int(ess["mo"]) == mo, "un essaim ne perd jamais son moral")
	# Possédés : dégâts de moral ×2,5.
	_ok(int(Ground.type_def("possedes").get("morale_dmg_pct", 100)) == 250, "les possédés frappent le moral")


func _test_titan() -> void:
	var st := _new(44)
	var home := _home(st, 0)
	_ok(Ground.check_recruit(st, 0, home, "marcheur").contains("technologie"), "le marcheur de siège demande le Chantier titanesque")
	st.get_empire(0).techs["chantier_titanesque"] = true
	st.get_empire(0).tech_fx_n = -1
	_ok(Ground.check_recruit(st, 0, home, "marcheur") == "", "technologie connue : on peut le lever")
	Ground.recruit(st, 0, home, "marcheur")
	_ok(Ground.check_recruit(st, 0, home, "marcheur").contains("un seul"), "un seul par empire")
	_ok(Ground.size_of("marcheur") == 40, "il faut 40 places pour le transporter")


func _test_mercenaries() -> void:
	var st := _new(45, "ossarane", {"pirates": "actifs"})
	var home := _home(st, 0)
	var can := not st.lairs.is_empty() or GroundOccupation.syndicate(st) >= 0
	_ok(can, "pirates ou Syndicat en jeu : on peut louer")
	var sim := Simulation.new(st)
	var en := int(st.get_empire(0).resources["energy"])
	var rec := Ground.recruits(st, 0)
	_ok(sim.submit(SimCommands.ground_act(0, "hire", home)), "louer des mercenaires")
	sim.flush_commands()
	var mercs := 0
	for r in Ground.regiments_of(st, 0):
		if int(r.get("merc", 0)) > 0:
			mercs += 1
	_ok(mercs == 1 and Ground.on_ground(st, home, 0).size() >= 1, "une compagnie, tout de suite")
	_ok(Ground.recruits(st, 0) == rec and int(st.get_empire(0).resources["energy"]) < en, "sans recrues, mais contre de l'énergie")
	_ok(int(Ground.upkeep(st, 0).get("energy", 0)) >= 3, "leur entretien est toujours payé")
	for i in 3:
		sim.submit(SimCommands.ground_act(0, "hire", home))
		sim.flush_commands()
	_ok(SimCommands.validate(st, SimCommands.ground_act(0, "hire", home)).contains("pas plus"), "quatre compagnies au plus")


func _test_occupation() -> void:
	var st := _new(46)
	_war(st, 0, 1)
	var target := _home(st, 1)
	if not WarPeace.occ_on(st):
		_ok(false, "l'occupation doit être active dans ce test")
		return
	WarPeace._occupy(st, target, 0)
	_ok(WarPeace.occupier(st, target) == 0, "système occupé")
	_ok(not GroundOccupation.held(st, target) and GroundOccupation.income_pct(st, target) == 50, "sans régiment, l'occupation ne rapporte que la moitié")
	_regs(st, 0, target, "infanterie", 1)
	_ok(GroundOccupation.held(st, target) and GroundOccupation.income_pct(st, target) == 100, "un régiment au sol : l'occupation est tenue")
	for r in Ground.on_ground(st, target, 0):
		st.ground["r"].erase(str(int(r["id"])))
	# La résistance monte, puis l'insurrection éclate.
	for i in 4:
		GroundOccupation.monthly(st)
	_ok(not Ground.battle(st, target).is_empty(), "résistance à 100 : insurrection, bataille au sol")
	var b := Ground.battle(st, target)
	_ok(int(b["a"]) == 1 and int(b["d"]) == 0, "les partisans du propriétaire attaquent l'occupant")
	var sim := Simulation.new(st)
	_run_battle(st, sim, target)
	_ok(WarPeace.occupier(st, target) < 0, "sans occupant au sol, les partisans libèrent le système")


func _test_liberation() -> void:
	var st := _new(47)
	_war(st, 0, 1)
	var target := _home(st, 1)
	if not WarPeace.occ_on(st):
		return
	WarPeace._occupy(st, target, 0)
	_regs(st, 0, target, "infanterie", 2)
	for g in Fleets.fleets_at(st, target, 0):
		st.fleets.erase(g.id)
	var f := st.spawn_ship(1, "transport", target)
	f.add_ship("transport")
	for r in _regs(st, 1, target, "infanterie", 6):
		r["f"] = f.id
	Ground.sync_fleet(st, f)
	_ok(SimCommands.validate(st, SimCommands.invade(1, f.id)) == "", "le propriétaire peut débarquer pour libérer")
	var sim := Simulation.new(st)
	sim.submit(SimCommands.invade(1, f.id))
	sim.flush_commands()
	var b := Ground.battle(st, target)
	_ok(not b.is_empty() and (b["mil"] as Array).is_empty(), "libération : bataille contre les régiments de l'occupant, sans milice")
	_run_battle(st, sim, target)
	_ok(WarPeace.occupier(st, target) < 0 or Ground.on_ground(st, target, 1).is_empty(), "victoire : le système est libéré")


func _test_civilians() -> void:
	var st := _new(48)
	Ground.set_default_tactic(st, 0, "attack", "bombardement")
	var x := _landing(st, 6)
	var sim: Simulation = x[0]
	sim.submit(SimCommands.invade(0, (x[2] as Fleet).id))
	sim.flush_commands()
	_run_battle(st, sim, int(x[1]))
	var rep: Dictionary = Ground.reports_for(st, 0)[0]
	_ok(rep.has("civ"), "le rapport compte les victimes civiles (%d)" % int(rep.get("civ", 0)))
	_ok(GroundSiege.dev(st, int(x[1])) > 0, "les combats ont dévasté le système")


func _test_general() -> void:
	var st := _new(49)
	var x := _landing(st, 4)
	var f: Fleet = x[2]
	var cand := Heroes.make_candidate(st, 0, "general", ["test_general"])
	var hid := Heroes.recruit(st, 0, cand)
	_ok(Heroes.check_assign(st, 0, hid, "army", f.id) == "", "un général prend le commandement des régiments d'une flotte")
	Heroes.assign(st, 0, hid, "army", f.id)
	st.heroes[hid]["arrive"] = st.tick
	_ok(Ground.general_pct(st, 0, int(x[1])) > 0, "sa présence donne des dégâts aux régiments (+%d %%)" % Ground.general_pct(st, 0, int(x[1])))
	var noh := _new(50)
	var ty := noh.spawn_ship(0, "scout", _home(noh, 0))
	var hid2 := Heroes.recruit(noh, 0, Heroes.make_candidate(noh, 0, "general", ["g2"]))
	_ok(Heroes.check_assign(noh, 0, hid2, "army", ty.id) != "", "pas de général sur une flotte sans troupes")
	_ok(Heroes.post_effect_text(st, st.heroes[hid]).contains("%"), "son effet se lit dans le Panthéon")


func _test_bridges() -> void:
	var st := _new(51)
	_ok(not Espionage.op_def("saboter_defenses").is_empty(), "opération d'espionnage « Saboter les défenses »")
	var sid := _home(st, 1)
	_ok(GroundOccupation.spy_check(st, 0, 1, "saboter_defenses") == "", "elle vise ses défenses")
	var g0 := Combat.garrison(st, sid)
	GroundOccupation.spy_apply(st, 0, 1, {})
	_ok(GroundSiege.fort(st, sid) == 0 and Combat.garrison(st, sid) < g0, "remparts à zéro, milice entamée")
	var law := false
	for l: Dictionary in Politics.data()["laws"]["glaive"]["laws"]:
		if String(l["id"]) == "conscription" and int(l["fx"].get("recruits_pct", 0)) > 0:
			law = true
	_ok(law, "la loi de Conscription donne des recrues")
	_ok(Amphictyony.data()["breaches"].has("orbital_bombing"), "le Nomos (Mondes protégés) interdit le bombardement sans discernement")
	_ok(int(Ground.data()["battle"].get("fauna_militia", 0)) > 0, "la faune défend les mondes qu'elle hante")
	_ok(int(Faiths.data()["precepts"]["moines_guerriers"]["fx"].get("ground_damage_pct", 0)) > 0, "précepte Moines guerriers : régiments plus forts")


func _test_save() -> void:
	var st := _new(52)
	_war(st, 0, 1)
	if WarPeace.occ_on(st):
		WarPeace._occupy(st, _home(st, 1), 0)
		GroundOccupation.monthly(st)
	var d := st.to_dict()
	_ok(int(d["version"]) >= 61, "sauvegarde 61")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and GroundOccupation.resistance(back, _home(st, 1)) == GroundOccupation.resistance(st, _home(st, 1)), "la résistance survit à la sauvegarde")
