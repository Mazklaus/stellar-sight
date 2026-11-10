extends RefCounted
## Tests de la diplomatie : statuts, propositions, traités, trêve, alliance qui partage les guerres,
## parjure, opinion (registres, credos, souvenirs), jugement de l'IA, talents des peuples (héritier,
## arbitrage, croisade, Essaim sans traité), sauvegarde et déterminisme. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Diplomatie…")
	_test_statuses_and_proposals()
	_test_truce_and_alliance()
	_test_alliance_shares_wars()
	_test_oathbreaker()
	_test_opinion()
	_test_swarm()
	_test_ai_judgement()
	_test_heir()
	_test_mediation()
	_test_crusade()
	_test_war_score()
	_test_save_roundtrip()
	_test_ai_diplomacy_game()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


## Partie sans IA : les rivaux sont des joueurs inertes, ils reçoivent donc les propositions.
func _state(faction := "ossarane", options := {"ai_level": ""}) -> GameState:
	var st := GameState.create(4242, 150, 1800.0, faction, options)
	# Les alliances demandent les Chancelleries : on les accorde à tous pour tester les traités.
	for e in st.empires:
		Research.grant(st, e.id, ["chancelleries"])
	return st


func _meet(st: GameState, a: int, b: int) -> void:
	if not st.get_empire(a).contacts.has(b):
		st.get_empire(a).contacts.append(b)
		st.get_empire(a).contacts.sort()
	if not st.get_empire(b).contacts.has(a):
		st.get_empire(b).contacts.append(a)
		st.get_empire(b).contacts.sort()


func _apply(st: GameState, cmd: Dictionary) -> bool:
	var why := SimCommands.validate(st, cmd)
	if why != "":
		return false
	SimCommands.apply(st, cmd)
	return true


func _sign_peace(st: GameState, a: int, b: int) -> void:
	_apply(st, SimCommands.propose_treaty(a, b, Diplomacy.PEACE))
	var p := Diplomacy.pending(st, a, b, Diplomacy.PEACE)
	if not p.is_empty():
		_apply(st, SimCommands.answer_proposal(b, int(p["id"]), true))


func _test_statuses_and_proposals() -> void:
	var st := _state()
	_ok(Diplomacy.status(st, 0, 1) == "none", "statut « aucun contact » avant la rencontre")
	_ok(SimCommands.validate(st, SimCommands.propose_treaty(0, 1, "peace")) != "", "pas de traité sans contact")
	_meet(st, 0, 1)
	_ok(Diplomacy.status(st, 0, 1) == "cold", "la rencontre ouvre la guerre froide (Endless Space 2)")
	_ok(SimCommands.validate(st, SimCommands.propose_treaty(0, 1, "alliance")) != "", "pas d'alliance sans paix")
	_ok(SimCommands.validate(st, SimCommands.propose_treaty(0, 1, "trade")) != "", "pas de commerce sans paix")
	_ok(SimCommands.validate(st, SimCommands.propose_treaty(0, 1, "bidule")) != "", "traité inconnu refusé")
	_ok(_apply(st, SimCommands.propose_treaty(0, 1, "peace")), "proposition de paix envoyée")
	var p := Diplomacy.pending(st, 0, 1, "peace")
	_ok(not p.is_empty() and Diplomacy.proposals_for(st, 1).size() == 1, "un joueur humain reçoit la proposition")
	_ok(SimCommands.validate(st, SimCommands.propose_treaty(0, 1, "peace")) != "", "pas deux fois la même proposition")
	_ok(SimCommands.validate(st, SimCommands.answer_proposal(0, int(p["id"]), true)) != "", "seul le destinataire répond")
	_ok(_apply(st, SimCommands.answer_proposal(1, int(p["id"]), false)), "refus accepté")
	_ok(Diplomacy.status(st, 0, 1) == "cold" and st.proposals.is_empty(), "un refus laisse la guerre froide")
	_ok(Diplomacy.cooldown_left(st, 0, 1, "peace") > 0, "un refus impose un délai avant de reproposer")
	# Expiration : une proposition sans réponse disparaît après proposal_days.
	var st2 := _state()
	_meet(st2, 0, 2)
	_apply(st2, SimCommands.propose_treaty(0, 2, "maps"))
	_ok(st2.proposals.size() == 1, "proposition d'échange de cartes en attente")
	var sim := Simulation.new(st2)
	sim.advance(Diplomacy.days("proposal_days", 30) + 1)
	_ok(st2.proposals.is_empty(), "une proposition sans réponse expire")


