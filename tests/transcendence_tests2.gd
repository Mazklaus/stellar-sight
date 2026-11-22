class_name TranscendenceTests2
extends RefCounted
## Tests de la Transcendance, lot 2 (la galaxie) : Lieux minces, signes, Renoncement, Restants,
## effacement et voile, opinion, Amphictyonie, guerre « Ascension », espionnage, départ avec État
## successeur, Curée, les Partis, leur culte, renoncer. Appelés par TranscendenceTests.

static var _check: Callable


static func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func run(check: Callable) -> void:
	_check = check
	print("Transcendance, lot 2…")
	print("  - minces_signs")
	_test_minces_signs()
	print("  - society")
	_test_society()
	print("  - passage_world")
	_test_passage_world()
	print("  - war_spy")
	_test_war_spy()
	print("  - succession")
	_test_succession()
	print("  - curee_partis")
	_test_curee_partis()


static func _game(extra := {}) -> GameState:
	return TranscendenceTests.new_game("complete", "ossarane", extra)


static func _test_minces_signs() -> void:
	var st := _game()
	var ms := TranscendenceWorld.minces(st)
	_ok(ms.size() >= 3 and ms.size() <= 6, "Lieux minces : 3 à 6 sur la carte (%d)" % ms.size())
	_ok(TranscendenceTests.new_game("victoire").transcendence.get("minces", {}).is_empty(), "Victoire seule : pas de Lieux minces")
	var oss := TranscendenceTests.eid_of(st, "ossarane")
	st.get_empire(oss).techs["oree"] = true
	Transcendence.choose_path(st, oss, "depart", [])
	var sid := ms[0]
	var pid := st.galaxy.systems[sid].planet_ids[0]
	var c := Colony.new()
	c.planet_id = pid
	c.owner = oss
	st.colonies[pid] = c
	st.rebuild_ownership()
	_ok(TranscendenceWorld.minces_held(st, oss) == 1, "Un Lieu mince tenu")
	var has := false
	for x in Transcendence.gain_parts(st, oss):
		if String(x[0]).begins_with("Lieux minces"):
			has = true
	_ok(has, "Lieu mince : la jauge monte plus vite")
	_ok(Transcendence.passage_need(st, oss) == 1080 - 90, "Lieu mince : trois mois de moins au Passage")
	Transcendence.sub(st, "gauge")[str(oss)] = 260
	TranscendenceTests.months(st, 1)
	var inbox: Array = Events.meta(st, oss)["inbox"]
	var got := false
	for it in inbox:
		if String(it["card"]) == "orree_signe_depart":
			got = true
	_ok(got, "Signe avant-coureur à 25 % de jauge (fenêtre d'événement)")
	_ok(not Events.card("orree_raccourci").is_empty(), "Carte du Raccourci chargée")


static func _test_society() -> void:
	var st := _game()
	var oss := TranscendenceTests.eid_of(st, "ossarane")
	st.get_empire(oss).techs["oree"] = true
	Transcendence.choose_path(st, oss, "apotheose", [])
	Transcendence.sub(st, "gauge")[str(oss)] = 600
	var fx := Transcendence.effects(st, oss)
	_ok(int((fx.get("production_pct", {}) as Dictionary).get("all", 0)) == -5, "Renoncement : production -5 % au premier palier")
	var stab := 0
	for p in Transcendence.empire_stability_parts(st, oss):
		if String(p[0]).begins_with("Renoncement"):
			stab = int(p[1])
	_ok(stab == 5, "Renoncement : stabilité +5")
	_ok(TranscendenceWorld.restants_target(st, oss) > 0, "Les Restants grandissent avec la jauge")
	Transcendence.sub(st, "rest")[str(oss)] = 70
	var g := Transcendence.gauge(st, oss)
	TranscendenceTests.months(st, 1)
	_ok(Transcendence.gauge(st, oss) == g, "Les Restants au-dessus de 60 gèlent la jauge")
	_ok(TranscendenceWorld.restants(st, oss) < 70, "Les Restants retombent vers leur cible")
	# Renoncer : crise de stabilité, Restants au pouvoir.
	TranscendenceTests.cmd(st, oss, "renounce")
	var crisis := 0
	for p in Transcendence.empire_stability_parts(st, oss):
		if String(p[0]).contains("Renoncement à l'Orée"):
			crisis = int(p[1])
	_ok(crisis == -20 and TranscendenceWorld.restants(st, oss) == 100, "Renoncer : stabilité -20 pendant 5 ans, les Restants au pouvoir")


