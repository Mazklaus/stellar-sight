extends RefCounted
## Tests du pilier buts de guerre et traités de paix, lot 3 : ultimatums, crise diplomatique (ralliés,
## recul, escalade), préavis de guerre, kanly (guerre limitée, sans parjure), droit de la guerre au Nomos
## (crimes de guerre), talents de peuple, médiation, garantie de l'Arbitre, sécession du Koinon,
## opérations d'espionnage, guerre juste, héros captifs et diplomates, IA, sauvegarde 55.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Buts de guerre, lot 3…")
	_test_ultimatum()
	_test_crisis()
	_test_escalation()
	_test_prep()
	_test_kanly()
	_test_talents()
	_test_mediation()
	_test_nomos()
	_test_guarantee()
	_test_secession()
	_test_spy()
	_test_heroes()
	_test_ai()
	_test_save()
	Wars.data()["claims"]["max_jumps"] = 4


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 7, opts := {}) -> GameState:
	Wars.data()["claims"]["max_jumps"] = 99
	var o := {"ai_level": "", "wargoals": "actifs", "occupation": "occupation", "vassals": "actifs"}
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
		var cap := FactionTraits.capital_system(st, e.id)
		var dist := FactionTraits.jumps_from(st.galaxy, cap)
		var best := -1
		for sys in st.galaxy.systems:
			if sys.planet_ids.size() > 0 and st.system_owner(sys.id) == -1 and dist.has(sys.id) \
					and (best < 0 or int(dist[sys.id]) < int(dist[best])):
				best = sys.id
		if best >= 0:
			var c := Colony.new()
			c.planet_id = st.galaxy.get_system(best).planet_ids[0]
			c.owner = e.id
			c.kind = Colony.KIND_COLONY
			c.population = 3
			st.add_colony(c)
	st.tick += 800
	return st


func _by(st: GameState, fid: String) -> int:
	for e in st.empires:
		if e.faction_id == fid:
			return e.id
	return -1


func _fief(st: GameState, b: int) -> int:
	var cap := FactionTraits.capital_system(st, b)
	for sid in EmpireReport.owned_systems(st, b):
		if sid != cap:
			return sid
	return -1


## Puissance écrasante pour eid (flotte de croiseurs à sa capitale).
func _arm(st: GameState, eid: int, n := 12) -> void:
	var cap := FactionTraits.capital_system(st, eid)
	for i in n:
		st.spawn_ship(eid, "croiseur", cap)


func _has_mem(st: GameState, who: int, about: int, kind: String) -> bool:
	for m in st.memories:
		if int(m["who"]) == who and int(m["about"]) == about and String(m["kind"]) == kind:
			return true
	return false


