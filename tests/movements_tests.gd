extends RefCounted
## Tests des populations mixtes, lot 3 (mouvements) : traité de migration, migration intérieure,
## politique d'accueil, réfugiés (conquête, expulsion, famine), convois, diaspora (revendication,
## renaissance), sécession par affinité, luxe aimé, opérations d'espionnage, talents de peuples
## mêlés, IA, sauvegarde 42, options coupées.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Peuples mêlés, mouvements (migrations, réfugiés, convois, diaspora, sécession, espionnage)…")
	_test_off()
	_test_treaty()
	_test_policy()
	_test_refugees()
	_test_conquest()
	_test_expulsion()
	_test_convoys()
	_test_migration()
	_test_claims()
	_test_renaissance()
	_test_affinity()
	_test_loved()
	_test_spy()
	_test_talents()
	_test_ai()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _state(migrations := false, peoples := true) -> GameState:
	var st := GameState.create(4242, 150, 1800.0, "vael", {"ai_level": "", "peoples": "actifs" if peoples else "aucuns",
			"migrations": "actives" if migrations else "aucunes"})
	for e in st.empires:
		e.resources["energy"] = 5000
		e.resources["influence"] = 5000
		e.resources["materials"] = 5000
		e.resources["food"] = 5000
	return st


func _id_of(st: GameState, faction: String) -> int:
	for e in st.empires:
		if e.faction_id == faction:
			return e.id
	return -1


## Une colonie établie dans un système libre (habitable pour son propriétaire), au plus près de near.
func _plant(st: GameState, owner: int, pop: int, near := -1) -> Colony:
	var jumps := FactionTraits.jumps_from(st.galaxy, near) if near >= 0 else {}
	var best := -1
	var bj := 1 << 20
	for s in st.galaxy.systems:
		if st.system_owner(s.id) >= 0:
			continue
		var j := int(jumps.get(s.id, 999)) if near >= 0 else s.id
		if j >= bj or j == 0:
			continue
		for pid in s.planet_ids:
			if Economy._pop_hab(st, owner, st.galaxy.get_planet(pid).type) >= 60:
				best = pid
				bj = j
				break
	if best < 0:
		return null
	return _plant_at(st, owner, best, pop)


func _plant_at(st: GameState, owner: int, pid: int, pop: int) -> Colony:
	var c := Colony.new()
	c.planet_id = pid
	c.owner = owner
	c.kind = Colony.KIND_COLONY
	c.population = pop
	st.add_colony(c)
	st.rebuild_ownership()
	return c


func _sid(st: GameState, c: Colony) -> int:
	return st.galaxy.get_planet(c.planet_id).system_id


func _part(parts: Array, prefix: String) -> int:
	for p in parts:
		if String(p[0]).begins_with(prefix):
			return int(p[1])
	return 0


func _meet(st: GameState, a: int, b: int) -> void:
	if not st.get_empire(a).contacts.has(b):
		st.get_empire(a).contacts.append(b)
	if not st.get_empire(b).contacts.has(a):
		st.get_empire(b).contacts.append(a)


## Supprime un empire IA : plus aucune colonie, éliminé.
func _kill(st: GameState, id: int) -> void:
	for pid in st.colonies.keys():
		if st.colonies[pid].owner == id:
			st.colonies.erase(pid)
	st.rebuild_ownership()
	st.get_empire(id).eliminated = true
	st.get_empire(id).ai_level = "normal"


func _test_off() -> void:
	var st := _state(false, false)
	var v := _id_of(st, "vael")
	var o := _id_of(st, "ossarane")
	_meet(st, v, o)
	_ok(not st.migrations_on and st.moves.is_empty(), "sans l'option : ni migrations ni mouvements")
	_ok(Diplomacy.check_terms(st, v, o, Diplomacy.MIGRATION) != "", "pas de traité de migration sans les peuples mêlés")
	_ok(SimCommands.validate(st, SimCommands.refugee_policy(v, "ouverte")) != "", "pas de politique d'accueil sans les peuples mêlés")
	_ok(Espionage.check_op(st, v, o, "frictions") != "", "pas d'opération des peuples sans les peuples mêlés")
	var added: Array[Dictionary] = []
	Movements.monthly(st, added)
	_ok(added.is_empty() and st.moves.is_empty(), "le bilan des mouvements ne fait rien")
	var st2 := _state(false, true)
	_ok(not st2.migrations_on, "Migrations : option à part (désactivée par défaut)")
	_ok(_state(true).migrations_on, "Migrations activées")


