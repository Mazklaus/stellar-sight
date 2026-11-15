class_name AiCulture
extends RefCounted
## L'IA et le rayonnement culturel (prop. 36), selon son tempérament : elle bâtit un Musée galactique,
## ses stations de villégiature dans les beaux systèmes et les merveilles culturelles quand les
## matériaux s'entassent ; elle achète des savoirs par osmose quand l'énergie déborde ; pacifique ou
## prudente, elle ouvre une ambassade culturelle et envoie sa Troupe de spectacle ; agressive ou
## belliqueuse, elle mène campagnes et dénigrement par l'espionnage, vole les œuvres exposées, et vote
## l'Exception culturelle quand une culture étrangère la domine. Les osmoses de lois se décident au
## moment de l'offre (CultureLife._ai_accepts). La Recrue oublie la moitié de tout cela.


static func wants_late(ctx: Dictionary) -> bool:
	var state: GameState = ctx["state"]
	return Culture.enabled(state) and (ctx["e"] as Empire).techs.has("arts_holographiques")


## Chantiers culturels souhaités pour une colonie (appelé par AiPlayer.late_wishes).
static func late_wishes(ctx: Dictionary, c: Colony) -> Array[String]:
	var out: Array[String] = []
	var state: GameState = ctx["state"]
	if not Culture.enabled(state):
		return out
	var e: Empire = ctx["e"]
	var mat := AiPlayer._res(ctx, "materials")
	if c.is_colony() and AiPlayer._is_main_yard(ctx, c):
		if Economy.building_unlocked(state, e.id, "musee_galactique") and mat >= 450 and not AiPlayer._empire_has_building(ctx, "musee_galactique"):
			out.append("musee_galactique")
	if Economy.building_unlocked(state, e.id, "villegiature") and mat >= 350:
		var sid := state.galaxy.get_planet(c.planet_id).system_id
		if Culture.beauty(state, sid) >= 3:
			out.append("villegiature")
	return out


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	if not Culture.enabled(state):
		return
	var e: Empire = ctx["e"]
	var every := maxi(1, int(ctx["lv"].get("think_days", 10)))
	if posmod(state.tick + e.id * 11, 30) >= every:
		return  # environ une fois par mois
	if String(e.ai_level) == "recrue" and posmod(int(state.tick / 30.0) + e.id, 2) == 0:
		return  # la Recrue oublie un mois sur deux
	var temper := clampi(AiLevels.aggression(e), -2, 2)
	_osmosis(ctx)
	_defend(ctx)
	if temper <= 0:
		_embassy(ctx)
		_troupe(ctx)
	else:
		_ops(ctx, temper)


## Osmose des savoirs : la moins chère, si l'énergie couvre trois fois le prix.
static func _osmosis(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var best := ""
	var bc := 0
	for tid in CultureLife.tech_offers(state, e.id):
		var c := int(CultureLife.tech_cost(state, e.id, tid)["energy"])
		if best == "" or c < bc:
			best = tid
			bc = c
	if best != "" and AiPlayer._res(ctx, "energy") >= bc * 3:
		if AiPlayer._issue(ctx, SimCommands.cul_act(e.id, "savoir", -1, best)):
			AiPlayer._intent(ctx, "Apprend « %s » par osmose" % String(Research.tech(best).get("label", best)))


## Une culture étrangère Influente ou mieux chez soi : l'Exception culturelle.
static func _defend(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not state.politics_on:
		return
	var top := Culture.top_influencer(state, e.id)
	if int(top[0]) >= 4 and not Laws.is_enacted(state, e.id, "exception_culturelle"):
		if AiPlayer._issue(ctx, SimCommands.law_adopt(e.id, "exception_culturelle")):
			AiPlayer._intent(ctx, "Vote l'Exception culturelle")


static func _embassy(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if CultureBridges.embassies(state, e.id).size() >= CultureBridges.embassy_max(state, e.id):
		return
	if AiPlayer._res(ctx, "influence") < 200:
		return
	var best := -1
	for b in Culture.targets(state, e.id):
		if GameState.is_minor(b) or not CultureBridges.embassy_ok(state, e.id, b):
			continue
		if best < 0 or Culture.last(state, e.id, b) > Culture.last(state, e.id, best):
			best = b
	if best >= 0 and AiPlayer._issue(ctx, SimCommands.cul_act(e.id, "ambassade", best)):
		AiPlayer._intent(ctx, "Ouvre une ambassade culturelle chez %s" % state.get_empire(best).short_name())


## La Troupe part chez l'empire où l'on est le plus près du palier suivant.
static func _troupe(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if AiPlayer._res(ctx, "energy") < 400 or AiPlayer._res(ctx, "influence") < 120:
		return
	var best := -1
	var bm := 0
	for b in Culture.targets(state, e.id):
		if GameState.is_minor(b):
			continue
		var m := Culture.months_to_next(state, e.id, b)
		if m > 0 and (best < 0 or m < bm):
			best = b
			bm = m
	if best >= 0 and AiPlayer._issue(ctx, SimCommands.cul_act(e.id, "troupe", best)):
		AiPlayer._intent(ctx, "Envoie sa Troupe de spectacle chez %s" % state.get_empire(best).short_name())


## Agressive : campagne chez le voisin où l'on rayonne le plus ; belliqueuse : vol d'œuvre et dénigrement.
static func _ops(ctx: Dictionary, temper: int) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if AiPlayer._res(ctx, "influence") < 150:
		return
	var ops := ["campagne_culturelle"]
	if temper >= 2:
		ops = ["vol_oeuvre", "denigrement", "campagne_culturelle"]
	for b in Culture.living(state):
		if b == e.id or not e.contacts.has(b):
			continue
		for op in ops:
			if AiPlayer._issue(ctx, SimCommands.spy_op(e.id, b, op)):
				AiPlayer._intent(ctx, "%s chez %s" % [String(Espionage.op_def(op).get("label", op)), state.get_empire(b).short_name()])
				return
