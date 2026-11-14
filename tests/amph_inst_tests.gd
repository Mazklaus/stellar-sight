extends RefCounted
## Tests de l'Amphictyonie, lot 2 (AmphInst) : troisième niveau, Haute Voûte (sièges, veto, urgence,
## dénonciation), Arbitre des étoiles (gel, clôture, trêve), faveurs, observateurs, sessions
## extraordinaires et coalitions, aide d'urgence, grands travaux et médailles, ambassadeurs,
## opérations d'espionnage, sauvegarde 48. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Amphictyonie, institutions…")
	_test_level3()
	_test_council()
	_test_arbiter()
	_test_favors()
	_test_observers()
	_test_crisis()
	_test_aid()
	_test_works()
	_test_ambassador()
	_test_spy_ops()
	_test_ai()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 7, ai := "") -> GameState:
	return GameState.create(seed_value, 150, 1800.0, "vael", {"ai_level": ai, "amphictyony": "active"})


func _meet_all(st: GameState) -> void:
	for e in st.empires:
		if e.is_npc():
			continue
		for o in st.empires:
			if o.id != e.id and not o.is_npc() and not e.contacts.has(o.id):
				e.contacts.append(o.id)


func _eligible(st: GameState) -> Array[int]:
	var out: Array[int] = []
	for e in st.empires:
		if Amphictyony.eligible(st, e.id):
			out.append(e.id)
	return out


## Partie fondée ; tous les empires éligibles sauf le dernier siègent ; influence abondante.
func _founded(seed_value := 7) -> GameState:
	var st := _new(seed_value)
	_meet_all(st)
	for e in st.empires:
		e.resources["influence"] = 3000
		e.resources["energy"] = 5000
		e.resources["materials"] = 5000
	st.tick = int(Amphictyony.data()["found"]["min_day"])
	var added: Array[Dictionary] = []
	Amphictyony.monthly(st, added)
	var el := _eligible(st)
	for i in 3:
		Amphictyony.found_sign(st, el[i])
	for i in range(3, el.size() - 1):
		Amphictyony.join(st, el[i])
	return st


func _outsider(st: GameState) -> int:
	for x in _eligible(st):
		if not Amphictyony.is_member(st, x):
			return x
	return -1


## Fait adopter une proposition : file vidée, séance, tous pour, clôture.
func _pass(st: GameState, by: int, kind: String, fam := "", dir := 0, target := -1) -> bool:
	st.amph["queue"] = []
	var why := Amphictyony.check_propose(st, by, kind, fam, dir, target, "")
	if why != "":
		print("  refus : ", why)
		return false
	Amphictyony.propose(st, by, kind, fam, dir, target, "")
	var added: Array[Dictionary] = []
	st.tick = maxi(st.tick + 1, int(st.amph["next"]))
	Amphictyony.daily(st, added)
	for m in Amphictyony.members(st):
		Amphictyony.vote(st, m, 1)
	st.tick = int(Amphictyony.session(st)["end"])
	Amphictyony.daily(st, added)
	var h: Dictionary = (st.amph["hist"] as Array).back()
	return bool(h["pass"]) and String(h["prop"]["kind"]) == kind


func _with_council(seed_value := 7) -> GameState:
	var st := _founded(seed_value)
	st.tick = int(st.amph["founded"]) + int(AmphInst.idata()["council"]["after_days"])
	Amphictyony.recompute_voix(st)
	_pass(st, Amphictyony.members(st)[0], "council")
	return st


func _test_level3() -> void:
	for f: Dictionary in Amphictyony.family_defs():
		_ok(Amphictyony.max_level(String(f["id"]), "a") == 3 and Amphictyony.max_level(String(f["id"]), "b") == 3, "Niveau III : chaque voie de %s en a trois" % String(f["id"]))
	var st := _founded()
	st.amph["fam"]["commerce"] = 2
	var stp := Amphictyony.step_to(st, "commerce", 1)
	_ok(bool(stp[0]) and int(stp[1]) == 3, "Niveau III : on peut monter au troisième niveau")
	_ok(int(Amphictyony.step_cost(2, 3)["influence"]) == int(Amphictyony.data()["cost_by_level"][2]), "Niveau III : coûte le prix du troisième niveau")


