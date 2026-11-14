class_name AmphInst
extends RefCounted
## Amphictyonie, lot 2 (étude « Conseil galactique », 2026-11-14) : institutions et crises.
## Règles : data/amphictyony.json (« institutions », « works »). Voir Amphictyony pour le cœur.
## - La Haute Voûte (Haut Conseil) : sièges aux plus fortes voix, veto, urgence, dénonciation.
## - L'Arbitre des étoiles : élu parmi les conseillers ; gel, clôture anticipée, trêve imposée.
## - Faveurs entre membres, observateurs, sessions extraordinaires et coalitions, aide d'urgence,
##   grands travaux (médailles), ambassadeurs (héros au poste « amph »).
##
## Clés de state.amph ajoutées au lot 2 :
## - "council" : {"seats", "members": [empires], "since", "reseat"} ({} sans Haute Voûte) ;
## - "arbiter" : {"eid", "until"} ; "den" : {empire: fin} (dénoncés) ; "cd" : {"acte:empire": jour} ;
## - "favors" : {"créancier>débiteur": n} ; "observers" : [empires] ;
## - "trig" : [{"id", "kind", "a", "b", "day", "used"}] (crises récentes) ;
## - "special" : {"trig", "kind", "target", "victim", "by", "start", "end", "votes"} (session extraordinaire) ;
## - "coal" : {"target", "victim", "members", "start", "end", "goal", "cap0", "sys0"} (coalition) ;
## - "aid" : {empire: {"res", "need", "got", "end"}} ; "work" : {"id", "start", "end", "got": {empire: n}} ;
## - "done" : [{"id", "day", "medals": [or, argent, bronze]}] (grands travaux achevés).
## - en séance : "calls" {débiteur: créancier} (faveurs appelées), "bribe" {cible: espion} (délégué acheté).

const INST_KINDS := ["council", "council_size", "arbiter", "extend", "defiance", "work"]


static func idata() -> Dictionary:
	return Amphictyony.data()["institutions"]


static func _a(state: GameState) -> Dictionary:
	return state.amph


static func _name(state: GameState, eid: int) -> String:
	var e := state.get_empire(eid)
	return e.display_name() if e != null else "?"


static func _audience(state: GameState, extra: Array = []) -> Array:
	return Amphictyony.members(state) + observers(state) + extra


static func _cd_left(state: GameState, act: String, eid: int) -> int:
	return maxi(0, int((_a(state)["cd"] as Dictionary).get("%s:%d" % [act, eid], 0)) - state.tick)


static func _set_cd(state: GameState, act: String, eid: int, days: int) -> void:
	_a(state)["cd"]["%s:%d" % [act, eid]] = state.tick + days


# --- Haute Voûte ---------------------------------------------------------------------------------

static func council_on(state: GameState) -> bool:
	return Amphictyony.founded(state) and not (_a(state)["council"] as Dictionary).is_empty()


static func councillors(state: GameState) -> Array[int]:
	var out: Array[int] = []
	if not council_on(state):
		return out
	for x in _a(state)["council"]["members"]:
		out.append(int(x))
	return out


static func is_councillor(state: GameState, eid: int) -> bool:
	return councillors(state).has(eid)


static func seats(state: GameState) -> int:
	return int(_a(state)["council"].get("seats", 0)) if council_on(state) else 0


## Les sièges vont aux plus fortes voix de base (les hors-la-loi n'y siègent pas).
static func _reseat(state: GameState) -> void:
	var c: Dictionary = _a(state)["council"]
	var ranked: Array[int] = []
	for m in Amphictyony.members(state):
		if not Amphictyony.outlaw(state, m):
			ranked.append(m)
	ranked.sort_custom(func(x: int, y: int) -> bool:
		var vx := Amphictyony.base_voix(state, x)
		var vy := Amphictyony.base_voix(state, y)
		return vx > vy if vx != vy else x < y)
	var out: Array = []
	for m in ranked:
		if out.size() < int(c["seats"]):
			out.append(m)
	out.sort()
	c["members"] = out
	c["reseat"] = state.tick + int(idata()["council"]["reseat_days"])
	if arbiter(state) >= 0 and not out.has(arbiter(state)):
		_a(state)["arbiter"] = {}
	state.relic_rev += 1


static func check_veto(state: GameState, eid: int) -> String:
	if not is_councillor(state, eid):
		return "seuls les conseillers de la Haute Voûte ont un veto"
	if not Amphictyony.in_session(state):
		return "aucun vote en cours"
	if int(Amphictyony.session(state)["prop"]["by"]) == eid:
		return "on ne met pas son veto à sa propre proposition"
	var left := _cd_left(state, "veto", eid)
	if left > 0:
		return "votre veto revient dans %d jours" % left
	return ""


static func veto(state: GameState, eid: int) -> void:
	_set_cd(state, "veto", eid, int(idata()["council"]["veto_cd"]))
	var added: Array[Dictionary] = []
	Amphictyony._close_session(state, added, eid)


static func check_urgent(state: GameState, eid: int, pid: int) -> String:
	if not is_councillor(state, eid):
		return "seuls les conseillers de la Haute Voûte peuvent presser un vote"
	if Amphictyony.in_session(state):
		return "un vote est déjà en cours"
	var p := _queued(state, pid)
	if p.is_empty():
		return "proposition inconnue"
	if not Amphictyony.still_valid(state, p):
		return "cette proposition n'a plus d'objet"
	var left := _cd_left(state, "urgent", eid)
	if left > 0:
		return "la procédure d'urgence revient dans %d jours" % left
	return ""


static func urgent(state: GameState, eid: int, pid: int) -> void:
	_set_cd(state, "urgent", eid, int(idata()["council"]["urgent_cd"]))
	state.add_chronicle("%s invoque l'urgence sous la Haute Voûte : le vote s'ouvre sur-le-champ." % _name(state, eid), Espionage.public_to(state, _audience(state)))
	var added: Array[Dictionary] = []
	Amphictyony._open_session(state, added, pid)