func _test_treaty() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var o := _id_of(st, "ossarane")
	_meet(st, v, o)
	_ok(Diplomacy.check_terms(st, v, o, Diplomacy.MIGRATION) != "", "traité de migration : il faut la paix")
	Diplomacy.sign_treaty(st, v, o, Diplomacy.PEACE)
	_ok(Diplomacy.check_terms(st, v, o, Diplomacy.MIGRATION) == "", "en paix, le traité est possible")
	Diplomacy.sign_treaty(st, v, o, Diplomacy.MIGRATION)
	_ok(Diplomacy.has_migration(st, v, o) and Diplomacy.has_migration(st, o, v), "traité de migration signé")
	_ok(Movements.partners(st, v).has(o), "Ossarane devient partenaire de migration")
	Peoples.refresh(st)
	_ok(Peoples.colonist_species(st, v).has("ossarane"), "les Vael peuvent coloniser avec les Ossarane")
	_ok(Diplomacy.check_cancel(st, v, o, Diplomacy.MIGRATION) == "", "on peut fermer la migration")
	st.tick += 400
	Diplomacy.cancel(st, v, o, Diplomacy.PEACE)
	_ok(not Diplomacy.has_migration(st, v, o), "dénoncer la paix ferme la migration")
	var ev := AiDiplomacy.evaluate(st, o, v, Diplomacy.MIGRATION)
	_ok(ev.has("score") and not (ev["parts"] as Array).is_empty(), "l'IA sait juger un traité de migration")


func _test_policy() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var o := _id_of(st, "ossarane")
	_ok(Movements.policy(st, v) == "citoyens", "politique par défaut : peuples citoyens seulement")
	_ok(Movements.accepts(st, v, "vael") and Movements.accepts(st, v, "ossarane"), "les Ossarane, citoyens par défaut, sont acceptés")
	Peoples.set_status(st, v, "ossarane", "residents")
	_ok(not Movements.accepts(st, v, "ossarane"), "des résidents ne le sont plus")
	var cmd := SimCommands.refugee_policy(v, "ouverte")
	_ok(SimCommands.validate(st, cmd) == "", "ordre accepté")
	SimCommands.apply(st, cmd)
	_ok(Movements.accepts(st, v, "ossarane") and Movements.accepts(st, v, "khthari"), "politique ouverte : tout le monde")
	_ok(SimCommands.validate(st, cmd) != "", "c'est déjà la politique")
	Movements.set_policy(st, v, "fermee")
	_ok(not Movements.accepts(st, v, "vael"), "fermée : personne, pas même les siens")
	_ok(not Movements.accepts(st, GameState.NPC_ID, "vael"), "les Sans-Bannière n'accueillent personne")
	_ok(o >= 0, "Ossarane est en jeu")