func _test_ultimatum() -> void:
	var st := _new()
	var a := _by(st, "ferrocornes")
	var b := _by(st, "teyl")
	var sid := _fief(st, b)
	Wars.claim(st, a, sid)
	_arm(st, a, 30)
	_ok(WarLaws.ult_whats(st, a, b).has("cede:%d" % sid), "Ultimatum : céder un système revendiqué")
	_ok(not WarLaws.ult_whats(st, a, b).has("cede:%d" % FactionTraits.capital_system(st, b)), "Ultimatum : jamais la capitale")
	var cmd := SimCommands.war_act(a, "ultimatum", b, "cede:%d" % sid)
	_ok(SimCommands.validate(st, cmd) == "", "Ultimatum possible (%s)" % SimCommands.validate(st, cmd))
	var inf := int(st.get_empire(a).resources["influence"])
	_ok(WarLaws.ai_accepts_ult(st, a, b), "Ultimatum : l'IA bien plus faible cède")
	SimCommands.apply(st, cmd)
	_ok(st.system_owner(sid) == a and not Combat.at_war(st, a, b), "Ultimatum accepté : système cédé, sans guerre")
	_ok(int(st.get_empire(a).resources["influence"]) == inf - 20, "Ultimatum : coûte 20 influence")
	_ok(_has_mem(st, b, a, "ultimatum_yielded"), "Ultimatum accepté : souvenir d'humiliation")
	_ok(WarPeace.treaties_of(st, a).size() == 1, "Ultimatum accepté : inscrit au registre")
	_ok(SimCommands.validate(st, SimCommands.war_act(a, "ultimatum", b, "tribut")) != "", "Ultimatum : délai avant le suivant")
	# Refus : motif « Ultimatum refusé » (l'IA plus forte ne plie pas).
	var c := _by(st, "choeur")
	_arm(st, c, 40)
	_ok(not Wars.casus_list(st, b, c).has("ultimatum"), "Pas de motif Ultimatum avant le refus")
	SimCommands.apply(st, SimCommands.war_act(b, "ultimatum", c, "tribut"))
	_ok(Wars.casus_list(st, b, c).has("ultimatum") and bool(Wars.casus_def("ultimatum").get("just", false)), "Ultimatum refusé : motif juste pour l'exigeant")
	_ok(not Combat.at_war(st, b, c), "Ultimatum refusé : pas de guerre automatique")
	# Joueur humain visé : une proposition, qu'il accepte.
	SimCommands.apply(st, SimCommands.war_act(c, "ultimatum", 0, "tribut"))
	var p := Diplomacy.pending(st, c, 0, "wult")
	_ok(not p.is_empty() and Wars.is_kind("wult"), "Ultimatum au joueur : une proposition")
	_ok(Wars.kind_text(st, p).contains("tribut") or Wars.kind_text(st, p).contains("Payer"), "Ultimatum : texte de la proposition")
	var n := (st.vassals.get("trib", []) as Array).size()
	SimCommands.apply(st, SimCommands.answer_proposal(0, int(p["id"]), true))
	_ok((st.vassals.get("trib", []) as Array).size() == n + 1, "Ultimatum accepté : tribut")


func _test_crisis() -> void:
	var st := _new()
	var a := _by(st, "ferrocornes")
	var d := 0
	var sid := _fief(st, d)
	Wars.claim(st, a, sid)
	var s := "revendication|conquete"
	var cmd := SimCommands.war_act(a, "crisis", d, s)
	_ok(SimCommands.validate(st, cmd) == "", "Crise possible (%s)" % SimCommands.validate(st, cmd))
	_ok(SimCommands.validate(st, SimCommands.war_act(a, "crisis", d, "agression|kanly")) != "", "Crise : motif et but vérifiés")
	SimCommands.apply(st, cmd)
	var rec := WarLaws.crisis_between(st, a, d)
	_ok(not rec.is_empty() and int(rec["end"]) == st.tick + 30, "Crise : trente jours d'escalade")
	_ok(not Combat.at_war(st, a, d), "Crise : pas encore la guerre")
	_ok(SimCommands.validate(st, SimCommands.war_act(a, "crisis", d, s)) != "", "Crise : une seule à la fois")
	# Le joueur rallie un tiers (IA) : il accepte selon son estime.
	var t := -1
	for x in WarLaws.rally_candidates(st, rec, d):
		t = x
		break
	_ok(t >= 0, "Crise : des tiers à rallier")
	Diplomacy.sign_treaty(st, d, t, Diplomacy.PEACE)
	Diplomacy.sign_treaty(st, d, t, Diplomacy.ALLIANCE)
	_ok(WarLaws.ai_rally_accepts(st, rec, d, t), "Crise : un allié se rallie")
	SimCommands.apply(st, SimCommands.war_act(d, "rally", t, str(a)))
	_ok((rec["rd"] as Array).has(t), "Crise : le tiers est rallié au défenseur")
	# Le joueur (défenseur) recule : il cède le but.
	SimCommands.apply(st, SimCommands.war_act(d, "backdown", a))
	_ok(WarLaws.crisis_between(st, a, d).is_empty() and not Combat.at_war(st, a, d), "Recul : crise close, sans guerre")
	_ok(st.system_owner(sid) == a, "Recul du défenseur : il cède les revendications")
	_ok(Diplomacy.in_truce(st, a, d), "Recul : trêve")
	_ok(_has_mem(st, d, a, "crisis_backdown"), "Recul : souvenir")
	# L'agresseur recule : il abandonne ses revendications.
	var st2 := _new()
	var sid2 := _fief(st2, d)
	Wars.claim(st2, a, sid2)
	st2.get_empire(a).ai_level = ""
	SimCommands.apply(st2, SimCommands.war_act(a, "crisis", d, s))
	var inf := int(st2.get_empire(a).resources["influence"])
	SimCommands.apply(st2, SimCommands.war_act(a, "backdown", d))
	_ok(not Wars.has_claim(st2, a, sid2) and int(st2.get_empire(a).resources["influence"]) == inf - 50, "Recul de l'agresseur : revendications et prestige perdus")


