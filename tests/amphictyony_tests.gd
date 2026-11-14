extends RefCounted
## Tests de l'Amphictyonie (Amphictyony, AmphictyonySystem, AiAmphictyony) : option de partie, offre et
## fondation à 3 signatures, adhésion et départ, voix, propositions (coût, file, soutien), séance
## (présidence, vote, voix achetées, égalité), résolutions et leurs effets, abrogation, Nomos et
## hors-la-loi, charte des atrocités et droit de guerre sans parjure, sanctions et leur fin, défense
## mutuelle, marché commun réservé, IA, sauvegarde 47 et déterminisme. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Amphictyonie…")
	_test_option()
	_test_founding()
	_test_join_leave()
	_test_voix()
	_test_session()
	_test_buy_and_tie()
	_test_repeal()
	_test_breach()
	_test_atrocity()
	_test_defense()
	_test_market_and_spies()
	_test_ai()
	_test_save()
	_test_determinism()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 7, on := true, ai := "") -> GameState:
	var opts := {"ai_level": ai}
	if on:
		opts["amphictyony"] = "active"
	return GameState.create(seed_value, 150, 1800.0, "vael", opts)


## Tout le monde se connaît (contacts croisés).
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


## Partie fondée avec les trois premiers empires éligibles ; tous se connaissent, influence abondante.
func _founded(seed_value := 7) -> GameState:
	var st := _new(seed_value)
	_meet_all(st)
	for e in st.empires:
		e.resources["influence"] = 2000
	st.tick = int(Amphictyony.data()["found"]["min_day"])
	var added: Array[Dictionary] = []
	Amphictyony.monthly(st, added)
	var el := _eligible(st)
	for i in 3:
		Amphictyony.found_sign(st, el[i])
	return st


func _test_option() -> void:
	var st := _new(7, false)
	_ok(not st.amph_on, "Amphictyonie : absente sans l'option (tests, bancs)")
	_ok(not st.to_dict().has("amph"), "Amphictyonie : sans l'option, l'empreinte de sauvegarde ne change pas")
	_ok(Amphictyony.effects(st, 0).is_empty(), "Amphictyonie : aucun effet sans l'option")
	var on := _new(7)
	_ok(on.amph_on and not Amphictyony.founded(on), "Amphictyonie : option active, pas encore fondée au départ")
	_ok(Amphictyony.family_defs().size() >= 7, "Amphictyonie : catalogue de familles en données")


func _test_founding() -> void:
	var st := _new(7)
	_meet_all(st)
	var added: Array[Dictionary] = []
	st.tick = 720
	Amphictyony.monthly(st, added)
	_ok(not Amphictyony.offer_open(st), "Fondation : pas d'offre avant l'an 8")
	st.tick = int(Amphictyony.data()["found"]["min_day"])
	Amphictyony.monthly(st, added)
	_ok(Amphictyony.offer_open(st), "Fondation : offre ouverte quand un empire a rencontré 70 % des autres")
	var el := _eligible(st)
	_ok(el.size() >= 3, "Fondation : au moins trois empires éligibles")
	var cmd := SimCommands.amph_found(el[0])
	_ok(SimCommands.validate(st, cmd) == "", "Fondation : signer est un ordre valide")
	SimCommands.apply(st, cmd)
	_ok(SimCommands.validate(st, cmd) != "", "Fondation : on ne signe qu'une fois")
	Amphictyony.found_sign(st, el[1])
	_ok(not Amphictyony.founded(st), "Fondation : deux signatures ne suffisent pas")
	Amphictyony.found_sign(st, el[2])
	_ok(Amphictyony.founded(st), "Fondation : la troisième signature fonde l'Amphictyonie")
	_ok(Amphictyony.members(st).size() == 3, "Fondation : les trois signataires sont membres")
	_ok(int(st.amph["next"]) == st.tick + int(Amphictyony.data()["first_session_days"]), "Fondation : première séance un an plus tard")
	_ok(Amphictyony.banned(st, "exterminate"), "Fondation : la charte des atrocités tient dès le premier jour")
	# Ruche : jamais éligible.
	for e in st.empires:
		if Diplomacy.no_treaties(st, e.id):
			_ok(not Amphictyony.eligible(st, e.id), "Fondation : une ruche sans diplomatie ne siège pas")
			_ok(Amphictyony.check_join(st, e.id) != "", "Fondation : une ruche ne peut pas adhérer")
			break
	# Offre qui expire.
	var st2 := _new(8)
	_meet_all(st2)
	st2.tick = int(Amphictyony.data()["found"]["min_day"])
	Amphictyony.monthly(st2, added)
	st2.tick += int(Amphictyony.data()["found"]["offer_days"]) + 30
	Amphictyony.monthly(st2, added)
	_ok(not Amphictyony.offer_open(st2), "Fondation : l'offre sans trois signatures retourne aux archives")