func _test_refugees() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var o := _id_of(st, "ossarane")
	for e in st.empires:
		Movements.set_policy(st, e.id, "fermee")
	Movements.set_policy(st, v, "ouverte")
	var home: Colony = st.colonies[st.get_empire(v).home_planet]
	var src := _plant(st, o, 8, _sid(st, home))
	src.species = {"teyl": 4}
	var dest := Movements.refuge_for(st, _sid(st, src), "teyl", [o])
	_ok(dest != null and dest.owner == v, "le refuge est chez les Vael, seuls à accueillir")
	var inf := int(st.get_empire(v).resources["influence"])
	var food := int(st.get_empire(v).resources["food"])
	var before := dest.population
	var added: Array[Dictionary] = []
	var n := Movements.flee(st, src, "teyl", 2, [o], added)
	_ok(n == 2 and src.population == 6 and int(src.species.get("teyl", 0)) == 2, "deux Teyl quittent la colonie")
	_ok(dest.population == before + 2 and int(dest.species.get("teyl", 0)) == 2, "ils arrivent chez les Vael")
	_ok(Peoples.integration(dest, "teyl") == 50, "réfugiés intégrés à 50 %% (%d)" % Peoples.integration(dest, "teyl"))
	_ok(int(st.get_empire(v).resources["influence"]) > inf and int(st.get_empire(v).resources["food"]) < food, "accueillir rapporte de l'influence et coûte de la nourriture")
	_ok(_part(Movements.stability_parts(st, _sid(st, dest), v), "Réfugiés reconnaissants") > 0, "réfugiés reconnaissants : stabilité")
	var t := _id_of(st, "teyl")
	var thanked := false
	for m in st.memories:
		if int(m["who"]) == t and int(m["about"]) == v and String(m["kind"]) == "refugees_welcomed":
			thanked = true
	_ok(thanked, "l'empire des Teyl s'en souvient")


func _test_conquest() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var o := _id_of(st, "ossarane")
	var f := _id_of(st, "ferrocornes")
	var c := _plant(st, v, 10)
	c.species = {"ossarane": 10}
	Combat.capture_system(st, _sid(st, c), f)
	_ok(c.owner == f and c.population == 8, "monde conquis : 1 habitant sur 5 s'enfuit (%d restent)" % c.population)
	_ok(int(c.species.get("ossarane", 0)) == 8, "ce sont des Ossarane qui partent")
	_ok(o >= 0, "Ossarane est en jeu")


func _test_expulsion() -> void:
	var st := _state()
	var f := _id_of(st, "ferrocornes")
	var c := _plant(st, f, 10)
	c.species = {"vael": 4}
	Peoples.set_status(st, f, "vael", "expulses")
	for e in st.empires:
		Movements.set_policy(st, e.id, "fermee")
	st.tick = 90
	Peoples.refresh(st)
	var added: Array[Dictionary] = []
	Peoples.monthly(st, added)
	_ok(int(c.species.get("vael", 0)) == 3, "un expulsé de moins")
	var cv := Movements.convoys(st)
	_ok(cv.size() == 1 and String(cv[0]["fid"]) == "vael" and int(cv[0]["n"]) == 1, "sans refuge, l'expulsé part en convoi")


func _test_convoys() -> void:
	var st := _state()
	var f := _id_of(st, "ferrocornes")
	var c := _plant(st, f, 10)
	c.species = {"vael": 5}
	for e in st.empires:
		Movements.set_policy(st, e.id, "fermee")
	var added: Array[Dictionary] = []
	Movements.flee(st, c, "vael", 3, [f], added)
	var cvs := Movements.convoys(st)
	_ok(cvs.size() == 1 and int(cvs[0]["n"]) == 3, "un convoi de 3 réfugiés")
	_ok(not added.is_empty(), "la chronique le raconte")
	Movements.flee(st, c, "vael", 1, [f], added)
	_ok(Movements.convoys(st).size() == 1 and int(Movements.convoys(st)[0]["n"]) == 4, "le convoi grossit plutôt que d'en créer un autre")
	var cv: Dictionary = Movements.convoys(st)[0]
	var start := int(cv["sid"])
	st.tick = 30
	Movements._convoys_month(st, added)
	var moved := Movements.convoys(st).size() == 1 and int(Movements.convoys(st)[0]["sid"]) != start
	_ok(moved or Movements.convoys(st).is_empty(), "le convoi erre d'un saut (ou tombe sur des pirates)")
	if Movements.convoys(st).is_empty():
		return
	cv = Movements.convoys(st)[0]
	# Trois ans plus tard, loin des repaires : il se pose sur un monde libre.
	for s in st.galaxy.systems:
		if not Pirates.is_lair(st, s.id) and st.system_owner(s.id) < 0:
			cv["sid"] = s.id
			break
	st.tick = int(cv["born"]) + int(Movements.data()["convoy_days"])
	var before := st.colonies.size()
	Movements._convoys_month(st, added)
	_ok(Movements.convoys(st).is_empty() and st.colonies.size() == before + 1, "au bout de 3 ans, le convoi fonde une colonie")
	var npc := false
	for pid in st.colonies:
		var x: Colony = st.colonies[pid]
		if x.owner == GameState.NPC_ID and int(x.species.get("vael", 0)) == 4:
			npc = true
	_ok(npc, "une colonie libre des Sans-Bannière, peuplée de Vael")
	# Le convoi trouve un refuge dès qu'un empire ouvre ses portes.
	Movements.flee(st, c, "vael", 1, [f], added)
	var v := _id_of(st, "vael")
	Movements.set_policy(st, v, "ouverte")
	var pop := 0
	for pid in st.colonies:
		if st.colonies[pid].owner == v:
			pop += st.colonies[pid].population
	st.tick += 30
	Movements._convoys_month(st, added)
	var pop2 := 0
	for pid in st.colonies:
		if st.colonies[pid].owner == v:
			pop2 += st.colonies[pid].population
	_ok(Movements.convoys(st).is_empty() and pop2 == pop + 1, "un convoi accueilli débarque")


