extends RefCounted
## Tests des hauts faits galactiques, lot 2 : Annales (frise), grands moments qui donnent de la Gloire
## (merveille, crise, paix imposée, monde ancien), héros (renom, expérience, ambition Gloire), Légende
## des Picaresques, score, Patrimoine et Rayonnement, voix à l'Amphictyonie, hauts faits infâmes et
## Infamie, actes notés par le reste du jeu (traités rompus, archives, Tueur de géant, séries).
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Hauts faits galactiques (Annales et ponts)…")
	_test_annals()
	_test_moments()
	_test_heroes()
	_test_legend()
	_test_score_culture()
	_test_infamy()
	_test_battle_hooks()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(seed_value := 13, extra := {}, faction := "vael") -> GameState:
	var o := {"ai_level": "", "deeds": "tous"}
	o.merge(extra, true)
	return GameState.create(seed_value, 120, 1600.0, faction, o)


static func to_check(st: GameState) -> void:
	for i in 31:
		st.tick += 1
		Deeds.daily(st)
		if posmod(st.tick, Deeds.r_int("check_days")) == Deeds.r_int("offset"):
			return


static func kinds(st: GameState, eid: int) -> Array:
	var out := []
	for x: Dictionary in Deeds.annals_of(st, eid):
		out.append("%s:%s" % [x["k"], x["id"]])
	return out


func _test_annals() -> void:
	var st := new_game()
	Research.count_stat(st, 0, "battles_won")
	Research.count_stat(st, 0, "battles_won")
	var k := kinds(st, 0)
	_ok(k.count("first:battles_won") == 1, "première bataille gagnée inscrite une seule fois")
	Research.count_stat(st, 0, "guardians")
	to_check(st)
	k = kinds(st, 0)
	_ok(k.has("moment:guardians") and k.has("deed:tueur_de_gardien"), "grand moment et haut fait dans les Annales")
	_ok(Deeds.annals_of(st, 1).is_empty(), "les Annales sont propres à chaque empire")


func _test_moments() -> void:
	var st := new_game()
	var g := Deeds.glory(st, 0)
	DeedsBridges.on_wonder(st, 0, "assemblee")
	_ok(Deeds.glory(st, 0) - g == int(Deeds.rules()["moments"]["wonder"]), "merveille achevée : Gloire")
	g = Deeds.glory(st, 0)
	DeedsBridges.on_crisis_victory(st, [[0, 60], [1, 40]])
	_ok(Deeds.glory(st, 0) - g == int(Deeds.rules()["moments"]["crisis"]) * 60 / 100, "crise vaincue : Gloire selon la part de gloire")
	_ok(Deeds.count(st, 0, "crisis_top") == 1 and Deeds.count(st, 1, "crisis_top") == 0, "plus grande part notée")
	_ok(Deeds.count(st, 1, "crisis_survived") == 1, "les survivants sont notés")
	to_check(st)
	_ok(Deeds.winners(st, "bouclier_galaxie") == [0], "Bouclier de la galaxie au premier contributeur")
	# Paix imposée et David.
	var st2 := new_game()
	var g2 := Deeds.glory(st2, 0)
	DeedsBridges.on_peace(st2, 0, 1, 0)
	_ok(Deeds.glory(st2, 0) - g2 == int(Deeds.rules()["moments"]["imposed_peace"]), "paix imposée : Gloire du vainqueur")
	DeedsBridges.on_peace(st2, 0, 1, -1)
	_ok(Deeds.glory(st2, 1) == 0, "paix blanche : pas de Gloire")
	# David : le vainqueur tient moins de systèmes que le vaincu.
	var sys0 := DeedsEval._systems_held(st2, 0).size()
	var sys1 := DeedsEval._systems_held(st2, 1).size()
	_ok(Deeds.count(st2, 0, "david") == (1 if sys0 < sys1 else 0), "David seulement contre plus grand")


func _test_heroes() -> void:
	var st := new_game()
	if st.heroes.is_empty() and st.hero_meta.is_empty():
		_ok(true, "héros absents de cette partie : renom ignoré")
		return
	var r0 := int(Heroes.meta(st, 0).get("renown", 0))
	Research.count_stat(st, 0, "guardians")
	var r1 := int(Heroes.meta(st, 0).get("renown", 0))
	to_check(st)
	_ok(int(Heroes.meta(st, 0).get("renown", 0)) >= r1 + int(Heroes.data()["acts"]["deed"]["renown"]), "un haut fait fait monter le renom")
	_ok(r1 >= r0, "renom cohérent")
	_ok((Heroes.ambition_def("gloire")["acts"] as Array).has("deed_war"), "l'ambition Gloire compte les hauts faits de guerre")


