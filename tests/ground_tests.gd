extends RefCounted
## Tests du pilier combat au sol et armées, lot 1 : option de partie, recrues, recrutement,
## embarquement, places à bord, bataille au sol (milice, régiments, moral), renforts, retraite,
## entretien (part gratuite des couches guerrières), fusion et scission, sauvegarde 59, IA.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Combat au sol, lot 1…")
	_test_modes()
	_test_recruit()
	_test_embark()
	_test_battle()
	_test_reinforce_retreat()
	_test_transport_losses()
	_test_upkeep()
	_test_merge_split()
	_test_save()
	_test_ai()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 11, faction := "ossarane", opts := {}) -> GameState:
	var o := {"ai_level": "", "ground": "complet"}
	o.merge(opts, true)
	var st := GameState.create(seed_value, 120, 1600.0, faction, o)
	for e in st.empires:
		e.resources["materials"] = 5000
		e.resources["energy"] = 5000
		e.resources["food"] = 5000
		st.ground["rec"][str(e.id)] = 40
	return st


func _home(st: GameState, eid: int) -> int:
	return FactionTraits.capital_system(st, eid)


func _war(st: GameState, a: int, b: int) -> void:
	var ea := st.get_empire(a)
	var eb := st.get_empire(b)
	if not ea.contacts.has(b):
		ea.contacts.append(b)
	if not eb.contacts.has(a):
		eb.contacts.append(a)
	Combat.start_war(st, a, b)


