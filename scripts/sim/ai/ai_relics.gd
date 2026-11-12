class_name AiRelics
extends RefCounted
## Fouilles et reliques des empires IA (voir Relics) : à chaque réflexion, lancer les fouilles de ses
## systèmes, acheter un indice quand les fragments le permettent, célébrer un Triomphe quand
## l'influence déborde, confier une relique à un héros libre ; un peuple du Profit revend ses
## fragments en trop.

const INFLUENCE_RESERVE := 60
const FRAGMENT_KEEP := 40


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if state.relics.is_empty():
		return
	if AiPlayer._forgets(ctx):
		return
	var keys := state.digs.keys()
	keys.sort()
	for k in keys:
		var sid := int(k)
		if Relics.check_start(state, e.id, sid) == "" and _affordable(e):
			AiPlayer._issue(ctx, SimCommands.dig_start(e.id, sid))
		elif Relics.check_clue(state, e.id, sid) == "" and Relics.fragments(state, e.id) >= int(Relics.data()["digs"]["clue_fragments"]) + 5:
			AiPlayer._issue(ctx, SimCommands.dig_clue(e.id, sid))
	for rid in Relics.owned(state, e.id):
		var cost := Relics.triumph_split(state, e.id, rid)
		if Relics.check_triumph(state, e.id, rid) == "" and int(e.resources.get("influence", 0)) >= cost[0] + INFLUENCE_RESERVE:
			AiPlayer._issue(ctx, SimCommands.relic_triumph(e.id, rid))
			break
	# Un héros libre porte une relique du Reliquaire (il en tire de l'expérience).
	var free_rel := Relics.in_reliquary(state, e.id)
	if not free_rel.is_empty():
		for hid in Heroes.ids_of(state, e.id):
			if Relics.check_assign(state, e.id, free_rel[0], hid) == "" and String(state.heroes[hid]["post"]) == "council":
				AiPlayer._issue(ctx, SimCommands.relic_assign(e.id, free_rel[0], hid))
				break
	if Relics.can_trade(state, e.id) and Relics.fragments(state, e.id) > FRAGMENT_KEEP and Relics.check_sell_fragments(state, e.id) == "":
		AiPlayer._issue(ctx, SimCommands.fragments_sell(e.id))


static func _affordable(e: Empire) -> bool:
	var cost: Dictionary = Relics.data()["digs"]["start_cost"]
	for r in cost:
		if int(e.resources.get(r, 0)) < int(cost[r]) * 3 / 2:
			return false
	return true