static func _queued(state: GameState, pid: int) -> Dictionary:
	for p: Dictionary in _a(state)["queue"]:
		if int(p["id"]) == pid:
			return p
	return {}


static func denounced(state: GameState, eid: int) -> bool:
	return state.amph_on and int((_a(state)["den"] as Dictionary).get(str(eid), 0)) > state.tick


static func denounce_cost() -> Dictionary:
	return (idata()["council"]["denounce"]["cost"] as Dictionary).duplicate()


static func check_denounce(state: GameState, eid: int, target: int) -> String:
	if not is_councillor(state, eid):
		return "seuls les conseillers de la Haute Voûte dénoncent"
	var t := state.get_empire(target)
	if t == null or t.eliminated or t.is_npc() or target == eid:
		return "cible inconnue"
	if not state.get_empire(eid).contacts.has(target):
		return "empire jamais rencontré"
	if denounced(state, target):
		return "déjà dénoncé"
	var left := _cd_left(state, "denounce", eid)
	if left > 0:
		return "vous pourrez dénoncer de nouveau dans %d jours" % left
	if not Economy.can_afford(state.get_empire(eid), denounce_cost()):
		return "il faut %s" % GameData.format_amounts(denounce_cost())
	return ""


static func denounce(state: GameState, eid: int, target: int) -> void:
	var dd: Dictionary = idata()["council"]["denounce"]
	Economy.pay(state.get_empire(eid), denounce_cost())
	_set_cd(state, "denounce", eid, int(dd["cd"]))
	_a(state)["den"][str(target)] = state.tick + int(dd["days"])
	Diplomacy.remember(state, target, eid, "amph_denounced")
	state.add_chronicle("%s dénonce %s sous la Haute Voûte. Pendant 5 ans, les amphictyons pourront voter des sanctions contre lui." % [_name(state, eid), _name(state, target)],
			Espionage.public_to(state, _audience(state, [target])))


# --- Arbitre des étoiles ---------------------------------------------------------------------------

static func arbiter(state: GameState) -> int:
	if not council_on(state):
		return -1
	var ar: Dictionary = _a(state)["arbiter"]
	if ar.is_empty() or int(ar.get("until", 0)) <= state.tick:
		return -1
	return int(ar["eid"])


static func arbiter_until(state: GameState) -> int:
	return int((_a(state)["arbiter"] as Dictionary).get("until", 0))


static func check_freeze(state: GameState, eid: int, pid: int) -> String:
	if arbiter(state) != eid:
		return "seul l'Arbitre des étoiles gèle une proposition"
	var p := _queued(state, pid)
	if p.is_empty():
		return "proposition inconnue"
	if int(p.get("frozen", 0)) > state.tick:
		return "déjà gelée"
	var left := _cd_left(state, "arb", eid)
	if left > 0:
		return "l'Arbitre agira de nouveau dans %d jours" % left
	return ""


static func freeze(state: GameState, eid: int, pid: int) -> void:
	var ad: Dictionary = idata()["arbiter"]
	_set_cd(state, "arb", eid, int(ad["cd"]))
	var p := _queued(state, pid)
	p["frozen"] = state.tick + int(ad["freeze_days"])
	state.add_chronicle("L'Arbitre des étoiles (%s) gèle pour deux ans une proposition : %s." % [_name(state, eid), Amphictyony.prop_label(state, p)], Espionage.public_to(state, _audience(state)))


static func check_close(state: GameState, eid: int) -> String:
	if arbiter(state) != eid:
		return "seul l'Arbitre des étoiles clôt un vote plus tôt"
	if not Amphictyony.in_session(state):
		return "aucun vote en cours"
	var left := _cd_left(state, "arb", eid)
	if left > 0:
		return "l'Arbitre agira de nouveau dans %d jours" % left
	return ""


static func close(state: GameState, eid: int) -> void:
	_set_cd(state, "arb", eid, int(idata()["arbiter"]["cd"]))
	state.add_chronicle("L'Arbitre des étoiles (%s) frappe la table : le vote est clos." % _name(state, eid), Espionage.public_to(state, _audience(state)))
	var added: Array[Dictionary] = []
	Amphictyony._close_session(state, added)


static func truce_cost() -> Dictionary:
	return (idata()["arbiter"]["truce_cost"] as Dictionary).duplicate()


static func check_truce(state: GameState, eid: int, a: int, b: int) -> String:
	if arbiter(state) != eid:
		return "seul l'Arbitre des étoiles impose une trêve"
	if a == b or not Amphictyony.is_member(state, a) or not Amphictyony.is_member(state, b):
		return "la trêve ne lie que deux amphictyons"
	if not Combat.at_war(state, a, b):
		return "ces deux membres ne sont pas en guerre"
	var left := _cd_left(state, "arb", eid)
	if left > 0:
		return "l'Arbitre agira de nouveau dans %d jours" % left
	if not Economy.can_afford(state.get_empire(eid), truce_cost()):
		return "il faut %s" % GameData.format_amounts(truce_cost())
	return ""


static func truce(state: GameState, eid: int, a: int, b: int) -> void:
	Economy.pay(state.get_empire(eid), truce_cost())
	_set_cd(state, "arb", eid, int(idata()["arbiter"]["cd"]))
	state.add_chronicle("L'Arbitre des étoiles (%s) impose une trêve à %s et %s. Les amiraux rangent les cartes en maugréant." % [_name(state, eid), _name(state, a), _name(state, b)],
			Espionage.public_to(state, _audience(state)))
	Diplomacy.sign_treaty(state, a, b, Diplomacy.PEACE)


# --- Faveurs ---------------------------------------------------------------------------------------