func _test_migration() -> void:
	var st := _state(true)
	var v := _id_of(st, "vael")
	var e := st.get_empire(v)
	var home: Colony = st.colonies[e.home_planet]
	var cap := Economy.max_pop(st, st.galaxy.get_planet(home.planet_id), v, home.buildings)
	home.population = cap
	var b := _plant(st, v, 1, _sid(st, home))
	_ok(Movements.push_reason(st, home) == "pleine", "une colonie pleine pousse ses habitants dehors")
	var dest := Movements.migration_dest(st, home, "vael", [v] as Array[int])
	_ok(dest == b, "ils partent vers la jeune colonie")
	var added: Array[Dictionary] = []
	var month := posmod(-v, 3)
	Movements._migrate(st, e, month, added)
	_ok(b.population > 1 and home.population < cap, "migration intérieure : %d migrant(s)" % (b.population - 1))
	var before := b.population
	Movements._migrate(st, e, month + 1, added)
	_ok(b.population == before, "seulement un trimestre sur trois")
	var off := _state(false)
	_ok(not Movements.migrations_on(off), "sans l'option, pas de migration intérieure")


func _test_claims() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var o := _id_of(st, "ossarane")
	_kill(st, o)
	var home: Colony = st.colonies[st.get_empire(v).home_planet]
	var c := _plant(st, v, 20, _sid(st, home))
	c.species = {"ossarane": 20}
	Peoples.refresh(st)
	var added: Array[Dictionary] = []
	Movements._claims(st, st.get_empire(v), added)
	var cl := Movements.claim(st, v)
	_ok(String(cl.get("fid", "")) == "ossarane", "une diaspora nombreuse réclame une terre")
	_ok(Movements.check_claim(st, v, "neutre") == "" or Movements.claim_planet(st, v, "ossarane") < 0, "un monde libre voisin peut lui être offert")
	_ok(SimCommands.validate(st, SimCommands.diaspora_answer(v, "n'importe")) != "", "réponse inconnue refusée")
	var cmd := SimCommands.diaspora_answer(v, "systeme")
	_ok(SimCommands.validate(st, cmd) == "", "lui céder un système est possible")
	SimCommands.apply(st, cmd)
	var eo := st.get_empire(o)
	_ok(not eo.eliminated and st.system_owner(_sid(st, c)) == o, "Ossarane renaît dans le système cédé")
	_ok(Diplomacy.pact(st, v, o) == Diplomacy.PEACE, "en paix avec son hôte")
	_ok(Movements.claim(st, v).is_empty(), "la revendication est close")
	# Refus : souvenir et renaissance plus proche.
	var st2 := _state()
	var v2 := _id_of(st2, "vael")
	var o2 := _id_of(st2, "ossarane")
	_kill(st2, o2)
	var c2 := _plant(st2, v2, 20, _sid(st2, st2.colonies[st2.get_empire(v2).home_planet]))
	c2.species = {"ossarane": 20}
	Peoples.refresh(st2)
	Movements._claims(st2, st2.get_empire(v2), added)
	st2.tick += int(Movements.data()["claim_days"])
	Movements._claims(st2, st2.get_empire(v2), added)
	_ok(Movements.claim(st2, v2).is_empty() and bool((st2.moves.get("refused", {}) as Dictionary).get("ossarane", false)), "sans réponse, c'est un refus")
	_ok(_part(Movements.stability_parts(st2, _sid(st2, c2), v2), "Diaspora") < 0, "diaspora éconduite : malus de stabilité")