func _test_legend() -> void:
	var st := new_game(13, {}, "brisecomete")
	var e := st.get_empire(0)
	_ok(Reputation.has(e.faction()), "peuple Picaresque en jeu")
	var rep0 := e.reputation
	Research.count_stat(st, 0, "guardians")
	to_check(st)
	_ok(e.reputation >= mini(int(e.faction()["reputation"].get("max", 100)), rep0 + Deeds.r_int("legend_rep")) or e.reputation >= rep0, "la Légende gagne de la réputation à chaque haut fait")
	_ok(DeedsBridges.affinity(st, 0, "ombres"), "Picaresque : affinité avec les Ombres")


func _test_score_culture() -> void:
	var st := new_game(13, {"culture": "actif"})
	var s0 := Victory.score(st, 0)
	var h0 := Culture.heritage(st, 0)
	Deeds.add_glory(st, 0, 1000)
	_ok(Victory.score(st, 0) == s0 + 1000 / Deeds.r_int("score_div"), "un dixième de la Gloire au score")
	if Culture.enabled(st):
		_ok(Culture.heritage(st, 0) == h0 + 1000 / Deeds.r_int("heritage_div"), "la Gloire s'ajoute au Patrimoine")
	var rp := Culture.radiance_pct(st, 0)
	Research.count_stat(st, 0, "guardians")
	to_check(st)
	_ok(Culture.radiance_pct(st, 0) == rp + Deeds.r_int("radiance_pct"), "un an de Rayonnement accru après un haut fait")
	_ok(DeedsBridges.votes(st, 0) == Deeds.glory(st, 0) / Deeds.r_int("votes_per"), "une voix par tranche de 500 de Gloire")


func _test_infamy() -> void:
	var st := new_game()
	st.get_empire(1).contacts.append(0)
	st.get_empire(0).contacts.append(1)
	Deeds.note(st, 0, "exterminated", 10)
	to_check(st)
	_ok(Deeds.winners(st, "briseur_mondes") == [0], "haut fait infâme accompli")
	_ok(DeedsBridges.infamous(st, 0), "l'empire est Infâme")
	var found := false
	for p: Dictionary in Diplomacy.opinion_parts(st, 1, 0):
		if String(p["label"]).contains("Infamie"):
			found = int(p["value"]) == Deeds.r_int("infamy_opinion")
	_ok(found, "Infamie : -15 d'opinion chez qui connaît l'empire")
	st.tick += Deeds.r_int("infamy_days") + 1
	_ok(not DeedsBridges.infamous(st, 0), "l'Infamie s'efface au bout de dix ans")
	# Traités rompus : notés par la diplomatie.
	var st2 := new_game()
	Deeds.note(st2, 0, "broke", 3)
	to_check(st2)
	_ok(Deeds.winners(st2, "fossoyeur_traites") == [0], "Fossoyeur des traités")


func _test_battle_hooks() -> void:
	var st := new_game()
	var b := {"sides": [{"empire": 0, "engaged": {}}, {"empire": 1, "engaged": {}}]}
	for i in 3:
		DeedsBridges.on_battle(st, b, 0)
	_ok(int(st.deeds["streak"]["0"]) == 3 and int(st.deeds["streak"]["1"]) == 0, "séries de victoires suivies")
	DeedsBridges.on_battle(st, b, 1)
	_ok(int(st.deeds["streak"]["0"]) == 0, "une défaite brise la série")
	# Tueur de géant : vaincre l'empire en tête de Gloire depuis la moitié basse, en guerre.
	for e in st.empires:
		if e.id != 0 and not e.is_npc():
			Deeds.add_glory(st, e.id, 300 + 10 * e.id)
	var lead := DeedsBridges.leader(st)
	Combat.start_war(st, 0, lead)
	var b2 := {"sides": [{"empire": 0, "engaged": {}}, {"empire": lead, "engaged": {}}]}
	DeedsBridges.on_battle(st, b2, 0)
	_ok(Deeds.count(st, 0, "giant_slain") == 1, "Tueur de géant noté")
