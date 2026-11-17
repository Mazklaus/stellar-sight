class_name AiArchaeo
extends RefCounted
## IA et archéologie (prop. 41 ; voir Archaeology, data/archaeology.json). Une fois par mois, si les Strates
## sont en jeu : cherche Archéologie stellaire dès l'ère II, choisit sa méthode selon son tempérament (les
## agressives pillent, les prudentes fouillent avec soin), fouille les sites libres où elle a une flotte,
## assemble ses Reconstitutions, lance les Secrets, restitue si elle est diplomate, et dépense ses fragments
## au-delà d'une réserve. Les cartes (Étudier, Extraire ou Classer, permis) passent par AiEvents.


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not Archaeology.applies(state, e.id):
		return
	@warning_ignore("integer_division")
	var month := state.tick / int(GameData.rules()["month_days"]) + 1
	if Archaeology.stat(state, e.id, "ai_month") >= month:
		return
	Archaeology._stat(state, e.id, "ai_month", month - Archaeology.stat(state, e.id, "ai_month"))
	if AiPlayer._forgets(ctx):
		return
	_research(ctx)
	_digs(ctx)
	for k in Archaeology.nature_ids():
		if Archaeology.check(state, e.id, "forge", {"k": k}) == "":
			AiPlayer._issue(ctx, SimCommands.ar_act(e.id, "forge", {"k": k}))
			return
	for d in Archaeology.in_game_disparus(state):
		if ArchaeoWorld.check_reco(state, e.id, d) == "":
			AiPlayer._issue(ctx, SimCommands.ar_act(e.id, "reco", {"d": d}))
			return
		if ArchaeoWorld.check_secrets(state, e.id, d) == "":
			AiPlayer._issue(ctx, SimCommands.ar_act(e.id, "secrets", {"d": d}))
			return
	if AiLevels.aggression(e) <= -1:
		for id in Archaeology.antiqs_of(state, e.id):
			if ArchaeoBridges.check(state, e.id, "restitute", {"id": id}) == "":
				AiPlayer._issue(ctx, SimCommands.ar_act(e.id, "restitute", {"id": id}))
				return
	var keep := int((Archaeology.data().get("ai", {}) as Dictionary).get("frag_keep", 60))
	for act in ["fa_reverse", "fa_proclaim", "fa_military", "fa_query", "fa_sell"]:
		if Relics.fragments(state, e.id) - int(Archaeology.action_def(act).get("cost", 0)) < keep:
			continue
		if Archaeology.check(state, e.id, act, {}) == "":
			AiPlayer._issue(ctx, SimCommands.ar_act(e.id, act))
			return


## Méthode de fouille selon le tempérament.
static func method_for(state: GameState, e: Empire, sid: int) -> String:
	if not Archaeology.full(state):
		return ""
	var a := AiLevels.aggression(e)
	if a >= 2 and Archaeology.method_reason(state, e.id, sid, "pillage") == "":
		return "pillage"
	if a <= -1:
		return "prudente"
	return "methodique"


static func _research(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var t := "archeologie_stellaire"
	if e.techs.has(t) or Research.current_era(state, e.id) < 2 or not e.research_queue.is_empty():
		return
	var step := AiGenetics.reachable(state, e, t, 2)
	if step != "":
		AiPlayer._issue(ctx, SimCommands.research(e.id, step))


## Sites libres où l'IA a une flotte à l'arrêt (ses propres systèmes passent par AiRelics).
static func _digs(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var keys := state.digs.keys()
	keys.sort()
	for k in keys:
		var sid := int(k)
		if state.system_owner(sid) == e.id or not Relics.knows(state, e.id, sid):
			continue
		if Relics.check_start(state, e.id, sid, method_for(state, e, sid)) == "" and AiRelics._affordable(e):
			AiPlayer._issue(ctx, SimCommands.dig_start(e.id, sid, method_for(state, e, sid)))
			return