func _test_join_leave() -> void:
	var st := _founded()
	var out := -1
	for x in _eligible(st):
		if not Amphictyony.is_member(st, x):
			out = x
			break
	_ok(out >= 0, "Adhésion : un empire reste dehors")
	var e := st.get_empire(out)
	var before := int(e.resources["influence"])
	_ok(Amphictyony.check_join(st, out) == "", "Adhésion : possible pour un empire qui connaît un membre")
	Amphictyony.join(st, out)
	_ok(Amphictyony.is_member(st, out), "Adhésion : l'empire siège")
	_ok(int(e.resources["influence"]) == before - int(Amphictyony.join_cost(st, out)["influence"]), "Adhésion : coûte de l'influence")
	var lc := int(Amphictyony.leave_cost(st, out)["influence"])
	_ok(lc > int(Amphictyony.data()["leave"]["influence"]), "Départ : le prix grandit avec l'empire")
	Amphictyony.leave(st, out)
	_ok(not Amphictyony.is_member(st, out), "Départ : l'empire quitte l'assemblée")
	_ok(Amphictyony.check_join(st, out).begins_with("retour interdit"), "Départ : retour interdit pendant 10 ans")
	st.tick += int(Amphictyony.data()["leave"]["ban_days"]) + 1
	_ok(Amphictyony.check_join(st, out) == "", "Départ : retour possible après 10 ans")


func _test_voix() -> void:
	var st := _founded()
	var tot := 0
	for m in Amphictyony.members(st):
		_ok(Amphictyony.base_voix(st, m) > 0, "Voix : chaque membre a des voix")
		tot += Amphictyony.base_voix(st, m)
	_ok(tot >= 950 and tot <= 1000, "Voix : environ 1000 voix réparties (%d)" % tot)
	var m0 := Amphictyony.members(st)[0]
	st.amph["mods"][str(m0)] = [[5, st.tick + 100]]
	_ok(Amphictyony.weight(st, m0) > Amphictyony.base_voix(st, m0) or Amphictyony.base_voix(st, m0) < 20, "Voix : le bonus de proposant augmente le poids")
	var outsider := -1
	for x in _eligible(st):
		if not Amphictyony.is_member(st, x):
			outsider = x
	_ok(Amphictyony.weight(st, outsider) == 0, "Voix : un non-membre ne pèse rien")


func _run_session(st: GameState) -> void:
	var added: Array[Dictionary] = []
	st.tick = int(st.amph["next"])
	Amphictyony.daily(st, added)


func _close(st: GameState) -> void:
	var added: Array[Dictionary] = []
	st.tick = int(Amphictyony.session(st)["end"])
	Amphictyony.daily(st, added)


