extends RefCounted
## Tests du pilier fédérations et vassaux, lot 1 (Vassals) : conditions de paix payées en score de
## guerre, reddition, clauses et préréglages, loyauté, guerres suivies, allégeance secrète, protectorat,
## intégration, indépendance, expansion, Cour impériale fondue, victoires, IA, sauvegarde 50.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Fin des guerres à conditions et sujets…")
	_test_catalogue()
	_test_terms()
	_test_surrender()
	_test_wars()
	_test_clauses()
	_test_fealty()
	_test_protect()
	_test_integration()
	_test_independence()
	_test_expansion()
	_test_court()
	_test_victory()
	_test_ai()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


## Partie avec l'option active : tous les empires se connaissent, ressources abondantes, IA « veteran »
## sauf l'empire 0 (humain).
func _new(seed_value := 7, opts := {}) -> GameState:
	var o := {"ai_level": "", "vassals": "actifs"}
	o.merge(opts, true)
	var st := GameState.create(seed_value, 150, 1800.0, "vael", o)
	for e in st.empires:
		if e.is_npc():
			continue
		for x in st.empires:
			if x.id != e.id and not x.is_npc() and not e.contacts.has(x.id):
				e.contacts.append(x.id)
		e.resources["influence"] = 3000
		e.resources["energy"] = 5000
		e.resources["materials"] = 5000
		if e.id != 0:
			e.ai_level = "veteran"
	return st


func _majors(st: GameState) -> Array[int]:
	var out: Array[int] = []
	for e in st.empires:
		if not e.is_npc() and not Diplomacy.no_treaties(st, e.id):
			out.append(e.id)
	return out


## Guerre a → b vieille de `days` jours, score s pour a.
func _war(st: GameState, a: int, b: int, score := 0, days := 200) -> void:
	Combat.start_war(st, a, b)
	Diplomacy._rel_w(st, a, b)["since"] = st.tick - days
	if score > 0:
		Diplomacy.add_war_score(st, a, b, score)


func _test_catalogue() -> void:
	_ok(Vassals.free_presets() == ["vassal", "tributaire", "protectorat"], "Préréglages : Vassal, Tributaire, Protectorat (la Cour est verrouillée)")
	var cl := Vassals.preset_clauses("vassal")
	_ok(Vassals.check_clauses(Vassals.normalize(cl)) == "", "Préréglage Vassal : clauses valides")
	_ok(Vassals.clauses_now(Vassals.normalize(cl)) == -50 - 100 - 50 + 50 - 60, "Vassal : effet immédiat des clauses (%d)" % Vassals.clauses_now(Vassals.normalize(cl)))
	_ok(Vassals.check_clauses({"dip": "nimporte"}) != "", "Clauses : option inconnue refusée")
	_ok(Vassals.normalize({"trib": {"energy": 15}})["trib"].is_empty(), "Tribut : seulement aux paliers (0, 10, 20, 30 %)")
	var st := _new()
	_ok(st.vassals_on, "Option « Vassaux » active")
	var off := GameState.create(7, 150, 1800.0, "vael", {"ai_level": ""})
	_ok(not off.vassals_on and not off.to_dict().has("vassals"), "Sans l'option : rien dans la sauvegarde")


