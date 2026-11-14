extends RefCounted
## Tests du pilier fédérations et vassaux, lot 2 (Koinon) : fondation, adhésion, synode et ses votes,
## lois et rangs, Stratège élu (règle achéenne), Hégémonie et sécession, défense mutuelle, cohésion,
## impôt et trésor, consigne à l'Amphictyonie, bonus des formes, délai de grâce des victoires, IA,
## sauvegarde 51. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Koinon…")
	_test_catalogue()
	_test_found()
	_test_admit()
	_test_laws()
	_test_exclude()
	_test_wars()
	_test_strategos()
	_test_leave()
	_test_monthly()
	_test_consigne()
	_test_bonuses()
	_test_victory()
	_test_vassal_links()
	_test_ai()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 7, opts := {}) -> GameState:
	var o := {"ai_level": "", "koinon": "actif", "vassals": "actifs"}
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


## Alliance ancienne entre a et b, et estime réciproque.
func _ally(st: GameState, a: int, b: int) -> void:
	if Combat.at_war(st, a, b):
		Diplomacy.sign_treaty(st, a, b, Diplomacy.PEACE)
	Diplomacy.sign_treaty(st, a, b, Diplomacy.ALLIANCE)
	Diplomacy._rel_w(st, a, b)["since"] = st.tick - int(Koinon.data()["found"]["alliance_days"])
	Diplomacy._rel_w(st, a, b)["truce"] = 0
	Diplomacy._rel_w(st, a, b)["trust"] = 100


## Ligue de deux membres (a fonde avec b), forme fid.
func _league(st: GameState, a: int, b: int, fid := "marchande") -> int:
	_ally(st, a, b)
	return Koinon.found(st, a, b, fid)


## Ces empires votent à la main (les IA votent sinon dès le dépôt).
func _humans(st: GameState, ids: Array) -> void:
	for i in ids:
		st.get_empire(int(i)).ai_level = ""


## Tous les membres votent v comme demandé, puis le vote est tranché.
func _force(st: GameState, lid: int, kind: String, yes: bool) -> void:
	for v in (Koinon.league(st, lid)["votes"] as Array).duplicate():
		if String(v["kind"]) != kind:
			continue
		(v["yes"] as Array).clear()
		(v["no"] as Array).clear()
		for m in Koinon.members_of(st, lid):
			if kind == "exclude" and m == int(v["x"]):
				continue
			(v["yes" if yes else "no"] as Array).append(m)
		Koinon._try_close(st, lid, v, true)


func _test_catalogue() -> void:
	_ok(Koinon.form_defs().size() >= 5, "Koinon : au moins cinq formes en données (catalogue ouvert)")
	var ok := true
	for f in Koinon.form_defs():
		if (f.get("ranks", []) as Array).size() != 3:
			ok = false
	_ok(ok, "Koinon : chaque forme a trois rangs")
	_ok(Koinon.law_defs().size() >= 3 and not Koinon.law_def("trade").is_empty(), "Koinon : lois en données (commerce, impôt, centralisation)")
	var st := GameState.create(7, 150, 1800.0, "vael", {"ai_level": ""})
	_ok(not st.koinon_on, "Koinon : inactif par défaut")