static func favors(state: GameState, creditor: int, debtor: int) -> int:
	return int((_a(state)["favors"] as Dictionary).get("%d>%d" % [creditor, debtor], 0))


static func add_favor(state: GameState, creditor: int, debtor: int, n: int) -> void:
	if creditor == debtor or n == 0:
		return
	var k := "%d>%d" % [creditor, debtor]
	var v := clampi(favors(state, creditor, debtor) + n, 0, int(idata()["favors"]["max"]))
	if v <= 0:
		(_a(state)["favors"] as Dictionary).erase(k)
	else:
		_a(state)["favors"][k] = v


## Débiteurs de eid : [[débiteur, n]] triés par empire.
static func debtors(state: GameState, eid: int) -> Array:
	var out: Array = []
	var ks := (_a(state)["favors"] as Dictionary).keys()
	ks.sort()
	for k in ks:
		var parts := String(k).split(">")
		if int(parts[0]) == eid:
			out.append([int(parts[1]), int(_a(state)["favors"][k])])
	return out


static func check_call(state: GameState, eid: int, debtor: int) -> String:
	if not Amphictyony.in_session(state):
		return "aucun vote en cours"
	if Amphictyony.vote_of(state, eid) == 0:
		return "votez d'abord pour ou contre"
	if not Amphictyony.is_member(state, debtor):
		return "il ne siège pas"
	if favors(state, eid, debtor) <= 0:
		return "il ne vous doit rien"
	if (Amphictyony.session(state).get("calls", {}) as Dictionary).has(str(debtor)):
		return "sa faveur est déjà appelée pour ce vote"
	return ""


static func call_favor(state: GameState, eid: int, debtor: int) -> void:
	var s := Amphictyony.session(state)
	if not s.has("calls"):
		s["calls"] = {}
	s["calls"][str(debtor)] = eid
	add_favor(state, eid, debtor, -1)


# --- Observateurs ----------------------------------------------------------------------------------

static func observers(state: GameState) -> Array[int]:
	var out: Array[int] = []
	if not state.amph_on:
		return out
	for x in _a(state)["observers"]:
		out.append(int(x))
	return out


static func is_observer(state: GameState, eid: int) -> bool:
	return observers(state).has(eid)


static func check_observe(state: GameState, eid: int) -> String:
	if not Amphictyony.founded(state):
		return "l'Amphictyonie n'est pas fondée"
	if is_observer(state, eid):
		return ""
	if Amphictyony.is_member(state, eid):
		return "vous siégez déjà"
	if not Amphictyony.eligible(state, eid):
		return "votre peuple ne siège pas dans les assemblées"
	for m in Amphictyony.members(state):
		if state.get_empire(eid).contacts.has(m):
			return ""
	return "vous n'avez rencontré aucun amphictyon"


## Prendre ou quitter le banc des observateurs.
static func observe(state: GameState, eid: int) -> void:
	var l: Array = _a(state)["observers"]
	if l.has(eid):
		l.erase(eid)
		return
	l.append(eid)
	l.sort()
	state.add_chronicle("%s prend place au banc des observateurs de %s : on écoute, on note, on ne vote pas." % [_name(state, eid), Amphictyony.name_short()],
			Espionage.public_to(state, _audience(state)))


# --- Crises et sessions extraordinaires ------------------------------------------------------------

static func crisis_label(state: GameState, t: Dictionary) -> String:
	var fmt := String(idata()["crisis"]["labels"].get(String(t["kind"]), "%s"))
	if fmt.count("%s") >= 2:
		return fmt % [_name(state, int(t["a"])), _name(state, int(t["b"]))]
	return fmt % _name(state, int(t["a"]))


static func add_trig(state: GameState, kind: String, a: int, b: int) -> void:
	if not Amphictyony.founded(state) or GameState.is_npc(a):
		return
	var a2: Dictionary = _a(state)
	var tid := int(a2["next_id"])
	a2["next_id"] = tid + 1
	(a2["trig"] as Array).append({"id": tid, "kind": kind, "a": a, "b": b, "day": state.tick, "used": false})


static func on_capital(state: GameState, taker: int, victim: int) -> void:
	if GameState.is_npc(victim):
		return
	add_trig(state, "capital", taker, victim)


static func on_holy_war(state: GameState, a: int, b: int) -> void:
	add_trig(state, "holy_war", a, b)


static func trig(state: GameState, tid: int) -> Dictionary:
	for t: Dictionary in _a(state)["trig"]:
		if int(t["id"]) == tid:
			return t
	return {}


## Crises qu'on peut encore porter devant une session extraordinaire.
static func open_trigs(state: GameState) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not Amphictyony.founded(state):
		return out
	for t: Dictionary in _a(state)["trig"]:
		var tg := state.get_empire(int(t["a"]))
		if not bool(t["used"]) and tg != null and not tg.eliminated:
			out.append(t)
	return out


static func special_on(state: GameState) -> bool:
	return Amphictyony.founded(state) and not (_a(state)["special"] as Dictionary).is_empty()


static func coal_on(state: GameState) -> bool:
	return Amphictyony.founded(state) and not (_a(state)["coal"] as Dictionary).is_empty()


static func convene_cost() -> Dictionary:
	return (idata()["crisis"]["convene_cost"] as Dictionary).duplicate()


static func check_convene(state: GameState, eid: int, tid: int) -> String:
	if not Amphictyony.founded(state):
		return "l'Amphictyonie n'est pas fondée"
	var t := trig(state, tid)
	if t.is_empty() or bool(t["used"]):
		return "crise inconnue ou déjà portée devant l'assemblée"
	if not Amphictyony.is_member(state, eid) and not (is_observer(state, eid) and int(t["b"]) == eid):
		return "seuls les membres, ou la victime au banc des observateurs, convoquent"
	if int(t["a"]) == eid:
		return "on ne se convoque pas soi-même"
	var tg := state.get_empire(int(t["a"]))
	if tg == null or tg.eliminated:
		return "le fautif n'existe plus"
	if special_on(state):
		return "une session extraordinaire siège déjà"
	if coal_on(state):
		return "une coalition est déjà en campagne"
	if not Economy.can_afford(state.get_empire(eid), convene_cost()):
		return "il faut %s" % GameData.format_amounts(convene_cost())
	return ""


