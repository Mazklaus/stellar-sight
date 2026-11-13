class_name GoodsSystem
extends RefCounted
## Luxes, stratégiques et marché (voir Goods), chaque mois, le jour du bilan, avant les routes :
## gisements exploités, stratégiques extraits, licences, monopoles, contrats d'échange, retour des
## prix et ordres mensuels du marché ; accords de recherche et propositions de licence (TechTrade).
## Aucun aléatoire.


static func process(state: GameState) -> Array[Dictionary]:
	if state.tick % int(GameData.rules()["month_days"]) != 0:
		return []
	var added := Goods.monthly(state)
	added.append_array(TechTrade.monthly(state))
	added.append_array(TradeLinks.monthly(state))
	return added
