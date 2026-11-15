class_name AiAncients
extends RefCounted
## L'IA face aux puissances anciennes (prop. 28) : elle répond aux cartes par AiEvents (Ancients.ai_value),
## verse des contributions quand ses réserves le permettent pour briguer les postes, et demande la paix
## dès qu'elle le peut si elle s'est mise en guerre avec une ancienne. Les actes de l'Éveil passent par
## AncientsWake.ai_think.


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	if not Ancients.enabled(state):
		return
	var e: Empire = ctx["e"]
	var met := Ancients.met(state, e.id)
	if met.is_empty():
		return
	for id in met:
		if Ancients.at_war_with(state, id, e.id) and AiPlayer._issue(ctx, SimCommands.anc_act(e.id, "peace", id)):
			AiPlayer._intent(ctx, "Fait la paix avec %s" % Ancients.name_of(state, id))
	AncientsWake.ai_think(ctx)
	_contribute(ctx, met)


## Une contribution environ tous les contrib_every jours, à l'ancienne la mieux disposée, avec la
## ressource la plus abondante au-delà de la réserve gardée.
static func _contribute(ctx: Dictionary, met: Array[int]) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var cfg: Dictionary = Ancients.data()["ai"]
	var every := maxi(1, int(ctx["lv"].get("think_days", 10)))
	if Ancients._h(state, ["contrib-ia", e.id, state.tick]) % maxi(1, int(cfg["contrib_every"])) >= every:
		return
	var best := -1
	var best_op := -99999
	for id in met:
		if Ancients.at_war_with(state, id, e.id) or (Ancients.kind_def(Ancients.kind_of(state, id)).get("posts", []) as Array).is_empty():
			continue
		var op := Ancients.opinion(state, id, e.id)
		if op > best_op:
			best_op = op
			best = id
	if best < 0:
		return
	var res := ""
	var spare := 0
	for r in cfg["contrib_reserve"]:
		var left := int(e.resources.get(String(r), 0)) - int(cfg["contrib_reserve"][r]) - Ancients.give_cost(state, e.id, String(r))
		if left > spare:
			spare = left
			res = String(r)
	if res != "" and AiPlayer._issue(ctx, SimCommands.anc_act(e.id, "give", best, res)):
		AiPlayer._intent(ctx, "Courtise %s" % Ancients.name_of(state, best))
