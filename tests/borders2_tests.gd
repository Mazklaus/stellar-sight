extends RefCounted
## Tests du pilier frontières et droit de passage, lot 2 : sommation (obéie, ignorée), motif de guerre
## « Violation de frontière », riposte en guerre froide (jamais en paix), laissez-passer (IA, humain),
## péage, friction allégée, flottes à nos portes, famille Navigation de l'Amphictyonie, Arbitre,
## IA (sommer, obéir), interface, sauvegarde 57. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Frontières, lot 2…")
	_test_summons_obeyed()
	_test_summons_ignored()
	_test_riposte()
	_test_pass_ai()
	_test_pass_human()
	_test_toll()
	_test_friction_gates()
	_test_navigation()
	_test_arbiter()
	_test_ai()
	_test_ui()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(opts := {}) -> GameState:
	var o := {"ai_level": "", "borders": "souples", "wargoals": "actifs"}
	o.merge(opts, true)
	var st := GameState.create(7, 120, 1600.0, "vael", o)
	for e in st.empires:
		if e.is_npc():
			continue
		for x in st.empires:
			if x.id != e.id and not x.is_npc() and not e.contacts.has(x.id):
				e.contacts.append(x.id)
		e.resources["influence"] = 500
		e.resources["energy"] = 500
	st.borders["first"]["0>1"] = 1
	return st


func _cap(st: GameState, eid: int) -> int:
	return FactionTraits.capital_system(st, eid)


func _spawn(st: GameState, owner: int, ships: Array, sid: int) -> Fleet:
	var f := st.spawn_ship(owner, String(ships[0]), sid)
	for i in range(1, ships.size()):
		f.add_ship(String(ships[i]))
	return f


func _memory(st: GameState, who: int, about: int, kind: String) -> int:
	for m in st.memories:
		if int(m["who"]) == who and int(m["about"]) == about and String(m["kind"]) == kind:
			return int(m["count"])
	return 0


## Un intrus de 1 chez 0, vu.
func _intruder(st: GameState) -> Array:
	var f := _spawn(st, 1, ["corvette"], _cap(st, 0))
	var sim := Simulation.new(st)
	sim.step()
	return [sim, f]


func _test_summons_obeyed() -> void:
	var st := _new()
	_ok(Borders.check_summons(st, 0, 1) != "", "Pas de sommation sans intrus")
	var x := _intruder(st)
	var sim: Simulation = x[0]
	var f: Fleet = x[1]
	_ok(Borders.check_summons(st, 0, 1) == "", "Sommation possible contre un intrus vu")
	SimCommands.apply(st, SimCommands.border_act(0, "summons", 1))
	_ok(Borders.summons_end(st, 0, 1) == st.tick + 30, "Sommation : 30 jours pour partir")
	_ok(Borders.check_summons(st, 0, 1) != "", "Une seule sommation à la fois")
	f.system_id = Borders.nearest_permitted(st, f)
	sim.step()
	_ok(Borders.summons_end(st, 0, 1) == 0 and not Borders.has_cb(st, 0, 1), "Sommation obéie : l'incident est clos, sans motif")
	_ok(_memory(st, 0, 1, "summons_ignored") == 0, "Obéir ne coûte rien de plus")


func _test_summons_ignored() -> void:
	var st := _new()
	var x := _intruder(st)
	var sim: Simulation = x[0]
	SimCommands.apply(st, SimCommands.border_act(0, "summons", 1))
	for i in 31:
		sim.step()
	_ok(Borders.summons_end(st, 0, 1) == 0 and Borders.has_cb(st, 0, 1), "Sommation ignorée : motif de guerre « Violation de frontière »")
	_ok(_memory(st, 0, 1, "summons_ignored") == 1, "Sommation ignorée : souvenir -15")
	_ok(Wars.casus_list(st, 0, 1).has("violation"), "Le motif « Violation de frontière » apparaît dans les motifs de guerre")
	_ok(not Wars.casus_list(st, 1, 0).has("violation"), "Le motif est à sens unique")
	_ok(Borders.check_summons(st, 0, 1) != "", "Délai avant une nouvelle sommation")