func _test_truce_and_alliance() -> void:
	var st := _state()
	_meet(st, 0, 1)
	_sign_peace(st, 0, 1)
	_ok(Diplomacy.status(st, 0, 1) == "peace", "la paix est signée")
	_ok(Diplomacy.in_truce(st, 0, 1), "une trêve suit la signature")
	_ok(SimCommands.validate(st, SimCommands.declare_war(0, 1)) != "", "pas de guerre pendant la trêve")
	_ok(SimCommands.validate(st, SimCommands.cancel_treaty(0, 1, "peace")) != "", "pas de dénonciation pendant la trêve")
	var before := int(Economy.empire_income(st, 0)["gross"]["influence"])
	_ok(int(Diplomacy.treaty_income(st, 0).get("influence", 0)) == 1, "la paix rapporte de l'influence")
	_ok(SimCommands.validate(st, SimCommands.propose_treaty(0, 1, "alliance")) != "", "l'alliance exige six mois de paix")
	_apply(st, SimCommands.propose_treaty(0, 1, "trade"))
	_apply(st, SimCommands.answer_proposal(1, int(Diplomacy.pending(st, 0, 1, "trade")["id"]), true))
	_ok(Diplomacy.has_trade(st, 0, 1), "accord commercial signé pendant la paix")
	_ok(int(Economy.empire_income(st, 0)["gross"]["influence"]) > before, "les traités comptent dans les revenus")
	Diplomacy._rel_w(st, 0, 1)["since"] = st.tick - 200
	_ok(_apply(st, SimCommands.propose_treaty(1, 0, "alliance")), "alliance proposée après six mois")
	_apply(st, SimCommands.answer_proposal(0, int(Diplomacy.pending(st, 1, 0, "alliance")["id"]), true))
	_ok(Diplomacy.allied(st, 0, 1) and Diplomacy.allies(st, 0) == [1], "alliance signée")
	_ok(SimCommands.validate(st, SimCommands.declare_war(1, 0)) != "", "on ne déclare pas la guerre à un allié")
	st.get_empire(1).explored[77] = true
	var sim := Simulation.new(st)
	sim.advance(30)
	_ok(st.get_empire(0).explored.has(77), "les alliés partagent leurs cartes chaque mois")
	_ok(Diplomacy.trust(st, 0, 1) > 0, "la confiance monte sous traité (Stellaris)")
	_ok(_apply(st, SimCommands.cancel_treaty(0, 1, "alliance")), "on peut quitter une alliance")
	_ok(Diplomacy.status(st, 0, 1) == "cold" and not Diplomacy.has_trade(st, 0, 1), "quitter l'alliance ramène à la guerre froide")
	_ok(Diplomacy.opinion_parts(st, 1, 0).any(func(p: Dictionary) -> bool: return String(p["label"]).contains("quitté")), "l'ancien allié s'en souvient")


func _test_alliance_shares_wars() -> void:
	var st := _state()
	_meet(st, 0, 1)
	_meet(st, 0, 2)
	_meet(st, 1, 2)
	_sign_peace(st, 0, 2)
	Diplomacy._rel_w(st, 0, 2)["since"] = st.tick - 200
	Diplomacy._rel_w(st, 0, 2)["truce"] = 0
	_apply(st, SimCommands.propose_treaty(0, 2, "alliance"))
	_apply(st, SimCommands.answer_proposal(2, int(Diplomacy.pending(st, 0, 2, "alliance")["id"]), true))
	_ok(Diplomacy.allied(st, 0, 2), "alliance 0-2")
	_ok(_apply(st, SimCommands.declare_war(1, 0)), "1 attaque 0")
	_ok(Combat.at_war(st, 2, 1), "l'allié de la victime entre en guerre contre l'agresseur")
	_ok(Diplomacy.opinion_parts(st, 0, 1).any(func(p: Dictionary) -> bool: return String(p["label"]).contains("déclaré")), "la victime se souvient de la déclaration")
	_ok(Diplomacy.opinion_parts(st, 0, 2).any(func(p: Dictionary) -> bool: return String(p["label"]).contains("côtés")), "la victime remercie son allié")
	_ok(Diplomacy.common_enemies(st, 0, 2) == [1], "ennemi commun")
	# Un allié lié par la paix à l'agresseur reste en dehors.
	var st2 := _state()
	for pair in [[0, 1], [0, 2], [1, 2], [0, 3], [2, 3]]:
		_meet(st2, pair[0], pair[1])
	_sign_peace(st2, 0, 2)
	Diplomacy._rel_w(st2, 0, 2)["since"] = st2.tick - 200
	_apply(st2, SimCommands.propose_treaty(0, 2, "alliance"))
	_apply(st2, SimCommands.answer_proposal(2, int(Diplomacy.pending(st2, 0, 2, "alliance")["id"]), true))
	_sign_peace(st2, 1, 2)
	_apply(st2, SimCommands.declare_war(1, 0))
	_ok(Combat.at_war(st2, 1, 0) and not Combat.at_war(st2, 2, 1), "un allié en paix avec l'agresseur reste en dehors")