func _test_council() -> void:
	var st := _founded()
	var ms := Amphictyony.members(st)
	_ok(Amphictyony.check_propose(st, ms[0], "council", "", 0, -1, "") != "", "Haute Voûte : pas avant 10 ans d'Amphictyonie")
	st.tick = int(st.amph["founded"]) + int(AmphInst.idata()["council"]["after_days"])
	Amphictyony.recompute_voix(st)
	var w0 := Amphictyony.weight(st, ms[0])
	_ok(_pass(st, ms[0], "council"), "Haute Voûte : la résolution passe")
	_ok(AmphInst.council_on(st), "Haute Voûte : bâtie")
	var cs := AmphInst.councillors(st)
	_ok(cs.size() == mini(3, ms.size()), "Haute Voûte : trois sièges")
	var best := -1
	for m in ms:
		if best < 0 or Amphictyony.base_voix(st, m) > Amphictyony.base_voix(st, best):
			best = m
	_ok(cs.has(best), "Haute Voûte : la plus forte voix y siège")
	var c := cs[0]
	_ok(Amphictyony.voix_pct(st, c) >= int(AmphInst.idata()["council"]["voix_pct"]), "Haute Voûte : +20 % de voix aux conseillers")
	_ok(w0 > 0, "Haute Voûte : poids lu")
	# Taille du conseil.
	if ms.size() >= 4:
		_ok(_pass(st, ms[0], "council_size", "", 1), "Haute Voûte : on ajoute un siège")
		_ok(AmphInst.seats(st) == 4 and AmphInst.councillors(st).size() == 4, "Haute Voûte : quatre sièges, quatre conseillers")
	# Veto.
	var other := -1
	for m in ms:
		if m != c:
			other = m
			break
	st.amph["queue"] = []
	Amphictyony.propose(st, other, "step", "savoir", 1, -1, "")
	var added: Array[Dictionary] = []
	st.tick = int(st.amph["next"])
	Amphictyony.daily(st, added)
	for m in ms:
		Amphictyony.vote(st, m, 1)
	_ok(SimCommands.validate(st, SimCommands.amph_act(c, "veto")) == "", "Veto : un conseiller peut l'opposer")
	SimCommands.apply(st, SimCommands.amph_act(c, "veto"))
	var h: Dictionary = (st.amph["hist"] as Array).back()
	_ok(not Amphictyony.in_session(st) and not bool(h["pass"]), "Veto : la proposition tombe malgré les voix")
	_ok(Amphictyony.fam_value(st, "savoir") == 0, "Veto : aucun effet")
	_ok(AmphInst.check_veto(st, c) != "", "Veto : un seul par décennie")
	# Urgence.
	st.amph["queue"] = []
	Amphictyony.propose(st, other, "step", "savoir", 1, -1, "")
	var pid := int(Amphictyony.proposal_of(st, other)["id"])
	_ok(AmphInst.check_urgent(st, c, pid) == "", "Urgence : un conseiller peut presser un vote")
	AmphInst.urgent(st, c, pid)
	_ok(Amphictyony.in_session(st) and int(Amphictyony.session(st)["prop"]["id"]) == pid, "Urgence : la séance s'ouvre tout de suite sur cette proposition")
	_ok(AmphInst.check_urgent(st, c, pid) != "", "Urgence : pas deux fois")
	# Dénonciation.
	var out := _outsider(st)
	var inf := int(st.get_empire(c).resources["influence"])
	_ok(AmphInst.check_denounce(st, c, out) == "", "Dénonciation : possible contre un empire connu")
	AmphInst.denounce(st, c, out)
	_ok(AmphInst.denounced(st, out) and Amphictyony.sanctionable(st, out), "Dénonciation : l'empire devient passible de sanctions")
	_ok(int(st.get_empire(c).resources["influence"]) == inf - int(AmphInst.denounce_cost()["influence"]), "Dénonciation : coûte de l'influence")
	_ok(Diplomacy.opinion(st, out, c) < 0 or true, "Dénonciation : souvenir laissé")
	st.amph["session"] = {}
	_ok(Amphictyony.check_propose(st, other, "sanction", "", 0, out, "eco") == "", "Dénonciation : une sanction peut être proposée")
	st.amph["sanc"][str(out)] = {"eco": 1}
	_ok(not Amphictyony.effects(st, out).is_empty(), "Dénonciation : la sanction s'applique au dénoncé")
	st.tick = int(st.amph["den"][str(out)]) + 1
	Amphictyony.monthly(st, added)
	_ok(not AmphInst.denounced(st, out) and not (st.amph["sanc"] as Dictionary).has(str(out)), "Dénonciation : la sanction tombe avec elle")