## Régiments tout prêts au sol, sans attendre le recrutement.
func _regs(st: GameState, eid: int, sid: int, t: String, n: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in n:
		out.append(Ground._new_regiment(st, eid, t, Peoples.founder_of(st, eid), sid))
	return out


func _transport(st: GameState, eid: int, sid: int, n := 1) -> Fleet:
	var f := st.spawn_ship(eid, "transport", sid)
	for i in n - 1:
		f.add_ship("transport")
	Ground.sync_fleet(st, f)
	return f


func _test_modes() -> void:
	var simple := GameState.create(3, 100, 1500.0, "vael", {"ai_level": ""})
	_ok(not Ground.full(simple), "sans option : combat au sol simplifié (règles d'avant)")
	_ok(not simple.to_dict().has("ground"), "mode simplifié : rien de sauvegardé (même empreinte)")
	var st := _new()
	_ok(Ground.full(st), "option Complet : armées en jeu")
	_ok(GameData.ground()["default_mode"] == "complet", "Nouvelle partie propose les armées par défaut")
	_ok(Ground.type_ids().has("infanterie") and not Ground.type_ids().has("milice"), "la milice ne se recrute pas")
	_ok(Ground.type_allowed(st, 0, "infanterie") and not Ground.type_allowed(st, 0, "blindes"), "les blindés demandent une technologie")
	_ok(Research.unlocks(st.get_empire(0).faction(), "blindes_assaut").has("régiment Blindés"), "la technologie affiche le régiment qu'elle débloque")


func _test_recruit() -> void:
	var st := _new()
	var home := _home(st, 0)
	var sim := Simulation.new(st)
	st.ground["rec"]["0"] = 1
	_ok(SimCommands.validate(st, SimCommands.ground_act(0, "recruit", home, "infanterie")).contains("recrues"), "pas assez de recrues : refusé")
	st.ground["rec"]["0"] = 10
	var other := _home(st, 1)
	_ok(SimCommands.validate(st, SimCommands.ground_act(0, "recruit", other, "infanterie")) != "", "on ne recrute que chez soi")
	_ok(SimCommands.validate(st, SimCommands.ground_act(0, "recruit", home, "blindes")).contains("technologie"), "type verrouillé : la technologie est nommée")
	var mats := int(st.get_empire(0).resources["materials"])
	_ok(sim.submit(SimCommands.ground_act(0, "recruit", home, "infanterie")), "recrutement d'infanterie")
	sim.flush_commands()
	_ok(Ground.recruits(st, 0) == 8, "le recrutement prend des recrues")
	_ok(int(st.get_empire(0).resources["materials"]) == mats - 20, "et son coût")
	_ok(Ground.queue_of(st, 0).size() == 1, "le régiment est en formation")
	for i in 31:
		sim.step()
	_ok(Ground.queue_of(st, 0).is_empty() and Ground.on_ground(st, home, 0).size() == 1, "le régiment est formé au bout de 30 jours")
	var r: Dictionary = Ground.on_ground(st, home, 0)[0]
	_ok(String(r["sp"]) == Peoples.founder_of(st, 0), "le régiment prend l'espèce de la colonie")
	# Réserve mensuelle.
	st.ground["rec"]["0"] = 0
	var gain := Ground.recruits_gain(st, 0)
	_ok(gain >= 1, "les colonies fournissent des recrues (%d par mois)" % gain)
	for i in 31:
		sim.step()
	_ok(Ground.recruits(st, 0) >= gain, "la réserve grandit chaque mois")
	# Démobilisation.
	st.ground["rec"]["0"] = 0
	var rid := int(r["id"])
	_ok(sim.submit(SimCommands.ground_act(0, "demob", rid)), "démobiliser un régiment chez soi")
	sim.flush_commands()
	_ok(Ground.regiment(st, rid).is_empty() and Ground.recruits(st, 0) == 1, "démobilisé : la moitié des recrues revient")


func _test_embark() -> void:
	var st := _new()
	var home := _home(st, 0)
	var sim := Simulation.new(st)
	_regs(st, 0, home, "infanterie", 5)
	var f := _transport(st, 0, home)
	var cap := Ground.capacity(st, f)
	var fit := cap / 4
	_regs(st, 0, home, "infanterie", fit + 1 - 5)
	_ok(cap >= 16, "un transport a des places (%d)" % cap)
	_ok(sim.submit(SimCommands.ground_act(0, "embark", f.id)), "embarquer")
	sim.flush_commands()
	_ok(Ground.aboard(st, f.id).size() == fit and f.troops == fit * 4, "l'infanterie (4 places par régiment) remplit le transport")
	_ok(Ground.on_ground(st, home, 0).size() == 1, "le dernier reste à quai")
	_ok(SimCommands.validate(st, SimCommands.ground_act(0, "embark", f.id)).contains("place"), "plus de place à bord")
	_ok(sim.submit(SimCommands.ground_act(0, "disembark", f.id)), "débarquer en garnison chez soi")
	sim.flush_commands()
	_ok(Ground.aboard(st, f.id).is_empty() and f.troops == 0, "tout le monde est à terre")
	# Pas d'invasion sans régiment, même avec des transports.
	_war(st, 0, 1)
	f.system_id = _home(st, 1)
	for g in Fleets.fleets_at(st, f.system_id, 1):
		st.fleets.erase(g.id)
	_ok(SimCommands.validate(st, SimCommands.invade(0, f.id)).contains("régiment"), "sans régiment à bord, pas d'invasion")


## Envahit la capitale de l'empire 1 avec n régiments : renvoie [sim, système, flotte].
func _invade(st: GameState, n: int, t := "infanterie") -> Array:
	var sim := Simulation.new(st)
	_war(st, 0, 1)
	var target := _home(st, 1)
	for g in Fleets.fleets_at(st, target, 1):
		st.fleets.erase(g.id)
	var f := _transport(st, 0, target, (n * Ground.size_of(t) + 15) / 16)
	for r in _regs(st, 0, target, t, n):
		r["f"] = f.id
	Ground.sync_fleet(st, f)
	return [sim, target, f]


func _test_battle() -> void:
	var st := _new(12)
	var x := _invade(st, 8)
	var sim: Simulation = x[0]
	var target: int = x[1]
	var f: Fleet = x[2]
	var g0 := Combat.garrison(st, target)
	_ok(g0 > 0, "la capitale a une garnison (%d)" % g0)
	_ok(SimCommands.validate(st, SimCommands.invade(0, f.id)) == "", "invasion permise même quand la garnison dépasse le nombre (la bataille décidera)")
	sim.submit(SimCommands.invade(0, f.id))
	sim.flush_commands()
	var b := Ground.battle(st, target)
	_ok(not b.is_empty(), "le débarquement ouvre une bataille au sol")
	_ok((b["mil"] as Array).size() == Ground.militia_units(st, target) or (b["mil"] as Array).size() > 0, "la garnison devient de la milice (%d unités)" % (b["mil"] as Array).size())
	_ok(Ground.aboard(st, f.id).is_empty() and f.troops == 0, "les régiments ont quitté le bord")
	_ok(Ground.front_width(st, target) >= 4, "front d'au moins 4 régiments (%d)" % Ground.front_width(st, target))
	var guard := 0
	while not Ground.battle(st, target).is_empty() and guard < 200:
		sim.step()
		guard += 1
	_ok(Ground.battle(st, target).is_empty(), "la bataille se termine (%d jours)" % guard)
	var reps := Ground.reports_for(st, 0)
	_ok(reps.size() == 1, "un rapport de bataille au sol")
	var rep: Dictionary = reps[0]
	_ok((rep["shots"] as Array).size() > 0 and (rep["units"] as Array).size() >= 8, "le rapport garde les unités et les coups (pour la vue de replay)")
	if int(rep["w"]) == 0:
		_ok(st.system_owner(target) == 0, "victoire : le système change de mains")
		_ok(Ground.on_ground(st, target, 0).size() > 0, "les survivants tiennent le système")
	else:
		_ok(st.system_owner(target) == 1, "défaite : le système reste au défenseur")
	_ok(int(rep["lost"][0]) > 0 and int(rep["lost"][1]) > 0, "des pertes des deux côtés")
	# Écrasante supériorité : victoire assurée.
	var st2 := _new(13)
	var y := _invade(st2, 24)
	var sim2: Simulation = y[0]
	sim2.submit(SimCommands.invade(0, (y[2] as Fleet).id))
	guard = 0
	while (guard == 0 or not Ground.battle(st2, int(y[1])).is_empty()) and guard < 300:
		sim2.step()
		guard += 1
	_ok(st2.system_owner(int(y[1])) == 0, "24 régiments prennent la capitale")
	# Système sans défenseur : pris sans combat.
	var st3 := _new(14)
	var z := _invade(st3, 1)
	st3.garrisons[int(z[1])] = 0
	var sim3: Simulation = z[0]
	sim3.submit(SimCommands.invade(0, (z[2] as Fleet).id))
	sim3.flush_commands()
	_ok(st3.system_owner(int(z[1])) == 0 and Ground.battle(st3, int(z[1])).is_empty(), "monde sans défenseur : pris dès le débarquement")
	# Moral : un régiment brisé quitte le front.
	var st4 := _new(15)
	var w := _invade(st4, 2)
	(w[0] as Simulation).submit(SimCommands.invade(0, (w[2] as Fleet).id))
	(w[0] as Simulation).flush_commands()
	var b4 := Ground.battle(st4, int(w[1]))
	if not b4.is_empty():
		var regs := Ground.on_ground(st4, int(w[1]), 0)
		regs[0]["mo"] = 0
		var front := Ground._front(Ground._units(st4, b4, 0), 4)
		_ok(front.size() == 1 and String(front[0]["k"]) == "r%d" % int(regs[1]["id"]), "un régiment sans moral quitte le front")


func _test_reinforce_retreat() -> void:
	var st := _new(16)
	var x := _invade(st, 3)
	var sim: Simulation = x[0]
	var target: int = x[1]
	st.garrisons[target] = 600
	sim.submit(SimCommands.invade(0, (x[2] as Fleet).id))
	sim.flush_commands()
	_ok(not Ground.battle(st, target).is_empty(), "bataille ouverte")
	var f2 := _transport(st, 0, target)
	for r in _regs(st, 0, target, "infanterie", 2):
		r["f"] = f2.id
	Ground.sync_fleet(st, f2)
	_ok(SimCommands.validate(st, SimCommands.invade(0, f2.id)) == "", "renfort possible pendant la bataille")
	sim.submit(SimCommands.invade(0, f2.id))
	sim.flush_commands()
	_ok(Ground.on_ground(st, target, 0).size() == 5, "les renforts rejoignent la bataille")
	_ok(SimCommands.validate(st, SimCommands.ground_act(0, "retreat", target)).contains("jour"), "pas de retraite avant 10 jours")
	for i in 10:
		sim.step()
	if not Ground.battle(st, target).is_empty():
		_ok(sim.submit(SimCommands.ground_act(0, "retreat", target)), "retraite après 10 jours")
		sim.flush_commands()
		_ok(Ground.battle(st, target).is_empty(), "la retraite clôt la bataille")
		_ok(Ground.on_ground(st, target, 0).is_empty(), "plus aucun régiment à terre")
		var back := Ground.aboard(st, (x[2] as Fleet).id).size() + Ground.aboard(st, f2.id).size()
		_ok(back <= 5, "les survivants rembarquent (%d)" % back)
		_ok(String(Ground.reports_for(st, 0)[0]["how"]) == "retreat", "le rapport note la retraite")
		_ok(st.system_owner(target) == 1, "le défenseur garde son monde")
	# La paix arrête la bataille et rapatrie.
	var st2 := _new(17)
	var y := _invade(st2, 3)
	st2.garrisons[int(y[1])] = 600
	(y[0] as Simulation).submit(SimCommands.invade(0, (y[2] as Fleet).id))
	(y[0] as Simulation).flush_commands()
	Diplomacy.end_war(st2, 0, 1)
	(y[0] as Simulation).step()
	_ok(Ground.battle(st2, int(y[1])).is_empty(), "la paix met fin à la bataille au sol")
	_ok(Ground.on_ground(st2, int(y[1]), 0).is_empty(), "les régiments rentrent au pays")


func _peace(st: GameState, a: int, b: int) -> void:
	st.get_empire(a).wars.erase(b)
	st.get_empire(b).wars.erase(a)


func _test_transport_losses() -> void:
	var st := _new(18)
	var home := _home(st, 0)
	var f := _transport(st, 0, home)
	for r in _regs(st, 0, home, "infanterie", 4):
		r["f"] = f.id
	var sim := Simulation.new(st)
	st.fleets.erase(f.id)
	sim.step()
	_ok(Ground.regiments_of(st, 0).is_empty(), "transport détruit : ses régiments périssent")
	var f2 := _transport(st, 0, home, 2)
	var per := Ground.capacity(st, f2) / 8
	for r in _regs(st, 0, home, "infanterie", per * 2):
		r["f"] = f2.id
	f2.remove_ship("transport")
	sim.step()
	_ok(Ground.aboard(st, f2.id).size() == per, "un transport perdu sur deux : les régiments en trop périssent")


func _test_upkeep() -> void:
	var st := _new(19, "ossarane")
	var home := _home(st, 0)
	var free := Ground.free_regiments(st, 0)
	_ok(free >= 2, "une part des régiments est gratuite (%d)" % free)
	_regs(st, 0, home, "infanterie", free)
	_ok(Ground.upkeep(st, 0).is_empty(), "dans la part gratuite : aucun entretien")
	_regs(st, 0, home, "infanterie", 2)
	_ok(int(Ground.upkeep(st, 0).get("food", 0)) == 2, "au-delà : chaque régiment coûte son entretien")
	var up: Dictionary = Economy.empire_income(st, 0)["upkeep"]
	_ok(int(up.get("food", 0)) >= 2, "l'entretien compte dans le bilan de l'empire")
	var fer := _new(19, "ferrocornes")
	var fe := 0
	for e in fer.empires:
		if e.faction_id == "ferrocornes":
			fe = e.id
	_ok(int(fer.get_empire(fe).faction().get("combat", {}).get("army_free_pct", 100)) == 300, "horde et honneur : trois fois plus de régiments gratuits")
	_ok(Ground.free_regiments(fer, fe) >= 2 * (int(GameData.ground()["upkeep"]["free_base"])), "les clans guerriers entretiennent plus d'armées sans payer")


func _test_merge_split() -> void:
	var st := _new(20)
	var home := _home(st, 0)
	var sim := Simulation.new(st)
	var a := _transport(st, 0, home)
	var b := _transport(st, 0, home)
	for r in _regs(st, 0, home, "infanterie", 3):
		r["f"] = a.id
	for r in _regs(st, 0, home, "infanterie", 2):
		r["f"] = b.id
	Ground.sync_all(st)
	_ok(sim.submit(SimCommands.merge_fleets(0, b.id, a.id)), "fusion")
	sim.flush_commands()
	_ok(Ground.aboard(st, a.id).size() == 5 and a.troops == 20, "les régiments suivent la fusion")
	_ok(sim.submit(SimCommands.split_fleet(0, a.id, "transport")), "scission")
	sim.flush_commands()
	var total := 0
	for fid in st.sorted_fleet_ids():
		total += Ground.aboard(st, fid).size()
	_ok(total == 5 and Ground.used_places(st, a.id) <= Ground.capacity(st, a), "scission : chacun garde sa place")


func _test_save() -> void:
	var st := _new(21)
	var x := _invade(st, 6)
	var sim: Simulation = x[0]
	st.garrisons[int(x[1])] = 300
	sim.submit(SimCommands.invade(0, (x[2] as Fleet).id))
	sim.step()
	sim.step()
	sim.submit(SimCommands.ground_act(0, "recruit", _home(st, 0), "infanterie"))
	sim.flush_commands()
	var d := st.to_dict()
	_ok(int(d["version"]) >= 59 and d.has("ground"), "sauvegarde 59 et plus avec les armées")
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(loaded != null and loaded.checksum() == st.checksum(), "relue à l'identique (bataille, régiments, file)")
	var s1 := Simulation.new(st)
	var s2 := Simulation.new(loaded)
	for i in 5:
		s1.step()
		s2.step()
	_ok(loaded.checksum() == st.checksum(), "la bataille se poursuit à l'identique après chargement")


func _test_ai() -> void:
	var st := GameState.create(5, 80, 1300.0, "ferrocornes", {"ai_level": "normal", "ground": "complet", "spectator": true})
	var sim := Simulation.new(st)
	for e in st.empires:
		for x in st.empires:
			if x.id != e.id and not e.contacts.has(x.id):
				e.contacts.append(x.id)
	_war(st, 0, 1)
	for i in 240:
		sim.step()
	var regs := 0
	for e in st.empires:
		regs += Ground.regiments_of(st, e.id).size() + Ground.queue_of(st, e.id).size()
	_ok(regs > 0, "les IA recrutent des régiments en guerre (%d)" % regs)