func _test_oathbreaker() -> void:
	var st := _state()
	_meet(st, 0, 1)
	_meet(st, 0, 2)
	_sign_peace(st, 0, 1)
	Diplomacy._rel_w(st, 0, 1)["truce"] = 0
	var op2 := Diplomacy.opinion(st, 2, 0)
	_ok(_apply(st, SimCommands.declare_war(0, 1)), "après la trêve, on peut rompre la paix par une guerre")
	_ok(Diplomacy.status(st, 0, 1) == "war" and not Diplomacy.has_pact(st, 0, 1), "le traité est rompu")
	_ok(Diplomacy.opinion_parts(st, 1, 0).any(func(p: Dictionary) -> bool: return String(p["label"]).contains("rompu")), "la victime retient la trahison")
	_ok(Diplomacy.opinion(st, 2, 0) < op2, "le reste de la galaxie retient le parjure")
	# La dénonciation après la trêve, elle, est permise sans guerre.
	var st2 := _state()
	_meet(st2, 0, 1)
	_sign_peace(st2, 0, 1)
	Diplomacy._rel_w(st2, 0, 1)["truce"] = 0
	_ok(_apply(st2, SimCommands.cancel_treaty(0, 1, "peace")), "dénoncer la paix après la trêve")
	_ok(Diplomacy.status(st2, 0, 1) == "cold", "retour à la guerre froide")


func _test_opinion() -> void:
	var st := _state()
	# 0 Ossarane, 1 Chœur (grimdark, théocratie, foi), 2 Vael (space opera, république, raison), 3 Kh'thari.
	var parts := Diplomacy.opinion_parts(st, 1, 2)
	var reg := 0
	var credo := 0
	for p in parts:
		if String(p["label"]).begins_with("Registres"):
			reg = int(p["value"])
		if String(p["label"]) == "Credos opposés":
			credo = int(p["value"])
	_ok(reg == -15, "grimdark face au space opera héroïque : dissonance -3 (×5)")
	_ok(credo == -10, "la foi face à la raison")
	_ok(Diplomacy.opinion_parts(st, 0, 3).any(func(p: Dictionary) -> bool: return String(p["label"]) == "Horreur biologique"), "une ruche inspire l'horreur")
	_ok(Diplomacy.opinion_parts(st, 2, 0).any(func(p: Dictionary) -> bool: return String(p["label"]).begins_with("Quarante")), "les quarante peuples de Vael aiment tout le monde (un peu)")
	_ok(Diplomacy.opinion_parts(st, 1, 0).any(func(p: Dictionary) -> bool: return String(p["label"]).begins_with("Fanatisme")), "le fanatisme du Chœur pèse sur l'opinion")
	var v := Diplomacy.opinion(st, 1, 2)
	_ok(v >= -100 and v <= 100 and v < 0, "opinion bornée, le Chœur n'aime pas Vael")
	# Les souvenirs s'effacent.
	Diplomacy.remember(st, 1, 2, "declared_war")
	var fresh := Diplomacy.opinion(st, 1, 2)
	_ok(fresh < v, "un souvenir pèse sur l'opinion")
	st.tick += 900
	_ok(Diplomacy.opinion(st, 1, 2) > fresh, "il s'efface avec le temps (griefs de Civilization VI)")
	st.tick += 1000
	Diplomacy.prune_memories(st)
	_ok(st.memories.is_empty(), "les souvenirs effacés sont oubliés")