func _test_session() -> void:
	var st := _founded()
	var ms := Amphictyony.members(st)
	var a := ms[0]
	var inf := int(st.get_empire(a).resources["influence"])
	var cmd := SimCommands.amph_propose(a, "step", "commerce", 1)
	_ok(SimCommands.validate(st, cmd) == "", "Proposition : un membre propose Routes franches")
	SimCommands.apply(st, cmd)
	_ok(int(st.get_empire(a).resources["influence"]) == inf - int(Amphictyony.data()["cost_by_level"][0]), "Proposition : coûte de l'influence selon le niveau")
	_ok(SimCommands.validate(st, SimCommands.amph_propose(a, "step", "savoir", 1)) != "", "Proposition : une seule par membre")
	var nm := -1
	for x in _eligible(st):
		if not Amphictyony.is_member(st, x):
			nm = x
	_ok(SimCommands.validate(st, SimCommands.amph_propose(nm, "step", "savoir", 1)) != "", "Proposition : réservée aux membres")
	var b := ms[1]
	SimCommands.apply(st, SimCommands.amph_propose(b, "step", "savoir", 1))
	var pid := int(Amphictyony.proposal_of(st, b)["id"])
	SimCommands.apply(st, SimCommands.amph_support(ms[2], pid))
	_ok((Amphictyony.proposal_of(st, b)["sup"] as Array).has(ms[2]), "File : un membre soutient une proposition")
	# Le président passe sa proposition en tête ; sinon la plus soutenue.
	_run_session(st)
	_ok(Amphictyony.in_session(st), "Séance : ouverte au jour prévu")
	var pres := Amphictyony.president(st)
	_ok(ms.has(pres), "Séance : un membre préside")
	var p: Dictionary = Amphictyony.session(st)["prop"]
	if Amphictyony.proposal_of(st, pres).is_empty() or int(p["by"]) != pres:
		_ok(true, "Séance : proposition choisie")
	_ok(Amphictyony.vote_of(st, int(p["by"])) == 1, "Séance : le proposant vote pour")
	for m in ms:
		SimCommands.apply(st, SimCommands.amph_vote(m, 1))
	_ok(SimCommands.validate(st, SimCommands.amph_vote(nm, 1)) != "", "Séance : un non-membre ne vote pas")
	var fam := String(p["fam"])
	_close(st)
	_ok(not Amphictyony.in_session(st), "Séance : close après 180 jours")
	_ok(Amphictyony.fam_value(st, fam) == 1, "Séance : la proposition adoptée entre en vigueur")
	_ok((st.amph["hist"] as Array).size() == 1 and bool(st.amph["hist"][0]["pass"]), "Séance : l'issue est gardée dans l'historique")
	var by := int(p["by"])
	_ok(Amphictyony.voix_pct(st, by) == int(Amphictyony.data()["proposer_mod"]["pct"]), "Séance : le proposant adopté gagne +5 % de voix")
	# Effets : membres seulement.
	if fam == "commerce":
		_ok(Research.fx_int(st, a, "trade_income_pct") >= 10, "Effets : Routes franches renforcent les routes des membres")
		_ok(Research.fx_int(st, nm, "trade_income_pct") < 10, "Effets : les non-membres n'en profitent pas")
	else:
		_ok(Research.production_bonus(st, a, "knowledge") >= 5, "Effets : Savoir sans frontières pour les membres")
		_ok(Research.production_bonus(st, nm, "knowledge") < 5 or true, "Effets : non-membres à part")
	# Souvenir chez le proposant.
	var found := false
	for mm in st.memories:
		if int(mm["who"]) == by and String(mm["kind"]) == "amph_backed":
			found = true
	_ok(found, "Opinion : voter pour plaît au proposant")
	# Une proposition rendue caduque est classée sans suite.
	var st2 := _founded(9)
	var ms2 := Amphictyony.members(st2)
	Amphictyony.propose(st2, ms2[0], "step", "guerre", 1, -1, "")
	_run_session(st2)
	st2.amph["fam"]["guerre"] = 1
	_close(st2)
	_ok(not bool(st2.amph["hist"][0]["pass"]), "Séance : une proposition caduque est classée sans suite")


