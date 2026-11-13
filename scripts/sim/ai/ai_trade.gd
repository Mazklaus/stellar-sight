class_name AiTrade
extends RefCounted
## Le commerce des empires IA (voir Trade) : réserver une route intérieure quand de jeunes colonies
## attendent et que la capacité le permet, lever un embargo devenu inutile, et dire quand un comptoir
## serait utile (AiPlayer.building_wishes le met alors dans ses chantiers). Les propositions de commerce
## et la montée des paliers passent par AiDiplomacy.
## La Recrue ne réserve rien et garde ses embargos ; Normal et au-delà gèrent tout.


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if AiPlayer._use(ctx) < 1 or AiPlayer._forgets(ctx):
		return
	_reserve(ctx)
	for t in Trade.embargoes_of(state, e.id):
		if Diplomacy.opinion(state, e.id, t) > 10 and not Combat.at_war(state, e.id, t):
			if AiPlayer._issue(ctx, SimCommands.lift_embargo(e.id, t)):
				AiPlayer._intent(ctx, "Lève son embargo contre %s" % state.get_empire(t).short_name())
				return


## Une place réservée aux jeunes colonies quand il y en a au moins deux et que les partenaires ne
## remplissent pas déjà toute la capacité ; aucune sinon.
static func _reserve(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var cap := Trade.capacity(state, e.id)
	var want := 0
	if Trade.young_colonies(state, e.id).size() >= 2 and cap >= 2 and Trade.partners(state, e.id).size() < cap:
		want = 1
	if want != Trade.reserved(state, e.id):
		AiPlayer._issue(ctx, SimCommands.trade_reserve(e.id, want))


## Un comptoir vaut-il le coup ? Plus de partenaires que de places, pas déjà de comptoir en chantier,
## au plus trois comptoirs.
static func wants_comptoir(ctx: Dictionary) -> bool:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not ctx.has("want_comptoir"):
		var cs := Trade.comptoirs(state, e.id)
		var building := false
		for c in AiPlayer._my_colonies(ctx):
			if c.construction == "comptoir":
				building = true
		ctx["want_comptoir"] = not building and cs.size() < 3 and Trade.partners(state, e.id).size() + mini(1, Trade.young_colonies(state, e.id).size()) > Trade.capacity(state, e.id)
	return bool(ctx["want_comptoir"])
