extends RefCounted
## Tests de l'Amphictyonie, lot 3 (AmphPower) : pleins pouvoirs (mandat à vie, Impérateur, soumis et
## rebelles, autorité, tribut, guerres de la Cour, effondrement), victoire diplomatique (élection du
## Chancelier, verdict, Dernière Guerre), politique (courants, conflits de lois, Souveraineté), religion
## (zèle, guerre sainte, Conclave), talents des 8 peuples, IA, sauvegarde 49. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Amphictyonie, pouvoir et légitimité…")
	_test_full_powers()
	_test_court()
	_test_chancellor()
	_test_last_war()
	_test_politics()
	_test_religion()
	_test_talents()
	_test_ai()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 7, opts := {}) -> GameState:
	var o := {"ai_level": "", "amphictyony": "active"}
	o.merge(opts, true)
	return GameState.create(seed_value, 150, 1800.0, "vael", o)


func _by_faction(st: GameState, fid: String) -> int:
	for e in st.empires:
		if e.faction_id == fid:
			return e.id
	return -1


## Partie fondée ; tous les empires éligibles sauf le dernier siègent ; ressources abondantes.
func _founded(seed_value := 7, opts := {}) -> GameState:
	var st := _new(seed_value, opts)
	for e in st.empires:
		if e.is_npc():
			continue
		for o in st.empires:
			if o.id != e.id and not o.is_npc() and not e.contacts.has(o.id):
				e.contacts.append(o.id)
		e.resources["influence"] = 3000
		e.resources["energy"] = 5000
		e.resources["materials"] = 5000
	st.tick = int(Amphictyony.data()["found"]["min_day"])
	var added: Array[Dictionary] = []
	Amphictyony.monthly(st, added)
	var el: Array[int] = []
	for e in st.empires:
		if Amphictyony.eligible(st, e.id):
			el.append(e.id)
	for i in 3:
		Amphictyony.found_sign(st, el[i])
	for i in range(3, el.size() - 1):
		Amphictyony.join(st, el[i])
	return st


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


## Haute Voûte et Arbitre élu ; renvoie l'Arbitre.
func _with_arbiter(st: GameState) -> int:
	st.tick = int(st.amph["founded"]) + int(AmphInst.idata()["council"]["after_days"])
	Amphictyony.recompute_voix(st)
	_pass(st, Amphictyony.members(st)[0], "council")
	var cs := AmphInst.councillors(st)
	_pass(st, cs[0], "arbiter", "", 0, cs[0])
	return AmphInst.arbiter(st)


func _imperator(st: GameState) -> int:
	var arb := _with_arbiter(st)
	_pass(st, arb, "term_lift")
	_pass(st, arb, "full_powers")
	return arb


func _test_full_powers() -> void:
	var st := _founded()
	var arb := _with_arbiter(st)
	_ok(arb >= 0, "Pleins pouvoirs : un Arbitre des étoiles est élu")
	var other := -1
	for m in Amphictyony.members(st):
		if m != arb:
			other = m
			break
	_ok(Amphictyony.check_propose(st, arb, "full_powers", "", 0, -1, "") != "", "Pleins pouvoirs : pas sans mandat à vie")
	_ok(_pass(st, other, "term_lift"), "Mandat à vie : adopté")
	_ok(AmphPower.life(st), "Mandat à vie : l'Arbitre n'a plus de terme")
	st.tick += int(AmphInst.idata()["arbiter"]["mandate_days"]) + 10
	_ok(AmphInst.arbiter(st) == arb, "Mandat à vie : il survit à la fin de son mandat")
	_ok(Amphictyony.check_propose(st, other, "full_powers", "", 0, -1, "") != "", "Pleins pouvoirs : seul l'Arbitre les réclame")
	_ok(Amphictyony.check_propose(st, arb, "extend", "", 0, -1, "") != "", "Mandat à vie : plus rien à prolonger")
	_ok(_pass(st, arb, "full_powers"), "Pleins pouvoirs : adoptés")
	_ok(AmphPower.imperator(st) == arb and AmphPower.choosing(st), "Impérateur : la Cour attend les réponses")
	_ok(AmphPower.authority(st) == int(AmphPower.pdata()["auth0"]), "Impérateur : autorité de départ")
	_ok(Amphictyony.voix_pct(st, arb) >= int(AmphPower.pdata()["voix_pct"]), "Impérateur : +50 % de voix")
	_ok(Amphictyony.check_propose(st, other, "defiance", "", 0, -1, "") != "", "Impérateur : plus de motion de défiance")