func _test_swarm() -> void:
	var st := _state()
	_meet(st, 0, 3)
	_ok(Diplomacy.no_treaties(st, 3), "l'Essaim ne signe rien (ruche + survie)")
	_ok(SimCommands.validate(st, SimCommands.propose_treaty(0, 3, "peace")) != "", "aucune proposition à l'Essaim")
	_ok(SimCommands.validate(st, SimCommands.propose_treaty(3, 0, "maps")) != "", "aucune proposition de l'Essaim")
	_ok(int(AiDiplomacy.evaluate(st, 3, 0, "peace")["score"]) < 0, "le jugement de l'Essaim est sans appel")
	_ok(SimCommands.validate(st, SimCommands.bribe_heir(3, 0)) != "", "l'Essaim n'achète personne")
	# Une espèce de l'éditeur : une ruche au credo différent pourrait négocier.
	var f := GameData.faction("khthari").duplicate(true)
	f["species"]["credo"] = "raison"
	_ok(not Diplomacy.has_ability_faction(f, "no_treaties"), "une ruche rationnelle peut négocier (contenu lié aux couches d'espèce)")
	var feo := {"species": {"gouvernement": "feodalite"}}
	_ok(Diplomacy.has_ability_faction(feo, "heir"), "toute féodalité a un héritier")


func _test_ai_judgement() -> void:
	var st := GameState.create(4242, 150, 1800.0, "ossarane", {"ai_level": "normal", "temperament": "normal"})
	_meet(st, 0, 1)
	_meet(st, 0, 2)
	_apply(st, SimCommands.declare_war(0, 2))
	var ev := AiDiplomacy.evaluate(st, 2, 0, "peace")
	_ok(int(ev["score"]) < 0 and not ev["parts"].is_empty(), "une guerre qui commence : l'IA refuse la paix, raisons à l'appui")
	_ok(not _apply(st, SimCommands.propose_treaty(0, 2, "peace")) or Combat.at_war(st, 0, 2), "proposition refusée par l'IA")
	_ok(Combat.at_war(st, 0, 2) and Diplomacy.cooldown_left(st, 0, 2, "peace") > 0, "toujours en guerre, délai avant de reproposer")
	# Longue guerre perdue par l'IA : elle accepte.
	var r := Diplomacy._rel_w(st, 0, 2)
	r["since"] = st.tick - 600
	r["cool"] = {}
	r["score"] = [200, 0]
	var ev2 := AiDiplomacy.evaluate(st, 2, 0, "peace")
	_ok(int(ev2["score"]) >= 0, "une guerre longue et perdue : l'IA veut la paix (%d)" % int(ev2["score"]))
	_ok(_apply(st, SimCommands.propose_treaty(0, 2, "peace")) and Diplomacy.status(st, 0, 2) == "peace", "l'IA signe tout de suite")
	# Tempérament : un belliqueux juge plus sévèrement qu'un pacifique.
	var calm := GameState.create(4242, 150, 1800.0, "ossarane", {"ai_level": "normal", "temperament": "pacifique"})
	var hot := GameState.create(4242, 150, 1800.0, "ossarane", {"ai_level": "normal", "temperament": "belliqueux"})
	for s in [calm, hot]:
		_meet(s, 0, 2)
	_ok(int(AiDiplomacy.evaluate(calm, 2, 0, "peace")["score"]) > int(AiDiplomacy.evaluate(hot, 2, 0, "peace")["score"]), "le tempérament pèse sur le jugement")
	# La Recrue juge à l'humeur du jour, mais la même tout le mois (déterministe).
	var rec := GameState.create(4242, 150, 1800.0, "ossarane", {"ai_level": "recrue"})
	_meet(rec, 0, 2)
	var a := AiDiplomacy.evaluate(rec, 2, 0, "maps")
	_ok(a["parts"].any(func(p: Dictionary) -> bool: return String(p["label"]) == "Humeur du jour") or int(AiDiplomacy._mood(rec, 2, 0, "maps")) == 0, "la Recrue a ses humeurs")
	_ok(int(AiDiplomacy.evaluate(rec, 2, 0, "maps")["score"]) == int(a["score"]), "même jugement le même jour")
	# Le Chœur répugne à signer la paix avec des hérétiques.
	var ch := GameState.create(4242, 150, 1800.0, "vael", {"ai_level": "veteran"})
	_meet(ch, 0, 2)
	_ok(AiDiplomacy.evaluate(ch, 2, 0, "peace")["parts"].any(func(p: Dictionary) -> bool: return String(p["label"]).contains("hérétiques")), "le Chœur ne fait pas la paix avec les hérétiques")


