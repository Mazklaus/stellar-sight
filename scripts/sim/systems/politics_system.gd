class_name PoliticsSystem
extends RefCounted
## Politique intérieure (voir Politics), exécutée chaque mois avant la stabilité : opinion qui revient
## vers le penchant du peuple, poussées du mois, consensus des consciences et élections échues.
## Aucun aléatoire hors des tirages par hachage de Politics ; empires parcourus dans l'ordre.


static func process(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	if not state.politics_on or state.tick % int(GameData.rules()["month_days"]) != 0:
		return added
	Politics.prune(state)
	for e in state.empires:
		if Politics.applies(state, e.id):
			Politics.monthly(state, e.id, added)
	return added
