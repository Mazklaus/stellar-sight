class_name AiKoinon
extends RefCounted
## Le Koinon vu par les empires IA (voir Koinon), une fois par mois (décalé selon l'empire) :
## - elle fonde un Koinon avec un allié de longue date qu'elle apprécie (même credo ou ennemi commun),
##   dans la forme qui lui ressemble (Communion pour la foi, Hégémonie pour les plus belliqueux,
##   Ligue martiale en guerre, savante pour la raison, marchande sinon) ;
## - elle demande à entrer dans une ligue dont elle aime les membres (associée si elle est petite) ;
## - au synode : elle admet qui elle apprécie, exclut qui elle déteste, vote la guerre contre un ennemi
##   détesté, monte les lois quand la cohésion le permet, élit le candidat qu'elle préfère ;
## - Stratège : elle propose les lois, secourt un membre à sec avec le trésor, donne la consigne de
##   vote à l'Amphictyonie (son propre vote) ;
## - elle part quand la ligue se délite.
## Recrue : elle vote au hasard de son humeur (opinion brouillée), mais elle vote.


static func cfg() -> Dictionary:
	return Koinon.data().get("ai", {})


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	if not state.koinon_on:
		return
	var e: Empire = ctx["e"]
	var every := maxi(1, int(ctx["lv"].get("think_days", 10)))
	if posmod(state.tick + e.id * 13 + 7, 30) >= every:
		return
	run(ctx)


static func think_state(state: GameState, eid: int) -> void:
	var e := state.get_empire(eid)
	run({"state": state, "e": e, "lv": AiLevels.level(e.ai_level), "ai": AiLevels.personality(e), "salt": 0, "intent": ""})