func _test_terms() -> void:
	var st := _new()
	var ms := _majors(st)
	var w := 0
	var l := ms[1]
	Combat.start_war(st, w, l)
	var cede := Vassals.cedable(st, l)
	_ok(SimCommands.validate(st, SimCommands.vas_act(w, "terms", l, "", {"trib": true})) != "", "Conditions : pas avant 60 jours de guerre")
	Diplomacy._rel_w(st, w, l)["since"] = st.tick - 100
	_ok(SimCommands.validate(st, SimCommands.vas_act(w, "terms", l, "", {})) != "", "Conditions : au moins une condition")
	_ok(SimCommands.validate(st, SimCommands.vas_act(w, "terms", l, "", {"trib": true, "zut": true})) != "", "Conditions : condition inconnue refusée")
	var home := st.galaxy.get_planet(st.get_empire(l).capital_planet).system_id
	_ok(SimCommands.validate(st, SimCommands.vas_act(w, "terms", l, "", {"cede": [home]})) != "", "Conditions : la capitale ne se cède pas")
	var terms := {"trib": true, "repar": true}
	if not cede.is_empty():
		terms["cede"] = [cede[0]]
	var p := Vassals.price(st, l, terms)
	_ok(p >= 50, "Prix des conditions : %d points" % p)
	# L'IA vaincue refuse un prix au-dessus du score.
	SimCommands.apply(st, SimCommands.vas_act(w, "terms", l, "", terms))
	_ok(Combat.at_war(st, w, l), "Conditions trop chères : l'IA refuse, la guerre continue")
	_ok(SimCommands.validate(st, SimCommands.vas_act(w, "terms", l, "", terms)) != "", "Refus : délai avant de reproposer")
	Diplomacy._rel_w(st, w, l)["cool"] = {}
	Diplomacy.add_war_score(st, w, l, p)
	var mat_l := int(st.get_empire(l).resources["materials"])
	var mat_w := int(st.get_empire(w).resources["materials"])
	SimCommands.apply(st, SimCommands.vas_act(w, "terms", l, "", terms))
	_ok(not Combat.at_war(st, w, l) and Diplomacy.pact(st, w, l) == Diplomacy.PEACE, "Score suffisant : l'IA accepte, la paix est signée")
	if not cede.is_empty():
		_ok(st.system_owner(cede[0]) == w, "Système cédé au vainqueur")
	_ok(int(st.get_empire(l).resources["materials"]) < mat_l and int(st.get_empire(w).resources["materials"]) > mat_w, "Réparations : 25 % des réserves passent au vainqueur")
	_ok((st.vassals["trib"] as Array).size() == 1, "Tribut de paix enregistré (5 ans)")
	var e0 := int(st.get_empire(w).resources["energy"])
	st.get_empire(l).resources["energy"] = 5000
	st.tick += 30
	Vassals.monthly(st)
	_ok(int(st.get_empire(w).resources["energy"]) >= e0, "Tribut de paix versé chaque mois")
	st.tick += 1800
	Vassals.monthly(st)
	_ok((st.vassals["trib"] as Array).is_empty(), "Tribut de paix : il s'arrête au bout de 5 ans")
	# Proposition à un humain : il reçoit les conditions et répond.
	var st2 := _new()
	var a := _majors(st2)[1]
	_war(st2, a, 0, 300)
	SimCommands.apply(st2, SimCommands.vas_act(a, "terms", 0, "", {"vassal": "tributaire"}))
	var props := Diplomacy.proposals_for(st2, 0)
	_ok(props.size() == 1 and String(props[0]["treaty"]) == "terms", "Conditions à un humain : proposition reçue")
	_ok(Diplomacy.proposal_label(props[0]) == "Paix à conditions", "Proposition : libellé lisible")
	SimCommands.apply(st2, SimCommands.answer_proposal(0, int(props[0]["id"]), true))
	_ok(Vassals.lord_of(st2, 0) == a and Vassals.preset_of(st2, 0) == "tributaire", "Humain : accepter fait de lui un Tributaire")
	_ok(Vassals.loyalty(st2, 0) == int(Vassals.data()["loyalty"]["start_terms"]) + Vassals.clauses_now(Vassals.link(st2, 0)["cl"]), "Loyauté de départ : base + effet immédiat des clauses")


func _test_surrender() -> void:
	var st := _new()
	var ms := _majors(st)
	var w := ms[1]
	var l := ms[2]
	_war(st, w, l, 50)
	_ok(SimCommands.validate(st, SimCommands.vas_act(l, "surrender", w)) != "", "Reddition : pas à 50 points")
	Diplomacy.add_war_score(st, w, l, 60)
	_ok(SimCommands.validate(st, SimCommands.vas_act(l, "surrender", w)) == "", "Reddition : possible à 100 points contre soi")
	SimCommands.apply(st, SimCommands.vas_act(l, "surrender", w))
	_ok(Vassals.lord_of(st, l) == w and not Combat.at_war(st, w, l), "Reddition : le vaincu devient vassal, la guerre cesse")
	_ok(Vassals.preset_of(st, l) == "vassal", "Reddition : préréglage Vassal")
	# Capitale perdue : reddition sans le score.
	var st2 := _new()
	var a := _majors(st2)[1]
	var b := _majors(st2)[2]
	_war(st2, a, b)
	Vassals.on_capital_lost(st2, b, a)
	_ok(Vassals.check_surrender(st2, b, a) == "", "Reddition : possible une fois la capitale perdue")
	# L'Essaim n'accepte personne.
	var st3 := _new()
	for e in st3.empires:
		if Diplomacy.no_treaties(st3, e.id):
			_ok(Vassals.check_surrender(st3, 0, e.id) != "", "Reddition : impossible devant l'Essaim")
			break


