class_name AiAmphictyony
extends RefCounted
## L'Amphictyonie vue par les empires IA (voir Amphictyony), une fois par mois (décalé selon l'empire).
## Elle signe l'acte de fondation (sauf les plus belliqueuses, une fois sur deux), adhère quand elle en
## a les moyens, soutient et vote selon l'intérêt d'une proposition pour elle (credo, tempérament,
## situation), multiplié par son opinion du proposant (×0,5 à ×1,3, comme Stellaris) ; au-dessus du
## seuil elle vote pour, en dessous contre, sinon elle s'abstient. Elle propose ce qui l'avantage le plus,
## achète des voix si l'enjeu est fort et son camp en retard (Vétéran et au-dessus).
## Recrue : elle vote mal (intérêt brouillé), mais elle vote toujours.
## Lot 2 : elle observe quand elle ne peut pas siéger, appelle à l'aide quand elle est à sec, secourt
## ses amis, finance les grands travaux, use de son veto, de l'urgence et de la dénonciation à la Haute
## Voûte, arbitre en Arbitre des étoiles, appelle ses faveurs, convoque et vote les sessions
## extraordinaires (Vétéran et au-dessus pour les manœuvres fines).


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	if not state.amph_on:
		return
	var e: Empire = ctx["e"]
	var every := maxi(1, int(ctx["lv"].get("think_days", 10)))
	if posmod(state.tick + e.id * 7 + 5, 30) >= every:
		return
	if not Amphictyony.eligible(state, e.id):
		return
	var ag := AiLevels.aggression(e)
	if Amphictyony.offer_open(state):
		if Amphictyony.check_found(state, e.id) == "" and (ag < 2 or posmod(hash([state.seed_value, "amph_sign", e.id]), 2) == 0):
			AiPlayer._issue(ctx, SimCommands.amph_found(e.id))
		return
	if not Amphictyony.founded(state):
		return
	var skill := int(ctx["lv"].get("faction_use", 1))
	_aid_ask(ctx)
	if not Amphictyony.is_member(state, e.id):
		var reserve := 40 if ag < 2 else 120
		if int(e.resources.get("influence", 0)) >= int(Amphictyony.join_cost(state, e.id).get("influence", 0)) + reserve and Amphictyony.check_join(state, e.id) == "":
			AiPlayer._issue(ctx, SimCommands.amph_join(e.id))
		elif not AmphInst.is_observer(state, e.id) and AmphInst.check_observe(state, e.id) == "":
			AiPlayer._issue(ctx, SimCommands.amph_act(e.id, "observe"))
		_convene(ctx, skill)
		return
	_council(ctx, skill)
	_vote(ctx, skill)
	_support(ctx)
	_propose(ctx)
	_arbiter(ctx, skill)
	_convene(ctx, skill)
	_svote(ctx, skill)
	_give(ctx)
	_power(ctx, skill)


static func _vote(ctx: Dictionary, skill: int) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not Amphictyony.in_session(state):
		return
	var p: Dictionary = Amphictyony.session(state)["prop"]
	var want := 0
	if int(p["by"]) == e.id:
		want = 1
	else:
		var sc := score(state, e, p)
		if skill <= 0:
			# Recrue : intérêt brouillé, mais elle ne s'abstient pas.
			sc += posmod(hash([state.seed_value, "amph_vote", e.id, int(p["id"])]), 11) - 5
			want = 1 if sc >= 0 else -1
		else:
			var th: Dictionary = Amphictyony.data()["ai"]
			want = 1 if sc >= int(th["support"]) else (-1 if sc <= int(th["oppose"]) else 0)
		# Consigne du Stratège de son Koinon : suivie sauf si l'enjeu la heurte de front.
		var kc := Koinon.consigne(state, e.id)
		if kc != 0 and (want != -kc or absi(sc) < 6):
			want = kc
	if Amphictyony.vote_of(state, e.id) != want:
		AiPlayer._issue(ctx, SimCommands.amph_vote(e.id, want))
	# Voix achetées : enjeu fort, camp en retard, de quoi payer.
	if skill >= 2 and want != 0 and (absi(score(state, e, p)) >= 6 or int(p["by"]) == e.id):
		var t := Amphictyony.tally(state)
		var behind := int(t["pour"]) <= int(t["contre"]) if want > 0 else int(t["contre"]) <= int(t["pour"])
		var cost := int(Amphictyony.buy_cost(state, e.id).get("influence", 0))
		if behind and int(e.resources.get("influence", 0)) >= cost + 80 and Amphictyony.check_buy(state, e.id) == "":
			AiPlayer._issue(ctx, SimCommands.amph_buy(e.id))
		# Faveurs : on les appelle quand le camp est en retard (gratuit, mais elles s'épuisent).
		if behind:
			for d in AmphInst.debtors(state, e.id):
				if AmphInst.check_call(state, e.id, int(d[0])) == "":
					AiPlayer._issue(ctx, SimCommands.amph_act(e.id, "call", int(d[0])))