func _test_escalation() -> void:
	var st := _new()
	var a := 0
	var d := _by(st, "teyl")
	var t := _by(st, "brisecomete")
	var sid := _fief(st, d)
	Wars.claim(st, a, sid)
	SimCommands.apply(st, SimCommands.war_act(a, "crisis", d, "revendication|conquete"))
	var rec := WarLaws.crisis_between(st, a, d)
	(rec["ra"] as Array).append(t)
	_arm(st, d, 2)
	st.tick = int(rec["end"])
	# Défenseur IA contre camp à peu près égal : la guerre éclate, ralliés compris.
	var pa := WarLaws.camp_power(st, rec, a)
	var pd := WarLaws.camp_power(st, rec, d)
	WarLaws.daily(st)
	if pa * 100 >= pd * 150:
		_ok(not Combat.at_war(st, a, d) and st.system_owner(sid) == a, "Échéance : l'IA recule devant un camp bien plus fort")
	else:
		var w := Wars.war(st, a, d)
		_ok(Combat.at_war(st, a, d) and String(w.get("cb", "")) == "revendication" and String(w.get("ga", "")) == "conquete", "Échéance : la guerre éclate avec le motif et le but de la crise")
		_ok(Combat.at_war(st, t, d) and Wars.war(st, t, d).has("lead"), "Échéance : le rallié entre en guerre dans le camp")
	_ok(WarLaws.crisis_between(st, a, d).is_empty(), "Échéance : crise close")


func _test_prep() -> void:
	var st := _new()
	var a := _by(st, "ferrocornes")
	var b := 0
	var spy := _by(st, "choeur")
	var seer := _by(st, "teyl")
	st.networks[Espionage.key(spy, a)] = {"a": spy, "b": a, "inf": 100, "cells": 1}
	var n := st.chronicle.size()
	SimCommands.apply(st, SimCommands.war_act(a, "prep", b))
	var p := WarLaws.seen_prep(st, spy, a)
	_ok(not p.is_empty() and int(p["b"]) == b, "Préavis : un réseau d'espions le voit")
	_ok(not WarLaws.seen_prep(st, seer, a).is_empty(), "Préavis : la Prévision le voit sans espions")
	_ok(WarLaws.seen_prep(st, 0, a).is_empty(), "Préavis : la cible sans espions ne voit rien")
	_ok(st.chronicle.size() > n and WarLaws.warnings(st, spy).size() == 1, "Préavis : alerte dans la chronique")
	_ok(not WarLaws.prepared(st, a, b, 1), "Préavis : pas encore prêt")
	st.tick += WarLaws.prep_days(1)
	_ok(WarLaws.prepared(st, a, b, 1) and not WarLaws.prepared(st, a, spy, 1), "Préavis : prêt après le délai, contre la même cible")
	_ok(WarLaws.prep_days(0) > WarLaws.prep_days(1) and WarLaws.prep_days(1) > WarLaws.prep_days(2), "Préavis : la Recrue met plus longtemps")
	SimCommands.apply(st, SimCommands.declare_war(a, b))
	_ok(WarLaws.seen_prep(st, spy, a).is_empty(), "Préavis : oublié une fois la guerre déclarée")


