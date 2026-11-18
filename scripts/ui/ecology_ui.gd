class_name EcologyUi
extends RefCounted
## Actions de l'écologie dans la fiche de planète (vue système) : Monde-usine (prop. 24) et terre
## brûlée (prop. 23). Le reste de l'écologie s'affiche dans l'écran Colonies (onglet Biosphères).


static func system_actions(state: GameState, player: int, p: Planet, emit: Callable) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if state == null or player < 0 or not Ecology.enabled(state):
		return out
	var c: Colony = state.colonies.get(p.id)
	if c == null or c.owner != player or not Ecology.has_biosphere(state, p.id):
		return out
	var d := {"pid": p.id}
	var fc := EcologyBridges.cfg("factory")
	if (fc.get("from_types", []) as Array).has(p.type) or String(Ecology.tier(state, p.id).get("id", "")) == String(fc.get("from_tier", "effondree")):
		out.append(WondersUi._act(state, SimCommands.eco_act(player, "factory", d), "Faire un monde-usine", "irréversible",
				"On renonce à la biosphère : plus de palier ni de basculement, +%d %% de matériaux et d'énergie, %d stabilité dans le système (mondes-ruches de Warhammer 40K)." % [
				int(fc.get("yield_pct", 25)), int(fc.get("stab", -10))], emit))
	if EcologyBridges.evacuating(state, p.id) or Combat.is_besieged(state, p.system_id):
		out.append(WondersUi._act(state, SimCommands.eco_act(player, "scorch", d), "Terre brûlée", "biosphère à 0",
				"Ce qu'on ne peut garder, l'ennemi ne l'aura pas : la biosphère tombe à 0 et, en écologie Complète, le climat bascule le mois suivant.", emit))
	return out