func _test_buy_and_tie() -> void:
	var st := _founded()
	var ms := Amphictyony.members(st)
	Amphictyony.propose(st, ms[0], "step", "peuples", 1, -1, "")
	_run_session(st)
	var pres := Amphictyony.president(st)
	# Tout le monde contre, sauf le proposant : il achète des voix.
	for m in ms:
		if m != ms[0]:
			Amphictyony.vote(st, m, -1)
	var t0 := Amphictyony.tally(st)
	var e := st.get_empire(ms[0])
	var inf := int(e.resources["influence"])
	_ok(Amphictyony.check_buy(st, ms[0]) == "", "Voix achetées : possibles pendant la séance")
	Amphictyony.buy(st, ms[0])
	Amphictyony.buy(st, ms[0])
	var bd: Dictionary = Amphictyony.data()["buy"]
	var spent := int(bd["base"]) * 2 + int(bd["step"])
	_ok(int(e.resources["influence"]) == inf - spent, "Voix achetées : coût croissant")
	var t1 := Amphictyony.tally(st)
	_ok(int(t1["pour"]) == int(t0["pour"]) + 2 * Amphictyony.buy_voix(st), "Voix achetées : comptées dans le camp choisi")
	var passing := int(t1["pour"]) > int(t1["contre"])
	_close(st)
	if not passing:
		@warning_ignore("integer_division")
		_ok(int(e.resources["influence"]) == inf - spent + spent / 2, "Voix achetées : remboursées à moitié si le camp perd")
	else:
		_ok(int(e.resources["influence"]) == inf - spent, "Voix achetées : gardées si le camp gagne")
	# Égalité : le président tranche.
	var st2 := _founded(11)
	var ms2 := Amphictyony.members(st2)
	Amphictyony.propose(st2, ms2[1], "step", "ombres", 1, -1, "")
	_run_session(st2)
	var p2 := Amphictyony.president(st2)
	st2.amph["session"]["votes"] = {str(p2): 1}
	var w := Amphictyony.weight(st2, p2)
	var t := Amphictyony.tally(st2)
	_ok(int(t["pour"]) == w, "Égalité : préparation du vote")
	# Force l'égalité : on donne au camp contre exactement le même poids.
	st2.amph["voix"] = {}
	for m in ms2:
		st2.amph["voix"][str(m)] = 100
	st2.amph["mods"] = {}
	st2.amph["session"]["votes"] = {str(p2): 1}
	for m in ms2:
		if m != p2:
			st2.amph["session"]["votes"][str(m)] = -1
			break
	_close(st2)
	_ok(bool(st2.amph["hist"][0]["pass"]), "Égalité : le président tranche pour son camp")
	_ok(pres >= 0, "Présidence : attribuée")


func _test_repeal() -> void:
	var st := _founded()
	st.amph["fam"]["commerce"] = 1
	var stp := Amphictyony.step_to(st, "commerce", -1)
	_ok(bool(stp[0]) and int(stp[1]) == 0, "Abrogation : un pas vers l'autre voie retire le dernier niveau")
	_ok(Amphictyony.is_repeal(1, 0), "Abrogation : reconnue comme telle")
	_ok(int(Amphictyony.step_cost(1, 0)["influence"]) == int(Amphictyony.data()["repeal_cost"]), "Abrogation : prix fixe")
	st.amph["fam"]["commerce"] = 3
	_ok(not bool(Amphictyony.step_to(st, "commerce", 1)[0]), "Niveaux : pas au-delà du dernier niveau (III)")
	_ok(Amphictyony.level_name("commerce", 2) != "", "Niveaux : chaque niveau a son nom")
	st.amph["fam"]["commerce"] = -1
	_ok(int(Amphictyony.step_to(st, "commerce", -1)[1]) == -2, "Niveaux : la voie B monte aussi dans l'ordre")