func _test_kanly() -> void:
	var st := _new()
	var a := _by(st, "ossarane")
	var b := _by(st, "teyl")
	_ok(Wars.casus_list(st, a, b).has("kanly") and not Wars.casus_list(st, b, a).has("kanly"), "Kanly : talent des peuples féodaux")
	Diplomacy.sign_treaty(st, a, b, Diplomacy.PEACE)
	Diplomacy._rel_w(st, a, b)["truce"] = 0
	var third := _by(st, "choeur")
	SimCommands.apply(st, SimCommands.declare_war(a, b, "kanly", "kanly"))
	var rec := Wars.war(st, a, b)
	_ok(bool(rec.get("lim", false)) and String(rec["gd"]) == "kanly", "Kanly : guerre limitée, but apparié")
	_ok(not _has_mem(st, third, a, "oathbreaker") and not _has_mem(st, b, a, "broke_treaty"), "Kanly : ni parjure ni réprobation")
	_ok(int(rec["exm"][0]) == 50, "Kanly : lassitude de moitié")
	var sid := _fief(st, b)
	var f := st.spawn_ship(a, "corvette", sid)
	f.troops = 50
	st.garrisons[sid] = 0
	var why := SimCommands.validate(st, SimCommands.invade(a, f.id))
	_ok(why.contains("limitée"), "Kanly : pas de débarquement sur un monde peuplé (%s)" % why)
	rec["t"] = st.tick - 400
	Wars.on_battle(st, a, b, 100000)
	var ia := int(st.get_empire(a).resources["influence"])
	var owned := EmpireReport.owned_systems(st, b).size()
	Wars.apply_victory(st, a, b)
	_ok(int(st.get_empire(a).resources["influence"]) == ia + 60, "Kanly gagné : 60 influence")
	_ok(EmpireReport.owned_systems(st, b).size() == owned and _has_mem(st, b, a, "kanly_lost"), "Kanly gagné : rien n'est cédé, on s'en souvient")
	# L'IA féodale préfère le kanly à l'agression.
	var st2 := _new()
	var c := _by(st2, "choeur")
	var ch := Wars.auto_choice(st2, a, c)
	_ok(String(ch[0]) == "kanly" or not bool(Wars.casus_def(String(ch[0])).get("aggression", false)), "IA féodale : le kanly plutôt que l'agression (%s)" % [ch])


func _test_talents() -> void:
	var st := _new()
	var oss := _by(st, "ossarane")
	var fer := _by(st, "ferrocornes")
	var b := _by(st, "teyl")
	_ok(WarLaws.talent_labels(st, oss).size() >= 1 and WarLaws.talent_labels(st, _by(st, "khthari")).size() >= 1, "Talents : chaque peuple de départ en a un")
	var sid := _fief(st, b)
	_ok(WarLaws.claim_pct(st, oss) == 50, "Ossarane : revendications à moitié prix")
	_ok(WarLaws.has_talent(st, _by(st, "choeur"), "crusade") and WarLaws.has_talent(st, 0, "mediate") and WarLaws.has_talent(st, b, "foresight"), "Talents : croisade, médiation, prévision")
	# Croisade : guerre sainte à demi-lassitude.
	var ch := _by(st, "choeur")
	SimCommands.apply(st, SimCommands.declare_war(ch, b, "agression", "humiliation"))
	var rec := Wars.war(st, ch, b)
	rec["cb"] = "guerre_sainte"
	_ok(WarLaws._ex_pct(st, rec, ch) == 50 and WarLaws._ex_pct(st, rec, b) == 100, "Croisade : lassitude de moitié en guerre sainte")
	# Razzias : rançon moitié plus grosse.
	var st2 := _new()
	var v := _by(st2, "brisecomete")
	SimCommands.apply(st2, SimCommands.declare_war(fer, v, "agression", "rancon"))
	Wars.war(st2, fer, v)["t"] = st2.tick - 400
	var before := int(st2.get_empire(fer).resources["energy"])
	var stock := int(st2.get_empire(v).resources["energy"])
	Wars.apply_victory(st2, fer, v)
	var gain := int(st2.get_empire(fer).resources["energy"]) - before
	_ok(gain > stock * int(Wars.data()["ransom"]["repar_pct"]) / 100, "Razzias : la rançon prend moitié plus (%d)" % gain)
	_ok(sid >= 0, "Talents : système de test")