func _test_found() -> void:
	var st := _new()
	var ms := _majors(st)
	var a := ms[1]
	var b := ms[2]
	_ok(Koinon.check_found(st, a, b, "marchande") != "", "Fondation : il faut une alliance")
	Diplomacy.sign_treaty(st, a, b, Diplomacy.ALLIANCE)
	Diplomacy._rel_w(st, a, b)["trust"] = 100
	_ok(Koinon.check_found(st, a, b, "marchande").contains("ans d'alliance"), "Fondation : il faut deux ans d'alliance")
	Diplomacy._rel_w(st, a, b)["since"] = st.tick - 720
	_ok(Koinon.check_found(st, a, b, "marchande") == "", "Fondation : alliance ancienne, c'est possible (%s)" % Koinon.check_found(st, a, b, "marchande"))
	_ok(Koinon.check_found(st, a, b, "inconnue") != "", "Fondation : forme inconnue refusée")
	var inf := int(st.get_empire(a).resources["influence"])
	SimCommands.apply(st, SimCommands.koi_act(a, "found", b, "marchande"))
	var lid := Koinon.league_of(st, a)
	_ok(lid >= 0 and Koinon.league_of(st, b) == lid, "Fondation : les deux fondateurs sont membres")
	_ok(int(st.get_empire(a).resources["influence"]) == inf - 100, "Fondation : 100 d'influence payés")
	_ok(Koinon.strategos(st, lid) == a and Koinon.rank(st, lid) == 1, "Fondation : le fondateur est Stratège, rang I")
	_ok(Koinon.check_found(st, a, ms[3], "marchande") != "", "Fondation : un membre ne fonde pas une seconde ligue")
	# Un joueur reçoit la proposition.
	var st2 := _new()
	var c := _majors(st2)[1]
	_ally(st2, c, 0)
	SimCommands.apply(st2, SimCommands.koi_act(c, "found", 0, "savante"))
	_ok(Koinon.league_of(st2, c) < 0 and not Diplomacy.pending(st2, c, 0, "kfound").is_empty(), "Fondation : le joueur reçoit l'offre")
	var pid := int(Diplomacy.pending(st2, c, 0, "kfound")["id"])
	_ok(Diplomacy.check_answer(st2, 0, pid, true) == "", "Fondation : le joueur peut accepter")
	Diplomacy.answer(st2, pid, true)
	_ok(Koinon.same_league(st2, c, 0), "Fondation : acceptée, la ligue naît")


func _test_admit() -> void:
	var st := _new()
	var ms := _majors(st)
	var lid := _league(st, 0, ms[1])
	_humans(st, [ms[1]])
	var c := ms[2]
	_ok(Koinon.check_propose(st, c, "admit", 0, "member") == "", "Adhésion : on peut demander à entrer (%s)" % Koinon.check_propose(st, c, "admit", 0, "member"))
	SimCommands.apply(st, SimCommands.koi_act(c, "join", 0, "member"))
	_ok(Koinon.pending_kind(st, lid, "admit", c, "member") or Koinon.league_of(st, c) == lid, "Adhésion : la demande passe au synode")
	_force(st, lid, "admit", true)
	_ok(Koinon.is_member(st, c), "Adhésion : admis par le synode")
	_ok(Koinon.cohesion(st, lid) == int(Koinon.data()["cohesion"]["start"]) + int(Koinon.data()["cohesion"]["join"]), "Adhésion : la cohésion baisse à chaque entrée")
	var d := ms[3]
	SimCommands.apply(st, SimCommands.koi_act(d, "join", 0, "assoc"))
	_force(st, lid, "admit", true)
	_ok(Koinon.is_assoc(st, d) and not Koinon.is_member(st, d), "Adhésion : associé, sans voix")
	_ok(Koinon.check_propose(st, d, "law", 1, "trade") != "", "Associé : il ne propose rien")
	# Un refus impose un délai.
	var st2 := _new()
	var m2 := _majors(st2)
	var l2 := _league(st2, 0, m2[1])
	_humans(st2, [m2[1]])
	SimCommands.apply(st2, SimCommands.koi_act(m2[2], "join", 0, "member"))
	_force(st2, l2, "admit", false)
	_ok(Koinon.league_of(st2, m2[2]) < 0 and Koinon.check_propose(st2, m2[2], "admit", 0, "member").contains("rejeté"), "Adhésion : refusée, il faut attendre avant de redemander")


func _test_laws() -> void:
	var st := _new()
	var ms := _majors(st)
	var lid := _league(st, 0, ms[1])
	_humans(st, [ms[1]])
	_ok(Koinon.check_propose(st, 0, "law", 2, "trade") != "", "Lois : un cran à la fois")
	_ok(Koinon.check_propose(st, 0, "law", 1, "central") != "", "Lois : l'Union exige le rang II")
	SimCommands.apply(st, SimCommands.koi_act(0, "propose", 1, "law:trade"))
	_force(st, lid, "law", true)
	_ok(Koinon.law_step(st, lid, "trade") == 1, "Lois : routes privilégiées adoptées")
	_ok(Trade.tier(st, 0, ms[1]) >= 2, "Lois : entre membres, le commerce vaut un accord commercial")
	Koinon.league(st, lid)["xp"] = 120
	_ok(Koinon.rank(st, lid) == 2 and Koinon.check_propose(st, 0, "law", 1, "central") == "", "Rangs : 120 d'expérience, rang II, l'Union devient possible")
	SimCommands.apply(st, SimCommands.koi_act(0, "propose", 1, "law:tax"))
	_force(st, lid, "law", true)
	_ok(Koinon.law_step(st, lid, "tax") == 1, "Lois : impôt fédéral à 5 %")


