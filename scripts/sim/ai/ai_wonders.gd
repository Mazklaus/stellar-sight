class_name AiWonders
extends RefCounted
## L'IA et les merveilles galactiques (prop. 27). Une fois par mois environ : elle abandonne une course
## où un rival connu a deux quarts d'avance ; elle verse depuis ses colonies proches et presse le dernier
## quart quand ses réserves débordent ; puis, si elle n'a pas de grand chantier, elle choisit une
## merveille à sa portée selon son peuple, son credo et son tempérament, sur le meilleur site, et s'écarte
## des courses déjà mal engagées. La Recrue choisit mal (une merveille au hasard parmi les possibles,
## même trop chère pour elle) plutôt que de ne pas jouer ; elle ne sait pas renoncer.

const COLONY_LOOK := 6


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	if not Wonders.enabled(state):
		return
	var e: Empire = ctx["e"]
	if posmod(state.tick + e.id * 13, 30) >= maxi(1, int(ctx["lv"].get("think_days", 10))):
		return  # environ une fois par mois
	var rookie := String(e.ai_level) == "recrue"
	var seen := {}
	for pair in Wonders.builds_by(state, e.id):
		var wid := String(pair[0])
		var entry: Dictionary = pair[1]
		if not rookie and _behind(state, e.id, wid, entry, seen):
			if AiPlayer._issue(ctx, SimCommands.won_act(e.id, "cancel", wid)):
				AiPlayer._intent(ctx, "Renonce à %s : un rival a trop d'avance" % Wonders.label(wid))
				continue
		_help(ctx, wid, entry)
	WondersBridges.ai_think(ctx)
	if Wonders.active_count(state, e.id) >= Wonders.max_builds(state, e.id):
		return
	var pick := choose(ctx, seen)
	if pick.is_empty():
		return
	if AiPlayer._issue(ctx, SimCommands.won_act(e.id, "start", String(pick[0]), int(pick[1]))):
		AiPlayer._intent(ctx, "Lance %s" % Wonders.label(String(pick[0])))


## Un rival connu a deux quarts d'avance sur ce chantier.
static func _behind(state: GameState, eid: int, wid: String, entry: Dictionary, seen: Dictionary) -> bool:
	if not Wonders.galaxy_unique(wid):
		return false
	if seen.is_empty():
		seen.merge(Fleets.visible_systems(state, eid))
	var mine := Wonders.quarter(entry)
	for r in Wonders.rivals_known(state, eid, wid, seen):
		if int(r[1]) >= mine + 2:
			return true
	return false


## Verser depuis les colonies proches et presser le dernier quart, quand les réserves débordent.
static func _help(ctx: Dictionary, wid: String, entry: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var reserve := AiPlayer._material_reserve(ctx)
	var cost := int(Wonders.contribute_cost(state, e.id, wid).get("materials", 0))
	var n := 0
	for c in AiPlayer._my_colonies(ctx):
		if n >= 2 or AiPlayer._res(ctx, "materials") < reserve + cost * 4:
			break
		if Wonders.check_contribute(state, e.id, wid, c.planet_id) == "":
			if AiPlayer._issue(ctx, SimCommands.won_act(e.id, "contribute", wid, c.planet_id)):
				n += 1
	if Wonders.pct(entry) >= Wonders.r_int("rush_from_pct"):
		var rc := Wonders.rush_cost(state, e.id, wid)
		if AiPlayer._res(ctx, "influence") >= rc * 2 + 150:
			if AiPlayer._issue(ctx, SimCommands.won_act(e.id, "rush", wid)):
				AiPlayer._intent(ctx, "Presse l'achèvement de %s" % Wonders.label(wid))


## Meilleure merveille à lancer : [merveille, planète] ou [] si rien ne convient ou ne se paie.
static func choose(ctx: Dictionary, seen: Dictionary) -> Array:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var rookie := String(e.ai_level) == "recrue"
	var mat := AiPlayer._res(ctx, "materials")
	var cols := _sites(ctx)
	var cands: Array = []
	for wid in Wonders.all_ids():
		var d := Wonders.def(wid)
		if d.has("collective") or not Wonders.visible_for(state, e.id, wid) or not Wonders.unlocked(state, e.id, wid):
			continue
		if not Wonders.build_of(state, e.id, wid).is_empty():
			continue
		if Wonders.galaxy_unique(wid) and Wonders.built_at(state, wid) >= 0:
			continue
		var tot := Wonders.total_cost(state, e.id, wid)
		# Il faut l'avance et de quoi tenir : un tiers du coût en matériaux d'avance (la Recrue s'en moque).
		if not rookie and mat < AiPlayer._material_reserve(ctx) + int(tot.get("materials", 0)) / 3:
			continue
		var w := score(ctx, wid)
		if w <= 0:
			continue
		if not rookie and Wonders.galaxy_unique(wid):
			if seen.is_empty():
				seen.merge(Fleets.visible_systems(state, e.id))
			var late := false
			for r in Wonders.rivals_known(state, e.id, wid, seen):
				if int(r[1]) >= 2:
					late = true
			if late:
				continue
		for c: Colony in cols:
			if Wonders.check_start(state, e.id, c.planet_id, wid) == "":
				cands.append([wid, c.planet_id, w])
				break
	if cands.is_empty():
		return []
	if rookie:
		var i := absi(hash([state.seed_value, e.id, state.tick, "merveille"])) % cands.size()
		return [cands[i][0], cands[i][1]]
	cands.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) > int(b[2]) if int(a[2]) != int(b[2]) else String(a[0]) < String(b[0]))
	return [cands[0][0], cands[0][1]]


## Colonies où chercher un site : la capitale, les plus peuplées, puis les avant-postes.
static func _sites(ctx: Dictionary) -> Array[Colony]:
	var e: Empire = ctx["e"]
	var cols: Array[Colony] = []
	var outposts: Array[Colony] = []
	for c in AiPlayer._my_colonies(ctx):
		if not c.is_established():
			continue
		if c.is_colony():
			cols.append(c)
		else:
			outposts.append(c)
	cols.sort_custom(func(a: Colony, b: Colony) -> bool:
		if (a.planet_id == e.capital_planet) != (b.planet_id == e.capital_planet):
			return a.planet_id == e.capital_planet
		return a.population > b.population if a.population != b.population else a.planet_id < b.planet_id)
	var out: Array[Colony] = cols.slice(0, COLONY_LOOK)
	out.append_array(outposts.slice(0, 3))
	return out


## Intérêt d'une merveille pour ce peuple : sa famille, son ère, et ce que son tempérament aime.
static func score(ctx: Dictionary, wid: String) -> int:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var d := Wonders.def(wid)
	var w := 10 + int(d.get("era", 1)) * 2 + int(d.get("score", 0)) / 5
	match Wonders.family(wid):
		"registre", "credo":
			w += 8
		"mega":
			w += 6
		"oeuvre":
			w += 20 if WondersBridges.oeuvres_on(state) else -100
	var temper := clampi(AiLevels.aggression(e), -2, 2)
	var fx: Dictionary = d.get("fx", {})
	for k in ["damage_pct", "ship_cost_pct", "ground_damage_pct", "garrison_pct", "home_damage_pct", "supply_range"]:
		if fx.has(k):
			w += 3 * temper
	for k in ["opinion_all", "culture_pct", "trade_routes", "trade_income_pct", "stability"]:
		if fx.has(k):
			w -= 2 * temper
	if bool(d.get("culture", false)) or int(d.get("culture_wonder", 0)) > 0:
		w += 4 if temper <= 0 else 0
	return w
