class_name AiTechTrade
extends RefCounted
## Accords de recherche et licences de technologie des empires IA (voir TechTrade). Une fois par
## mois (jour décalé par empire) : proposer un accord de recherche à un voisin en paix quand
## l'énergie le permet, acheter une licence de la technologie la plus utile chez un partenaire.
## Les réponses aux propositions se jugent ici aussi. La Recrue ne propose rien (elle répond).


## L'IA accepte-t-elle l'accord proposé par cet empire ? Il faut de quoi payer en gardant une
## réserve, et ne pas détester l'autre.
static func accepts_pact(state: GameState, eid: int, other: int) -> bool:
	var e := state.get_empire(eid)
	var cost := TechTrade.pact_cost(state, eid, other)
	return Diplomacy.opinion(state, eid, other) >= -5 and int(e.resources.get("energy", 0)) >= cost + 150


## L'IA vend-elle cette technologie ? Pas à un ennemi, pas à un empire qu'elle déteste, et pas une
## technologie d'armement à un empire plus puissant qu'elle.
static func sells_licence(state: GameState, seller: int, buyer: int, tid: String) -> bool:
	if not AiGoods.sells_to(state, seller, buyer) or Diplomacy.opinion(state, seller, buyer) < 0:
		return false
	if String(Research.tech(tid).get("domain", "")) == "armement" and FactionTraits.war_power(state, buyer) > FactionTraits.war_power(state, seller):
		return false
	return true


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if state.goods.is_empty() or AiPlayer._use(ctx) < 1:
		return
	if posmod(state.tick - e.id * 7 - 10, int(GameData.rules()["month_days"])) != 0 or AiPlayer._forgets(ctx):
		return
	_pact(ctx)
	_licence(ctx)


static func _pact(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if TechTrade.pacts_of(state, e.id).size() >= int(TechTrade.data()["pact_max"]):
		return
	var best := []
	for o in e.contacts:
		if TechTrade.check_pact(state, e.id, int(o)) != "":
			continue
		if int(e.resources.get("energy", 0)) < TechTrade.pact_cost(state, e.id, int(o)) + 400:
			return
		best.append([-Diplomacy.opinion(state, e.id, int(o)), int(o)])
	if best.is_empty():
		return
	best.sort()
	var pick := int(best[0][1])
	if AiPlayer._issue(ctx, SimCommands.research_pact(e.id, pick)):
		AiPlayer._intent(ctx, "Propose un accord de recherche à %s" % state.get_empire(pick).short_name())


static func _licence(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var energy := int(e.resources.get("energy", 0))
	# Une licence par trimestre au plus : le Savoir acheté ne remplace pas la recherche.
	@warning_ignore("integer_division")
	if energy < 600 or posmod(state.tick / int(GameData.rules()["month_days"]) - e.id, 3) != 0:
		return
	# Ce qui est en tête de la file d'abord, puis la licence qui apporte le plus de Savoir par énergie.
	var want := e.research_queue[0] if not e.research_queue.is_empty() else ""
	var best := []
	for o in Trade.partners(state, e.id):
		for tid in TechTrade.licences_offered(state, e.id, o):
			if TechTrade.check_licence(state, e.id, o, tid) != "":
				continue
			var price := TechTrade.licence_price(state, e.id, tid)
			if price > energy - 400:
				continue
			best.append([0 if tid == want else 1, price, o, tid])
	if best.is_empty():
		return
	best.sort()
	var pick: Array = best[0]
	if AiPlayer._issue(ctx, SimCommands.tech_licence(e.id, int(pick[2]), String(pick[3]))):
		AiPlayer._intent(ctx, "Achète une licence : %s" % String(Research.tech(String(pick[3])).get("label", pick[3])))
