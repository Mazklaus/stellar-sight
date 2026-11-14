class_name AiAmphictyony
extends RefCounted
## L'Amphictyonie vue par les empires IA (voir Amphictyony), une fois par mois (décalé selon l'empire).
## Elle signe l'acte de fondation (sauf les plus belliqueuses, une fois sur deux), adhère quand elle en
## a les moyens, soutient et vote selon l'intérêt d'une proposition pour elle (credo, tempérament,
## situation), multiplié par son opinion du proposant (×0,5 à ×1,3, comme Stellaris) ; au-dessus du
## seuil elle vote pour, en dessous contre, sinon elle s'abstient. Elle propose ce qui l'avantage le plus,
## achète des voix si l'enjeu est fort et son camp en retard (Vétéran et au-dessus).
## Recrue : elle vote mal (intérêt brouillé), mais elle vote toujours.


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
	if not Amphictyony.is_member(state, e.id):
		var reserve := 40 if ag < 2 else 120
		if int(e.resources.get("influence", 0)) >= int(Amphictyony.join_cost(state, e.id).get("influence", 0)) + reserve and Amphictyony.check_join(state, e.id) == "":
			AiPlayer._issue(ctx, SimCommands.amph_join(e.id))
		return
	var skill := int(ctx["lv"].get("faction_use", 1))
	_vote(ctx, skill)
	_support(ctx)
	_propose(ctx)


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
	if Amphictyony.vote_of(state, e.id) != want:
		AiPlayer._issue(ctx, SimCommands.amph_vote(e.id, want))
	# Voix achetées : enjeu fort, camp en retard, de quoi payer.
	if skill >= 2 and want != 0 and (absi(score(state, e, p)) >= 6 or int(p["by"]) == e.id):
		var t := Amphictyony.tally(state)
		var behind := int(t["pour"]) <= int(t["contre"]) if want > 0 else int(t["contre"]) <= int(t["pour"])
		var cost := int(Amphictyony.buy_cost(state, e.id).get("influence", 0))
		if behind and int(e.resources.get("influence", 0)) >= cost + 80 and Amphictyony.check_buy(state, e.id) == "":
			AiPlayer._issue(ctx, SimCommands.amph_buy(e.id))


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
		var cost := int(Amphictyony.prop_cost(state, String(cand["kind"]), String(cand["fam"]), int(cand["dir"])).get("influence", 0))
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
	for t in Amphictyony.outlaws(state):
		if t == eid:
			continue
		for s: Dictionary in Amphictyony.sanction_defs():
			out.append({"kind": "sanction", "fam": "", "dir": 0, "from": 0, "to": 0, "target": t, "sanc": String(s["id"]), "by": eid})
		if Amphictyony.is_member(state, t):
			out.append({"kind": "expel", "fam": "", "dir": 0, "from": 0, "to": 0, "target": t, "sanc": "", "by": eid})
	return out


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
	return 0


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