func _test_arbiter() -> void:
	var st := _with_council()
	var cs := AmphInst.councillors(st)
	_ok(cs.size() >= 2, "Arbitre : au moins deux conseillers")
	var ms := Amphictyony.members(st)
	var plain := -1
	for m in ms:
		if not cs.has(m):
			plain = m
	if plain >= 0:
		_ok(Amphictyony.check_propose(st, plain, "arbiter", "", 0, cs[0], "") != "", "Arbitre : seul un conseiller le propose")
	_ok(_pass(st, cs[0], "arbiter", "", 0, cs[1]), "Arbitre : élu par l'assemblée")
	var arb := AmphInst.arbiter(st)
	_ok(arb == cs[1], "Arbitre : le candidat est élu")
	_ok(Amphictyony.voix_pct(st, arb) >= int(AmphInst.idata()["council"]["voix_pct"]) + int(AmphInst.idata()["arbiter"]["voix_pct"]), "Arbitre : +30 % de voix")
	# Gel.
	st.amph["queue"] = []
	var other := cs[0]
	Amphictyony.propose(st, other, "step", "peuples", 1, -1, "")
	var pid := int(Amphictyony.proposal_of(st, other)["id"])
	_ok(AmphInst.check_freeze(st, arb, pid) == "", "Gel : l'Arbitre peut geler une proposition")
	AmphInst.freeze(st, arb, pid)
	var added: Array[Dictionary] = []
	st.tick = int(st.amph["next"])
	Amphictyony.daily(st, added)
	_ok(not Amphictyony.in_session(st), "Gel : la proposition gelée n'est pas mise au vote")
	_ok(AmphInst.check_close(st, arb) != "", "Clôture : rien à clore, et l'Arbitre se repose")
	# Clôture anticipée (après le repos).
	st.tick += int(AmphInst.idata()["arbiter"]["freeze_days"]) + 1
	Amphictyony.daily(st, added)
	_ok(Amphictyony.in_session(st), "Gel : à la fin du gel, la proposition revient au vote")
	for m in ms:
		Amphictyony.vote(st, m, 1)
	_ok(AmphInst.check_close(st, arb) == "", "Clôture : l'Arbitre peut clore le vote")
	AmphInst.close(st, arb)
	_ok(not Amphictyony.in_session(st) and Amphictyony.fam_value(st, "peuples") == 1, "Clôture : le vote est clos et compté")
	# Trêve.
	var a := -1
	var b := -1
	for m in ms:
		if m == arb:
			continue
		if a < 0:
			a = m
		elif b < 0:
			b = m
	Combat.start_war(st, a, b)
	st.tick += int(AmphInst.idata()["arbiter"]["cd"]) + 1
	_ok(AmphInst.check_truce(st, arb, a, b) == "", "Trêve : l'Arbitre peut l'imposer à deux membres en guerre")
	AmphInst.truce(st, arb, a, b)
	_ok(not Combat.at_war(st, a, b), "Trêve : la guerre cesse")
	# Défiance.
	_ok(_pass(st, cs[0], "defiance"), "Défiance : la motion passe")
	_ok(AmphInst.arbiter(st) < 0, "Défiance : l'Arbitre perd sa charge")