static func convene(state: GameState, eid: int, tid: int) -> void:
	Economy.pay(state.get_empire(eid), convene_cost())
	var t := trig(state, tid)
	t["used"] = true
	var votes := {}
	if Amphictyony.is_member(state, eid):
		votes[str(eid)] = 1
	_a(state)["special"] = {"trig": tid, "kind": String(t["kind"]), "target": int(t["a"]), "victim": int(t["b"]), "by": eid,
			"start": state.tick, "end": state.tick + int(idata()["crisis"]["vote_days"]), "votes": votes}
	state.add_chronicle("Session extraordinaire de %s, convoquée par %s : %s. Faut-il former une coalition ? Vote en 2 mois ; voter pour, c'est s'engager." % [
			Amphictyony.name_short(), _name(state, eid), crisis_label(state, t)], Espionage.public_to(state, _audience(state, [int(t["a"])])))


static func special(state: GameState) -> Dictionary:
	return _a(state)["special"]


static func svote_of(state: GameState, eid: int) -> int:
	if not special_on(state):
		return 0
	return int((special(state)["votes"] as Dictionary).get(str(eid), 0))


static func check_svote(state: GameState, eid: int, v: int) -> String:
	if not special_on(state):
		return "aucune session extraordinaire"
	if not Amphictyony.is_member(state, eid):
		return "seuls les amphictyons votent"
	if eid == int(special(state)["target"]):
		return "le fautif ne vote pas sur son propre sort"
	if v < -1 or v > 1:
		return "vote inconnu"
	return ""


static func svote(state: GameState, eid: int, v: int) -> void:
	var votes: Dictionary = special(state)["votes"]
	if v == 0:
		votes.erase(str(eid))
	else:
		votes[str(eid)] = v


static func stally(state: GameState) -> Dictionary:
	var out := {"pour": 0, "contre": 0}
	if not special_on(state):
		return out
	for k in special(state)["votes"]:
		var v := int(special(state)["votes"][k])
		var w := Amphictyony.weight(state, int(k))
		if v > 0:
			out["pour"] = int(out["pour"]) + w
		elif v < 0:
			out["contre"] = int(out["contre"]) + w
	return out


static func _close_special(state: GameState, added: Array[Dictionary]) -> void:
	var s: Dictionary = special(state)
	var t := stally(state)
	var target := int(s["target"])
	var tg := state.get_empire(target)
	_a(state)["special"] = {}
	var passed := int(t["pour"]) > int(t["contre"]) and tg != null and not tg.eliminated
	if not passed:
		added.append(state.add_chronicle("La session extraordinaire se sépare sans coalition (%d voix pour, %d contre). %s respire." % [int(t["pour"]), int(t["contre"]), _name(state, target)],
				Espionage.public_to(state, _audience(state, [target]))))
		return
	var cd: Dictionary = idata()["crisis"]
	var ms: Array = []
	for k in s["votes"]:
		if int(s["votes"][k]) > 0 and Amphictyony.is_member(state, int(k)):
			ms.append(int(k))
	var victim := int(s["victim"])
	var ve := state.get_empire(victim)
	if victim >= 0 and victim != target and ve != null and not ve.eliminated and not ms.has(victim):
		ms.append(victim)
	ms.sort()
	var goal := "capital" if String(s["kind"]) == "capital" else "half"
	_a(state)["casus"][str(target)] = state.tick + int(cd["coalition_days"])
	_a(state)["coal"] = {"target": target, "victim": victim, "members": ms, "start": state.tick, "end": state.tick + int(cd["coalition_days"]),
			"goal": goal, "cap0": FactionTraits.capital_system(state, target), "sys0": Stability.systems_of(state, target).size()}
	state.relic_rev += 1
	var names := PackedStringArray()
	for m in ms:
		names.append(_name(state, m))
		if Combat.at_war(state, m, target) or not state.get_empire(m).contacts.has(target):
			continue
		if Diplomacy.check_war(state, m, target) != "":
			continue
		Combat.start_war(state, m, target)
	added.append(state.add_chronicle("Coalition de %s contre %s : %s. But : %s, en 5 ans au plus." % [Amphictyony.name_short(), _name(state, target), ", ".join(names),
			String(cd["goals"][goal])], Espionage.public_to(state, _audience(state, [target]))))


static func coal(state: GameState) -> Dictionary:
	return _a(state)["coal"]


static func in_coalition(state: GameState, eid: int) -> bool:
	return coal_on(state) and (coal(state)["members"] as Array).has(eid)


static func _coal_success(state: GameState) -> bool:
	var c := coal(state)
	var tg := state.get_empire(int(c["target"]))
	if tg == null or tg.eliminated:
		return true
	if String(c["goal"]) == "capital":
		var cap := int(c["cap0"])
		return cap >= 0 and state.system_owner(cap) != int(c["target"])
	@warning_ignore("integer_division")
	return Stability.systems_of(state, int(c["target"])).size() * 2 <= int(c["sys0"])