func _test_exclude() -> void:
	var st := _new()
	var ms := _majors(st)
	var lid := _league(st, 0, ms[1])
	Koinon.league(st, lid)["members"].append(ms[2])
	Koinon.league(st, lid)["joined"][str(ms[2])] = st.tick
	_humans(st, [ms[1], ms[2]])
	_ok(Koinon.check_vote(st, ms[2], 999, "yes") != "", "Synode : vote inconnu refusé")
	SimCommands.apply(st, SimCommands.koi_act(0, "propose", ms[2], "exclude"))
	var v: Dictionary = Koinon.league(st, lid)["votes"][0] if not (Koinon.league(st, lid)["votes"] as Array).is_empty() else {}
	_ok(not v.is_empty() and Koinon.check_vote(st, ms[2], int(v["id"]), "no") != "", "Exclusion : on ne vote pas la sienne")
	_force(st, lid, "exclude", true)
	_ok(Koinon.league_of(st, ms[2]) < 0 and Koinon.league_of(st, 0) == lid, "Exclusion : adoptée aux deux tiers")


func _test_wars() -> void:
	var st := _new()
	var ms := _majors(st)
	var lid := _league(st, ms[1], ms[2])
	_ok(Diplomacy.check_war(st, ms[1], ms[2]) != "", "Guerre : pas entre membres")
	var foe := ms[3]
	if Combat.at_war(st, foe, ms[1]):
		Diplomacy.sign_treaty(st, foe, ms[1], Diplomacy.PEACE)
	if Combat.at_war(st, foe, ms[2]):
		Diplomacy.sign_treaty(st, foe, ms[2], Diplomacy.PEACE)
	for x in [ms[1], ms[2]]:
		Diplomacy._rel_w(st, foe, x)["truce"] = 0
		Diplomacy._rel_w(st, foe, x)["pact"] = Diplomacy.COLD
	Combat.start_war(st, foe, ms[1])
	_ok(Combat.at_war(st, ms[2], foe), "Défense : le Koinon défend un membre attaqué")
	# Guerre commune votée.
	var st2 := _new()
	var m2 := _majors(st2)
	var l2 := _league(st2, 0, m2[1])
	_humans(st2, [m2[1]])
	var t := m2[2]
	for x in [0, m2[1]]:
		if Combat.at_war(st2, x, t):
			Diplomacy.sign_treaty(st2, x, t, Diplomacy.PEACE)
		Diplomacy._rel_w(st2, x, t)["truce"] = 0
		Diplomacy._rel_w(st2, x, t)["pact"] = Diplomacy.COLD
	SimCommands.apply(st2, SimCommands.koi_act(0, "propose", t, "war"))
	_force(st2, l2, "war", true)
	_ok(Combat.at_war(st2, 0, t) and Combat.at_war(st2, m2[1], t), "Guerre commune : ceux qui votent pour entrent en guerre")
	# Victoire commune : la cohésion monte.
	var coh := Koinon.cohesion(st2, l2)
	Diplomacy.add_war_score(st2, 0, t, 80)
	Diplomacy.sign_treaty(st2, 0, t, Diplomacy.PEACE)
	_ok(Koinon.cohesion(st2, l2) == coh + int(Koinon.data()["cohesion"]["war_won"]), "Guerre gagnée ensemble : la ligue se soude")
	_ok(lid >= 0, "Défense : ligue toujours là")