func _test_court() -> void:
	var st := _founded()
	var imp := _imperator(st)
	var ms := Amphictyony.members(st)
	var sub := -1
	var reb := -1
	for m in ms:
		if m == imp:
			continue
		if sub < 0:
			sub = m
		elif reb < 0:
			reb = m
	_ok(SimCommands.validate(st, SimCommands.amph_act(sub, "submit")) == "", "Cour : un membre peut se soumettre")
	SimCommands.apply(st, SimCommands.amph_act(sub, "submit"))
	_ok(AmphPower.submitted(st, sub), "Cour : il est vassal")
	_ok(SimCommands.validate(st, SimCommands.amph_act(imp, "rebel")) != "", "Cour : l'Impérateur ne se soulève pas contre lui-même")
	SimCommands.apply(st, SimCommands.amph_act(reb, "rebel"))
	_ok(not Amphictyony.is_member(st, reb) and Amphictyony.banned_until(st, reb) > st.tick, "Rebelle : il quitte l'assemblée, banni")
	_ok(Combat.at_war(st, reb, imp), "Rebelle : en guerre contre l'Impérateur")
	_ok(AmphPower.is_rebel(st, reb), "Rebelle : compté comme tel")
	# Fin du délai : qui n'a rien dit s'est soumis.
	var added: Array[Dictionary] = []
	st.tick = int(st.amph["imp"]["until"])
	var inf_imp := int(st.get_empire(imp).resources["influence"])
	var a0 := AmphPower.authority(st)
	AmphPower.monthly(st, added)
	_ok(not AmphPower.choosing(st), "Cour : le délai expire")
	var all_sub := true
	for m in Amphictyony.members(st):
		if m != imp and not AmphPower.submitted(st, m):
			all_sub = false
	_ok(all_sub, "Cour : le silence vaut soumission")
	_ok(int(st.get_empire(imp).resources["influence"]) > inf_imp, "Cour : tribut versé à l'Impérateur")
	var subs := (st.amph["imp"]["sub"] as Array).size()
	var want := a0 + mini(int(AmphPower.pdata()["auth_sub_max"]), subs) + int(AmphPower.pdata()["auth_reb"])
	_ok(AmphPower.authority(st) == want, "Autorité : +1 par vassal (3 au plus), -3 par rebelle en guerre (%d, attendu %d)" % [AmphPower.authority(st), want])
	# Un rebelle abattu.
	st.get_empire(reb).eliminated = true
	var a1 := AmphPower.authority(st)
	AmphPower.monthly(st, added)
	_ok(AmphPower.authority(st) >= a1 + int(AmphPower.pdata()["auth_kill"]), "Autorité : +10 par rebelle abattu")
	st.get_empire(reb).eliminated = false
	# On attaque l'Impérateur : ses vassaux le défendent.
	var outsider := -1
	for e in st.empires:
		if not e.is_npc() and not Amphictyony.is_member(st, e.id) and e.id != reb and not Combat.at_war(st, e.id, imp) and Diplomacy.check_war(st, e.id, imp) == "":
			outsider = e.id
	if outsider >= 0:
		Combat.start_war(st, outsider, imp)
		var joined := 0
		for s in st.amph["imp"]["sub"]:
			if Combat.at_war(st, int(s), outsider):
				joined += 1
		_ok(joined >= 1, "Cour : les vassaux entrent en guerre aux côtés de l'Impérateur")
	# Espions : sous 50 seulement.
	var spy := reb
	_ok(AmphInst.spy_check(st, spy, imp, "saper_autorite") != "" or AmphPower.authority(st) < 50, "Saper l'autorité : pas contre une autorité solide")
	st.amph["imp"]["auth"] = 40
	_ok(AmphInst.spy_check(st, spy, imp, "saper_autorite") == "", "Saper l'autorité : possible sous 50")
	AmphInst.spy_apply(st, spy, imp, Espionage.op_def("saper_autorite"))
	_ok(AmphPower.authority(st) == 25, "Saper l'autorité : -15")
	_ok(AmphInst.spy_check(st, spy, sub, "allumer_rebellion") == "", "Allumer la rébellion : possible contre un vassal")
	AmphInst.spy_apply(st, spy, sub, Espionage.op_def("allumer_rebellion"))
	_ok(AmphPower.is_rebel(st, sub) and not Amphictyony.is_member(st, sub), "Allumer la rébellion : le vassal se soulève")
	st.amph["imp"]["auth"] = 10
	AmphInst.spy_apply(st, spy, imp, Espionage.op_def("saper_autorite"))
	_ok(not AmphPower.imp_on(st) and AmphInst.arbiter(st) < 0, "Effondrement : autorité nulle, plus d'Impérateur ni d'Arbitre")