static func _check_coal(state: GameState, added: Array[Dictionary]) -> void:
	if not coal_on(state):
		return
	var c := coal(state)
	var cd: Dictionary = idata()["crisis"]
	var target := int(c["target"])
	if _coal_success(state):
		var ms: Array = c["members"]
		for m in ms:
			var e := state.get_empire(m)
			if e == null or e.eliminated:
				continue
			for r in cd["win"]:
				e.resources[r] = int(e.resources.get(r, 0)) + int(cd["win"][r])
			for o in ms:
				if o != m:
					Diplomacy.remember(state, m, o, "amph_coalition")
					add_favor(state, m, target, int(idata()["favors"]["coalition"]))
		_a(state)["coal"] = {}
		state.relic_rev += 1
		added.append(state.add_chronicle("La coalition de %s atteint son but contre %s. Médailles, banquets, et une plaque de plus sous la voûte." % [Amphictyony.name_short(), _name(state, target)],
				Espionage.public_to(state, _audience(state, [target]))))
	elif state.tick >= int(c["end"]):
		var te := state.get_empire(target)
		if te != null and not te.eliminated:
			for r in cd["fail"]:
				te.resources[r] = int(te.resources.get(r, 0)) + int(cd["fail"][r])
		_a(state)["coal"] = {}
		state.relic_rev += 1
		added.append(state.add_chronicle("La coalition contre %s se disperse sans avoir atteint son but. Le fautif en sort grandi, et s'en vante." % _name(state, target),
				Espionage.public_to(state, _audience(state, [target]))))


# --- Aide d'urgence --------------------------------------------------------------------------------

static func aid_of(state: GameState, eid: int) -> Dictionary:
	return (_a(state)["aid"] as Dictionary).get(str(eid), {})


static func check_aid_ask(state: GameState, eid: int, res: String) -> String:
	var ad: Dictionary = idata()["aid"]
	if not Amphictyony.founded(state):
		return "l'Amphictyonie n'est pas fondée"
	if not Amphictyony.is_member(state, eid) and not is_observer(state, eid):
		return "il faut siéger ou observer"
	if not (ad["res"] as Array).has(res):
		return "ressource inconnue"
	if not aid_of(state, eid).is_empty():
		return "votre appel court encore"
	if int(state.get_empire(eid).resources.get(res, 0)) >= int(ad["below"]):
		return "il faut être presque à sec (moins de %d)" % int(ad["below"])
	var left := _cd_left(state, "aid", eid)
	if left > 0:
		return "nouvel appel possible dans %d jours" % left
	return ""


static func aid_ask(state: GameState, eid: int, res: String) -> void:
	var ad: Dictionary = idata()["aid"]
	_set_cd(state, "aid", eid, int(ad["cd"]))
	_a(state)["aid"][str(eid)] = {"res": res, "need": int(ad["need"]), "got": 0, "end": state.tick + int(ad["days"])}
	state.add_chronicle("%s lance un appel à l'aide devant %s : il lui faut %d %s." % [_name(state, eid), Amphictyony.name_short(), int(ad["need"]), GameData.resource_label(res)],
			Espionage.public_to(state, _audience(state)))


static func check_aid_give(state: GameState, eid: int, target: int, n: int) -> String:
	if not Amphictyony.is_member(state, eid):
		return "seuls les amphictyons secourent"
	var ai := aid_of(state, target)
	if ai.is_empty() or target == eid:
		return "aucun appel de cet empire"
	var step := int(idata()["aid"]["step"])
	if n <= 0 or n % step != 0:
		return "par tranches de %d" % step
	if n > int(ai["need"]) - int(ai["got"]):
		return "c'est plus qu'il ne demande"
	if int(state.get_empire(eid).resources.get(String(ai["res"]), 0)) < n:
		return "vous n'avez pas %d %s" % [n, GameData.resource_label(String(ai["res"]))]
	return ""


static func aid_give(state: GameState, eid: int, target: int, n: int) -> void:
	var ai := aid_of(state, target)
	var res := String(ai["res"])
	var e := state.get_empire(eid)
	var t := state.get_empire(target)
	e.resources[res] = int(e.resources.get(res, 0)) - n
	t.resources[res] = int(t.resources.get(res, 0)) + n
	ai["got"] = int(ai["got"]) + n
	@warning_ignore("integer_division")
	add_favor(state, eid, target, n / int(idata()["aid"]["step"]))
	Diplomacy.remember(state, target, eid, "amph_aided")
	if int(ai["got"]) >= int(ai["need"]):
		(_a(state)["aid"] as Dictionary).erase(str(target))
		state.add_chronicle("L'appel de %s est entendu : %d %s réunis par les amphictyons." % [t.display_name(), int(ai["got"]), GameData.resource_label(res)],
				Espionage.public_to(state, _audience(state)))


# --- Grands travaux --------------------------------------------------------------------------------

static func work_defs() -> Array:
	return Amphictyony.data()["works"]


static func work_def(wid: String) -> Dictionary:
	for w: Dictionary in work_defs():
		if String(w["id"]) == wid:
			return w
	return {}


static func work_done(state: GameState, wid: String) -> bool:
	for d: Dictionary in _a(state)["done"]:
		if String(d["id"]) == wid:
			return true
	return false


static func work_on(state: GameState) -> bool:
	return Amphictyony.founded(state) and not (_a(state)["work"] as Dictionary).is_empty()


static func work(state: GameState) -> Dictionary:
	return _a(state)["work"]


static func work_total(state: GameState) -> int:
	var n := 0
	if not work_on(state):
		return n
	for k in work(state)["got"]:
		n += int(work(state)["got"][k])
	return n


static func check_work_give(state: GameState, eid: int, n: int) -> String:
	if not Amphictyony.is_member(state, eid):
		return "seuls les amphictyons contribuent"
	if not work_on(state):
		return "aucun grand chantier en cours"
	var step := int(idata()["work_step"])
	if n <= 0 or n % step != 0:
		return "par tranches de %d" % step
	var w := work_def(String(work(state)["id"]))
	if int(state.get_empire(eid).resources.get(String(w["res"]), 0)) < n:
		return "vous n'avez pas %d %s" % [n, GameData.resource_label(String(w["res"]))]
	return ""