func _test_strategos() -> void:
	var st := _new()
	var ms := _majors(st)
	var lid := _league(st, ms[1], ms[2])
	Koinon.league(st, lid)["members"].append(ms[3])
	_ok(not Koinon.candidates(st, lid).has(ms[1]), "Stratège : le sortant n'est pas rééligible (règle achéenne)")
	st.tick = int(Koinon.league(st, lid)["strat_until"])
	Koinon.monthly(st)
	_ok(Koinon.strategos(st, lid) != ms[1] and Koinon.members_of(st, lid).has(Koinon.strategos(st, lid)), "Stratège : élu par le synode à la fin du mandat")
	# Hégémonie : le plus puissant, à vie ; voix pesées à la population.
	var st2 := _new()
	var m2 := _majors(st2)
	var l2 := _league(st2, m2[1], m2[2], "hegemonie")
	_ok(Koinon.strategos(st2, l2) == Koinon._strongest(st2, l2), "Hégémonie : le plus puissant préside")
	_ok(Koinon.weight(st2, l2, m2[1]) >= 1 and Koinon.weight(st2, l2, m2[1]) == maxi(1, int(EmpireReport.totals(st2, m2[1])["population"])), "Hégémonie : voix pesées à la population")


func _test_leave() -> void:
	var st := _new()
	var ms := _majors(st)
	var lid := _league(st, 0, ms[1])
	Koinon.league(st, lid)["members"].append(ms[2])
	SimCommands.apply(st, SimCommands.koi_act(ms[2], "leave"))
	_ok(Koinon.league_of(st, ms[2]) < 0, "Sortie : libre hors Hégémonie")
	_ok(Diplomacy.in_truce(st, 0, ms[2]), "Sortie : trêve avec les anciens membres")
	SimCommands.apply(st, SimCommands.koi_act(ms[1], "leave"))
	_ok(Koinon.league(st, lid).is_empty(), "Sortie : à un seul membre, la ligue se dissout")
	# Hégémonie : un faible qui part sans accord déclenche la sécession.
	var st2 := _new()
	var m2 := _majors(st2)
	var l2 := _league(st2, m2[1], m2[2], "hegemonie")
	Koinon.league(st2, l2)["members"].append(m2[3])
	var strat := Koinon.strategos(st2, l2)
	var weak := m2[3] if strat != m2[3] else m2[2]
	Koinon.league(st2, l2)["coh"] = 50
	var leaving_pow := Vassals.power(st2, weak) * 2 >= Vassals.power(st2, strat)
	SimCommands.apply(st2, SimCommands.koi_act(weak, "leave"))
	_ok(Koinon.league_of(st2, weak) < 0, "Hégémonie : le partant quitte la ligue, de gré ou par la guerre")
	_ok(leaving_pow or Combat.at_war(st2, weak, strat), "Hégémonie : sans l'accord du Stratège, c'est la sécession")


func _test_monthly() -> void:
	var st := _new()
	var ms := _majors(st)
	var lid := _league(st, ms[1], ms[2])
	var coh := Koinon.cohesion(st, lid)
	var trend := Koinon.cohesion_trend(st, lid)
	Koinon.monthly(st)
	_ok(Koinon.cohesion(st, lid) == clampi(coh + trend, -100, 100), "Cohésion : tendance mensuelle appliquée")
	_ok(int(Koinon.league(st, lid)["xp"]) > 0, "Expérience : la ligue en gagne quand la cohésion est positive")
	Koinon.league(st, lid)["laws"]["tax"] = 1
	var tre := int(Koinon.league(st, lid)["treasury"])
	var due := 0
	for m in [ms[1], ms[2]]:
		@warning_ignore("integer_division")
		due += mini(maxi(0, int(Economy.empire_income(st, m)["net"].get("energy", 0))) * 5 / 100, int(st.get_empire(m).resources["energy"]))
	Koinon.monthly(st)
	_ok(int(Koinon.league(st, lid)["treasury"]) == tre + due, "Impôt fédéral : 5 %% du revenu net va au trésor (%d)" % due)
	Koinon.league(st, lid)["treasury"] = 300
	var strat := Koinon.strategos(st, lid)
	var other := ms[2] if strat == ms[1] else ms[1]
	_ok(Koinon.check_grant(st, other, strat, 100) != "", "Trésor : seul le Stratège en dispose")
	var en := int(st.get_empire(other).resources["energy"])
	SimCommands.apply(st, SimCommands.koi_act(strat, "grant", other, "", 200))
	_ok(int(st.get_empire(other).resources["energy"]) == en + 200 and int(Koinon.league(st, lid)["treasury"]) == 100, "Trésor : le Stratège secourt un membre")
	Koinon.league(st, lid)["coh"] = -40
	var xp := int(Koinon.league(st, lid)["xp"])
	Koinon.monthly(st)
	_ok(int(Koinon.league(st, lid)["xp"]) < xp or xp == 0, "Expérience : une ligue désunie en perd")