func _chan_game() -> GameState:
	var st := _founded()
	st.tick = int(AmphPower.cdata()["from_day"])
	Amphictyony.recompute_voix(st)
	var added: Array[Dictionary] = []
	Amphictyony.daily(st, added)
	return st


## Tous votent pour le premier candidat ; renvoie [élu, battu].
func _elect(st: GameState) -> Array:
	var cands: Array = AmphPower.chan(st)["cands"]
	for m in Amphictyony.members(st):
		if not cands.has(m):
			AmphPower.cvote(st, m, int(cands[0]))
	var added: Array[Dictionary] = []
	st.tick = int(AmphPower.chan(st)["end"])
	Amphictyony.daily(st, added)
	return [int(cands[0]), int(cands[1])]


func _test_chancellor() -> void:
	var st0 := _founded()
	_ok(Victory.enabled(st0, "diplomatique"), "Victoire diplomatique : en jeu avec l'Amphictyonie")
	_ok(not Victory.enabled(_new(7, {"amphictyony": "aucune"}), "diplomatique"), "Victoire diplomatique : absente sans Amphictyonie")
	_ok(not Victory.rule_text("diplomatique").contains("%d"), "Victoire diplomatique : texte de règle complet")
	st0.tick = int(AmphPower.cdata()["from_day"]) - 30
	var added: Array[Dictionary] = []
	Amphictyony.daily(st0, added)
	_ok(not AmphPower.chan_on(st0), "Chancelier : pas d'élection avant l'an 30")
	var st := _chan_game()
	_ok(AmphPower.chan_on(st), "Chancelier : l'élection s'ouvre à l'an 30")
	var cands: Array = AmphPower.chan(st)["cands"]
	_ok(cands.size() == 2 and AmphPower.cvote_of(st, int(cands[0])) == int(cands[0]), "Chancelier : deux candidats, qui votent pour eux-mêmes")
	_ok(AmphPower.check_cvote(st, int(cands[0]), int(cands[1])) != "", "Chancelier : un candidat ne vote pas pour l'autre")
	var voter := -1
	for m in Amphictyony.members(st):
		if not cands.has(m):
			voter = m
	_ok(SimCommands.validate(st, SimCommands.amph_act(voter, "cvote", int(cands[0]))) == "", "Chancelier : un membre vote")
	var t := AmphPower.ctally(st)
	var r := _elect(st)
	@warning_ignore("integer_division")
	var share := (int(t["total"]) - Amphictyony.weight(st, int(r[1]))) * 100 / int(t["total"])
	var won := share >= int(AmphPower.cdata()["win_pct"])
	_ok(int(st.amph["share"][str(r[0])]) == share, "Chancelier : score en part de toutes les voix (%d %%)" % share)
	_ok(AmphPower.pending_verdict(st) == won, "Chancelier : élu seulement à 67 %")
	if won:
		_ok(AmphPower.check_refuse(st, int(r[0])) != "" and AmphPower.check_refuse(st, int(r[1])) == "", "Verdict : seul le battu peut refuser")
		st.tick = int(AmphPower.dip(st)["until"])
		Amphictyony.monthly(st, added)
		_ok(bool(Victory.progress(st, int(r[0]), "diplomatique")["won"]), "Verdict : sans refus, l'élu gagne")
	# Abstentions : elles comptent contre.
	var st2 := _chan_game()
	var added2: Array[Dictionary] = []
	st2.tick = int(AmphPower.chan(st2)["end"])
	Amphictyony.daily(st2, added2)
	_ok(not AmphPower.pending_verdict(st2), "Chancelier : sans majorité qualifiée, pas d'élu")
	_ok(int(Victory.progress(st2, Amphictyony.members(st2)[0], "diplomatique")["pct"]) < 100, "Chancelier : l'avancée reste sous 100")
	# Assemblée trop maigre.
	var st3 := _founded()
	for m in Amphictyony.members(st3).slice(3):
		Amphictyony._remove_member(st3, m, 10)
	_ok(AmphPower.check_ready(st3) != "", "Chancelier : il faut une assemblée qui représente la galaxie")