static func work_give(state: GameState, eid: int, n: int) -> void:
	var wk := work(state)
	var w := work_def(String(wk["id"]))
	var e := state.get_empire(eid)
	e.resources[String(w["res"])] = int(e.resources.get(String(w["res"]), 0)) - n
	wk["got"][str(eid)] = int(wk["got"].get(str(eid), 0)) + n
	if work_total(state) >= int(w["need"]):
		_finish_work(state)


static func _finish_work(state: GameState) -> void:
	var wk := work(state)
	var w := work_def(String(wk["id"]))
	var ranked: Array = (wk["got"] as Dictionary).keys()
	ranked.sort_custom(func(x: String, y: String) -> bool:
		var vx := int(wk["got"][x])
		var vy := int(wk["got"][y])
		return vx > vy if vx != vy else int(x) < int(y))
	var medals: Array = []
	for k in ranked:
		if medals.size() < (idata()["medals"] as Array).size():
			medals.append(int(k))
	(_a(state)["done"] as Array).append({"id": String(wk["id"]), "day": state.tick, "medals": medals})
	_a(state)["work"] = {}
	state.relic_rev += 1
	var gold := _name(state, int(medals[0])) if not medals.is_empty() else "?"
	state.add_chronicle("Grand chantier achevé : %s. Médaille d'or à %s, qui le rappellera à chaque séance." % [String(w["label"]), gold], Espionage.public_to(state, _audience(state)))


## Points de % de voix des médailles des grands travaux.
static func medal_pct(state: GameState, eid: int) -> int:
	var pct := 0
	var md: Array = idata()["medals"]
	for d: Dictionary in _a(state)["done"]:
		var i := (d["medals"] as Array).find(eid)
		if i >= 0 and i < md.size():
			pct += int(md[i])
	return pct


# --- Ambassadeurs ----------------------------------------------------------------------------------

static func ambassador(state: GameState, eid: int) -> Dictionary:
	return Heroes.at_post(state, "amph", 0, eid)


@warning_ignore("integer_division")
static func ambassador_pct(state: GameState, eid: int) -> int:
	var h := ambassador(state, eid)
	if h.is_empty() or not Amphictyony.is_member(state, eid):
		return 0
	var ad: Dictionary = idata()["ambassador"]
	var hl := int(h["lvl"]) * 2 if String(h["cls"]) == "orateur" else Heroes.half_levels(h, "amph")
	return mini(int(ad["max"]), int(ad["per_half"]) * hl)


# --- Propositions d'institutions -------------------------------------------------------------------

static func prop_cost(kind: String) -> Dictionary:
	var c: Dictionary = idata()["council"]
	var ad: Dictionary = idata()["arbiter"]
	match kind:
		"council":
			return {"influence": int(c["cost"])}
		"council_size":
			return {"influence": int(c["size_cost"])}
		"arbiter":
			return {"influence": int(ad["cost"])}
		"extend":
			return {"influence": int(ad["extend_cost"])}
		"defiance":
			return {"influence": int(ad["defiance_cost"])}
		"work":
			return {"influence": int(idata()["work_cost"])}
	return {}


static func check_prop(state: GameState, eid: int, kind: String, fam: String, dir: int, target: int) -> String:
	var c: Dictionary = idata()["council"]
	match kind:
		"council":
			if council_on(state):
				return "la Haute Voûte existe déjà"
			var left := int(_a(state)["founded"]) + int(c["after_days"]) - state.tick
			if left > 0:
				return "la Haute Voûte ne se bâtit qu'après 10 ans d'Amphictyonie (encore %d jours)" % left
		"council_size":
			if not council_on(state):
				return "il n'y a pas de Haute Voûte"
			var to := seats(state) + signi(dir)
			if dir == 0 or to < int(c["min"]) or to > int(c["max"]):
				return "entre %d et %d sièges" % [int(c["min"]), int(c["max"])]
			if to > Amphictyony.members(state).size():
				return "plus de sièges que de membres"
		"arbiter":
			if not council_on(state):
				return "il n'y a pas de Haute Voûte"
			if arbiter(state) >= 0:
				return "il y a déjà un Arbitre des étoiles"
			if not is_councillor(state, eid):
				return "seul un conseiller propose l'Arbitre"
			if not is_councillor(state, target):
				return "l'Arbitre est choisi parmi les conseillers"
		"extend", "defiance":
			if arbiter(state) < 0:
				return "il n'y a pas d'Arbitre des étoiles"
			if kind == "defiance" and arbiter(state) == eid:
				return "démissionnez plutôt"
		"work":
			var w := work_def(fam)
			if w.is_empty():
				return "grand chantier inconnu"
			if work_done(state, fam):
				return "déjà bâti"
			if work_on(state):
				return "un grand chantier est déjà ouvert"
		_:
			return "proposition inconnue"
	var pending: Array = (_a(state)["queue"] as Array).duplicate()
	if Amphictyony.in_session(state):
		pending.append(Amphictyony.session(state)["prop"])
	for p: Dictionary in pending:
		if String(p["kind"]) == kind and (kind != "work" or String(p["fam"]) == fam):
			return "la même proposition attend déjà"
		if kind == "work" and String(p["kind"]) == "work":
			return "un autre grand chantier attend déjà"
	return ""


static func make_fields(state: GameState, kind: String, fam: String, dir: int, target: int) -> Dictionary:
	match kind:
		"council_size":
			return {"from": seats(state), "to": seats(state) + signi(dir), "fam": "", "target": -1}
		"arbiter":
			return {"from": 0, "to": 0, "fam": "", "target": target}
		"extend", "defiance":
			return {"from": 0, "to": 0, "fam": "", "target": arbiter(state)}
		"work":
			return {"from": 0, "to": 0, "fam": fam, "target": -1}
	return {"from": 0, "to": 0, "fam": "", "target": -1}