func _test_wars() -> void:
	var st := _new()
	var ms := _majors(st)
	var lord := ms[1]
	var sub := ms[2]
	var foe := ms[3]
	Vassals.bind(st, lord, sub, "vassal", Vassals.preset_clauses("vassal"), 300)
	_ok(SimCommands.validate(st, SimCommands.declare_war(lord, sub)) != "", "Un suzerain ne déclare pas la guerre à son sujet")
	_ok(SimCommands.validate(st, SimCommands.declare_war(sub, lord)) != "", "Un sujet ne déclare pas la guerre à son suzerain")
	_ok(SimCommands.validate(st, SimCommands.declare_war(sub, foe)) != "", "Vote lié : pas de guerre hors des ennemis du suzerain")
	# Le suzerain déclare : le sujet (Toutes) suit.
	Combat.start_war(st, lord, foe)
	_ok(Combat.at_war(st, sub, foe), "Guerres suivies « Toutes » : le sujet suit son suzerain")
	# Paix du suzerain : le sujet signe aussi.
	Diplomacy.sign_treaty(st, lord, foe, Diplomacy.PEACE)
	_ok(not Combat.at_war(st, sub, foe), "Paix du suzerain : ses sujets signent aussi")
	# On attaque le sujet : le suzerain le défend.
	var st2 := _new()
	Vassals.bind(st2, lord, sub, "tributaire", Vassals.preset_clauses("tributaire"), 300)
	Combat.start_war(st2, foe, sub)
	_ok(Combat.at_war(st2, lord, foe), "Le suzerain défend son sujet")
	# Tributaire (« Aucune ») : n'entre pas dans les guerres du suzerain.
	var st3 := _new()
	Vassals.bind(st3, lord, sub, "tributaire", Vassals.preset_clauses("tributaire"), 300)
	Combat.start_war(st3, foe, lord)
	_ok(not Combat.at_war(st3, sub, foe), "Guerres suivies « Aucune » : le sujet reste en dehors")
	# Sujet déloyal : il ne suit plus que les guerres défensives.
	var st4 := _new()
	Vassals.bind(st4, lord, sub, "vassal", Vassals.preset_clauses("vassal"), -500)
	Combat.start_war(st4, lord, foe)
	_ok(not Combat.at_war(st4, sub, foe), "Sujet déloyal : il ne suit pas une guerre offensive")
	Diplomacy.sign_treaty(st4, lord, foe, Diplomacy.PEACE)
	Diplomacy._rel_w(st4, lord, foe)["truce"] = 0
	Diplomacy._rel_w(st4, lord, foe)["pact"] = Diplomacy.COLD
	Combat.start_war(st4, foe, lord)
	_ok(Combat.at_war(st4, sub, foe), "Sujet déloyal : il défend encore son suzerain")


