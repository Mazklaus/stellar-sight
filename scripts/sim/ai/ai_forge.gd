class_name AiForge
extends RefCounted
## IA et Forge des mondes (prop. 34 ; voir WorldForge, data/worldforge.json).
## Une fois par mois, si le pilier est en jeu : cherche l'Agglomération puis les Mondes-coquilles, garde un
## Vaisseau-architecte, fond sa Masse quand les matériaux manquent, et lance des chantiers planétaires par
## ordre de préférence en gardant une réserve. Elle démantèle les géantes et les ceintures sans valeur,
## jamais un monde habitable si elle est pacifique ou prudente ; elle n'évacue jamais, ne lance jamais de
## bélier (choix laissé au joueur) et ouvre les mondes-reliquaires qu'elle tient. La Recrue oublie souvent.

const PREFS := ["ouvrir", "coquille", "habitat", "module", "agglomerer", "creuser", "comprimer", "sur_mesure", "demanteler"]
const TECHS := [["agglomeration", 3], ["mondes_coquilles", 4], ["compression_gravitationnelle", 4], ["demantelement", 4]]


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not WorldForge.applies(state, e.id):
		return
	@warning_ignore("integer_division")
	var month := state.tick / int(GameData.rules()["month_days"]) + 1
	if WorldForge.stat(state, e.id, "ai_month") >= month:
		return
	WorldForge._stat(state, e.id, "ai_month", month - WorldForge.stat(state, e.id, "ai_month"))
	if AiPlayer._forgets(ctx):
		return
	_research(ctx)
	_melt(ctx)
	if not _architect(ctx):
		return
	_plan(ctx)


static func _reserve() -> Dictionary:
	return WorldForge.r_dict("ai_reserve")


static func _rich(e: Empire, cost: Dictionary) -> bool:
	var res := _reserve()
	for r in res:
		if int(e.resources.get(r, 0)) < int(res[r]) + int(cost.get(r, 0)):
			return false
	return Economy.can_afford(e, cost)


static func _research(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not e.research_queue.is_empty():
		return
	for pair in TECHS:
		var t := String(pair[0])
		if e.techs.has(t) or Research.current_era(state, e.id) < int(pair[1]):
			continue
		if t == "demantelement" and not WorldForge.dismantle_on(state):
			continue
		var step := AiGenetics.reachable(state, e, t, 2)
		if step != "":
			AiPlayer._issue(ctx, SimCommands.research(e.id, step))
		return


static func _melt(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var m := WorldForge.mass(state, e.id)
	if m < 10 or int(e.resources.get("materials", 0)) >= int(_reserve().get("materials", 250)):
		return
	# On garde de quoi bâtir une planète sur mesure si on sait en faire.
	var keep := WorldForge.op_mass("sur_mesure") if WorldForge.unlocked(state, e.id, "sur_mesure") else 0
	var n := (m - keep) / 10 * 10
	if n > 0:
		AiPlayer._issue(ctx, SimCommands.forge_act(e.id, "melt", {"n": n}))


static func _architect(ctx: Dictionary) -> bool:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if WorldForge.busy(state, e.id) >= WorldForge.slots(state, e.id):
		return false
	return AiMegas._architect(ctx)


## Démanteler ce corps ? Seulement les géantes et les ceintures ; un monde stérile si l'IA n'est ni
## pacifique ni prudente. Jamais un monde habitable.
static func _wants_dismantle(state: GameState, e: Empire, pid: int) -> bool:
	var p := state.galaxy.get_planet(pid)
	if p == null or int(GameData.planet_type(p.type).get("base_hab", 0)) > 0:
		return false
	if not WorldForgeBridges.untouchable(state, e.id, pid).is_empty():
		return false
	if p.type == "gas_giant" or p.type == "asteroids":
		return true
	var calm := e.ai_temperament == "pacifique" or e.ai_temperament == "prudent"
	return p.type == "barren" and not calm and bool(WorldForge.cfg("ai").get("builder_dismantle", true))


static func _plan(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	for op in PREFS:
		if not WorldForge.unlocked(state, e.id, op):
			continue
		var arg := "prefere" if op == "sur_mesure" else ""
		var sites := WorldForge.sites(state, e.id, op, 6, arg)
		for site: Array in sites:
			var sid := int(site[0])
			var pid := int(site[1])
			if op == "demanteler" and not _wants_dismantle(state, e, pid):
				continue
			if op == "agglomerer" and state.galaxy.get_planet(pid).deposits.size() > 1:
				continue  # une ceinture riche rapporte plus telle quelle
			if not _rich(e, WorldForge.op_cost(state, e.id, op, sid)):
				return
			if WorldForge.check_plan(state, e.id, op, sid, pid, arg) != "":
				continue
			if AiPlayer._issue(ctx, SimCommands.forge_act(e.id, "plan", {"op": op, "s": sid, "p": pid, "a": arg})):
				AiPlayer._intent(ctx, "Forge des mondes : %s" % WorldForge.op_label(op).to_lower())
			return