func _test_heir() -> void:
	var st := _state()
	var oss := st.get_empire(0)
	_ok(Diplomacy.has_heir(st, 0) and oss.heir_loyalty == int(Diplomacy.ability("heir")["start"]), "Ossarane a un héritier")
	_ok(not Diplomacy.has_heir(st, 1) and not Diplomacy.has_heir(st, 2), "les autres peuples n'en ont pas")
	_meet(st, 0, 2)
	st.get_empire(2).resources["influence"] = 100
	_ok(_apply(st, SimCommands.bribe_heir(2, 0)), "Vael soudoie l'héritier")
	_ok(oss.heir_loyalty == 70 - int(Diplomacy.ability("heir")["bribe_loss"]) and oss.heir_suitor == 2, "sa loyauté baisse, Vael est son prétendant")
	_ok(int(st.get_empire(2).resources["influence"]) == 70, "la bourse coûte de l'influence")
	_ok(Diplomacy.opinion_parts(st, 0, 2).any(func(p: Dictionary) -> bool: return String(p["label"]).contains("soudoyé")), "Ossarane le sait")
	oss.resources["influence"] = 50
	oss.resources["crystals"] = 10
	_ok(_apply(st, SimCommands.banquet(0)), "banquet des lignées")
	_ok(oss.heir_loyalty == 75, "la loyauté remonte")
	# Trahison : un fief lointain change de mains.
	var cap := st.galaxy.get_planet(oss.capital_planet).system_id
	var far := -1
	var dist := FactionTraits.jumps_from(st.galaxy, cap)
	for s in st.galaxy.systems:
		if st.system_owner(s.id) == -1 and s.planet_ids.size() > 0 and int(dist.get(s.id, 0)) >= 3:
			far = s.id
			break
	var c := Colony.new()
	c.planet_id = st.galaxy.systems[far].planet_ids[0]
	c.owner = 0
	c.kind = Colony.KIND_COLONY
	c.population = 2
	st.add_colony(c)
	_ok(Diplomacy.heir_fief(st, 0) == far, "le fief le plus lointain est désigné")
	oss.heir_loyalty = 1
	oss.dissent = true
	Diplomacy.heir_month(st, 0)
	_ok(st.system_owner(far) == 2, "à 0, l'héritier livre son fief au prétendant")
	_ok(oss.heir_loyalty == int(Diplomacy.ability("heir")["after_betrayal"]) and oss.heir_suitor == -1, "un nouvel héritier prend sa place")
	_ok(not Combat.at_war(st, 0, 2), "la trahison ne déclare pas la guerre")


func _test_mediation() -> void:
	var st := _state("vael")
	# 0 Vael, 1 Ossarane, 2 Chœur, 3 Kh'thari.
	for pair in [[0, 1], [0, 2], [1, 2]]:
		_meet(st, pair[0], pair[1])
	_ok(Diplomacy.has_ability(st, 0, "mediation") and not Diplomacy.has_ability(st, 1, "mediation"), "seule la république arbitre")
	_apply(st, SimCommands.declare_war(1, 2))
	st.get_empire(0).resources["influence"] = 200
	_ok(SimCommands.validate(st, SimCommands.mediate(0, 1, 2)) != "", "trop tôt : la guerre vient de commencer")
	Diplomacy._rel_w(st, 1, 2)["since"] = st.tick - 100
	if Diplomacy.opinion(st, 1, 0) < 0 or Diplomacy.opinion(st, 2, 0) < 0:
		_ok(SimCommands.validate(st, SimCommands.mediate(0, 1, 2)) != "", "il faut être respecté des deux camps")
	for i in 3:
		Diplomacy.remember(st, 1, 0, "peace_signed")
		Diplomacy.remember(st, 2, 0, "ally_joined")
	st.memories.append({"who": 1, "about": 0, "kind": "mediated", "tick": st.tick, "count": 1})
	st.memories.append({"who": 2, "about": 0, "kind": "mediated", "tick": st.tick, "count": 1})
	st.memories.append({"who": 2, "about": 0, "kind": "heir_gift", "tick": st.tick, "count": 1})
	var why := SimCommands.validate(st, SimCommands.mediate(0, 1, 2))
	_ok(why == "", "arbitrage possible (%s)" % why)
	_apply(st, SimCommands.mediate(0, 1, 2))
	_ok(Diplomacy.status(st, 1, 2) == "peace" and Diplomacy.in_truce(st, 1, 2), "les Veilleurs imposent la paix et sa trêve")
	_ok(int(st.get_empire(0).resources["influence"]) == 160, "l'arbitrage coûte de l'influence")
	_ok(SimCommands.validate(st, SimCommands.mediate(0, 1, 2)) != "", "les Veilleurs se reposent ensuite")