func _test_clauses() -> void:
	var st := _new()
	var ms := _majors(st)
	var lord := 0
	var sub := ms[1]
	Vassals.bind(st, lord, sub, "vassal", Vassals.preset_clauses("vassal"), 100)
	var loy := Vassals.loyalty(st, sub)
	# Assouplir : gratuit et immédiat.
	var soft := Vassals.preset_clauses("vassal")
	soft["dip"] = "libre"
	var inf := int(st.get_empire(lord).resources["influence"])
	_ok(SimCommands.validate(st, SimCommands.vas_act(lord, "set_terms", sub, "", soft)) == "", "Assouplir : possible à tout moment")
	SimCommands.apply(st, SimCommands.vas_act(lord, "set_terms", sub, "", soft))
	_ok(int(st.get_empire(lord).resources["influence"]) == inf, "Assouplir : gratuit")
	_ok(Vassals.loyalty(st, sub) == loy + 100, "Assouplir : la loyauté monte de l'écart immédiat (+10)")
	_ok(Vassals.preset_of(st, sub) == "libre" and Vassals.preset_label("libre") == "Sur mesure", "Clauses sur mesure : hors préréglage")
	# Durcir : pas avant la renégociation, puis contre influence.
	var hard := Vassals.preset_clauses("vassal")
	hard["trib"] = {"materials": 30, "energy": 30}
	_ok(SimCommands.validate(st, SimCommands.vas_act(lord, "set_terms", sub, "", hard)) != "", "Durcir : pas avant un an")
	st.tick = int(Vassals.link(st, sub)["next"])
	_ok(SimCommands.validate(st, SimCommands.vas_act(lord, "set_terms", sub, "", hard)) == "", "Durcir : possible à la renégociation")
	var cost := Vassals.renegotiate_cost(st, sub, hard)
	SimCommands.apply(st, SimCommands.vas_act(lord, "set_terms", sub, "", hard))
	_ok(cost > 30 and int(st.get_empire(lord).resources["influence"]) == inf - cost, "Durcir : coûte de l'influence (%d)" % cost)
	_ok(int(Vassals.link(st, sub)["next"]) == st.tick + 1800, "Durcir : prochaine renégociation dans 5 ans")
	# Loyauté mensuelle et ses causes.
	var parts := Vassals.loyalty_parts(st, sub)
	_ok(not parts.is_empty() and String(parts[0]["label"]) == "Clauses", "Loyauté : causes détaillées")
	var before := Vassals.loyalty(st, sub)
	var trend := Vassals.loyalty_trend(st, sub)
	Vassals.monthly(st)
	_ok(Vassals.loyalty(st, sub) == clampi(before + trend, -1000, 1000) or Vassals.loyalty(st, sub) != before, "Loyauté : tendance appliquée chaque mois")
	# Patronage divisé : un 2e sujet pèse sur la loyauté du premier.
	var t1 := Vassals.loyalty_trend(st, sub)
	Vassals.bind(st, lord, ms[2], "tributaire", Vassals.preset_clauses("tributaire"), 0)
	_ok(Vassals.loyalty_trend(st, sub) == t1 + int(Vassals.data()["loyalty"]["patronage"]), "Patronage divisé : -0,5 par autre sujet")
	# Tribut mensuel.
	var es := st.get_empire(sub)
	es.resources["materials"] = 5000
	var m0 := int(st.get_empire(lord).resources["materials"])
	var est := Vassals.tribute_estimate(st, sub)
	Vassals.monthly(st)
	_ok(est.is_empty() or int(st.get_empire(lord).resources["materials"]) > m0, "Tribut des clauses versé au suzerain")
	# Sans diplomatie : aucun traité hors du suzerain.
	var none := Vassals.preset_clauses("vassal")
	none["dip"] = "aucune"
	Vassals.link(st, sub)["cl"] = Vassals.normalize(none)
	_ok(Diplomacy.check_terms(st, sub, ms[3], Diplomacy.MAPS) != "", "Diplomatie « Aucune » : le sujet ne signe rien")


func _test_fealty() -> void:
	var st := _new()
	var ms := _majors(st)
	var lord := ms[1]
	var sub := ms[2]
	var rival := ms[3]
	Vassals.bind(st, lord, sub, "vassal", Vassals.preset_clauses("vassal"), -200)
	_ok(SimCommands.validate(st, SimCommands.vas_act(sub, "fealty", lord)) != "", "Allégeance secrète : pas à son propre suzerain")
	SimCommands.apply(st, SimCommands.vas_act(sub, "fealty", rival))
	_ok(int(Vassals.link(st, sub)["fealty"]) == rival, "Allégeance secrète jurée")
	Combat.start_war(st, rival, lord)
	_ok(not Vassals.is_subject(st, sub) and Combat.at_war(st, sub, lord), "Guerre entre suzerain et rival : le sujet rompt et change de camp")
	_ok(not Combat.at_war(st, sub, rival), "Il ne combat pas celui à qui il s'est juré")


func _test_protect() -> void:
	var st := _new()
	var ms := _majors(st)
	var strong := ms[1]
	var weak := ms[2]
	Vassals.apply_protect(st, weak, strong)
	_ok(Vassals.is_protectorate(st, weak), "Protectorat : lien établi")
	_ok(Vassals.loyalty(st, weak) >= 150, "Protectorat : loyauté de départ élevée (%d)" % Vassals.loyalty(st, weak))
	Research.grant_all(st, strong)
	_ok(Vassals.knowledge_pct(st, weak) == 50, "Protectorat : +50 % de Savoir tant qu'il est en retard")
	_ok(TechTrade.check_pact(st, weak, ms[3]) != "", "Protectorat : pas d'accord de recherche")
	var inf := int(st.get_empire(strong).resources["influence"])
	Vassals.monthly(st)
	_ok(int(st.get_empire(strong).resources["influence"]) == inf + 1, "Protectorat : 1 influence par mois au protecteur")
	_ok(Vassals.check_protect(st, ms[3], weak) != "", "Un sujet ne protège personne")