func _test_mediation() -> void:
	var st := _new()
	var a := _by(st, "ferrocornes")
	var b := _by(st, "teyl")
	SimCommands.apply(st, SimCommands.declare_war(a, b, "agression", "humiliation"))
	var cmd := SimCommands.war_act(0, "mediate", a, str(b))
	_ok(SimCommands.validate(st, cmd).contains("tôt"), "Médiation : pas avant six mois")
	Wars.war(st, a, b)["t"] = st.tick - 200
	_ok(SimCommands.validate(st, cmd) == "", "Médiation possible (%s)" % SimCommands.validate(st, cmd))
	_ok(SimCommands.validate(st, SimCommands.war_act(_by(st, "choeur"), "mediate", a, str(b))) != "", "Médiation : talent des républiques")
	SimCommands.apply(st, cmd)
	_ok(not Combat.at_war(st, a, b) and _has_mem(st, a, 0, "mediated") and _has_mem(st, b, 0, "mediated"), "Médiation : paix et reconnaissance des deux camps")
	_ok(String(WarPeace.treaties_of(st, a)[0]["kind"]).contains("statu"), "Médiation : statu quo au registre")


func _test_nomos() -> void:
	var st := _new(7, {"amphictyony": "active"})
	_ok(Amphictyony.family_available(st, "droit"), "Nomos : famille Droit de la guerre")
	var st0 := _new(7, {"amphictyony": "active", "wargoals": "aucuns"})
	_ok(not Amphictyony.family_available(st0, "droit"), "Nomos : sans buts de guerre, pas de droit de la guerre")
	var ms: Array[int] = []
	for e in st.empires:
		if Amphictyony.eligible(st, e.id):
			ms.append(e.id)
	st.tick = maxi(st.tick, int(Amphictyony.data()["found"]["min_day"]))
	var added: Array[Dictionary] = []
	Amphictyony.monthly(st, added)
	for i in 3:
		Amphictyony.found_sign(st, ms[i])
	for i in range(3, ms.size()):
		Amphictyony.join(st, ms[i])
	_ok(Amphictyony.founded(st), "Nomos : Amphictyonie fondée")
	st.amph["fam"]["droit"] = 3
	_ok(Amphictyony.banned(st, "hero_execution") and Amphictyony.banned(st, "invade_populated"), "Lois de la guerre : prisonniers et mondes protégés")
	var a := ms[1]
	var b := ms[2]
	SimCommands.apply(st, SimCommands.declare_war(a, b, "agression", "humiliation"))
	_ok(bool(Wars.war(st, a, b).get("lim", false)), "Guerre réglée : guerre limitée entre amphictyons")
	# Crime de guerre : exécuter un héros prisonnier.
	var hid := Heroes.recruit(st, b, Heroes.make_candidate(st, b, "orateur", ["crime"]))
	st.heroes[hid]["jailer"] = a
	Heroes.prisoner(st, a, hid, "execute")
	_ok(Amphictyony.outlaw(st, a) and Amphictyony.casus(st, ms[3], a), "Crime de guerre : hors-la-loi, motif pour tous")
	_ok(_has_mem(st, ms[3], a, "war_crime"), "Crime de guerre : souvenir chez les membres")
	# Agression condamnée.
	var c := ms[3]
	var d := ms[4] if ms.size() > 4 else ms[0]
	var n := 0
	SimCommands.apply(st, SimCommands.declare_war(c, d, "agression", "humiliation"))
	for m in Amphictyony.members(st):
		if m != c and _has_mem(st, m, c, "amph_condemned"):
			n += 1
	_ok(n > 0, "Agression sans motif : condamnée par l'Amphictyonie")
	# Raison d'État : lassitude réduite.
	st.amph["fam"]["droit"] = -2
	_ok(Amphictyony.level_sum(st, "war_ex_pct") == -20, "Raison d'État : lassitude -10 %% par niveau")