func _test_crusade() -> void:
	var st := _state("choeur")
	# 0 Chœur, 1 Ossarane, 2 Vael.
	_meet(st, 0, 2)
	var e := st.get_empire(0)
	e.fervor = 30
	_apply(st, SimCommands.declare_war(0, 2))
	_ok(e.fervor == 30 + int(Diplomacy.ability("crusade")["war_fervor"]), "une guerre contre des hérétiques nourrit la ferveur")
	var st2 := _state("choeur")
	_meet(st2, 0, 2)
	_sign_peace(st2, 0, 2)
	st2.get_empire(0).fervor = 40
	Diplomacy.crusade_month(st2, 0)
	_ok(st2.get_empire(0).fervor == 39, "un traité avec des hérétiques coûte de la ferveur chaque mois")


func _test_war_score() -> void:
	var st := _state()
	_meet(st, 0, 1)
	_apply(st, SimCommands.declare_war(0, 1))
	var target := -1
	for sid in EmpireReport.owned_systems(st, 1):
		target = sid
	Combat.capture_system(st, target, 0)
	_ok(Diplomacy.war_score(st, 0, 1) > 0 and Diplomacy.war_score(st, 1, 0) < 0, "une conquête fait monter le score de guerre")
	_ok(Diplomacy.opinion_parts(st, 1, 0).any(func(p: Dictionary) -> bool: return String(p["label"]).contains("pris")), "le vaincu s'en souvient")


func _test_save_roundtrip() -> void:
	var st := _state()
	_meet(st, 0, 1)
	_meet(st, 0, 2)
	_sign_peace(st, 0, 1)
	_apply(st, SimCommands.propose_treaty(0, 2, "maps"))
	Diplomacy.remember(st, 2, 0, "denounced")
	st.get_empire(0).heir_suitor = 2
	var d := st.to_dict()
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null, "sauvegarde relue (%s)" % GameState.last_error)
	if back == null:
		return
	_ok(back.checksum() == st.checksum(), "même empreinte après sauvegarde : relations, souvenirs, propositions, héritier")
	_ok(Diplomacy.status(back, 0, 1) == "peace" and back.proposals.size() == 1 and back.get_empire(0).heir_suitor == 2, "contenu diplomatique conservé")
	_ok(int(d["version"]) == 9, "format de sauvegarde 9")


## Une vraie partie entre IA : il se signe des traités, et deux parties identiques restent identiques.
func _test_ai_diplomacy_game() -> void:
	var runs: Array[String] = []
	var signed := 0
	var kinds := {}
	for r in 2:
		var st := GameState.create(777, 150, 1800.0, "vael", {"ai_level": "veteran", "spectator": true})
		var sim := Simulation.new(st)
		sim.advance(1200)
		runs.append(st.checksum())
		if r == 0:
			for k in st.relations:
				var rel: Dictionary = st.relations[k]
				if String(rel["pact"]) != "" or int(rel["trade"]) != 0:
					signed += 1
					kinds[String(rel["pact"])] = true
			print("  partie IA 1200 jours : %d relations sous traité %s, %d souvenirs" % [signed, str(kinds.keys()), st.memories.size()])
	_ok(runs[0] == runs[1], "diplomatie des IA déterministe")
	_ok(signed > 0, "les IA signent des traités entre elles")