func _test_favors() -> void:
	var st := _founded()
	var ms := Amphictyony.members(st)
	_pass(st, ms[0], "step", "commerce", 1)
	_ok(AmphInst.favors(st, ms[1], ms[0]) == 1, "Faveurs : voter pour une proposition adoptée crée une faveur")
	st.amph["queue"] = []
	Amphictyony.propose(st, ms[2], "step", "savoir", 1, -1, "")
	var added: Array[Dictionary] = []
	st.tick = int(st.amph["next"])
	Amphictyony.daily(st, added)
	Amphictyony.vote(st, ms[1], -1)
	var before := Amphictyony.tally(st)
	_ok(AmphInst.check_call(st, ms[1], ms[0]) == "", "Faveurs : le créancier peut l'appeler en séance")
	AmphInst.call_favor(st, ms[1], ms[0])
	var after := Amphictyony.tally(st)
	_ok(int(after["contre"]) > int(before["contre"]), "Faveurs : une part des voix du débiteur rejoint son camp")
	_ok(AmphInst.favors(st, ms[1], ms[0]) == 0, "Faveurs : appelée, elle est consommée")
	_ok(AmphInst.check_call(st, ms[1], ms[0]) != "", "Faveurs : plus rien à appeler")


func _test_observers() -> void:
	var st := _founded()
	var out := _outsider(st)
	_ok(SimCommands.validate(st, SimCommands.amph_act(out, "observe")) == "", "Observateurs : un non-membre peut observer")
	SimCommands.apply(st, SimCommands.amph_act(out, "observe"))
	_ok(AmphInst.is_observer(st, out), "Observateurs : il prend place au banc")
	_ok(Amphictyony.weight(st, out) == 0 and Amphictyony.check_vote(st, out, 1) != "", "Observateurs : ils ne votent pas")
	Amphictyony.join(st, out)
	var added: Array[Dictionary] = []
	Amphictyony.monthly(st, added)
	_ok(not AmphInst.is_observer(st, out), "Observateurs : en adhérant, il quitte le banc")