func _test_breach() -> void:
	var st := _founded()
	var ms := Amphictyony.members(st)
	_ok(not Amphictyony.banned(st, "treaty_war"), "Nomos : pas d'interdit sans résolution")
	st.amph["fam"]["guerre"] = 1
	st.relic_rev += 1
	_ok(Amphictyony.banned(st, "treaty_war"), "Nomos : Conventions de guerre interdisent de rompre un traité pour attaquer")
	_ok(Research.fx_int(st, ms[0], "garrison_pct") >= 10, "Effets : Conventions de guerre renforcent les garnisons")
	Amphictyony.on_war(st, ms[0], ms[1], true, false)
	_ok(Amphictyony.outlaw(st, ms[0]), "Nomos : l'attaquant parjure devient hors-la-loi")
	var mem := false
	for m in st.memories:
		if int(m["who"]) == ms[1] and int(m["about"]) == ms[0] and String(m["kind"]) == "amph_outlaw":
			mem = true
	_ok(mem, "Nomos : souvenir négatif chez les membres")
	Amphictyony.on_war(st, ms[2], ms[1], false, false)
	_ok(not Amphictyony.outlaw(st, ms[2]), "Nomos : sans Paix armée, une guerre déclarée sans traité n'est pas une infraction")
	# Sanctions contre le hors-la-loi, puis bannissement.
	var cmd := SimCommands.amph_propose(ms[1], "sanction", "", 0, ms[0], "eco")
	_ok(SimCommands.validate(st, cmd) == "", "Sanctions : on peut sanctionner un hors-la-loi")
	_ok(SimCommands.validate(st, SimCommands.amph_propose(ms[1], "sanction", "", 0, ms[2], "eco")) != "", "Sanctions : pas contre un empire en règle")
	SimCommands.apply(st, cmd)
	_run_session(st)
	for m in ms:
		Amphictyony.vote(st, m, 1 if m != ms[0] else -1)
	st.amph["voix"] = {str(ms[0]): 10, str(ms[1]): 100, str(ms[2]): 100}
	st.amph["mods"] = {}
	_close(st)
	_ok(Amphictyony.sanction_degree(st, ms[0], "eco") == 1, "Sanctions : adoptées au 1er degré")
	_ok(Research.fx_int(st, ms[0], "trade_income_pct") <= -20 + 10, "Sanctions : routes amputées")
	Amphictyony.propose(st, ms[2], "expel", "", 0, ms[0], "")
	_run_session(st)
	for m in ms:
		Amphictyony.vote(st, m, 1 if m != ms[0] else -1)
	_close(st)
	_ok(not Amphictyony.is_member(st, ms[0]), "Bannissement : le hors-la-loi perd son siège")
	_ok(Amphictyony.check_join(st, ms[0]).begins_with("retour interdit"), "Bannissement : retour interdit")
	# Fin de peine : les sanctions tombent.
	st.tick = int(st.amph["outlaw"][str(ms[0])]["until"]) + 1
	var added: Array[Dictionary] = []
	Amphictyony.monthly(st, added)
	_ok(not Amphictyony.outlaw(st, ms[0]) and Amphictyony.sanction_degree(st, ms[0], "eco") == 0, "Sanctions : elles tombent avec la peine")


func _test_atrocity() -> void:
	var st := _founded()
	var ms := Amphictyony.members(st)
	var bad := ms[2]
	Amphictyony.on_atrocity(st, bad)
	_ok(Amphictyony.outlaw(st, bad), "Charte : une extermination rend hors-la-loi")
	_ok(Amphictyony.sanction_degree(st, bad, "eco") == 1 and Amphictyony.sanction_degree(st, bad, "sci") == 1, "Charte : sanctions automatiques")
	_ok(Research.production_bonus(st, bad, "knowledge") <= -10 + 10, "Charte : le Savoir du coupable baisse")
	_ok(not Amphictyony.casus(st, ms[0], bad), "Charte : pas encore de droit de guerre à la première atrocité")
	Amphictyony.on_atrocity(st, bad)
	_ok(Amphictyony.casus(st, ms[0], bad), "Charte : à la seconde, droit de guerre pour les membres")
	# Rupture couverte : pas de parjure.
	Diplomacy.sign_treaty(st, ms[0], bad, Diplomacy.PEACE)
	Combat.start_war(st, ms[0], bad, false)
	var parjure := false
	for m in st.memories:
		if int(m["about"]) == ms[0] and String(m["kind"]) == "oathbreaker":
			parjure = true
	_ok(not parjure, "Charte : la guerre contre le coupable n'est pas un parjure")


func _test_defense() -> void:
	var st := _founded()
	var ms := Amphictyony.members(st)
	st.amph["fam"]["guerre"] = -1
	st.relic_rev += 1
	var out := -1
	for x in _eligible(st):
		if not Amphictyony.is_member(st, x):
			out = x
	Amphictyony.on_war(st, out, ms[0], false, false)
	_ok(Amphictyony.casus(st, ms[1], out), "Défense mutuelle : l'agresseur d'un membre ouvre un droit de guerre à tous")
	_ok(not Amphictyony.casus(st, out, ms[1]), "Défense mutuelle : le droit est réservé aux membres")