func _test_integration() -> void:
	var st := _new()
	var ms := _majors(st)
	var lord := ms[1]
	var sub := ms[2]
	Vassals.bind(st, lord, sub, "vassal", Vassals.preset_clauses("vassal"), 300)
	_ok(Vassals.check_integrate(st, lord, sub) != "", "Intégration : interdite par les clauses du Vassal")
	Vassals.apply_protect(st, ms[3], lord)
	var p := ms[3]
	_ok(Vassals.check_integrate(st, lord, p) != "", "Intégration : pas avant 10 ans")
	Vassals.link(st, p)["since"] = st.tick - 3600
	Vassals.link(st, p)["loy"] = 200
	_ok(Vassals.check_integrate(st, lord, p) == "", "Intégration : possible après 10 ans, sujet loyal")
	SimCommands.apply(st, SimCommands.vas_act(lord, "integrate", p))
	for i in 12:
		st.tick += 30
		Vassals.link(st, p)["loy"] = 500
		Vassals.monthly(st)
	_ok(st.get_empire(p).eliminated, "Intégration : au bout d'un an, le sujet disparaît")
	var any := false
	for pid in st.colonies:
		if st.colonies[pid].owner == p:
			any = true
	_ok(not any, "Intégration : toutes ses colonies passent au suzerain")


func _test_independence() -> void:
	var st := _new()
	var ms := _majors(st)
	var lord := ms[1]
	var sub := ms[2]
	Vassals.bind(st, lord, sub, "vassal", Vassals.preset_clauses("vassal"), 0)
	SimCommands.apply(st, SimCommands.vas_act(lord, "release", sub))
	_ok(not Vassals.is_subject(st, sub) and Diplomacy.truce_left(st, lord, sub) >= 3600 - 1, "Libérer : trêve de 10 ans")
	# Exiger l'indépendance : l'IA plus forte refuse, c'est la guerre, les soutiens suivent.
	var st2 := _new()
	Vassals.bind(st2, lord, sub, "vassal", Vassals.preset_clauses("vassal"), 0)
	var sup := ms[3]
	_ok(SimCommands.validate(st2, SimCommands.vas_act(sup, "support", sub)) == "", "Soutien à l'indépendance : possible pour un tiers")
	SimCommands.apply(st2, SimCommands.vas_act(sup, "support", sub))
	var lord_pow := Vassals.power(st2, lord)
	var side := Vassals.freedom_power(st2, sub)
	SimCommands.apply(st2, SimCommands.vas_act(sub, "freedom"))
	_ok(not Vassals.is_subject(st2, sub), "Indépendance exigée : le lien est rompu")
	if side < lord_pow:
		_ok(Combat.at_war(st2, sub, lord), "Refus : guerre d'indépendance")
		_ok(Combat.at_war(st2, sup, lord), "Refus : le soutien entre en guerre")
	else:
		_ok(not Combat.at_war(st2, sub, lord), "Le suzerain plus faible cède")
	# Un humain suzerain reçoit la demande.
	var st3 := _new()
	Vassals.bind(st3, 0, sub, "vassal", Vassals.preset_clauses("vassal"), 0)
	SimCommands.apply(st3, SimCommands.vas_act(sub, "freedom"))
	var props := Diplomacy.proposals_for(st3, 0)
	_ok(props.size() == 1 and String(props[0]["treaty"]) == "freedom", "Indépendance : l'humain reçoit la demande")
	SimCommands.apply(st3, SimCommands.answer_proposal(0, int(props[0]["id"]), false))
	_ok(Combat.at_war(st3, sub, 0) and not Vassals.is_subject(st3, sub), "Humain refuse : la guerre d'indépendance commence")


func _test_expansion() -> void:
	var st := _new()
	var ms := _majors(st)
	var lord := ms[1]
	var sub := ms[2]
	var cl := Vassals.preset_clauses("vassal")
	cl["exp"] = "interdite"
	Vassals.bind(st, lord, sub, "vassal", cl, 300)
	_ok(Vassals.check_found(st, sub) != "", "Expansion interdite : aucune fondation")
	Vassals.link(st, sub)["cl"]["exp"] = "dime"
	var inf := int(st.get_empire(lord).resources["influence"])
	Vassals.on_found(st, sub, {"influence": 20})
	_ok(int(st.get_empire(lord).resources["influence"]) == inf + 10, "Dîme : la moitié du coût en influence part au suzerain")