func _test_last_war() -> void:
	var st := _chan_game()
	# Les deux candidats gardent leurs voix ; on force une large victoire en vidant les voix du second.
	var cands: Array = AmphPower.chan(st)["cands"]
	st.amph["voix"][str(int(cands[1]))] = 1
	var r := _elect(st)
	_ok(AmphPower.pending_verdict(st), "Dernière Guerre : un élu")
	var loser := int(r[1])
	SimCommands.apply(st, SimCommands.amph_act(loser, "refuse"))
	_ok(int(AmphPower.dip(st)["war"]) == 1, "Dernière Guerre : le battu refuse le verdict")
	_ok(Combat.at_war(st, int(r[0]), loser) or Diplomacy.check_war(st, int(r[0]), loser) != "", "Dernière Guerre : l'élu marche contre lui")
	var added: Array[Dictionary] = []
	Amphictyony.monthly(st, added)
	_ok(not bool(Victory.progress(st, int(r[0]), "diplomatique")["won"]), "Dernière Guerre : pas de victoire tant qu'il tient sa capitale")
	st.get_empire(loser).eliminated = true
	Amphictyony.monthly(st, added)
	_ok(bool(Victory.progress(st, int(r[0]), "diplomatique")["won"]), "Dernière Guerre : sa chute donne la victoire")
	var st2 := _chan_game()
	var c2: Array = AmphPower.chan(st2)["cands"]
	st2.amph["voix"][str(int(c2[1]))] = 1
	var r2 := _elect(st2)
	SimCommands.apply(st2, SimCommands.amph_act(int(r2[1]), "refuse"))
	st2.tick = int(AmphPower.dip(st2)["war_end"])
	Amphictyony.monthly(st2, added)
	_ok(AmphPower.dip(st2).is_empty(), "Dernière Guerre : au bout de 10 ans, le titre retourne aux archives")
	var st3 := _chan_game()
	var c3: Array = AmphPower.chan(st3)["cands"]
	st3.amph["voix"][str(int(c3[1]))] = 1
	var r3 := _elect(st3)
	SimCommands.apply(st3, SimCommands.amph_act(int(r3[1]), "accept"))
	_ok(bool(Victory.progress(st3, int(r3[0]), "diplomatique")["won"]), "Verdict : s'incliner donne la victoire à l'élu")