static func _support(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var th: Dictionary = Amphictyony.data()["ai"]
	for p: Dictionary in state.amph["queue"]:
		if int(p["by"]) == e.id:
			continue
		var sc := score(state, e, p)
		var on := (p["sup"] as Array).has(e.id)
		if (sc >= int(th["support"]) and not on) or (sc < 0 and on):
			AiPlayer._issue(ctx, SimCommands.amph_support(e.id, int(p["id"])))


static func _propose(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not Amphictyony.proposal_of(state, e.id).is_empty():
		return
	var every := int(Amphictyony.data()["ai"]["propose_every"])
	if posmod(state.tick + e.id * 97, every) >= 30:
		return
	var best: Dictionary = {}
	# Une proposition à son avantage, même modeste (un cran sous le seuil de soutien).
	var best_sc := int(Amphictyony.data()["ai"]["support"]) - 2
	for cand in candidates(state, e.id):
		if Amphictyony.check_propose(state, e.id, String(cand["kind"]), String(cand["fam"]), int(cand["dir"]), int(cand["target"]), String(cand["sanc"])) != "":
			continue
		var cost := int(Amphictyony.prop_cost(state, String(cand["kind"]), String(cand["fam"]), int(cand["dir"]), e.id).get("influence", 0))
		if int(e.resources.get("influence", 0)) < cost + 50:
			continue
		var sc := interest(state, e, cand)
		if sc > best_sc:
			best_sc = sc
			best = cand
	if not best.is_empty():
		AiPlayer._issue(ctx, SimCommands.amph_propose(e.id, String(best["kind"]), String(best["fam"]), int(best["dir"]), int(best["target"]), String(best["sanc"])))


## Propositions qu'un membre pourrait déposer aujourd'hui (au format d'une proposition).
static func candidates(state: GameState, eid: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f: Dictionary in Amphictyony.family_defs():
		var fid := String(f["id"])
		if not Amphictyony.family_available(state, fid):
			continue
		for dir in [1, -1]:
			var st := Amphictyony.step_to(state, fid, dir)
			if bool(st[0]):
				out.append({"kind": "step", "fam": fid, "dir": dir, "from": Amphictyony.fam_value(state, fid), "to": int(st[1]), "target": -1, "sanc": "", "by": eid})
	for t in Amphictyony.sanctionables(state):
		if t == eid:
			continue
		for s: Dictionary in Amphictyony.sanction_defs():
			out.append({"kind": "sanction", "fam": "", "dir": 0, "from": 0, "to": 0, "target": t, "sanc": String(s["id"]), "by": eid})
		if Amphictyony.is_member(state, t) and Amphictyony.outlaw(state, t):
			out.append({"kind": "expel", "fam": "", "dir": 0, "from": 0, "to": 0, "target": t, "sanc": "", "by": eid})
	# Institutions (lot 2).
	out.append(_inst(state, eid, "council", "", 0, -1))
	for dir in [1, -1]:
		out.append(_inst(state, eid, "council_size", "", dir, -1))
	for c in AmphInst.councillors(state):
		out.append(_inst(state, eid, "arbiter", "", 0, c))
	out.append(_inst(state, eid, "extend", "", 0, -1))
	out.append(_inst(state, eid, "defiance", "", 0, -1))
	for w: Dictionary in AmphInst.work_defs():
		out.append(_inst(state, eid, "work", String(w["id"]), 0, -1))
	# Pleins pouvoirs (lot 3).
	out.append(_inst(state, eid, "term_lift", "", 0, -1))
	out.append(_inst(state, eid, "full_powers", "", 0, -1))
	return out


static func _inst(state: GameState, eid: int, kind: String, fam: String, dir: int, target: int) -> Dictionary:
	var p := {"kind": kind, "fam": fam, "dir": dir, "from": 0, "to": 0, "target": target, "sanc": "", "by": eid}
	p.merge(AmphInst.make_fields(state, kind, fam, dir, target), true)
	return p


## Note de vote : intérêt × opinion du proposant (de ×0,5 à ×1,3).
@warning_ignore("integer_division")
static func score(state: GameState, e: Empire, p: Dictionary) -> int:
	var it := interest(state, e, p)
	var by := int(p["by"])
	if by == e.id:
		return maxi(it, 10)
	var op := Diplomacy.opinion(state, e.id, by)
	var mult := clampi(100 + op * 3 / 10, 50, 130)
	return it * mult / 100


## Intérêt d'une proposition pour l'empire, de -10 à +10.
static func interest(state: GameState, e: Empire, p: Dictionary) -> int:
	match String(p["kind"]):
		"step":
			var from := int(p["from"])
			var to := int(p["to"])
			if Amphictyony.is_repeal(from, to):
				return -way_interest(state, e, String(p["fam"]), Amphictyony.way_of(from))
			return way_interest(state, e, String(p["fam"]), Amphictyony.way_of(to))
		"sanction", "expel":
			var t := int(p["target"])
			if t == e.id:
				return -10
			if Diplomacy.allied(state, e.id, t):
				return -6
			@warning_ignore("integer_division")
			return clampi(4 - Diplomacy.opinion(state, e.id, t) / 20, -8, 10)
		"council":
			return 6 if _rank(state, e.id) < int(AmphInst.idata()["council"]["seats"]) else -2
		"council_size":
			var r := _rank(state, e.id)
			var seated := r < AmphInst.seats(state)
			var after := r < int(p["to"])
			return 5 if after and not seated else (-5 if seated and not after else (1 if int(p["to"]) > int(p["from"]) else -1))
		"arbiter", "extend":
			var t2 := int(p["target"])
			if t2 == e.id:
				return 9
			# Tribune : on voit volontiers une république à l'arbitrage.
			var trib := 3 if AmphPower.has_talent(state, t2, "tribune") else 0
			@warning_ignore("integer_division")
			return clampi(Diplomacy.opinion(state, e.id, t2) / 15 - 1 + trib, -8, 8)
		"term_lift":
			var t4 := int(p["target"])
			if t4 == e.id:
				return 9
			@warning_ignore("integer_division")
			return clampi(Diplomacy.opinion(state, e.id, t4) / 15 - 3, -8, 6)
		"full_powers":
			var t5 := int(p["target"])
			if t5 == e.id:
				return 10
			# Nul n'aime un maître : seuls les amis très proches et les faibles s'y résignent.
			@warning_ignore("integer_division")
			return clampi(Diplomacy.opinion(state, e.id, t5) / 12 - 5 - AiLevels.aggression(e), -10, 6)
		"defiance":
			var t3 := int(p["target"])
			if t3 == e.id:
				return -10
			@warning_ignore("integer_division")
			return clampi(-Diplomacy.opinion(state, e.id, t3) / 15, -8, 8)
		"work":
			var w := AmphInst.work_def(String(p["fam"]))
			@warning_ignore("integer_division")
			return 4 + (1 if int(e.resources.get(String(w.get("res", "")), 0)) >= int(w.get("need", 0)) / 4 else -1)
	return 0


## Rang d'un membre par ses voix de base (0 = le plus fort).
static func _rank(state: GameState, eid: int) -> int:
	var mine := Amphictyony.base_voix(state, eid)
	var r := 0
	for m in Amphictyony.members(state):
		var v := Amphictyony.base_voix(state, m)
		if m != eid and (v > mine or (v == mine and m < eid)):
			r += 1
	return r


# --- Lot 2 : Haute Voûte, Arbitre, crises, aide, grands travaux ------------------------------------

static func _council(ctx: Dictionary, skill: int) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not AmphInst.is_councillor(state, e.id):
		return
	# Veto : contre une proposition qui nous nuit vraiment et qui risque de passer.
	if Amphictyony.in_session(state) and AmphInst.check_veto(state, e.id) == "":
		var sc := score(state, e, Amphictyony.session(state)["prop"])
		var t := Amphictyony.tally(state)
		if sc <= -6 and int(t["pour"]) >= int(t["contre"]):
			AiPlayer._issue(ctx, SimCommands.amph_act(e.id, "veto"))
			return
	# Urgence : pour sa propre proposition, quand rien ne siège.
	var mine := Amphictyony.proposal_of(state, e.id)
	if skill >= 1 and not mine.is_empty() and not Amphictyony.in_session(state) and AmphInst.check_urgent(state, e.id, int(mine["id"])) == "":
		AiPlayer._issue(ctx, SimCommands.amph_act(e.id, "urgent", int(mine["id"])))
		return
	# Dénonciation : l'empire le plus détesté, s'il l'est vraiment.
	if int(e.resources.get("influence", 0)) < 130:
		return
	var worst := -1
	var low := -40
	for o in e.contacts:
		var op := Diplomacy.opinion(state, e.id, int(o))
		if op < low and AmphInst.check_denounce(state, e.id, int(o)) == "" and not Diplomacy.allied(state, e.id, int(o)):
			low = op
			worst = int(o)
	if worst >= 0:
		AiPlayer._issue(ctx, SimCommands.amph_act(e.id, "denounce", worst))


static func _arbiter(ctx: Dictionary, skill: int) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if AmphInst.arbiter(state) != e.id or skill <= 0:
		return
	# Trêve entre deux membres en guerre qu'il apprécie.
	var ms := Amphictyony.members(state)
	for a in ms:
		for b in ms:
			if a < b and a != e.id and b != e.id and AmphInst.check_truce(state, e.id, a, b) == "" \
					and Diplomacy.opinion(state, e.id, a) >= 0 and Diplomacy.opinion(state, e.id, b) >= 0 \
					and int(e.resources.get("influence", 0)) >= 120:
				AiPlayer._issue(ctx, SimCommands.amph_act(e.id, "truce", a, b))
				return
	# Clôture anticipée quand le vote penche comme il le souhaite sur un enjeu fort.
	if Amphictyony.in_session(state) and AmphInst.check_close(state, e.id) == "":
		var p: Dictionary = Amphictyony.session(state)["prop"]
		var sc := score(state, e, p)
		var t := Amphictyony.tally(state)
		if (sc >= 6 and int(t["pour"]) > int(t["contre"])) or (sc <= -6 and int(t["contre"]) > int(t["pour"])):
			AiPlayer._issue(ctx, SimCommands.amph_act(e.id, "close"))
			return
	# Gel de la proposition la mieux soutenue si elle lui nuit.
	var q := Amphictyony.sorted_queue(state)
	if not q.is_empty():
		var top: Dictionary = q[0]
		if score(state, e, top) <= -6 and AmphInst.check_freeze(state, e.id, int(top["id"])) == "":
			AiPlayer._issue(ctx, SimCommands.amph_act(e.id, "freeze", int(top["id"])))


## Intérêt d'une coalition contre la cible : victime, haine, tempérament, alliance.
@warning_ignore("integer_division")
static func coalition_interest(state: GameState, e: Empire, target: int, victim: int) -> int:
	if target == e.id:
		return -10
	if Diplomacy.allied(state, e.id, target):
		return -8
	var sc := -Diplomacy.opinion(state, e.id, target) / 10 + AiLevels.aggression(e)
	if victim == e.id:
		sc += 8
	elif victim >= 0 and Diplomacy.allied(state, e.id, victim):
		sc += 4
	if Combat.at_war(state, e.id, target):
		sc += 3
	if Diplomacy.warships(state, e.id) * 2 < Diplomacy.warships(state, target):
		sc -= 2
	return clampi(sc, -10, 10)


static func _convene(ctx: Dictionary, skill: int) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if int(e.resources.get("influence", 0)) < 130:
		return
	for t: Dictionary in AmphInst.open_trigs(state):
		var need := 3 if int(t["b"]) == e.id else (5 if skill >= 1 else 99)
		if coalition_interest(state, e, int(t["a"]), int(t["b"])) >= need and AmphInst.check_convene(state, e.id, int(t["id"])) == "":
			AiPlayer._issue(ctx, SimCommands.amph_act(e.id, "convene", int(t["id"])))
			return


static func _svote(ctx: Dictionary, skill: int) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not AmphInst.special_on(state):
		return
	var s := AmphInst.special(state)
	var sc := coalition_interest(state, e, int(s["target"]), int(s["victim"]))
	if skill <= 0:
		sc += posmod(hash([state.seed_value, "amph_svote", e.id, int(s["trig"])]), 7) - 3
	var want := 1 if sc >= 2 else (-1 if sc <= -2 else 0)
	if AmphInst.svote_of(state, e.id) != want and AmphInst.check_svote(state, e.id, want) == "":
		AiPlayer._issue(ctx, SimCommands.amph_act(e.id, "svote", want))


static func _aid_ask(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	for res in AmphInst.idata()["aid"]["res"]:
		if AmphInst.check_aid_ask(state, e.id, String(res)) == "":
			AiPlayer._issue(ctx, SimCommands.amph_act(e.id, "aid_ask", -1, -1, String(res)))
			return


static func _give(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var step := int(AmphInst.idata()["aid"]["step"])
	# Aide d'urgence : à ceux qu'on apprécie, quand on a de quoi.
	var ks := (state.amph["aid"] as Dictionary).keys()
	ks.sort()
	for k in ks:
		var t := int(k)
		var ai := AmphInst.aid_of(state, t)
		if t == e.id or Diplomacy.opinion(state, e.id, t) < 10:
			continue
		if int(e.resources.get(String(ai["res"]), 0)) >= 600 and AmphInst.check_aid_give(state, e.id, t, step) == "":
			AiPlayer._issue(ctx, SimCommands.amph_act(e.id, "aid_give", t, step))
			return
	# Grands travaux : une à quatre tranches par mois quand on est riche dans la ressource.
	if AmphInst.work_on(state):
		var w := AmphInst.work_def(String(AmphInst.work(state)["id"]))
		var have := int(e.resources.get(String(w["res"]), 0))
		var n := step * (4 if have >= 2000 else (2 if have >= 1000 else 1))
		if have >= 500 and AmphInst.check_work_give(state, e.id, n) == "":
			AiPlayer._issue(ctx, SimCommands.amph_act(e.id, "work_give", n))


static func _credo(state: GameState, eid: int) -> String:
	return Events.layer_value(state, eid, "credo")


## Intérêt d'une voie de famille (« a » ou « b ») selon le credo, le tempérament et la situation.
static func way_interest(state: GameState, e: Empire, fid: String, way: String) -> int:
	var ag := AiLevels.aggression(e)
	var credo := _credo(state, e.id)
	var a := 0
	match fid:
		"commerce":
			a = 2 + (3 if credo == "profit" else 0) + (-2 if credo == "honneur" else 0)
		"savoir":
			a = 2 + (3 if credo == "raison" else 0) - (1 if ag >= 2 else 0)
		"guerre":
			# Voie A (conventions) : les pacifiques ; voie B (défense mutuelle) : les plus faibles.
			var weak := Diplomacy.warships(state, e.id) < _avg_warships(state)
			var conv := 1 - ag * 2
			var dfn := (3 if weak else -1) - maxi(0, ag)
			return clampi(conv if way == "a" else dfn, -10, 10)
		"foi":
			var mine := String((state.faiths.get("state", {}) as Dictionary).get(str(e.id), ""))
			var leads := mine != "" and mine == _top_faith(state)
			a = (1 if credo == "foi" else 0) + (-3 if leads else 2)
			if way == "b":
				return clampi(5 if leads else -3, -10, 10)
		"peuples":
			a = (2 if credo == "survie" else 0) + (1 if ag <= -1 else 0) - (2 if ag >= 2 else 0)
		"ombres":
			a = (2 if ag <= 0 else -1) - (3 if credo == "profit" else 0)
		"perils":
			a = (3 if Fauna.active(state) and Fauna.venerated(state, e.id) > 0 else -1) - (2 if state.pirate_density != "aucun" else 0)
	return clampi(a if way == "a" else -a, -10, 10)


static func _avg_warships(state: GameState) -> int:
	var n := 0
	var tot := 0
	for m in Amphictyony.members(state):
		tot += Diplomacy.warships(state, m)
		n += 1
	@warning_ignore("integer_division")
	return 0 if n == 0 else tot / n


## Foi la plus suivie chez les membres ("" sans religions).
static func _top_faith(state: GameState) -> String:
	if not state.faith_on:
		return ""
	var cnt := {}
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if not Amphictyony.is_member(state, c.owner):
			continue
		for fid in c.faith:
			cnt[String(fid)] = int(cnt.get(String(fid), 0)) + int(c.faith[fid])
	var best := ""
	var keys := cnt.keys()
	keys.sort()
	for k in keys:
		if best == "" or int(cnt[k]) > int(cnt[best]):
			best = String(k)
	return best


# --- Lot 3 : pleins pouvoirs, Chancelier, souveraineté, talents --------------------------------------

static func _power(ctx: Dictionary, skill: int) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var ag := AiLevels.aggression(e)
	# La Cour impériale attend une réponse : se soulever si l'on est fort, belliqueux ou hostile.
	if AmphPower.choosing(state) and AmphPower.check_submit(state, e.id) == "":
		var imp := AmphPower.imperator(state)
		@warning_ignore("integer_division")
		var strong := AmphPower._fleet(state, e.id) * 3 >= AmphPower._fleet(state, imp) * 2
		if (ag >= 2 and strong) or Diplomacy.opinion(state, e.id, imp) < -30:
			AiPlayer._issue(ctx, SimCommands.amph_act(e.id, "rebel"))
			return
		AiPlayer._issue(ctx, SimCommands.amph_act(e.id, "submit"))
	# Élection du Chancelier : le candidat qu'on préfère, ou l'abstention.
	if AmphPower.chan_on(state) and not (AmphPower.chan(state)["cands"] as Array).has(e.id):
		var best := -1
		var best_sc := -2
		for c in AmphPower.chan(state)["cands"]:
			@warning_ignore("integer_division")
			var sc := Diplomacy.opinion(state, e.id, int(c)) / 10 + (4 if Diplomacy.allied(state, e.id, int(c)) else 0)
			if skill <= 0:
				sc += posmod(hash([state.seed_value, "chan", e.id, int(c)]), 5) - 2
			if sc > best_sc:
				best_sc = sc
				best = int(c)
		if AmphPower.cvote_of(state, e.id) != best and AmphPower.check_cvote(state, e.id, best) == "":
			AiPlayer._issue(ctx, SimCommands.amph_act(e.id, "cvote", best))
	# Verdict du Chancelier : refuser si l'on est belliqueux ou de force à tenir.
	if AmphPower.check_refuse(state, e.id) == "":
		var w := int(AmphPower.dip(state)["eid"])
		@warning_ignore("integer_division")
		if ag >= 2 or AmphPower._fleet(state, e.id) * 3 >= AmphPower._fleet(state, w) * 2:
			AiPlayer._issue(ctx, SimCommands.amph_act(e.id, "refuse"))
	# Souveraineté : contre une résolution qui heurte nos lois.
	var cf := AmphPower.conflicts(state, e.id)
	if not cf.is_empty() and AmphPower.check_sovereign(state, e.id, String(cf[0]["fam"])) == "":
		AiPlayer._issue(ctx, SimCommands.amph_act(e.id, "sovereign", -1, -1, String(cf[0]["fam"])))
	if skill <= 0:
		return
	# Anathème : contre l'empire d'une autre foi qu'on déteste le plus.
	if AmphPower.has_talent(state, e.id, "anatheme"):
		var worst := -1
		var low := -25
		for o in e.contacts:
			var op := Diplomacy.opinion(state, e.id, int(o))
			if op < low and AmphPower.check_anathema(state, e.id, int(o)) == "":
				low = op
				worst = int(o)
		if worst >= 0 and int(e.resources.get("influence", 0)) >= 100:
			AiPlayer._issue(ctx, SimCommands.amph_act(e.id, "anathema", worst))
	# Duel de champions : seulement quand on est sûr de gagner.
	if AmphPower.check_duel(state, e.id) == "":
		var h := AmphPower.duel_target(state, e.id)
		if AmphPower._fleet(state, e.id) > AmphPower._fleet(state, int(h["prop"]["by"])) and score(state, e, h["prop"]) <= -3:
			AiPlayer._issue(ctx, SimCommands.amph_act(e.id, "duel"))