func _test_renaissance() -> void:
	var st := _state()
	var o := _id_of(st, "ossarane")
	_kill(st, o)
	var c := _plant(st, GameState.NPC_ID, 16)
	c.species = {"ossarane": 16}
	var added: Array[Dictionary] = []
	Movements._renaissance(st, added)
	_ok(not st.get_empire(o).eliminated and c.owner == o, "un monde libre peuplé d'Ossarane fait renaître leur empire")
	_ok(st.get_empire(o).capital_planet == c.planet_id, "avec une capitale")
	_ok(c.species.is_empty() and c.population == 16, "ses habitants deviennent son peuple fondateur")


func _test_affinity() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var o := _id_of(st, "ossarane")
	var pair := []
	for s in st.galaxy.systems:
		if st.system_owner(s.id) >= 0 or s.planet_ids.is_empty():
			continue
		for n in s.neighbors:
			if st.system_owner(n) < 0 and not st.galaxy.systems[n].planet_ids.is_empty():
				pair = [s.id, n]
				break
		if not pair.is_empty():
			break
	var c := _plant_at(st, v, st.galaxy.systems[pair[0]].planet_ids[0], 10)
	c.species = {"ossarane": 7}
	_plant_at(st, o, st.galaxy.systems[pair[1]].planet_ids[0], 3)
	_ok(Movements.affinity_target(st, pair[0], v) == o, "majorité ossarane à la frontière d'Ossarane")
	var added: Array[Dictionary] = []
	StabilitySystem.secede(st, pair[0], v, added)
	_ok(c.owner == o, "la sécession rejoint l'empire de son peuple, pas les Sans-Bannière")


func _test_loved() -> void:
	var st := _state()
	_ok(Movements.loved("vael") == "vin_nebuleuse", "chaque peuple aime un luxe")
	_ok(Movements.loved("peuple_cree") != "" and Movements.loved("peuple_cree") == Movements.loved("peuple_cree"), "un peuple créé en a un aussi, toujours le même")
	var f := _id_of(st, "ferrocornes")
	var c := _plant(st, f, 10)
	c.species = {"vael": 5}
	var sid := _sid(st, c)
	var base := _part(Peoples.stability_parts(st, sid, f), "Luxe aimé")
	var w0 := int(Peoples.birth_weights(st, c).get("vael", 0))
	if not Goods.active(st):
		_ok(base == 0, "sans luxes dans la partie, rien")
		return
	st.goods["own"] = {f: {"vin_nebuleuse": 1}}
	Goods._dirty(st)
	_ok(Movements.loved_served(st, f, "vael"), "le vin de nébuleuse est servi")
	_ok(_part(Peoples.stability_parts(st, sid, f), "Luxe aimé") == 5, "luxe aimé : +5 de stabilité")
	_ok(int(Peoples.birth_weights(st, c).get("vael", 0)) == w0 * 2, "et les naissances doublent")