func _test_politics() -> void:
	var st := _founded(7, {"politics": "active"})
	var ms := Amphictyony.members(st)
	var m := -1
	for x in ms:
		if Politics.applies(st, x) and Laws.applies(st, x):
			m = x
			break
	_ok(m >= 0, "Politique : un membre a une vie politique")
	if m < 0:
		return
	var en := Politics._emp_w(st, m)
	en["laws"] = ["libre_echange"]
	st.amph["fam"]["commerce"] = -1
	st.relic_rev += 1
	_ok(AmphPower.conflicts(st, m).size() == 1, "Conflit : Libre-échange contre Préférence impériale")
	var parts := AmphPower.stability_parts(st, m)
	_ok(parts.size() == 1 and int(parts[0][1]) == int(AmphPower.poldata()["conflict_stability"]), "Conflit : de la stabilité en moins")
	_ok(AmphPower.check_sovereign(st, m, "commerce") != "", "Souveraineté : il faut la loi")
	en["laws"] = ["libre_echange", "souverainete"]
	_ok(SimCommands.validate(st, SimCommands.amph_act(m, "sovereign", -1, -1, "commerce")) == "", "Souveraineté : invocable avec la loi")
	var fx0 := Amphictyony.effects(st, m)
	SimCommands.apply(st, SimCommands.amph_act(m, "sovereign", -1, -1, "commerce"))
	_ok(AmphPower.conflicts(st, m).is_empty(), "Souveraineté : plus de conflit")
	var fx1 := Amphictyony.effects(st, m)
	_ok(int(fx1.get("trade_income_pct", 0)) > int(fx0.get("trade_income_pct", 0)), "Souveraineté : les effets de la famille ne s'appliquent plus")
	_ok(AmphPower.check_sovereign(st, m, "commerce") != "", "Souveraineté : une fois par an")
	var o := ms[0] if ms[0] != m else ms[1]
	var mem := false
	for x in st.memories:
		if String(x["kind"]) == "amph_sovereign" and int(x["about"]) == m:
			mem = true
	_ok(mem and o >= 0, "Souveraineté : les autres membres s'en souviennent")
	st.amph["fam"]["guerre"] = 1
	_ok(not AmphPower.exempt_kind(st, m, "treaty_war"), "Souveraineté : seulement sur la famille invoquée")
	st.amph["sov"][str(m)]["guerre"] = st.tick + 100
	_ok(AmphPower.exempt_kind(st, m, "treaty_war"), "Souveraineté : les interdits de la famille ne le lient plus")
	_ok(not GameData.politics()["acts"].get("amph_member", {}).is_empty(), "Politique : siéger pousse un courant")
	_ok(Laws.check_adopt(_new(7, {"politics": "active", "amphictyony": "aucune"}), 0, "souverainete") != "", "Souveraineté : pas sans Amphictyonie")
	# Une résolution adoptée pousse le courant de sa voie chez ceux qui l'ont votée.
	var i := Politics.index_of("academie")
	var sid: int = Stability.systems_of(st, m)[0]
	var before := int(Politics.opinion(st, sid)[i])
	AmphPower.on_close(st, {"kind": "step", "fam": "savoir", "from": 0, "to": 1}, {str(m): 1}, true)
	_ok(int(Politics.opinion(st, sid)[i]) > before, "Politique : Savoir sans frontières pousse l'Académie chez qui l'a voté")


func _test_religion() -> void:
	var st := _founded(7, {"faiths": "actives"})
	var ms := Amphictyony.members(st)
	var faiths: Dictionary = st.faiths.get("list", {})
	var fid := ""
	for k in faiths:
		fid = String(k)
		break
	_ok(fid != "", "Religion : une grande foi existe")
	if fid == "":
		return
	st.amph["gfaith"] = fid
	var z := FaithWars.zeal(st, fid)
	var added: Array[Dictionary] = []
	AmphPower.monthly(st, added)
	_ok(FaithWars.zeal(st, fid) == mini(z + 1, 100) or FaithWars.zeal(st, fid) > z, "Religion : la foi galactique gagne du zèle")
	var ch := _by_faction(st, "choeur")
	var mu := _by_faction(st, "murmurants")
	st.faiths["state"][str(ch)] = fid
	st.faiths["state"][str(mu)] = fid
	_ok(AmphPower.conclave(st, ch, mu), "Conclave : deux théocraties de même foi")
	st.faiths["state"][str(mu)] = "laicite"
	_ok(not AmphPower.conclave(st, ch, mu), "Conclave : pas sans la même foi d'État")
	AmphInst.on_holy_war(st, ms[1], ms[0])
	_ok(AmphInst.special_on(st) and int(AmphInst.special(st)["by"]) == -1, "Guerre sainte : l'assemblée se réunit d'elle-même")