func _test_guarantee() -> void:
	var st := _new(7, {"amphictyony": "active"})
	var a := _by(st, "ferrocornes")
	var b := _by(st, "teyl")
	var t := WarPeace.register(st, a, b, a, "reddition", {"dmz": st.tick + 1800}, "guerre test")
	_ok(SimCommands.validate(st, SimCommands.war_act(0, "guarantee", int(t["id"]))).contains("Arbitre"), "Garantie : réservée à l'Arbitre")
	st.amph["founded"] = st.tick
	t["g"] = 0
	WarLaws.on_violated(st, t, b)
	_ok(int((st.amph["casus"] as Dictionary).get(str(b), 0)) > st.tick, "Traité garanti violé : motif Défense commune contre le fautif")


func _test_secession() -> void:
	var st := _new()
	var a := _by(st, "ferrocornes")
	var b := _by(st, "teyl")
	WarLaws.on_secession(st, a, b)
	Combat.start_war(st, a, b)
	var rec := Wars.war(st, a, b)
	_ok(String(rec["cb"]) == "secession" and String(rec["ga"]) == "quitter" and String(rec["gd"]) == "retenir", "Sécession : buts Quitter et Retenir")
	_ok(not Wars.casus_list(st, a, b).has("secession"), "Sécession : jamais au menu")


func _test_spy() -> void:
	var st := _new()
	var a := _by(st, "ferrocornes")
	var b := _by(st, "teyl")
	var o := Espionage.op_def("fabriquer_revendication")
	_ok(not o.is_empty() and bool(o.get("war", false)), "Espionnage : Fabriquer une revendication")
	_ok(WarLaws.spy_check(st, a, b, "fabriquer_revendication") == "", "Fabriquer : possible")
	var before := Wars.claims_on(st, a, b).size()
	WarLaws.spy_apply(st, a, b, o)
	_ok(Wars.claims_on(st, a, b).size() == before + 1, "Fabriquer : une revendication gratuite")
	WarLaws.spy_apply(st, a, b, Espionage.op_def("provoquer_incident"))
	_ok(Wars.casus_list(st, a, b).has("incident") and WarLaws.spy_check(st, a, b, "provoquer_incident") != "", "Incident : motif de guerre")
	SimCommands.apply(st, SimCommands.declare_war(a, b, "incident", "rancon"))
	_ok(Wars.stability_parts(st, a).any(func(q: Array) -> bool: return String(q[0]) == "Guerre juste"), "Guerre juste : stabilité +1")
	var st0 := _new(7, {"wargoals": "aucuns"})
	_ok(WarLaws.spy_check(st0, a, b, "provoquer_incident") != "", "Espionnage : sans buts de guerre, pas d'incident")