func _test_consigne() -> void:
	var st := _new()
	var ms := _majors(st)
	var lid := _league(st, ms[1], ms[2])
	Koinon.league(st, lid)["consigne"] = 1
	var coh := Koinon.cohesion(st, lid)
	Koinon.on_amph_close(st, {str(ms[1]): 1, str(ms[2]): -1})
	_ok(Koinon.cohesion(st, lid) == coh + int(Koinon.data()["cohesion"]["consigne_kept"]) + int(Koinon.data()["cohesion"]["consigne_broken"]), "Consigne : suivie, elle soude ; trahie, elle abîme")
	_ok(Koinon.consigne(st, ms[1]) == 0, "Consigne : effacée après la séance")
	_ok(Koinon.check_consigne(st, ms[1], 1) != "", "Consigne : seulement pendant une séance de l'Amphictyonie")


func _test_bonuses() -> void:
	var st := _new()
	var ms := _majors(st)
	var lid := _league(st, ms[1], ms[2], "savante")
	_ok(Koinon.knowledge_pct(st, ms[1]) == 5, "Ligue savante : +5 % de Savoir au rang I")
	Koinon.league(st, lid)["xp"] = 400
	_ok(Koinon.knowledge_pct(st, ms[1]) == 15, "Ligue savante : +15 % au rang III")
	var st2 := _new()
	var m2 := _majors(st2)
	var l2 := _league(st2, m2[1], m2[2], "martiale")
	_ok(Combat.weapon_bonus(st2, m2[1], "beam") > Combat.weapon_bonus(st2, m2[3], "beam") or Koinon.weapon_pct(st2, m2[1]) == 5, "Ligue martiale : les armes frappent plus fort")
	_ok(Koinon.opinion_bonus(st2, m2[1], m2[2]) == 0 and l2 >= 0, "Ligue martiale : pas de bonus d'opinion")
	var st3 := _new()
	var m3 := _majors(st3)
	var l3 := _league(st3, m3[1], m3[2], "marchande")
	Koinon.league(st3, l3)["laws"]["central"] = 1
	_ok(Koinon.opinion_bonus(st3, m3[1], m3[2]) == 5, "Union : +5 d'opinion entre membres")
	_ok(Koinon.route_pct(st3, m3[1], m3[2]) == 10 and Koinon.route_pct(st3, m3[1], m3[3]) == 0, "Ligue marchande : routes entre membres +10 %")


func _test_victory() -> void:
	var st := _new()
	var ms := _majors(st)
	var lid := _league(st, ms[1], ms[2])
	var c := ms[3]
	Koinon.league(st, lid)["members"].append(c)
	Koinon.league(st, lid)["joined"][str(c)] = st.tick
	_ok(not Diplomacy.allied(st, ms[1], c) and not Victory.bloc(st, ms[1]).has(c), "Victoire : délai de grâce, un membre tout neuf ne compte pas")
	for m in Koinon.members_of(st, lid):
		Koinon.league(st, lid)["joined"][str(m)] = st.tick - int(Koinon.data()["grace_days"])
	_ok(Victory.bloc(st, ms[1]).has(c), "Victoire : après cinq ans, les membres avancent ensemble")