func _test_riposte() -> void:
	var st := _new()
	var x := _intruder(st)
	var sim: Simulation = x[0]
	var f: Fleet = x[1]
	var guard := _spawn(st, 0, ["corvette", "corvette"], _cap(st, 1))
	_ok(not Combat.hostile_fleets(st, guard, f), "Sans sommation ignorée, pas de riposte")
	st.borders["ign"]["0>1"] = st.tick + 1000
	guard.system_id = f.system_id
	_ok(Combat.hostile_fleets(st, guard, f) and Combat.hostile_fleets(st, f, guard), "Guerre froide, sommation ignorée : riposte contre l'intrus chez soi")
	Diplomacy._rel_w(st, 0, 1)["pact"] = Diplomacy.PEACE
	_ok(not Combat.hostile_fleets(st, guard, f), "En paix, jamais de riposte")
	Diplomacy._rel_w(st, 0, 1)["pact"] = Diplomacy.COLD
	var before := f.ships.size() + guard.ships.size()
	for i in 8:
		sim.step()
	var after := (f.ships.size() if st.fleets.has(f.id) else 0) + (guard.ships.size() if st.fleets.has(guard.id) else 0)
	_ok(after < before or not st.battle_reports.is_empty(), "La riposte livre bataille sans déclaration de guerre")
	_ok(not Combat.at_war(st, 0, 1), "La riposte n'est pas une guerre")


func _test_pass_ai() -> void:
	var st := _new()
	st.get_empire(0).ai_level = "veteran"
	var f := _spawn(st, 1, ["corvette"], _cap(st, 1))
	_ok(Borders.check_pass(st, 1, f.id, 0) == "", "Laissez-passer possible pour une flotte armée")
	var inf := int(st.get_empire(1).resources["influence"])
	for i in 6:
		Diplomacy.remember(st, 0, 1, "pass_granted")
	var score := AiBorders.pass_score(st, 0, 1, f)
	SimCommands.apply(st, SimCommands.border_act(1, "pass", f.id, 0))
	var cost := int(Borders.pass_cost(st, 1).get("influence", 0))
	_ok(int(st.get_empire(1).resources["influence"]) == inf - cost, "Laissez-passer : coût en influence (%d, gratuit pour une république)" % cost)
	_ok(Borders.has_pass(st, f.id, 0) == (score >= 0), "L'IA répond selon son opinion et la taille de la flotte (score %d)" % score)
	st.borders["fp"][str(f.id)] = {"o": 0, "end": st.tick + 90}
	f.system_id = _cap(st, 0)
	_ok(Borders.fleet_right(st, f, 0), "Laissez-passer : la flotte passe")
	var other := _spawn(st, 1, ["corvette"], _cap(st, 0))
	_ok(not Borders.fleet_right(st, other, 0), "Le laissez-passer vaut pour une flotte précise")
	st.tick += 91
	Borders.daily(st)
	_ok(not Borders.has_pass(st, f.id, 0), "Laissez-passer échu au bout de 90 jours")
	var big := _spawn(st, 1, ["corvette", "corvette", "corvette", "corvette", "corvette", "corvette"], _cap(st, 1))
	_ok(AiBorders.pass_score(st, 0, 1, big) < AiBorders.pass_score(st, 0, 1, f), "Une grosse flotte obtient moins facilement un laissez-passer")


func _test_pass_human() -> void:
	var st := _new()
	var f := _spawn(st, 0, ["corvette"], _cap(st, 0))
	st.get_empire(1).ai_level = ""
	SimCommands.apply(st, SimCommands.border_act(0, "pass", f.id, 1))
	var prop := {}
	for p in st.proposals:
		if String(p["treaty"]) == "bpass":
			prop = p
	_ok(not prop.is_empty() and Diplomacy.proposal_limit(prop) == 15, "Entre humains, la demande passe par les propositions (15 jours)")
	_ok(Borders.check_pass(st, 0, f.id, 1) != "", "Une seule demande à la fois")
	_ok(Diplomacy.check_answer(st, 1, int(prop["id"]), true) == "", "La demande peut être acceptée")
	SimCommands.apply(st, SimCommands.answer_proposal(1, int(prop["id"]), true))
	_ok(Borders.has_pass(st, f.id, 1), "Demande acceptée : laissez-passer accordé")
	_ok(_memory(st, 0, 1, "pass_granted") == 1, "Accorder un laissez-passer plaît")