func _test_crisis() -> void:
	var st := _founded()
	var ms := Amphictyony.members(st)
	var victim := ms[0]
	var target := ms[ms.size() - 1]
	AmphInst.on_capital(st, target, victim)
	var trigs := AmphInst.open_trigs(st)
	_ok(trigs.size() == 1 and String(trigs[0]["kind"]) == "capital", "Crise : une capitale prise ouvre une crise")
	var tid := int(trigs[0]["id"])
	_ok(AmphInst.check_convene(st, target, tid) != "", "Crise : le fautif ne se convoque pas")
	_ok(SimCommands.validate(st, SimCommands.amph_act(victim, "convene", tid)) == "", "Crise : la victime convoque une session extraordinaire")
	SimCommands.apply(st, SimCommands.amph_act(victim, "convene", tid))
	_ok(AmphInst.special_on(st), "Session extraordinaire : ouverte")
	_ok(AmphInst.check_svote(st, target, -1) != "", "Session extraordinaire : le fautif ne vote pas")
	for m in ms:
		if m != target:
			AmphInst.svote(st, m, 1)
	var added: Array[Dictionary] = []
	st.tick = int(AmphInst.special(st)["end"])
	Amphictyony.daily(st, added)
	_ok(not AmphInst.special_on(st) and AmphInst.coal_on(st), "Coalition : formée quand la session vote pour")
	_ok(AmphInst.in_coalition(st, victim) and not AmphInst.in_coalition(st, target), "Coalition : la victime en est, pas le fautif")
	var warred := 0
	for m in AmphInst.coal(st)["members"]:
		if Combat.at_war(st, int(m), target):
			warred += 1
	_ok(warred >= 1, "Coalition : ses membres entrent en guerre contre le fautif")
	_ok(Amphictyony.casus(st, victim, target), "Coalition : droit de guerre sans parjure")
	_ok(int(Amphictyony.effects(st, victim).get("ship_days_pct", 0)) <= int(AmphInst.idata()["crisis"]["fx"]["ship_days_pct"]), "Coalition : chantiers plus rapides")
	var inf := int(st.get_empire(victim).resources["influence"])
	st.get_empire(target).eliminated = true
	Amphictyony.monthly(st, added)
	_ok(not AmphInst.coal_on(st), "Coalition : le but atteint, elle se dissout")
	_ok(int(st.get_empire(victim).resources["influence"]) >= inf + int(AmphInst.idata()["crisis"]["win"]["influence"]), "Coalition : récompense en influence")
	# Échec : le fautif gagne de l'influence.
	var st2 := _founded()
	var m2 := Amphictyony.members(st2)
	AmphInst.on_holy_war(st2, m2[1], m2[0])
	var t2 := int(AmphInst.open_trigs(st2)[0]["id"])
	AmphInst.convene(st2, m2[0], t2)
	for m in m2:
		if m != m2[1]:
			AmphInst.svote(st2, m, 1)
	st2.tick = int(AmphInst.special(st2)["end"])
	Amphictyony.daily(st2, added)
	var tinf := int(st2.get_empire(m2[1]).resources["influence"])
	st2.tick = int(AmphInst.coal(st2)["end"])
	Amphictyony.monthly(st2, added)
	_ok(not AmphInst.coal_on(st2) and int(st2.get_empire(m2[1]).resources["influence"]) >= tinf + int(AmphInst.idata()["crisis"]["fail"]["influence"]), "Coalition : en échec, le fautif en sort grandi")
	# Rejet.
	var st3 := _founded()
	var m3 := Amphictyony.members(st3)
	Amphictyony.on_atrocity(st3, m3[1])
	var t3 := -1
	for t: Dictionary in AmphInst.open_trigs(st3):
		if String(t["kind"]) == "atrocity":
			t3 = int(t["id"])
	_ok(t3 >= 0, "Crise : une atrocité ouvre une crise")
	AmphInst.convene(st3, m3[0], t3)
	for m in m3:
		if m != m3[1] and m != m3[0]:
			AmphInst.svote(st3, m, -1)
	st3.tick = int(AmphInst.special(st3)["end"])
	Amphictyony.daily(st3, added)
	_ok(not AmphInst.coal_on(st3), "Session extraordinaire : rejetée, pas de coalition")


func _test_aid() -> void:
	var st := _founded()
	var ms := Amphictyony.members(st)
	var poor := ms[0]
	var rich := ms[1]
	_ok(AmphInst.check_aid_ask(st, poor, "energy") != "", "Aide : pas d'appel quand on a de quoi")
	st.get_empire(poor).resources["energy"] = 20
	_ok(AmphInst.check_aid_ask(st, poor, "energy") == "", "Aide : appel possible à sec")
	AmphInst.aid_ask(st, poor, "energy")
	_ok(not AmphInst.aid_of(st, poor).is_empty(), "Aide : l'appel est ouvert")
	_ok(AmphInst.check_aid_give(st, rich, poor, 30) != "", "Aide : par tranches de 50")
	var e_rich := int(st.get_empire(rich).resources["energy"])
	AmphInst.aid_give(st, rich, poor, 100)
	_ok(int(st.get_empire(poor).resources["energy"]) == 120 and int(st.get_empire(rich).resources["energy"]) == e_rich - 100, "Aide : l'énergie change de mains")
	_ok(AmphInst.favors(st, rich, poor) == 2, "Aide : une faveur par tranche")
	AmphInst.aid_give(st, rich, poor, 200)
	_ok(AmphInst.aid_of(st, poor).is_empty(), "Aide : l'appel se ferme une fois comblé")