static func prop_label(state: GameState, p: Dictionary) -> String:
	match String(p["kind"]):
		"council":
			return "bâtir la Haute Voûte (%d sièges)" % int(idata()["council"]["seats"])
		"council_size":
			return "porter la Haute Voûte à %d sièges" % int(p["to"])
		"arbiter":
			return "élire %s Arbitre des étoiles" % _name(state, int(p["target"]))
		"extend":
			return "prolonger le mandat de l'Arbitre (%s)" % _name(state, int(p["target"]))
		"defiance":
			return "motion de défiance contre l'Arbitre (%s)" % _name(state, int(p["target"]))
		"work":
			return "grand chantier : %s" % String(work_def(String(p["fam"])).get("label", "?"))
	return "?"


static func prop_text(_state: GameState, p: Dictionary) -> String:
	match String(p["kind"]):
		"council":
			return "Les plus fortes voix y siègent (redistribuées tous les 10 ans) : +20 % de voix, un veto et une procédure d'urgence par décennie, le droit de dénoncer."
		"council_size":
			return "Change le nombre de sièges de la Haute Voûte."
		"arbiter":
			return "Mandat de 15 ans : +30 % de voix ; peut geler une proposition, clore un vote plus tôt, imposer une trêve entre deux membres."
		"extend":
			return "Le mandat repart pour 15 ans."
		"defiance":
			return "L'Arbitre perd sa charge."
		"work":
			var w := work_def(String(p["fam"]))
			return "%s Il faudra %d %s en 5 ans ; les trois plus gros donateurs reçoivent une médaille (voix en plus)." % [String(w.get("text", "")), int(w.get("need", 0)), GameData.resource_label(String(w.get("res", "")))]
	return ""


static func still_valid(state: GameState, p: Dictionary) -> bool:
	match String(p["kind"]):
		"council":
			return not council_on(state)
		"council_size":
			return council_on(state) and seats(state) == int(p["from"]) and int(p["to"]) <= Amphictyony.members(state).size()
		"arbiter":
			return council_on(state) and arbiter(state) < 0 and is_councillor(state, int(p["target"]))
		"extend", "defiance":
			return arbiter(state) >= 0 and arbiter(state) == int(p["target"])
		"work":
			return not work_on(state) and not work_done(state, String(p["fam"]))
	return false


static func apply_prop(state: GameState, p: Dictionary, added: Array[Dictionary]) -> void:
	var a: Dictionary = _a(state)
	match String(p["kind"]):
		"council":
			a["council"] = {"seats": int(idata()["council"]["seats"]), "members": [], "since": state.tick, "reseat": 0}
			_reseat(state)
			added.append(state.add_chronicle("La Haute Voûte est bâtie. Y siègent : %s." % _names(state, councillors(state)), Espionage.public_to(state, _audience(state))))
		"council_size":
			a["council"]["seats"] = int(p["to"])
			_reseat(state)
		"arbiter":
			a["arbiter"] = {"eid": int(p["target"]), "until": state.tick + int(idata()["arbiter"]["mandate_days"])}
			added.append(state.add_chronicle("%s devient Arbitre des étoiles pour 15 ans. On lui remet une toge trop grande et un marteau trop lourd." % _name(state, int(p["target"])),
					Espionage.public_to(state, _audience(state))))
		"extend":
			a["arbiter"]["until"] = state.tick + int(idata()["arbiter"]["mandate_days"])
		"defiance":
			a["arbiter"] = {}
		"work":
			a["work"] = {"id": String(p["fam"]), "start": state.tick, "end": state.tick + int(idata()["work_days"]), "got": {}}


static func _names(state: GameState, ids: Array) -> String:
	var n := PackedStringArray()
	for x in ids:
		n.append(_name(state, int(x)))
	return ", ".join(n)


# --- Opérations d'espionnage (data/espionage.json, drapeau « amph ») ---------------------------------

static func spy_check(state: GameState, a: int, b: int, op_id: String) -> String:
	if not Amphictyony.founded(state):
		return "il n'y a pas d'Amphictyonie"
	if not Amphictyony.is_member(state, b):
		return "la cible ne siège pas"
	match op_id:
		"acheter_delegue":
			if not Amphictyony.in_session(state):
				return "aucun vote en cours"
			if Amphictyony.vote_of(state, a) == 0:
				return "il faut siéger et voter pour en profiter"
			if (Amphictyony.session(state).get("bribe", {}) as Dictionary).has(str(b)):
				return "ses délégués sont déjà achetés"
		"fuite_dossier":
			var mine := false
			for p: Dictionary in _a(state)["queue"]:
				if int(p["by"]) == b:
					mine = true
			if not mine:
				return "il n'a aucune proposition dans la file"
	return ""


static func spy_apply(state: GameState, a: int, b: int, o: Dictionary) -> String:
	match String(o["id"]):
		"acheter_delegue":
			if not Amphictyony.in_session(state):
				return "le vote était déjà clos : l'enveloppe reste dans la poche."
			var s := Amphictyony.session(state)
			if not s.has("bribe"):
				s["bribe"] = {}
			s["bribe"][str(b)] = a
			return "un quart de ses délégués votera comme nous. Ils ont juré de ne rien dire, contre un supplément."
		"fuite_dossier":
			for p: Dictionary in _a(state)["queue"]:
				if int(p["by"]) == b:
					var label := Amphictyony.prop_label(state, p)
					Amphictyony.withdraw(state, b)
					return "le dossier fuite dans toutes les chancelleries : « %s » est retirée de la file." % label
			return "la proposition avait déjà quitté la file."
		"scandale":
			var kept: Array = []
			for m in (_a(state)["mods"] as Dictionary).get(str(b), []):
				if int(m[0]) < 0:
					kept.append(m)
			kept.append([int(o.get("voix_pct", -10)), state.tick + int(o.get("voix_days", 2160))])
			_a(state)["mods"][str(b)] = kept
			return "le scandale éclate sous la voûte : ses voix fondent, ses amis l'évitent dans les couloirs."
	return ""


