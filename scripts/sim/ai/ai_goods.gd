class_name AiGoods
extends RefCounted
## Luxes, marché et échanges des empires IA (voir Goods). Une fois par mois (jour décalé par empire) :
## acheter une licence d'un luxe qui manque quand l'énergie le permet, acheter au marché les
## stratégiques qui manquent et vendre les surplus, fermer ses licences aux empires détestés.
## Les échanges proposés se jugent dans evaluate_offer, avec un détail lisible comme un traité.
## La Recrue ne fait rien de tout cela (elle répond seulement aux propositions).


## L'IA vend-elle ses licences à cet empire ? Non à un ennemi ni à un empire qu'elle déteste.
static func sells_to(state: GameState, seller: int, buyer: int) -> bool:
	return not Combat.at_war(state, seller, buyer) and Diplomacy.opinion(state, seller, buyer) >= -10


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if state.goods.is_empty() or AiPlayer._use(ctx) < 1:
		return
	if posmod(state.tick - e.id * 7, int(GameData.rules()["month_days"])) != 0 or AiPlayer._forgets(ctx):
		return
	if Goods.active(state):
		_licences(ctx)
	if Goods.market_on(state):
		_market(ctx)


static func _licences(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var energy := int(e.resources.get("energy", 0))
	var net := int(AiPlayer._net(ctx).get("energy", 0))
	if energy < 250 or net < 5:
		return
	var best := []
	for o in Trade.partners(state, e.id):
		for g in Goods.luxury_ids():
			if Goods.check_licence(state, e.id, o, g) != "":
				continue
			var t := int(Goods.luxury(g)["tier"])
			best.append([-t, Goods.licence_price(state, o, e.id, g), o, g])
	if best.is_empty():
		return
	best.sort()
	var pick: Array = best[0]
	if int(pick[1]) * 3 > net:
		return
	if AiPlayer._issue(ctx, SimCommands.licence_buy(e.id, int(pick[2]), String(pick[3]))):
		AiPlayer._intent(ctx, "Achète une licence : %s" % Goods.label(String(pick[3])))


static func _market(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var energy := int(e.resources.get("energy", 0))
	# Stratégiques : une petite réserve dès l'ère qui les demande.
	if Goods.active(state):
		var era := Research.current_era(state, e.id)
		for s in GameData.strategic_ids():
			var need_era := int(Goods.strategic(s)["era"]) + 1
			if era < need_era or int(e.resources.get(s, 0)) >= 12:
				continue
			var n := 12 - int(e.resources.get(s, 0))
			if energy > 400 + Goods.buy_cost(state, e.id, s, n) and AiPlayer._issue(ctx, SimCommands.market_trade(e.id, s, n)):
				energy = int(e.resources.get("energy", 0))
				AiPlayer._intent(ctx, "Achète du %s au marché" % Goods.label(s).to_lower())
	# Stratégiques en trop : la réserve au-delà de 150 part au marché.
	if Goods.active(state):
		for s in GameData.strategic_ids():
			var st_n := int(e.resources.get(s, 0))
			if st_n > 150:
				AiPlayer._issue(ctx, SimCommands.market_trade(e.id, s, -(st_n - 100)))
	# Surplus : vendre ; manques : acheter.
	var mats := int(e.resources.get("materials", 0))
	var food := int(e.resources.get("food", 0))
	if mats > 2500:
		AiPlayer._issue(ctx, SimCommands.market_trade(e.id, "materials", -(mats - 2000)))
	elif mats < 80 and energy > 600:
		AiPlayer._issue(ctx, SimCommands.market_trade(e.id, "materials", 100))
	if food > 1500:
		AiPlayer._issue(ctx, SimCommands.market_trade(e.id, "food", -(food - 1200)))
	elif food < 20 and int(e.resources.get("energy", 0)) > 300:
		AiPlayer._issue(ctx, SimCommands.market_trade(e.id, "food", 60))


## Jugement d'un échange proposé à l'IA : {"score", "lines"} (accepté si score >= 0).
static func evaluate_offer(state: GameState, eid: int, o: Dictionary) -> Dictionary:
	var lines := []
	var e := state.get_empire(eid)
	var other := int(o["from"]) if int(o["to"]) == eid else int(o["to"])
	var mine := eid == int(o["to"])
	var recv: Dictionary = o["give"] if mine else o["get"]
	var pay: Dictionary = o["get"] if mine else o["give"]
	# Sur la durée, chaque versement se juge comme le premier (le reste est une promesse).
	var gain := Goods.value_of(state, eid, recv) - Goods.value_of(state, eid, pay)
	# Ce qui manque vaut plus : un stratégique qu'elle n'a pas, une ressource presque épuisée.
	var need := 0
	for r in recv:
		if GameData.strategic_ids().has(String(r)) and int(e.resources.get(r, 0)) < 5:
			@warning_ignore("integer_division")
			need += int(recv[r]) * Goods.base_price(String(r)) / 2
		elif (String(r) == "food" or String(r) == "materials") and int(e.resources.get(r, 0)) < 50:
			@warning_ignore("integer_division")
			need += int(recv[r]) / 2
	lines.append(["Valeur de l'échange", gain])
	if need > 0:
		lines.append(["Ce qui nous manque", need])
	@warning_ignore("integer_division")
	var op := Diplomacy.opinion(state, eid, other) / 5
	lines.append(["Opinion", op])
	if int(o["months"]) > 0:
		lines.append(["Engagement sur la durée", -5])
	var score := 0
	for l in lines:
		score += int(l[1])
	return {"score": score, "lines": lines}