func _test_toll() -> void:
	var st := _new()
	_ok(SimCommands.validate(st, SimCommands.border_act(0, "toll", 2)) == "", "Ordre de péage valide")
	SimCommands.apply(st, SimCommands.border_act(0, "toll", 2))
	_ok(Borders.toll_of(st, 0) == 5, "Péage au palier 2 : 5 énergie par saut")
	Borders.set_policy(st, 0, 1, Borders.OPEN)
	var f := _spawn(st, 1, ["corvette"], _cap(st, 1))
	var e1 := int(st.get_empire(1).resources["energy"])
	var e0 := int(st.get_empire(0).resources["energy"])
	Borders.charge_toll(st, f, _cap(st, 0))
	var mult := maxi(1, int(Borders.talent(st, 0).get("toll_x", 1)))
	_ok(int(st.get_empire(1).resources["energy"]) == e1 - 5 and int(st.get_empire(0).resources["energy"]) == e0 + 5 * mult, "Le péage passe d'un trésor à l'autre")
	var scout := _spawn(st, 1, ["scout"], _cap(st, 1))
	Borders.charge_toll(st, scout, _cap(st, 0))
	_ok(int(st.get_empire(1).resources["energy"]) == e1 - 5, "Les vaisseaux sans armes ne paient pas")
	Diplomacy._rel_w(st, 0, 1)["pact"] = Diplomacy.ALLIANCE
	Borders.charge_toll(st, f, _cap(st, 0))
	_ok(int(st.get_empire(1).resources["energy"]) == e1 - 5, "Les alliés ne paient pas")
	_ok(int(Borders.data()["talents"]["gouvernement"]["feodalite"]["toll_x"]) == 2, "Droit de péage féodal : le double")


func _test_friction_gates() -> void:
	var st := _new()
	var before := 0
	for p in Diplomacy.opinion_parts(st, 0, 1):
		if String(p["label"]).begins_with("Frontières communes"):
			before = int(p["value"])
	Diplomacy.sign_treaty(st, 0, 1, Diplomacy.PASSAGE)
	var after := 0
	for p in Diplomacy.opinion_parts(st, 0, 1):
		if String(p["label"]).begins_with("Frontières communes"):
			after = int(p["value"])
	_ok(after == before / 2, "Libre-passage : friction des frontières communes divisée par deux (%d → %d)" % [before, after])
	var st2 := _new()
	var cap0 := _cap(st2, 0)
	var nb := -1
	for n in st2.galaxy.systems[cap0].neighbors:
		if st2.system_owner(int(n)) != 0:
			nb = int(n)
	if nb >= 0:
		_spawn(st2, 1, ["corvette", "corvette", "corvette", "corvette"], nb)
		Simulation.new(st2).step()
		Borders.monthly(st2)
		_ok(Borders.at_gates(st2, 0, 1), "Grosse flotte armée à un saut, sans droit : « Flottes à nos portes »")
		var found := false
		for p in Diplomacy.opinion_parts(st2, 0, 1):
			if String(p["label"]) == "Ses flottes à nos portes":
				found = int(p["value"]) == -5
		_ok(found, "Flottes à nos portes : -5 d'opinion")


func _amph(st: GameState, way: int) -> void:
	st.amph["founded"] = 0
	st.amph["members"] = [0, 1]
	st.amph["fam"]["navigation"] = way