# --- Effets, départs, mois et jours ----------------------------------------------------------------

## Points de % de voix du lot 2 : conseiller, Arbitre, médailles, ambassadeur.
static func voix_pct(state: GameState, eid: int) -> int:
	var pct := 0
	if is_councillor(state, eid):
		pct += int(idata()["council"]["voix_pct"])
	if arbiter(state) == eid:
		pct += int(idata()["arbiter"]["voix_pct"])
	return pct + medal_pct(state, eid) + ambassador_pct(state, eid)


static func effects(state: GameState, eid: int, out: Dictionary) -> void:
	if in_coalition(state, eid):
		Research._merge(out, idata()["crisis"]["fx"])
	if Amphictyony.is_member(state, eid):
		for d: Dictionary in _a(state)["done"]:
			Research._merge(out, work_def(String(d["id"])).get("fx", {}))


static func on_remove(state: GameState, eid: int) -> void:
	var a: Dictionary = _a(state)
	if council_on(state):
		(a["council"]["members"] as Array).erase(eid)
	if not (a["arbiter"] as Dictionary).is_empty() and int(a["arbiter"]["eid"]) == eid:
		a["arbiter"] = {}
	if special_on(state):
		(special(state)["votes"] as Dictionary).erase(str(eid))
	var h := Heroes.assigned_to(state, "amph", 0, eid)
	if not h.is_empty():
		Heroes.assign(state, eid, int(h["id"]), "", -1)


static func monthly(state: GameState, added: Array[Dictionary]) -> void:
	var a: Dictionary = _a(state)
	var cd: Dictionary = idata()["crisis"]
	# Observateurs devenus membres ou disparus.
	var obs: Array = []
	for x in a["observers"]:
		if not Amphictyony.is_member(state, int(x)) and Amphictyony.eligible(state, int(x)):
			obs.append(int(x))
	a["observers"] = obs
	if council_on(state):
		var cm: Array = a["council"]["members"]
		var drop := false
		for x in cm:
			if not Amphictyony.is_member(state, int(x)) or Amphictyony.outlaw(state, int(x)):
				drop = true
		if drop or state.tick >= int(a["council"]["reseat"]):
			_reseat(state)
	if not (a["arbiter"] as Dictionary).is_empty() and arbiter(state) < 0:
		added.append(state.add_chronicle("Le mandat de l'Arbitre des étoiles (%s) s'achève. La toge retourne au vestiaire." % _name(state, int(a["arbiter"]["eid"])), Espionage.public_to(state, _audience(state))))
		a["arbiter"] = {}
	# La Moisson de l'Essaim à mi-course : une crise pour l'assemblée.
	for e in state.empires:
		if e.eliminated or e.is_npc() or Victory.cached_pct(state, e.id, "moisson") < int(cd["moisson_pct"]):
			continue
		var seen := false
		for t: Dictionary in a["trig"]:
			if String(t["kind"]) == "moisson" and int(t["a"]) == e.id:
				seen = true
		if not seen:
			add_trig(state, "moisson", e.id, -1)
	var kept: Array = []
	for t: Dictionary in a["trig"]:
		if state.tick - int(t["day"]) < int(cd["keep_days"]) or String(t["kind"]) == "moisson":
			kept.append(t)
	a["trig"] = kept
	_check_coal(state, added)
	for k in (a["aid"] as Dictionary).keys():
		if int(a["aid"][k]["end"]) <= state.tick:
			(a["aid"] as Dictionary).erase(k)
	for k in (a["den"] as Dictionary).keys():
		if int(a["den"][k]) <= state.tick:
			(a["den"] as Dictionary).erase(k)
	if work_on(state) and state.tick >= int(work(state)["end"]):
		added.append(state.add_chronicle("Le grand chantier %s est abandonné, faute de donateurs. Les échafaudages rouillent en orbite." % String(work_def(String(work(state)["id"])).get("label", "?")),
				Espionage.public_to(state, _audience(state))))
		a["work"] = {}


static func daily(state: GameState, added: Array[Dictionary]) -> void:
	if special_on(state) and state.tick >= int(special(state)["end"]):
		_close_special(state, added)


# --- Ordres (une seule commande, « amph_act ») -----------------------------------------------------

static func check_act(state: GameState, eid: int, act: String, x: int, y: int, s: String) -> String:
	if not state.amph_on:
		return "pas d'Amphictyonie dans cette partie"
	match act:
		"veto":
			return check_veto(state, eid)
		"urgent":
			return check_urgent(state, eid, x)
		"denounce":
			return check_denounce(state, eid, x)
		"freeze":
			return check_freeze(state, eid, x)
		"close":
			return check_close(state, eid)
		"truce":
			return check_truce(state, eid, x, y)
		"call":
			return check_call(state, eid, x)
		"observe":
			return check_observe(state, eid)
		"convene":
			return check_convene(state, eid, x)
		"svote":
			return check_svote(state, eid, x)
		"aid_ask":
			return check_aid_ask(state, eid, s)
		"aid_give":
			return check_aid_give(state, eid, x, y)
		"work_give":
			return check_work_give(state, eid, x)
	return "ordre inconnu"


static func act(state: GameState, eid: int, act_id: String, x: int, y: int, s: String) -> void:
	match act_id:
		"veto":
			veto(state, eid)
		"urgent":
			urgent(state, eid, x)
		"denounce":
			denounce(state, eid, x)
		"freeze":
			freeze(state, eid, x)
		"close":
			close(state, eid)
		"truce":
			truce(state, eid, x, y)
		"call":
			call_favor(state, eid, x)
		"observe":
			observe(state, eid)
		"convene":
			convene(state, eid, x)
		"svote":
			svote(state, eid, x)
		"aid_ask":
			aid_ask(state, eid, s)
		"aid_give":
			aid_give(state, eid, x, y)
		"work_give":
			work_give(state, eid, x)