func _test_talents() -> void:
	var want := {"ossarane": "landsraad", "choeur": "anatheme", "vael": "tribune", "khthari": "hors_concert", "teyl": "consensus", "ferrocornes": "plus_fort", "brisecomete": "lobby", "murmurants": "siege_voile"}
	for f in want:
		var ids := []
		for t: Dictionary in AmphPower.talent_defs():
			if FactionTraits.species_matches(GameData.faction(f), t.get("requires", {})):
				ids.append(String(t["id"]))
		_ok(ids == [want[f]], "Talent : %s a %s (%s)" % [f, want[f], str(ids)])
	var st := _founded(7, {"faiths": "actives"})
	var vael := _by_faction(st, "vael")
	var base := int(Amphictyony.prop_cost(st, "step", "commerce", 1)["influence"])
	@warning_ignore("integer_division")
	_ok(int(Amphictyony.prop_cost(st, "step", "commerce", 1, vael)["influence"]) == base * 75 / 100, "Tribune : propositions 25 % moins chères")
	_ok(AmphPower.max_props(st, vael) == 2, "Tribune : deux propositions à la fois")
	var ch := _by_faction(st, "choeur")
	var fbase := int(Amphictyony.prop_cost(st, "step", "foi", -1)["influence"])
	@warning_ignore("integer_division")
	_ok(int(Amphictyony.prop_cost(st, "step", "foi", -1, ch)["influence"]) == fbase / 2, "Anathème : Foi à moitié prix")
	var kh := _by_faction(st, "khthari")
	_ok(AmphPower.immune(st, kh) and AmphPower.moisson_steps(st, kh) == [25, 50, 75], "Hors du concert : insensible aux sanctions, Moisson à 25, 50 et 75 %")
	st.amph["den"][str(kh)] = st.tick + 1000
	_ok(Amphictyony.check_propose(st, vael, "sanction", "", 0, kh, "eco").contains("ruche"), "Hors du concert : pas de sanction contre la ruche")
	var fe := _by_faction(st, "ferrocornes")
	_ok(AmphPower.fleet_x(st, fe) == 2 and AmphPower.fleet_x(st, vael) == 1, "Droit du plus fort : la flotte compte double")
	var mu := _by_faction(st, "murmurants")
	_ok(AmphPower.veiled(st, mu) and not AmphPower.veiled(st, vael), "Siège voilé : seulement les Murmurants")
	var br := _by_faction(st, "brisecomete")
	# Une séance pour les voix achetées, le Landsraad et le Consensus.
	var ms := Amphictyony.members(st)
	Amphictyony.propose(st, ms[0], "step", "savoir", 1, -1, "")
	var added: Array[Dictionary] = []
	st.tick = int(st.amph["next"])
	Amphictyony.daily(st, added)
	_ok(Amphictyony.in_session(st), "Talents : une séance s'ouvre")
	if Amphictyony.is_member(st, br):
		_ok(Amphictyony.buy_cost(st, br).has("energy") and not Amphictyony.buy_cost(st, br).has("influence"), "Lobby : voix achetées en énergie")
		var en0 := int(st.get_empire(br).resources["energy"])
		Amphictyony.vote(st, vael, 1)
		Amphictyony.buy(st, vael)
		_ok(int(st.get_empire(br).resources["energy"]) == en0 + 5, "Lobby : commission sur les voix achetées par les autres")
	var te := _by_faction(st, "teyl")
	_ok(not AmphPower.sees_tally(st, te), "Consensus calculé : pas en début de vote")
	st.tick = int(Amphictyony.session(st)["end"]) - 20
	_ok(AmphPower.sees_tally(st, te) and not AmphPower.sees_tally(st, vael), "Consensus calculé : le vrai décompte dans les 30 derniers jours")
	var os := _by_faction(st, "ossarane")
	if Amphictyony.is_member(st, os):
		var ally := vael
		Diplomacy.sign_treaty(st, os, ally, Diplomacy.ALLIANCE)
		Amphictyony.vote(st, os, -1)
		Amphictyony.vote(st, ally, -1)
		var t0 := Amphictyony.tally(st)
		Diplomacy._rel_w(st, os, ally)["union"] = maxi(1, st.tick)
		var t1 := Amphictyony.tally(st)
		_ok(Victory.united(st, os, ally) and int(t1["contre"]) > int(t0["contre"]), "Landsraad : la lignée unie qui vote pareil pèse plus")
	# Anathème : contre une autre foi d'État.
	var faiths: Dictionary = st.faiths.get("list", {})
	if not faiths.is_empty():
		var fid := String(faiths.keys()[0])
		st.faiths["state"][str(ch)] = fid
		st.amph["special"] = {}
		st.amph["coal"] = {}
		var tg := -1
		for x in ms:
			if x != ch and Faiths.state_faith(st, x) != fid:
				tg = x
				break
		_ok(tg >= 0 and AmphPower.check_anathema(st, ch, tg) == "", "Anathème : possible contre une autre foi")
		if tg >= 0:
			SimCommands.apply(st, SimCommands.amph_act(ch, "anathema", tg))
			_ok(AmphInst.special_on(st) and int(AmphInst.special(st)["target"]) == tg, "Anathème : une session extraordinaire s'ouvre contre lui")
			_ok(AmphPower.check_anathema(st, ch, tg) != "", "Anathème : une fois par décennie")
	# Duel de champions.
	if Amphictyony.is_member(st, fe):
		var st2 := _founded()
		var by := vael
		_pass(st2, by, "step", "commerce", 1)
		var h: Dictionary = (st2.amph["hist"] as Array).back()
		h["votes"][str(fe)] = -1
		_ok(AmphPower.check_duel(st2, fe) == "", "Duel : contre une résolution récente votée contre lui")
		var mine := AmphPower._fleet(st2, fe) > AmphPower._fleet(st2, by)
		SimCommands.apply(st2, SimCommands.amph_act(fe, "duel"))
		_ok((Amphictyony.fam_value(st2, "commerce") == 0) == mine, "Duel : la plus forte flotte l'emporte")
		_ok(AmphPower.check_duel(st2, fe) != "", "Duel : une fois par décennie")