func _test_navigation() -> void:
	var st := _new({"amphictyony": "active"})
	_ok(Amphictyony.family_available(st, "navigation"), "Famille Navigation au Nomos avec les frontières")
	_ok(not Amphictyony.family_available(_new({"amphictyony": "active", "borders": "libres"}), "navigation"), "Pas de Navigation sans frontières")
	_amph(st, 1)
	_ok(Borders.check_policy(st, 0, 1, Borders.CLOSED) != "", "Libre navigation : pas de frontière close entre amphictyons")
	_amph(st, 3)
	var f := _spawn(st, 1, ["corvette"], _cap(st, 0))
	_ok(Borders.fleet_right(st, f, 0), "Libre navigation III : les flottes de guerre des membres passent")
	_amph(st, -1)
	var x := _intruder(st)
	_ok(Borders.summons_days(st, 0, 1) == 15, "Espaces souverains : sommation en 15 jours")
	_amph(st, -3)
	var g := _spawn(st, 1, ["corvette"], _cap(st, 0))
	var n0 := _memory(st, 0, 1, "intrusion")
	(x[0] as Simulation).step()
	_ok(_memory(st, 0, 1, "intrusion") >= n0 + 2 or g == null, "Espaces souverains III : intrusion comptée double")


func _test_arbiter() -> void:
	var st := _new({"amphictyony": "active"})
	_ok(Borders.check_arbiter(st, 0, 1, 2) != "", "Seul l'Arbitre impose un libre-passage")
	st.amph["founded"] = 0
	st.amph["members"] = [0, 1, 2]
	st.amph["council"] = {"seats": [0]}
	st.amph["arbiter"] = {"eid": 0, "until": st.tick + 1000}
	if AmphInst.arbiter(st) == 0:
		_ok(Borders.check_arbiter(st, 0, 1, 2) == "", "L'Arbitre peut imposer le libre-passage entre deux amphictyons")
		SimCommands.apply(st, SimCommands.border_act(0, "arbiter", 1, 2))
		_ok(Borders.grants(st, 1, 2) and Borders.grants(st, 2, 1), "Libre-passage imposé dans les deux sens")
		_ok(Borders.check_arbiter(st, 0, 1, 2) != "", "Pas deux fois")


func _test_ai() -> void:
	var st := _new()
	st.get_empire(0).ai_level = "veteran"
	st.get_empire(1).ai_level = "veteran"
	var x := _intruder(st)
	AiBorders.think_state(st, 0)
	(x[0] as Simulation).flush_commands()
	_ok(Borders.summons_end(st, 0, 1) > 0 or Diplomacy.opinion(st, 0, 1) >= 40, "L'IA somme les intrus")
	_ok(AiBorders.obeys(st, 1, 0) == (AiLevels.aggression(st.get_empire(1)) <= 0 or Diplomacy.warships(st, 1) <= Diplomacy.warships(st, 0) * (1 + AiLevels.aggression(st.get_empire(1)))),
			"Obéir dépend du tempérament et du rapport de forces")


func _test_ui() -> void:
	var st := _new()
	_intruder(st)
	var buttons := {}
	var box := BordersUi.relation(st, 0, 1, func(_c: Dictionary) -> void: pass, buttons)
	_ok(buttons.has("summons") and not (buttons["summons"] as Button).disabled, "Interface : bouton de sommation")
	box.free()
	var b2 := {}
	var side := BordersUi.side(st, 0, 300, func(_c: Dictionary) -> void: pass, b2)
	_ok(b2.has("toll_0") and b2.has("toll_3"), "Interface : paliers de péage")
	side.free()


func _test_save() -> void:
	var st := _new()
	_intruder(st)
	SimCommands.apply(st, SimCommands.border_act(0, "summons", 1))
	SimCommands.apply(st, SimCommands.border_act(0, "toll", 1))
	var d := st.to_dict()
	_ok(int(d["version"]) == GameState.FORMAT_VERSION and GameState.FORMAT_VERSION >= 57, "Sauvegarde 57")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and back.checksum() == st.checksum() and Borders.summons_end(back, 0, 1) > 0 and Borders.toll_level(back, 0) == 1,
			"Sauvegarde : sommation et péage relus")