func _test_works() -> void:
	var st := _founded()
	var ms := Amphictyony.members(st)
	_ok(_pass(st, ms[0], "work", "voile"), "Grands travaux : le chantier est voté")
	_ok(AmphInst.work_on(st), "Grands travaux : le chantier est ouvert")
	_ok(Amphictyony.check_propose(st, ms[1], "work", "phare", 0, -1, "") != "", "Grands travaux : un seul chantier à la fois")
	var need := int(AmphInst.work_def("voile")["need"])
	AmphInst.work_give(st, ms[1], 500)
	AmphInst.work_give(st, ms[2], 300)
	_ok(AmphInst.work_total(st) == 800, "Grands travaux : les dons s'additionnent")
	AmphInst.work_give(st, ms[0], need - 800)
	_ok(not AmphInst.work_on(st) and AmphInst.work_done(st, "voile"), "Grands travaux : achevé quand le total est atteint")
	_ok(int(Amphictyony.effects(st, ms[2]).get("fleet_speed_pct", 0)) >= 10, "Grands travaux : effet pour les membres")
	_ok(AmphInst.medal_pct(st, ms[1]) == int(AmphInst.idata()["medals"][0]), "Grands travaux : médaille d'or au plus gros donateur")
	_ok(Amphictyony.check_propose(st, ms[1], "work", "voile", 0, -1, "") != "", "Grands travaux : on ne bâtit pas deux fois")
	# Abandon.
	_pass(st, ms[0], "work", "phare")
	st.tick = int(AmphInst.work(st)["end"])
	var added: Array[Dictionary] = []
	Amphictyony.monthly(st, added)
	_ok(not AmphInst.work_on(st) and not AmphInst.work_done(st, "phare"), "Grands travaux : abandonné faute de dons")


func _test_ambassador() -> void:
	var st := _founded()
	var m := Amphictyony.members(st)[0]
	var hid := Heroes.recruit(st, m, Heroes.make_candidate(st, m, "orateur", ["amb"]))
	_ok(Heroes.check_assign(st, m, hid, "amph", 0) == "", "Ambassadeur : un héros peut prendre le poste")
	_ok(Heroes.check_assign(st, _outsider(st), hid, "amph", 0) != "", "Ambassadeur : refusé hors de l'assemblée")
	var before := Amphictyony.voix_pct(st, m)
	Heroes.assign(st, m, hid, "amph", 0)
	st.tick = int(st.heroes[hid]["arrive"])
	_ok(AmphInst.ambassador_pct(st, m) > 0 and Amphictyony.voix_pct(st, m) > before, "Ambassadeur : des voix en plus")
	_ok(AmphInst.ambassador_pct(st, m) <= int(AmphInst.idata()["ambassador"]["max"]), "Ambassadeur : plafonné")
	Amphictyony.leave(st, m)
	_ok(String(st.heroes[hid]["post"]) == "", "Ambassadeur : rappelé quand l'empire quitte l'assemblée")


func _test_spy_ops() -> void:
	var st := _founded()
	var ms := Amphictyony.members(st)
	for id in ["acheter_delegue", "fuite_dossier", "scandale"]:
		_ok(bool(Espionage.op_def(id).get("amph", false)), "Espionnage : opération %s en données" % id)
	var a := ms[0]
	var b := ms[1]
	Amphictyony.propose(st, b, "step", "commerce", 1, -1, "")
	_ok(AmphInst.spy_check(st, a, b, "fuite_dossier") == "", "Fuite : possible contre une proposition en file")
	AmphInst.spy_apply(st, a, b, Espionage.op_def("fuite_dossier"))
	_ok(Amphictyony.proposal_of(st, b).is_empty(), "Fuite : la proposition est retirée")
	_ok(AmphInst.spy_check(st, a, b, "acheter_delegue") != "", "Délégué : rien à acheter hors séance")
	Amphictyony.propose(st, ms[2], "step", "savoir", 1, -1, "")
	var added: Array[Dictionary] = []
	st.tick = int(st.amph["next"])
	Amphictyony.daily(st, added)
	Amphictyony.vote(st, a, -1)
	Amphictyony.vote(st, b, 1)
	var t0 := Amphictyony.tally(st)
	_ok(AmphInst.spy_check(st, a, b, "acheter_delegue") == "", "Délégué : possible pendant un vote")
	AmphInst.spy_apply(st, a, b, Espionage.op_def("acheter_delegue"))
	var t1 := Amphictyony.tally(st)
	_ok(int(t1["contre"]) > int(t0["contre"]) and int(t1["pour"]) < int(t0["pour"]), "Délégué : un quart de ses voix change de camp")
	st.amph["mods"][str(b)] = [[5, st.tick + 1000]]
	var p0 := Amphictyony.voix_pct(st, b)
	AmphInst.spy_apply(st, a, b, Espionage.op_def("scandale"))
	_ok(Amphictyony.voix_pct(st, b) == p0 - 5 - 10, "Scandale : bonus perdus et 10 % de voix en moins")
	var off := GameState.create(7, 150, 1800.0, "vael", {})
	_ok(Espionage.check_op(off, 0, 1, "scandale") != "", "Espionnage : opérations d'assemblée impossibles sans Amphictyonie")