func _test_ai() -> void:
	var st := _founded(5)
	for e in st.empires:
		e.ai_level = "veteran" if not e.is_npc() else e.ai_level
	var imp := _imperator(st)
	_ok(AmphPower.choosing(st), "IA : la Cour attend")
	var sim := Simulation.new(st)
	sim.advance(120)
	var answered := 0
	for e in st.empires:
		if e.id != imp and not e.is_npc() and (AmphPower.submitted(st, e.id) or AmphPower.is_rebel(st, e.id)):
			answered += 1
	_ok(answered >= 1, "IA : les membres répondent à la Cour (%d)" % answered)
	var st2 := _chan_game()
	for e in st2.empires:
		e.ai_level = "veteran" if not e.is_npc() else e.ai_level
	var sim2 := Simulation.new(st2)
	sim2.advance(60)
	_ok(AmphPower.chan_on(st2) and (AmphPower.chan(st2)["votes"] as Dictionary).size() > 2, "IA : les membres votent pour le Chancelier")


func _test_save() -> void:
	var st := _founded(7, {"politics": "active"})
	var imp := _imperator(st)
	var sub := -1
	for m in Amphictyony.members(st):
		if m != imp:
			sub = m
			break
	AmphPower.submit(st, sub)
	st.amph["sov"][str(sub)] = {"commerce": st.tick + 100}
	st.amph["share"][str(imp)] = 55
	st.amph["dip"] = {"eid": imp, "loser": sub, "until": st.tick + 60, "voters": [sub], "war": 0, "won": 0}
	var d: Dictionary = JSON.parse_string(JSON.stringify(st.to_snapshot()))
	_ok(int(d["version"]) == 50, "Sauvegarde : version 50")
	var back := GameState.from_dict(d)
	_ok(AmphPower.imperator(back) == imp and AmphPower.submitted(back, sub) and AmphPower.authority(back) == AmphPower.authority(st), "Sauvegarde : Impérateur, vassaux et autorité gardés")
	_ok(AmphPower.sovereign(back, sub, "commerce") and AmphPower.pending_verdict(back) and int(back.amph["share"][str(imp)]) == 55, "Sauvegarde : souveraineté, verdict et scores gardés")
	_ok(AmphPower.life(back), "Sauvegarde : mandat à vie gardé")
	_ok(back.checksum() == st.checksum(), "Sauvegarde : même empreinte après relecture")