static func _test_passage_world() -> void:
	var st := _game()
	var oss := TranscendenceTests.eid_of(st, "ossarane")
	TranscendenceTests.to_passage(st, oss, "apotheose")
	var fx := Transcendence.effects(st, oss)
	_ok(int(fx.get("damage_pct", 0)) == -10 and int(fx.get("growth_pct", 0)) == -100, "Effacement : -10 % de dégâts la première année, plus de croissance")
	_ok(Transcendence.bombard_pct(st, oss) == 50, "Voile de l'Orée : bombardement réduit de moitié")
	var other := -1
	for e in st.empires:
		if e.id != oss and not e.is_npc() and Transcendence.credo(st, e.id) == "survie":
			other = e.id
	if other >= 0:
		var v := 0
		for p in TranscendenceWorld.opinion_parts(st, other, oss):
			v += int(p[1])
		_ok(v <= -20, "Credo Survie : crainte du Passage (opinion %d)" % v)
	_ok(not Amphictyony.family_def("oree").is_empty() and Amphictyony.family_available(st, "oree"), "Amphictyonie : famille « L'Orée » en jeu")
	_ok(not Amphictyony.family_available(TranscendenceTests.new_game("victoire"), "oree"), "Victoire seule : pas de famille « L'Orée »")


static func _test_war_spy() -> void:
	var st := _game()
	var oss := TranscendenceTests.eid_of(st, "ossarane")
	var other := 0 if oss != 0 else 1
	_ok(not Wars.casus_list(st, other, oss).has("ascension"), "Pas de motif « Ascension » sans Passage")
	TranscendenceTests.to_passage(st, oss, "apotheose")
	_ok(Wars.casus_list(st, other, oss).has("ascension") and bool(Wars.casus_def("ascension").get("just", false)), "Motif juste « Empêcher l'Ascension » contre un empire en Passage")
	_ok(Wars.goal_ok(st, "ascension", other, oss), "But de guerre « Empêcher l'Ascension »")
	st.get_empire(other).techs["oree"] = true
	_ok(TranscendenceWorld.spy_check(st, other, oss, "feler_oeuvre") == "", "Fêler l'Exodium : possible contre un Passage")
	TranscendenceWorld.spy_apply(st, other, oss, {"id": "feler_oeuvre"})
	_ok(not Transcendence.in_passage(st, oss) and Transcendence.stage(st, oss) == 2, "Exodium fêlé : Passage brisé, une étape perdue")
	_ok(TranscendenceWorld.spy_check(st, other, oss, "voler_carnets") != "", "Voler les carnets : il faut une voie")
	Transcendence.choose_path(st, other, "depart", [])
	TranscendenceWorld.spy_apply(st, other, oss, {"id": "voler_carnets"})
	_ok(Transcendence.gauge(st, other) >= 100 and Transcendence.stat(st, other, "stolen_notes") == 1, "Carnets volés : jauge +10 %")


