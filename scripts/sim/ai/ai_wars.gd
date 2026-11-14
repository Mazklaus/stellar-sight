class_name AiWars
extends RefCounted
## Buts de guerre vus par les empires IA (voir Wars), une fois par mois (décalé selon l'empire) :
## - revendications : de temps en temps (tous les 2 ans en Recrue, 1 an en Normal, 6 mois au-delà),
##   le système le moins cher d'un voisin mal aimé, en gardant une réserve d'influence ; en guerre,
##   le défenseur revendique (c'est gratuit) ;
## - fin de guerre : vainqueur, il exige la reddition dès que l'adversaire l'accepterait (la Recrue
##   exige trop tôt et se fait éconduire) ; vaincu, il se rend quand la défaite est nette (marge
##   yield_at), sauf les peuples qui ne signent jamais.
## Le motif et le but de ses déclarations sont choisis par Wars.auto_choice ; le but du défenseur IA
## est fixé tout de suite (Wars._ai_defense_goal).


static func cfg() -> Dictionary:
	return Wars.data().get("ai", {})


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	if not state.wars_on:
		return
	var e: Empire = ctx["e"]
	if posmod(state.tick + e.id * 13 + 7, 30) != 0:
		return
	run(ctx)


## Sans cadence (tests, outils).
static func think_state(state: GameState, eid: int) -> void:
	var e := state.get_empire(eid)
	run({"state": state, "e": e, "lv": AiLevels.level(e.ai_level), "ai": AiLevels.personality(e), "salt": 0, "intent": ""})


static func run(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if e.eliminated or Diplomacy.no_treaties(state, e.id):
		return
	if _end_wars(ctx):
		return
	_claims(ctx)


static func _level(ctx: Dictionary) -> int:
	return clampi(AiPlayer._skill(ctx), 0, 2)


## Revendications : une par fenêtre de claim_days, sur le voisin le moins aimé.
static func _claims(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var c := cfg()
	var days: Array = c.get("claim_days", [720, 360, 180])
	var every := int(days[mini(_level(ctx), days.size() - 1)])
	var in_war_def := false
	for w in e.wars:
		var rec := Wars.war(state, e.id, int(w))
		if not rec.is_empty() and int(rec["d"]) == e.id:
			in_war_def = true
	if not in_war_def and posmod(state.tick + e.id * 97, every) >= 30:
		return
	var best := -1
	var best_cost := 0
	var best_key := 1 << 30
	for other in e.contacts:
		var o := state.get_empire(int(other))
		if o == null or o.eliminated or o.is_npc():
			continue
		var op := Diplomacy.opinion(state, e.id, o.id)
		var at_war := Combat.at_war(state, e.id, o.id)
		if not at_war and (op > 10 or Diplomacy.allied(state, e.id, o.id)):
			continue
		for cand in Wars.claim_candidates(state, e.id, o.id, 3):
			var sid := int(cand[0])
			if Wars.check_claim(state, e.id, sid) != "":
				continue
			var cost := int(cand[1])
			if cost > 0 and int(e.resources.get("influence", 0)) < cost + int(c.get("reserve", 60)):
				continue
			# Le moins cher d'abord, puis l'ennemi le plus détesté.
			var key := cost * 10 + maxi(-500, op) + 500
			if key < best_key:
				best_key = key
				best = sid
				best_cost = cost
	if best >= 0 and not AiPlayer._forgets(ctx):
		if AiPlayer._issue(ctx, SimCommands.war_act(e.id, "claim", best)):
			AiPlayer._intent(ctx, "Revendique %s (%d influence)" % [state.galaxy.systems[best].system_name, best_cost])


## Fin des guerres : exiger la reddition, ou se rendre. Vrai si un ordre est parti.
static func _end_wars(ctx: Dictionary) -> bool:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var c := cfg()
	var lvl := _level(ctx)
	var never := bool(AiLevels.personality(e).get("temperament", {}).get("never_peace", false))
	var wars := e.wars.duplicate()
	wars.sort()
	for w in wars:
		var o := int(w)
		var rec := Wars.war(state, e.id, o)
		if rec.is_empty():
			continue
		var days := state.tick - int(rec["t"])
		# Vainqueur : la Recrue exige trop tôt (marge -30), les autres quand l'autre accepterait.
		var need := int(c.get("demand_at", 0)) - (30 if lvl == 0 else 0)
		if days >= int(c.get("demand_min_days", 120)) and Wars.acceptance(state, e.id, o) >= need \
				and Wars.check_demand(state, e.id, o) == "" and not AiPlayer._forgets(ctx):
			if AiPlayer._issue(ctx, SimCommands.war_act(e.id, "demand", o)):
				AiPlayer._intent(ctx, "Exige la reddition de %s" % state.get_empire(o).short_name())
				return true
		# Vaincu : se rend quand la défaite est nette.
		if not never and Wars.acceptance(state, o, e.id) >= int(c.get("yield_at", 25)) and Wars.check_yield(state, e.id, o) == "":
			if AiPlayer._issue(ctx, SimCommands.war_act(e.id, "yield", o)):
				AiPlayer._intent(ctx, "Se rend à %s" % state.get_empire(o).short_name())
				return true
	return false