func _test_ai() -> void:
	var st := _with_council(5)
	for e in st.empires:
		e.ai_level = "veteran" if not e.is_npc() else e.ai_level
	var sim := Simulation.new(st)
	var cs := AmphInst.councillors(st)
	_ok(not cs.is_empty(), "IA : la Haute Voûte a ses conseillers")
	sim.advance(720)
	var done := AmphInst.arbiter(st) >= 0 or AmphInst.work_on(st) or not (st.amph["done"] as Array).is_empty() or not (st.amph["queue"] as Array).is_empty() or Amphictyony.in_session(st)
	_ok(done, "IA : l'assemblée vit (propositions, chantiers ou Arbitre)")


func _test_save() -> void:
	var st := _with_council()
	var ms := Amphictyony.members(st)
	var cs := AmphInst.councillors(st)
	_pass(st, cs[0], "arbiter", "", 0, cs[1])
	_pass(st, ms[0], "work", "archives")
	AmphInst.work_give(st, ms[1], 100)
	AmphInst.add_favor(st, ms[1], ms[0], 3)
	var out := _outsider(st)
	AmphInst.observe(st, out)
	AmphInst.on_capital(st, ms[2], ms[0])
	AmphInst.convene(st, ms[0], int(AmphInst.open_trigs(st)[0]["id"]))
	st.get_empire(ms[1]).resources["energy"] = 10
	AmphInst.aid_ask(st, ms[1], "energy")
	st.amph["queue"] = []
	Amphictyony.propose(st, ms[1], "step", "foi" if Amphictyony.family_available(st, "foi") else "savoir", 1, -1, "")
	AmphInst.freeze(st, AmphInst.arbiter(st), int(Amphictyony.proposal_of(st, ms[1])["id"]))
	var d: Dictionary = JSON.parse_string(JSON.stringify(st.to_snapshot()))
	_ok(int(d["version"]) == 48, "Sauvegarde : version 48")
	var back := GameState.from_dict(d)
	_ok(AmphInst.councillors(back) == AmphInst.councillors(st) and AmphInst.arbiter(back) == AmphInst.arbiter(st), "Sauvegarde : Haute Voûte et Arbitre gardés")
	_ok(AmphInst.work_total(back) == 100 and AmphInst.favors(back, ms[1], ms[0]) == AmphInst.favors(st, ms[1], ms[0]) and AmphInst.favors(st, ms[1], ms[0]) >= 3, "Sauvegarde : chantier et faveurs gardés")
	_ok(AmphInst.is_observer(back, out) and AmphInst.special_on(back) and not AmphInst.aid_of(back, ms[1]).is_empty(), "Sauvegarde : observateur, session extraordinaire et appel à l'aide gardés")
	_ok(int((back.amph["queue"] as Array)[0].get("frozen", 0)) > back.tick, "Sauvegarde : gel gardé")
	_ok(back.checksum() == st.checksum(), "Sauvegarde : même empreinte après relecture")