static func _test_succession() -> void:
	var st := _game({"transcendence_outcome": "depart"})
	var oss := TranscendenceTests.eid_of(st, "ossarane")
	var e := st.get_empire(oss)
	var other_fid := ""
	for o in st.empires:
		if o.faction_id != "ossarane" and not o.is_npc():
			other_fid = o.faction_id
			break
	var c: Colony = st.colonies[e.capital_planet]
	c.population = 10
	c.species = {other_fid: 4}
	var n0 := st.empires.size()
	var techs := e.techs.size()
	TranscendenceTests.to_passage(st, oss, "apotheose")
	Transcendence.sub(st, "passage")[str(oss)]["prog"] = 9999
	TranscendenceTests.months(st, 1)
	_ok(e.eliminated and Transcendence.done(st, oss), "Départ : l'espèce fondatrice quitte la galaxie")
	_ok(st.empires.size() == n0 + 1, "État successeur fondé")
	_ok(Transcendence.renounced(st, st.empires.back().id) and Transcendence.check_path(st, st.empires.back().id, "depart") != "", "ceux qui sont restés ne franchiront jamais l'Orée")
	var ne := st.empires[st.empires.size() - 1]
	_ok(ne.faction_id == other_fid and not ne.eliminated and ne.techs.size() >= techs, "Successeur : l'espèce restée, les techniques héritées")
	var col: Colony = st.colonies.get(c.planet_id)
	_ok(col != null and col.owner == ne.id and col.population == 4, "Successeur : le monde et ses habitants restés")
	_ok(TranscendenceWorld.has_partis(st) and not TranscendenceWorld.parti(st, oss).is_empty(), "Les Partis : l'empire devient une puissance hors carte")
	_ok(ne.wars.is_empty(), "Successeur : pas de guerre de succession")


static func _test_curee_partis() -> void:
	var st := _game({"transcendence_outcome": "depart"})
	var oss := TranscendenceTests.eid_of(st, "ossarane")
	var e := st.get_empire(oss)
	var cap := e.capital_planet
	var known := e.techs.keys()
	TranscendenceTests.to_passage(st, oss, "apotheose")
	var friend := 0 if oss != 0 else 1
	TranscendenceWorld.note_aid(st, oss, friend, 5)
	Transcendence.sub(st, "passage")[str(oss)]["prog"] = 9999
	TranscendenceTests.months(st, 1)
	_ok(st.colonies.get(cap) == null and Transcendence.sub(st, "ruins").has(str(cap)), "Sans autre espèce : monde délaissé, ruines à fouiller")
	# La Curée : qui colonise la ruine retrouve une relique de savoir.
	var fe := st.get_empire(friend)
	var missing := 0
	for t in known:
		if not fe.techs.has(t) and not Research.tech(String(t)).is_empty():
			missing += 1
	# Toutes les technologies en file : celle de la relique doit en sortir.
	for t in Research.data().get("technologies", {}):
		if not fe.techs.has(t):
			fe.research_queue.append(String(t))
	var c := Colony.new()
	c.planet_id = cap
	c.owner = friend
	c.population = 1
	st.colonies[cap] = c
	st.rebuild_ownership()
	var before := fe.techs.size()
	TranscendenceTests.months(st, 1)
	_ok(missing == 0 or fe.techs.size() > before, "La Curée : une relique de savoir fouillée")
	var stale := 0
	for t in fe.research_queue:
		if fe.techs.has(t):
			stale += 1
	_ok(stale == 0, "La Curée : la relique sort de la file de recherche (sinon la sauvegarde ne se recharge plus)")
	_ok(SaveGame.save_state(st, "user://test_curee.json") == OK and SaveGame.load_state("user://test_curee.json") != null, "La Curée : la partie se recharge")
	_ok(Transcendence.stat(st, friend, "tr_ruins") == 1, "La Curée : comptée pour le haut fait")
	# Interventions : le favori des Partis reçoit un bienfait.
	var pc := Transcendence.cfg("partis")
	var keep := int(pc["pct"])
	pc["pct"] = 100
	for i in 12:
		TranscendenceTests.months(st, 1)
	pc["pct"] = keep
	var cu: Dictionary = Transcendence.sub(st, "curse").get(str(friend), {})
	_ok(int(cu.get("v", 0)) > 0 or int(fe.resources.get("materials", 0)) > 0, "Les Partis interviennent pour ceux qui les ont aidés")
	_ok(TranscendenceWorld.is_legend_ally(st, friend) and int(TranscendenceWorld.effects(st, friend).get("culture_pct", 0)) == 10, "Légende des Partis : leurs alliés rayonnent")
	# Culte des Partis : proposé seulement une fois un peuple parti.
	var st2 := _game()
	_ok(not TranscendenceWorld.has_partis(st2), "Pas de Partis sans départ")