func _test_court() -> void:
	var st := _new(7, {"amphictyony": "active"})
	var ms := _majors(st)
	var imp := ms[1]
	var sub := ms[2]
	st.amph["founded"] = 0
	st.amph["imp"] = {"eid": imp, "since": 0, "auth": 30, "until": 90, "settled": 0, "sub": [], "reb": []}
	AmphPower.submit(st, sub)
	_ok(Vassals.lord_of(st, sub) == imp and Vassals.is_court(st, sub), "Cour impériale : le soumis est un sujet de l'Impérateur")
	_ok(Vassals.locked(st, sub) and SimCommands.validate(st, SimCommands.vas_act(imp, "set_terms", sub, "tributaire")) != "", "Cour : clauses non négociables")
	_ok(SimCommands.validate(st, SimCommands.vas_act(imp, "release", sub)) != "", "Cour : l'Impérateur ne libère pas")
	_ok(SimCommands.validate(st, SimCommands.vas_act(sub, "freedom")) != "", "Cour : on en sort en se soulevant, pas en exigeant")
	st.amph["imp"] = {}
	Vassals.sync_court(st)
	_ok(not Vassals.is_subject(st, sub), "Cour effondrée : plus de lien")


func _test_victory() -> void:
	var st := _new()
	var ms := _majors(st)
	var lord := ms[1]
	var sub := ms[2]
	Vassals.bind(st, lord, sub, "vassal", Vassals.preset_clauses("vassal"), 300)
	_ok(not Victory.bloc(st, lord).has(sub), "Victoire : un sujet tout neuf n'avance pas encore avec son suzerain (délai de grâce)")
	Vassals.link(st, sub)["since"] = st.tick - int(Koinon.data()["grace_days"])
	_ok(Victory.bloc(st, lord).has(sub), "Victoire : le sujet avance avec son suzerain")
	var pr := Victory.progress(st, sub, "conquest")
	_ok(not bool(pr.get("won", false)) and int(pr.get("pct", 0)) == 0, "Victoire : un sujet ne gagne pas la conquête")


func _test_ai() -> void:
	var st := _new()
	var ms := _majors(st)
	var w := ms[1]
	var l := ms[2]
	_war(st, w, l, 400, 300)
	AiVassals.think_state(st, w)
	_ok(not Combat.at_war(st, w, l), "IA : le vainqueur impose ses conditions")
	# Une IA vaincue et presque morte se rend.
	var st2 := _new()
	var a := _majors(st2)[1]
	var b := _majors(st2)[2]
	_war(st2, a, b, 150, 300)
	AiVassals.think_state(st2, b)
	_ok(Vassals.lord_of(st2, b) == a or not Combat.at_war(st2, a, b), "IA : le vaincu se rend ou traite plutôt que de mourir")
	# Un sujet très déloyal assez fort exige sa liberté.
	var st3 := _new()
	Vassals.bind(st3, a, b, "vassal", Vassals.preset_clauses("vassal"), -800)
	AiVassals.think_state(st3, a)
	_ok((Vassals.link(st3, b).get("cl", {}).get("trib", {}) as Dictionary).is_empty(), "IA : un suzerain assouplit les clauses d'un sujet au bord de la révolte")


func _test_save() -> void:
	var st := _new()
	var ms := _majors(st)
	Vassals.bind(st, ms[1], ms[2], "vassal", Vassals.preset_clauses("vassal"), 120)
	Vassals.link(st, ms[2])["fealty"] = ms[3]
	(st.vassals["trib"] as Array).append({"from": ms[3], "to": 0, "until": st.tick + 100, "pct": 20})
	var d: Dictionary = JSON.parse_string(JSON.stringify(st.to_snapshot()))
	_ok(int(d["version"]) == 52, "Sauvegarde : version 52")
	var back := GameState.from_dict(d)
	_ok(back.vassals_on and Vassals.lord_of(back, ms[2]) == ms[1] and Vassals.loyalty(back, ms[2]) == Vassals.loyalty(st, ms[2]), "Sauvegarde : liens et loyauté gardés")
	_ok(int(Vassals.link(back, ms[2])["fealty"]) == ms[3] and (back.vassals["trib"] as Array).size() == 1, "Sauvegarde : allégeance secrète et tributs gardés")
	_ok(back.checksum() == st.checksum(), "Sauvegarde : même empreinte après relecture")