func _test_heroes() -> void:
	var st := _new()
	var a := _by(st, "ferrocornes")
	var b := _by(st, "teyl")
	SimCommands.apply(st, SimCommands.declare_war(a, b, "agression", "humiliation"))
	var hb := Heroes.recruit(st, b, Heroes.make_candidate(st, b, "orateur", ["cap1"]))
	var ha := Heroes.recruit(st, a, Heroes.make_candidate(st, a, "orateur", ["cap2"]))
	st.heroes[hb]["jailer"] = a
	st.heroes[ha]["jailer"] = b
	var sp := Wars.score_parts(st, a, b)
	var found := false
	for p in sp["parts"]:
		if String(p[0]) == "Ses héros captifs":
			found = int(p[1]) == 8
	_ok(found, "Héros captif : compte au score")
	Wars.war(st, a, b)["t"] = st.tick - 400
	Wars.apply_victory(st, a, b)
	_ok(not Heroes.is_prisoner(st.heroes[ha]) and Heroes.is_prisoner(st.heroes[hb]), "Reddition : le vainqueur récupère ses héros, garde ceux du vaincu")
	# Diplomate : un orateur au conseil rend les clauses moins chères.
	var st2 := _new()
	var w := _by(st2, "ferrocornes")
	var l := _by(st2, "teyl")
	SimCommands.apply(st2, SimCommands.declare_war(w, l, "agression", "humiliation"))
	var p0 := Vassals.price(st2, l, {"repar": true}, w)
	var h := Heroes.recruit(st2, w, Heroes.make_candidate(st2, w, "orateur", ["dip"]))
	st2.heroes[h]["lvl"] = 3
	Heroes.assign(st2, w, h, "council", 0)
	st2.tick = maxi(st2.tick, int(st2.heroes[h]["arrive"]))
	_ok(WarLaws.diplomat_pct(st2, w) == 15, "Diplomate : 5 %% par niveau (%d)" % WarLaws.diplomat_pct(st2, w))
	_ok(Vassals.price(st2, l, {"repar": true}, w) < p0, "Diplomate : clauses moins chères")


func _test_ai() -> void:
	var st := _new()
	var a := _by(st, "ferrocornes")
	var b := _by(st, "teyl")
	# Médiation par l'IA républicaine.
	var st2 := _new()
	st2.get_empire(0).ai_level = "veteran"
	SimCommands.apply(st2, SimCommands.declare_war(a, b, "agression", "humiliation"))
	Wars.war(st2, a, b)["t"] = st2.tick - 200
	AiWars.think_state(st2, 0)
	_ok(not Combat.at_war(st2, a, b), "IA républicaine : elle s'offre en médiatrice")
	# Ultimatum de l'IA : sans guerre, contre plus faible qu'elle qu'elle n'aime pas.
	_arm(st, a, 40)
	var sid := _fief(st, b)
	Wars.claim(st, a, sid)
	for i in 6:
		Diplomacy.remember(st, a, b, "aggressor")
	st.tick += posmod(-(st.tick + a * 53), 360)
	AiWars.think_state(st, a)
	_ok(st.system_owner(sid) == a or WarLaws.has_ult_casus(st, a, b), "IA : ultimatum adressé")


func _test_save() -> void:
	var st := _new()
	var a := _by(st, "ferrocornes")
	var b := _by(st, "teyl")
	WarLaws._w(st)["ult"]["%d>%d" % [a, b]] = st.tick + 100
	WarLaws._w(st)["inc"]["%d>%d" % [b, a]] = st.tick + 100
	Wars.claim(st, a, _fief(st, 0))
	SimCommands.apply(st, SimCommands.war_act(a, "crisis", 0, "revendication|conquete"))
	SimCommands.apply(st, SimCommands.war_act(b, "prep", 0))
	var d := st.to_dict()
	_ok(int(d["version"]) >= 55, "Sauvegarde : version 55 ou plus")
	var st2 := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(st2 != null and WarLaws.has_ult_casus(st2, a, b) and WarLaws.has_incident(st2, b, a), "Sauvegarde : motifs Ultimatum et Incident")
	_ok(st2 != null and not WarLaws.crisis_between(st2, a, 0).is_empty() and (WarLaws.crisis_between(st2, a, 0)["ra"] is Array), "Sauvegarde : crise en cours")
	_ok(st2 != null and WarLaws.prepared(st2, b, 0, 0) == WarLaws.prepared(st, b, 0, 0) and not (st2.wars["prep"] as Dictionary).is_empty(), "Sauvegarde : préparations")