static func run(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if e.eliminated or Diplomacy.no_treaties(state, e.id) or Vassals.is_subject(state, e.id):
		return
	var lid := Koinon.league_of(state, e.id)
	if lid < 0:
		if not _found(ctx):
			_join(ctx)
		return
	if _leave(ctx, lid):
		return
	if Koinon.strategos(state, lid) == e.id:
		_strategos(ctx, lid)
	_propose(ctx, lid)


## Forme qui ressemble à l'empire.
static func pick_form(state: GameState, eid: int, partner: int) -> String:
	var sp := Diplomacy._species(state, eid)
	var e := state.get_empire(eid)
	if String(sp.get("credo", "")) == "foi" and Koinon.check_found(state, eid, partner, "communion") == "":
		return "communion"
	if e.is_ai() and AiLevels.aggression(e) >= 2:
		return "hegemonie"
	if not e.wars.is_empty():
		return "martiale"
	if String(sp.get("credo", "")) == "raison":
		return "savante"
	return "marchande"


static func _found(ctx: Dictionary) -> bool:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	for a in Diplomacy.allies(state, e.id):
		if Koinon.league_of(state, a) >= 0:
			continue
		var op := Diplomacy.opinion(state, e.id, a)
		var bond := op >= int(cfg()["found_opinion"]) or not Diplomacy.common_enemies(state, e.id, a).is_empty() \
				or TradeLinks.same_credo(state, e.id, a)
		if not bond:
			continue
		var fid := pick_form(state, e.id, a)
		if Koinon.check_found(state, e.id, a, fid) != "":
			continue
		var other := state.get_empire(a)
		if other.is_ai() and Diplomacy.opinion(state, a, e.id) < 0:
			continue
		if not other.is_ai() and (not Diplomacy.pending(state, e.id, a, "kfound").is_empty() or Diplomacy.cooldown_left(state, e.id, a, "kfound") > 0):
			continue
		if AiPlayer._issue(ctx, SimCommands.koi_act(e.id, "found", a, fid)):
			return true
	return false


static func _join(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var best := -1
	var best_op := -999
	for lid in Koinon.league_ids(state):
		var ms := Koinon.members_of(state, lid)
		var sum := 0
		for m in ms:
			sum += Diplomacy.opinion(state, e.id, m)
		@warning_ignore("integer_division")
		var avg := sum / maxi(1, ms.size())
		if avg >= int(cfg()["join_opinion"]) and avg > best_op:
			best = ms[0]
			best_op = avg
	if best < 0:
		return
	var small := EmpireReport.owned_systems(state, e.id).size() <= 3
	var kind := "assoc" if small else "member"
	if not AiPlayer._issue(ctx, SimCommands.koi_act(e.id, "join", best, kind)) and kind == "member":
		AiPlayer._issue(ctx, SimCommands.koi_act(e.id, "join", best, "assoc"))


static func _leave(ctx: Dictionary, lid: int) -> bool:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if Koinon.cohesion(state, lid) > int(cfg()["leave_cohesion"]):
		return false
	return AiPlayer._issue(ctx, SimCommands.koi_act(e.id, "leave"))


static func _strategos(ctx: Dictionary, lid: int) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var l := Koinon.league(state, lid)
	# Secours d'un membre à sec.
	for m in Koinon.all_of(state, lid):
		if int(state.get_empire(m).resources.get("energy", 0)) < int(cfg()["grant_below"]):
			var n := mini(int(Koinon.data()["grant_max"]), int(l["treasury"]))
			if n > 0 and AiPlayer._issue(ctx, SimCommands.koi_act(e.id, "grant", m, "", n)):
				break
	# Consigne : son propre vote.
	if state.amph_on and Amphictyony.in_session(state):
		var mine := int((Amphictyony.session(state)["votes"] as Dictionary).get(str(e.id), 0))
		if mine != 0 and Koinon.consigne(state, e.id) != mine:
			AiPlayer._issue(ctx, SimCommands.koi_act(e.id, "consigne", mine))
	# Lois : un cran de plus quand la cohésion le permet.
	if Koinon.cohesion(state, lid) >= int(cfg()["law_cohesion"]):
		for fam in ["trade", "tax", "central"]:
			var step := Koinon.law_step(state, lid, fam) + 1
			if AiPlayer._issue(ctx, SimCommands.koi_act(e.id, "propose", step, "law:" + fam)):
				return


static func _propose(ctx: Dictionary, lid: int) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var c := cfg()
	for m in Koinon.all_of(state, lid):
		if m != e.id and Diplomacy.opinion(state, e.id, m) <= int(c["exclude_opinion"]):
			if AiPlayer._issue(ctx, SimCommands.koi_act(e.id, "propose", m, "exclude")):
				return
	# Guerre commune contre un ennemi déjà combattu et détesté.
	for w in e.wars:
		var t := int(w)
		if GameState.is_npc(t) or Diplomacy.opinion(state, e.id, t) > int(c["war_opinion"]):
			continue
		var all_in := true
		for m in Koinon.members_of(state, lid):
			if not Combat.at_war(state, m, t):
				all_in = false
		if all_in:
			continue
		if AiPlayer._issue(ctx, SimCommands.koi_act(e.id, "propose", t, "war")):
			return


## Voix de l'IA m au synode.
static func vote_yes(state: GameState, m: int, lid: int, v: Dictionary) -> bool:
	var c := cfg()
	var x := int(v["x"])
	var e := state.get_empire(m)
	var noise := 0
	if e.is_ai() and int(AiLevels.level(e.ai_level).get("faction_use", 1)) == 0:
		noise = posmod(hash([state.seed_value, "koi", m, int(v["id"])]), 41) - 20
	match String(v["kind"]):
		"admit":
			return Diplomacy.opinion(state, m, x) + noise >= int(c["admit_opinion"])
		"exclude":
			return Diplomacy.opinion(state, m, x) + noise <= int(c["exclude_opinion"])
		"war":
			return Combat.at_war(state, m, x) or Diplomacy.opinion(state, m, x) + noise <= int(c["war_opinion"])
		"law":
			var step := x
			if step < Koinon.law_step(state, lid, String(v["s"])):
				return true
			return Koinon.cohesion(state, lid) + noise >= int(c["law_cohesion"]) - 10
		"form":
			return pick_form(state, m, m) == String(v["s"]) or noise > 10
	return false


static func elect_choice(state: GameState, m: int, cands: Array[int]) -> int:
	var best := -1
	var bs := -9999
	for cnd in cands:
		var s := 30 if cnd == m else Diplomacy.opinion(state, m, cnd)
		if s > bs:
			best = cnd
			bs = s
	return best
