class_name TradeSystem
extends RefCounted
## Commerce (voir Trade), exécuté chaque mois, le jour du bilan, après l'économie : routes du mois,
## risques des pirates sur les routes, revenus (versés au bilan suivant), repaires nés d'une route
## laissée sans garde. Aucun aléatoire.


static func process(state: GameState) -> Array[Dictionary]:
	if state.tick % int(GameData.rules()["month_days"]) != 0:
		return []
	return Trade.compute(state)
