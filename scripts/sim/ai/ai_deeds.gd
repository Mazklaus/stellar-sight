class_name AiDeeds
extends RefCounted
## L'IA et les hauts faits galactiques (prop. 30). Elle ne « vise » pas un haut fait en soi : ils
## tombent de ce qu'elle fait déjà (explorer, coloniser, se battre, signer). Ce module choisit sa
## récompense (tout de suite, sans fenêtre) selon son tempérament et ses besoins, et annonce dans son
## intention le haut fait qu'elle est sur le point de prendre. La Recrue choisit mal : toujours la
## première récompense proposée, quelle qu'elle soit.


## Récompense choisie parmi les choix tirés.
static func pick(state: GameState, eid: int, choices: Array) -> String:
	var e := state.get_empire(eid)
	if choices.is_empty():
		return ""
	if e == null or String(e.ai_level) == "recrue":
		return String(choices[0])
	var aggr := AiLevels.aggression(e)
	var best := String(choices[0])
	var best_v := -100000
	for rid in choices:
		var v := _value(state, e, String(rid), aggr)
		if v > best_v:
			best = String(rid)
			best_v = v
	return best


static func _value(state: GameState, e: Empire, rid: String, aggr: int) -> int:
	var r := Deeds.reward_def(rid)
	match String(r["k"]):
		"trophy":
			return 60  # unique et permanent
		"ships":
			return 30 + aggr * 15 + (25 if not e.wars.is_empty() else 0)
		"hero":
			return 45
		"research":
			return 40 - aggr * 5
		"res":
			var v := 30
			for res in r["res"]:
				if int(e.resources.get(res, 0)) < 200:
					v += 15
			return v
	return 0


## Une fois par mois : annoncer le haut fait encore à prendre qu'elle est la plus près d'accomplir.
static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	if not Deeds.enabled(state):
		return
	var e: Empire = ctx["e"]
	if posmod(state.tick + e.id * 7, 30) != 0:
		return
	var best := ""
	var best_p := 74
	for id in Deeds.pool(state):
		var sid := String(id)
		if Deeds.is_won(state, sid) or Deeds.sort_of(sid) == "secret":
			continue
		var p := Deeds.pct(state, e.id, sid)
		if p > best_p and p < 100:
			best = sid
			best_p = p
	if best != "":
		AiPlayer._intent(ctx, "Vise le haut fait « %s » (%d %%)" % [Deeds.label(best), best_p])