func _test_spy() -> void:
	var st := _state()
	var v := _id_of(st, "vael")
	var f := _id_of(st, "ferrocornes")
	_meet(st, v, f)
	var c := _plant(st, f, 10)
	c.species = {"vael": 5}
	_ok(Movements.most_mixed(st, f) == _sid(st, c), "le système le plus mêlé est repéré")
	_ok(Espionage.check_op(st, v, f, "propagande").find("peuples") < 0, "les opérations des peuples sont proposées")
	var txt := Espionage._apply(st, v, f, Espionage.op_def("frictions"))
	_ok(_part(Movements.stability_parts(st, _sid(st, c), f), "Frictions attisées") == -15, "frictions attisées : -15")
	var home: Colony = st.colonies[st.get_empire(v).home_planet]
	var hp := home.population
	_ok(Movements.call_home(st, v, f) == 3 and int(c.species.get("vael", 0)) == 2, "appel au retour : 3 Vael rentrent")
	var arrived := 0
	for pid in st.colonies:
		if st.colonies[pid].owner == v:
			arrived += st.colonies[pid].population
	_ok(arrived >= hp + 3, "ils arrivent chez les Vael")
	c.integ = {"vael": 0}
	var r0 := Peoples.integration_rate(st, c, "vael")
	Movements.xeno(st, f)
	_ok(Movements.xeno_left(st, f) > 0 and Peoples.integration_rate(st, c, "vael") == r0 / 2, "propagande xénophobe : intégration deux fois moins vite")
	_ok(txt.find("provocateurs") >= 0, "opération « Attiser les frictions » branchée")


func _test_talents() -> void:
	var st := _state()
	_ok(int(Movements.talent(st, _id_of(st, "vael")).get("integ_pct", 0)) == 50, "Vael (Pluriel) : intégration +50 %")
	_ok(int(Movements.talent(st, _id_of(st, "brisecomete")).get("refugee_integration", 0)) == 75, "Brisecomète (Syndicat) : réfugiés intégrés à 75 %")
	_ok(int(Movements.talent(st, _id_of(st, "ferrocornes")).get("loot_pops", 0)) == 2, "Ferrocornes (Horde) : butin vivant")
	_ok(int(Movements.talent(st, _id_of(st, "choeur")).get("assim_free", 0)) == 1, "Chœur (Foi) : conversion douce")
	_ok(int(Movements.talent(st, _id_of(st, "murmurants")).get("refugee_pull", 0)) == 1, "Murmurants (énergétiques) : le chant qui appelle")
	_ok(not Movements.talent_labels(st, _id_of(st, "teyl")).is_empty(), "les talents s'affichent")
	var t := _id_of(st, "teyl")
	var c := _plant(st, t, 10)
	c.species = {"vael": 5}
	c.integ = {"vael": 100}
	Peoples.set_status(st, t, "vael", "residents")
	_ok(Peoples.species_prod_mod(st, c, "vael") == 115, "Conscience : les résidents organiques produisent +15 %")
	var ch := _id_of(st, "choeur")
	var c2 := _plant(st, ch, 10)
	c2.species = {"vael": 5}
	Peoples.set_status(st, ch, "vael", "assimiler")
	_ok(_part(Peoples.stability_parts(st, _sid(st, c2), ch), "À assimiler") == 0, "Foi : l'assimilation ne coûte pas de stabilité")


func _test_ai() -> void:
	_ok(AiPeoples.policy_for(-2) == "ouverte" and AiPeoples.policy_for(3) == "fermee" and AiPeoples.policy_for(0) == "citoyens", "politique d'accueil selon le tempérament")
	var st := _state()
	var v := _id_of(st, "vael")
	_ok(AiPeoples.claim_answer(st, v, 2) == "refus", "une IA belliqueuse refuse")


func _test_save() -> void:
	var st := _state(true)
	var v := _id_of(st, "vael")
	var f := _id_of(st, "ferrocornes")
	Movements.set_policy(st, v, "ouverte")
	var c := _plant(st, f, 10)
	c.species = {"vael": 5}
	for e in st.empires:
		if e.id != v:
			Movements.set_policy(st, e.id, "fermee")
	Movements.set_policy(st, v, "fermee")
	var added: Array[Dictionary] = []
	Movements.flee(st, c, "vael", 2, [f], added)
	Movements.stir(st, _sid(st, c))
	var d := st.to_dict()
	_ok(int(d["version"]) >= 42, "sauvegarde version 42 ou plus")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and back.migrations_on, "option Migrations relue")
	_ok(back != null and Movements.convoys(back).size() == 1 and Movements.policy(back, v) == "fermee", "convois et politique relus")
	_ok(back != null and back.checksum() == st.checksum(), "même empreinte après relecture")