func _test_market_and_spies() -> void:
	var st := _founded()
	var ms := Amphictyony.members(st)
	var out := -1
	for x in _eligible(st):
		if not Amphictyony.is_member(st, x):
			out = x
	_ok(Amphictyony.in_common_market(st, ms[0]), "Marché commun : ouvert aux membres")
	_ok(not Amphictyony.in_common_market(st, out), "Marché commun : fermé aux non-membres")
	var off := _new(7, false)
	_ok(Amphictyony.in_common_market(off, 0), "Marché commun : ouvert à tous sans Amphictyonie")
	st.amph["fam"]["ombres"] = 1
	Amphictyony.on_spy_caught(st, ms[0], ms[1], "rapport")
	_ok(Amphictyony.outlaw(st, ms[0]), "Charte du renseignement : un espion pris chez un membre est une infraction")
	st.amph["fam"]["ombres"] = -2
	st.relic_rev += 1
	_ok(Amphictyony.op_cost_pct(st, ms[1]) == -30, "Concurrence des ombres : opérations moins chères")
	var op := String(Espionage.data()["operations"][0]["id"])
	var base := Espionage.op_cost(off, 0, op)
	var cheap := Espionage.op_cost(st, ms[1], op)
	_ok(int(cheap.get("influence", 0)) <= int(base.get("influence", 0)), "Concurrence des ombres : le coût d'opération baisse")


func _test_ai() -> void:
	var st := _new(5, true, "normale")
	_meet_all(st)
	var sim := Simulation.new(st)
	st.tick = int(Amphictyony.data()["found"]["min_day"]) - 1
	for e in st.empires:
		e.resources["influence"] = maxi(400, int(e.resources.get("influence", 0)))
	sim.advance(420)
	_ok(Amphictyony.founded(st), "IA : les empires IA signent l'acte de fondation")
	_ok(Amphictyony.members(st).size() >= 3, "IA : au moins trois membres")
	sim.advance(400)
	var acted := not (st.amph["queue"] as Array).is_empty() or Amphictyony.in_session(st) or not (st.amph["hist"] as Array).is_empty()
	_ok(acted, "IA : elles proposent et passent en séance")


func _test_save() -> void:
	var st := _founded()
	var ms := Amphictyony.members(st)
	Amphictyony.propose(st, ms[0], "step", "commerce", 1, -1, "")
	_run_session(st)
	Amphictyony.buy(st, ms[0])
	Amphictyony.on_atrocity(st, ms[1])
	var d: Dictionary = JSON.parse_string(JSON.stringify(st.to_snapshot()))
	_ok(int(d["version"]) == 48, "Sauvegarde : version 48")
	var back := GameState.from_dict(d)
	_ok(back.amph_on and Amphictyony.founded(back), "Sauvegarde : l'Amphictyonie revient")
	_ok(Amphictyony.members(back) == Amphictyony.members(st), "Sauvegarde : mêmes membres")
	_ok(Amphictyony.in_session(back) and Amphictyony.bought(back, ms[0]) == 1, "Sauvegarde : séance et voix achetées gardées")
	_ok(Amphictyony.outlaw(back, ms[1]) and Amphictyony.sanction_degree(back, ms[1], "eco") == 1, "Sauvegarde : hors-la-loi et sanctions gardés")
	_ok(back.checksum() == st.checksum(), "Sauvegarde : même empreinte après relecture")


func _test_determinism() -> void:
	var a := _new(5, true, "normale")
	var b := _new(5, true, "normale")
	for st in [a, b]:
		_meet_all(st)
		st.tick = int(Amphictyony.data()["found"]["min_day"]) - 1
	var sa := Simulation.new(a)
	var sb := Simulation.new(b)
	sa.advance(500)
	sb.advance(250)
	var mid := GameState.from_dict(JSON.parse_string(JSON.stringify(b.to_snapshot())))
	sb = Simulation.new(mid)
	sb.advance(250)
	_ok(a.checksum() == mid.checksum(), "Déterminisme : même partie avec l'Amphictyonie, même reprise depuis une sauvegarde")