func _test_vassal_links() -> void:
	var st := _new()
	var ms := _majors(st)
	var lid := _league(st, ms[1], ms[2])
	Koinon.league(st, lid)["members"].append(ms[3])
	Vassals.bind(st, ms[1], ms[3], "vassal", Vassals.preset_clauses("vassal"), 300)
	Koinon.monthly(st)
	_ok(Koinon.league_of(st, ms[3]) < 0, "Sujets : un membre devenu sujet quitte la ligue")
	_ok(Koinon.check_found(st, ms[3], ms[4] if ms.size() > 4 else 0, "marchande") != "", "Sujets : un sujet ne fonde pas de Koinon")
	_ok(Trade.tier(st, ms[1], ms[3]) >= 1, "Sujets : le lien vaut au moins un accord commercial")
	# Amphictyonie : vote lié et voix réduites.
	_ok(Vassals.voix_pct(st, ms[3]) == -50, "Amphictyonie : un sujet a moitié moins de voix")
	_ok(Vassals.bound_vote(st, ms[3], {str(ms[1]): -1, str(ms[3]): 1}) == -1, "Amphictyonie : un sujet au vote lié vote comme son suzerain")
	Vassals.link(st, ms[3])["cl"]["dip"] = "libre"
	_ok(Vassals.bound_vote(st, ms[3], {str(ms[1]): -1, str(ms[3]): 1}) == 1, "Amphictyonie : un sujet libre vote comme il veut")
	_ok(not Amphictyony.family_def("suzerains").is_empty() and Amphictyony.family_available(st, "suzerains"), "Amphictyonie : famille « Suzerains et sujets » quand les vassaux sont actifs")


func _test_ai() -> void:
	var st := _new()
	var ms := _majors(st)
	var a := ms[1]
	var b := ms[2]
	_ally(st, a, b)
	for i in 6:
		Diplomacy.remember(st, a, b, "protected_us")
		Diplomacy.remember(st, b, a, "protected_us")
	AiKoinon.think_state(st, a)
	_ok(Koinon.same_league(st, a, b), "IA : deux alliés anciens qui s'apprécient fondent un Koinon (opinion %d / %d)" % [Diplomacy.opinion(st, a, b), Diplomacy.opinion(st, b, a)])
	var lid := Koinon.league_of(st, a)
	if lid >= 0:
		var c := ms[3]
		for m in [a, b]:
			for i in 6:
				Diplomacy.remember(st, c, m, "protected_us")
				Diplomacy.remember(st, m, c, "protected_us")
			if Combat.at_war(st, c, m):
				Diplomacy.sign_treaty(st, c, m, Diplomacy.PEACE)
			Diplomacy._rel_w(st, c, m)["trust"] = 100
		AiKoinon.think_state(st, c)
		_ok(Koinon.league_of(st, c) == lid, "IA : une IA qui aime les membres demande à entrer, et le synode l'admet (%d, %d / %d, %d ; %s)" % [
				Diplomacy.opinion(st, c, a), Diplomacy.opinion(st, c, b), Diplomacy.opinion(st, a, c), Diplomacy.opinion(st, b, c), Koinon.check_propose(st, c, "admit", a, "member")])
	var v := {"id": 1, "kind": "law", "x": 1, "s": "trade"}
	_ok(AiKoinon.vote_yes(st, a, lid, v) == (Koinon.cohesion(st, lid) >= int(AiKoinon.cfg()["law_cohesion"]) - 10), "IA : vote les lois selon la cohésion")


func _test_save() -> void:
	var st := _new()
	var ms := _majors(st)
	var lid := _league(st, ms[1], ms[2], "savante")
	Koinon.league(st, lid)["treasury"] = 77
	Koinon.league(st, lid)["laws"]["trade"] = 1
	var d: Dictionary = JSON.parse_string(JSON.stringify(st.to_snapshot()))
	_ok(int(d["version"]) == 51, "Sauvegarde : version 51")
	var back := GameState.from_dict(d)
	_ok(back.koinon_on and Koinon.same_league(back, ms[1], ms[2]) and int(Koinon.league(back, lid)["treasury"]) == 77, "Sauvegarde : ligue, membres et trésor gardés")
	_ok(Koinon.law_step(back, lid, "trade") == 1 and String(Koinon.league(back, lid)["form"]) == "savante", "Sauvegarde : lois et forme gardées")
	_ok(back.checksum() == st.checksum(), "Sauvegarde : même empreinte après relecture")
	var off := GameState.create(7, 150, 1800.0, "vael", {"ai_level": ""})
	_ok(not (JSON.parse_string(JSON.stringify(off.to_snapshot())) as Dictionary).has("koinon"), "Sauvegarde : sans l'option, rien n'est écrit")
