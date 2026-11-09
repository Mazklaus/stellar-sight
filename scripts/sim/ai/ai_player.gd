class_name AiPlayer
extends RefCounted
## Le cerveau d'un empire IA. Appelé par AiSystem les jours où l'empire réfléchit.
##
## Organisation inspirée de l'IA d'Endless Space 2 (des objectifs qui reçoivent une « motivation »
## et se partagent les ressources) mais en beaucoup plus simple : une suite de modules, chacun
## examine l'état et donne des ordres ordinaires (SimCommands) tant que les ressources le permettent.
## Chaque ordre est validé puis appliqué tout de suite, si bien que le module suivant voit
## les ressources déjà dépensées.
##
## Modules, dans l'ordre :
## 1. talents du peuple (offrande du Chœur, vote d'urgence de Vael…) selon faction_use ;
## 2. bâtiments : ce qui manque à l'économie, avec le penchant du peuple ;
## 3. revendications sans vaisseau dans les systèmes déjà tenus ;
## 4. chantiers spatiaux : éclaireurs et vaisseaux colons (ou spores) ;
## 5. flottes : exploration automatique, vaisseaux colons vers la meilleure cible ;
## 6. militaire et 7. diplomatie : points d'extension, vides tant que ces systèmes n'existent pas.
##
## Règles d'or : la simulation reste déterministe (aucun aléatoire hors de l'état : les « oublis »
## des niveaux bas viennent d'un hachage de la graine, du jour et de l'empire), l'IA ne lit que
## ce que son empire sait (systèmes explorés, routes connues), et tout passe par SimCommands.

## Valeur minimale d'une planète pour justifier un vaisseau colon.
const MIN_TARGET_VALUE := 12
## Matériaux gardés de côté pour un vaisseau colon quand il en manque un.
const COLONIZER_RESERVE := 100


## Réfléchit et agit pour l'empire e.
static func think(state: GameState, e: Empire) -> void:
	var ctx := {
		"state": state,
		"e": e,
		"lv": AiLevels.level(e.ai_level),
		"ai": AiLevels.personality(e),
		"salt": 0,
		"intent": "",
	}
	_faction_talents(ctx)
	_buildings(ctx)
	_foothold_claims(ctx)
	_shipyards(ctx)
	_fleets(ctx)
	_military(ctx)
	_diplomacy(ctx)
	if String(ctx["intent"]) != "":
		e.ai_intent = ctx["intent"]


# --- Outils ------------------------------------------------------------------------------------

## Valide puis applique un ordre de l'IA. Renvoie true s'il a été appliqué.
static func _issue(ctx: Dictionary, cmd: Dictionary) -> bool:
	var state: GameState = ctx["state"]
	if SimCommands.validate(state, cmd) != "":
		return false
	SimCommands.apply(state, cmd)
	return true


## Les niveaux bas « oublient » parfois une décision (moins réactifs, comme dans Endless Space 2).
## Déterministe : hachage de la graine, du jour, de l'empire et d'un compteur.
static func _forgets(ctx: Dictionary) -> bool:
	var pct := int(ctx["lv"].get("mistake_pct", 0))
	if pct <= 0:
		return false
	var state: GameState = ctx["state"]
	ctx["salt"] = int(ctx["salt"]) + 1
	return posmod(hash([state.seed_value, state.tick, ctx["e"].id, ctx["salt"]]), 100) < pct


## Niveau d'usage des talents du peuple : 0 aucun, 1 les bases, 2 tout.
static func _use(ctx: Dictionary) -> int:
	return int(ctx["lv"].get("faction_use", 1))


static func _intent(ctx: Dictionary, text: String) -> void:
	if String(ctx["intent"]) == "":
		ctx["intent"] = text


## Bilan mensuel de l'empire, calculé une fois par réflexion : les ordres du jour (chantiers,
## fondations) ne changent la production qu'une fois achevés.
static func _net(ctx: Dictionary) -> Dictionary:
	if not ctx.has("net"):
		ctx["net"] = Economy.empire_income(ctx["state"], ctx["e"].id)["net"]
	return ctx["net"]


static func _res(ctx: Dictionary, r: String) -> int:
	return int(ctx["e"].resources.get(r, 0))


## Colonies établies de l'empire, par identifiant de planète.
static func _own_colonies(state: GameState, empire_id: int, established_only := true) -> Array[Colony]:
	var out: Array[Colony] = []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == empire_id and (c.is_established() or not established_only):
			out.append(c)
	return out


## Classe de vaisseau colonisateur que l'empire construit ("" si aucune).
static func colonizer_class(e: Empire) -> String:
	for sid in FactionTraits.ship_ids_for(e.faction_id):
		if GameData.ship(sid).get("colonizer", false):
			return sid
	return ""


## Classe d'éclaireur : le vaisseau non colonisateur qui voit le plus loin.
static func scout_class(e: Empire) -> String:
	var best := ""
	for sid in FactionTraits.ship_ids_for(e.faction_id):
		var sd := GameData.ship(sid)
		if sd.get("colonizer", false):
			continue
		if best == "" or int(sd.get("vision", 0)) > int(GameData.ship(best).get("vision", 0)):
			best = sid
	return best


# --- Valeur des planètes et des cibles ---------------------------------------------------------

## Ce que vaut une planète libre pour l'empire : {"kind": colonie ou avant-poste, "value": int}.
## Les talents du peuple pèsent dès faction_use 1.
static func planet_value(state: GameState, e: Empire, p: Planet, use := 1) -> Dictionary:
	var ai := AiLevels.personality(e)
	var deposits := 0
	var crystals := false
	for d in p.deposits:
		deposits += 1
		crystals = crystals or d == "crystals"
	var maxp := Economy.max_pop(state, p, e.id)
	var kind := Colony.KIND_COLONY if maxp >= 1 else Colony.KIND_OUTPOST
	var value := 0
	if kind == Colony.KIND_COLONY:
		value = maxp * 3 + deposits * 6
	else:
		var y: Dictionary = GameData.planet_type(p.type).get("outpost_yields", {})
		for r in y:
			value += int(y[r]) * 4
		value += deposits * 6
	# Les goûts du peuple pèsent à tous les niveaux ; la Recrue les suit sans réfléchir
	# (Ossarane court après les cristaux sans compter ce que coûtent les fiefs lointains).
	value += int(ai.get("colony_bonus", 0)) if kind == Colony.KIND_COLONY else int(ai.get("outpost_bonus", 0))
	if crystals:
		value += int(ai.get("crystal_bonus", 0))
	return {"kind": kind, "value": value}


## Meilleure planète à revendiquer dans un système pour l'empire : {"planet", "kind", "value"},
## ou {} s'il n'y a rien à prendre (déjà pris, ou système d'un autre empire).
static func best_claim(state: GameState, e: Empire, system_id: int, use := 1) -> Dictionary:
	var owner := state.system_owner(system_id)
	if owner != -1 and owner != e.id:
		return {}
	var best := {}
	for pid in state.galaxy.systems[system_id].planet_ids:
		var c: Colony = state.colonies.get(pid)
		var p := state.galaxy.get_planet(pid)
		var v := {}
		if c == null:
			v = planet_value(state, e, p, use)
		elif c.owner == e.id and c.kind == Colony.KIND_OUTPOST and c.is_established() and Economy.max_pop(state, p, e.id) >= 1:
			v = planet_value(state, e, p, use)  # un avant-poste habitable peut devenir colonie
			if v["kind"] != Colony.KIND_COLONY:
				continue
		else:
			continue
		if best.is_empty() or int(v["value"]) > int(best["value"]):
			best = {"planet": pid, "kind": v["kind"], "value": v["value"]}
	return best


## Systèmes déjà visés par l'empire : destinations de ses vaisseaux colons, et systèmes où une
## revendication est en cours de fondation.
static func _targeted(state: GameState, e: Empire, except_fleet := -1) -> Dictionary:
	var out := {}
	for f in Fleets.empire_fleets(state, e.id):
		if f.id != except_fleet and Fleets.colonizer_ship(f) != "":
			out[f.destination()] = true
	return out


## Pénalité Ossarane : un fief lointain coûte des cristaux ; l'IA l'évite tant qu'elle ne peut pas
## les payer (faction_use 1 : évite tout fief lointain sans production de cristaux ; 2 : fait le
## compte exact des cristaux disponibles).
static func _far_fief_penalty(ctx: Dictionary, system_id: int) -> int:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var f := e.faction()
	if not FactionTraits.has_fiefs(f) or _use(ctx) < 1 or e.capital_planet < 0:
		return 0
	var cap_sys := state.galaxy.get_planet(e.capital_planet).system_id
	var jumps := int(FactionTraits.jumps_from(state.galaxy, cap_sys).get(system_id, 999))
	if jumps <= int(f["fiefs"]["far_jumps"]):
		return 0
	var crystal_net := int(_net(ctx).get("crystals", 0))
	var spare := crystal_net if _use(ctx) >= 2 else crystal_net - 1
	return 0 if spare >= int(f["fiefs"]["crystal_upkeep"]) else 1000


## Meilleure cible de colonisation pour une flotte colonisatrice : {"system", "planet", "kind", "value"}
## ou {}. Les niveaux qui planifient pèsent valeur et distance ; la Recrue prend la plus proche.
static func colonize_target(ctx: Dictionary, f: Fleet) -> Dictionary:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var use := _use(ctx)
	var plan := bool(ctx["lv"].get("plan_targets", true))
	var taken := _targeted(state, e, f.id)
	var res := Fleets._dijkstra(state, e.id, f.system_id)
	var speed := Fleets.speed(f, state)
	var best := {}
	var best_score := 0
	var ids: Array = res["dist"].keys()
	ids.sort()
	for k in ids:
		var sid := int(k)
		if not Fleets.is_explored(state, e.id, sid) or taken.has(sid) or Economy.has_foothold(state, e.id, sid):
			continue
		if state.system_owner(sid) != -1:
			continue
		var claim := best_claim(state, e, sid, use)
		if claim.is_empty() or int(claim["value"]) < MIN_TARGET_VALUE:
			continue
		@warning_ignore("integer_division")
		var days := int(res["dist"][k]) / maxi(1, speed)
		var score := int(claim["value"]) * 10 - days * 2 if plan else 100000 - days
		score -= _far_fief_penalty(ctx, sid) * 10
		if best.is_empty() or score > best_score:
			best_score = score
			best = claim.duplicate()
			best["system"] = sid
	return best


## Y a-t-il au moins `need` systèmes libres qui mériteraient un vaisseau colon ?
static func _has_open_targets(state: GameState, e: Empire, use: int, need: int) -> bool:
	var n := 0
	for sid in e.sorted_explored():
		if state.system_owner(int(sid)) != -1:
			continue
		var claim := best_claim(state, e, int(sid), use)
		if not claim.is_empty() and int(claim["value"]) >= MIN_TARGET_VALUE:
			n += 1
			if n >= need:
				return true
	return false


# --- 1. Talents du peuple ----------------------------------------------------------------------

static func _faction_talents(ctx: Dictionary) -> void:
	var use := _use(ctx)
	if use <= 0:
		_clumsy_talents(ctx)
		return
	var e: Empire = ctx["e"]
	var f := e.faction()
	if FactionTraits.has_fervor(f):
		_fervor(ctx, use)
	if FactionTraits.can_rush(f):
		_rush(ctx, use)


## Recrue : elle connaît les talents de son peuple, mais s'en sert très mal.
## - Chœur : attend que le dieu se taise pour réagir, et sacrifie dans sa plus petite colonie
##   (celle qui avait le plus besoin de grandir).
## - Vael : vote l'urgence sur des chantiers presque finis, au prix plancher, sans garder d'influence
##   pour ses revendications.
## - Ossarane et Kh'thari : voir planet_value (court après ses goûts sans compter les cristaux)
##   et _best_yard (lance les spores depuis ses colonies les plus fragiles).
static func _clumsy_talents(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var f := e.faction()
	if FactionTraits.has_fervor(f) and e.fervor <= 0 and not _forgets(ctx):
		var smallest: Colony = null
		for c in _own_colonies(state, e.id):
			if FactionTraits.check_sacrifice(state, e.id, c.planet_id) == "" and (smallest == null or c.population < smallest.population):
				smallest = c
		if smallest and _issue(ctx, SimCommands.sacrifice(e.id, smallest.planet_id)):
			_intent(ctx, "Offrande tardive, sur une colonie qui n'en demandait pas tant")
	if FactionTraits.can_rush(f):
		for c in _own_colonies(state, e.id):
			if _forgets(ctx):
				continue
			if c.construction != "" and c.construction_days <= 8 and _issue(ctx, SimCommands.rush(e.id, c.planet_id, FactionTraits.RUSH_BUILDING)):
				_intent(ctx, "Vote d'urgence… sur un chantier presque fini")
			elif c.ship_build != "" and c.ship_days <= 8 and _issue(ctx, SimCommands.rush(e.id, c.planet_id, FactionTraits.RUSH_SHIP)):
				_intent(ctx, "Vote d'urgence… sur un vaisseau presque fini")


## Chœur Éternel : offrande quand la ferveur va manquer. Les bases évitent le Silence du dieu ;
## le registre complet entretient l'Exaltation (+25 % de production).
static func _fervor(ctx: Dictionary, use: int) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var fv: Dictionary = e.faction()["fervor"]
	var next := e.fervor + FactionTraits.fervor_delta(state, e.id)
	var floor_wanted := int(fv["exalted_at"]) if use >= 2 else int(fv["decay"]) * 2
	if next >= floor_wanted or _forgets(ctx):
		return
	# Le fidèle vient de la colonie la plus peuplée (jamais en dessous de 3 : on garde de quoi grandir).
	# Pour entretenir l'Exaltation, le registre complet ne prend que dans une colonie pleine (elle
	# regrandit sans rien perdre) ou très peuplée ; contre le Silence du dieu, toute colonie fait l'affaire.
	var silent := next <= 0
	var best: Colony = null
	for c in _own_colonies(state, e.id):
		if not c.is_colony() or c.population < maxi(3, int(fv["sacrifice_min_pop"])):
			continue
		if use >= 2 and not silent:
			var cap := Economy.max_pop(state, state.galaxy.get_planet(c.planet_id), e.id, c.buildings)
			if c.population < cap and c.population < 6:
				continue
		if best == null or c.population > best.population:
			best = c
	if best and _issue(ctx, SimCommands.sacrifice(e.id, best.planet_id)):
		_intent(ctx, "Offrande pour raviver la ferveur" if use < 2 else "Offrande : garder le dieu exalté")


## Vael : vote d'urgence. Les bases votent quand l'influence déborde largement ; le registre complet
## vote dès qu'il reste de quoi payer la prochaine revendication, et sur des chantiers plus courts.
static func _rush(ctx: Dictionary, use: int) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var keep := int(Economy.claim_cost(Colony.KIND_COLONY).get("influence", 0)) + (60 if use < 2 else 0)
	for c in _own_colonies(state, e.id):
		if c.ship_build != "" and c.ship_days > 4 and GameData.ship(c.ship_build).get("colonizer", false):
			var cost := FactionTraits.rush_cost(state, e.id, c.planet_id, FactionTraits.RUSH_SHIP)
			if cost >= 0 and _res(ctx, "influence") - cost >= keep and not _forgets(ctx):
				if _issue(ctx, SimCommands.rush(e.id, c.planet_id, FactionTraits.RUSH_SHIP)):
					_intent(ctx, "Vote d'urgence : un vaisseau colon de plus")
	var min_days := 20 if use < 2 else 10
	for c in _own_colonies(state, e.id):
		if c.construction != "" and c.construction_days > min_days:
			var cost := FactionTraits.rush_cost(state, e.id, c.planet_id, FactionTraits.RUSH_BUILDING)
			if cost >= 0 and _res(ctx, "influence") - cost >= keep:
				if _issue(ctx, SimCommands.rush(e.id, c.planet_id, FactionTraits.RUSH_BUILDING)):
					_intent(ctx, "Vote d'urgence sur un chantier")


# --- 2. Bâtiments ------------------------------------------------------------------------------

static func _buildings(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var net := _net(ctx).duplicate()
	var reserve := _material_reserve(ctx)
	for c in _own_colonies(state, e.id):
		if c.construction != "" or Economy.building_slots_used(c) >= Economy.building_slots(state, c) or _forgets(ctx):
			continue
		var urgent := urgent_needs(ctx, net)
		for b in building_wishes(ctx, c, net):
			var cost: Dictionary = GameData.building(b).get("cost", {})
			if _res(ctx, "materials") - int(cost.get("materials", 0)) < reserve and not urgent.has(b):
				continue  # on garde de quoi lancer le vaisseau colon
			if _issue(ctx, SimCommands.build(e.id, c.planet_id, b)):
				var bd := GameData.building(b)
				for r in bd.get("yields", {}):
					net[r] = int(net.get(r, 0)) + int(bd["yields"][r])
				for r in bd.get("upkeep", {}):
					net[r] = int(net.get(r, 0)) - int(bd["upkeep"][r])
				break


## Bâtiments qui comblent un manque (famine ou panne d'énergie en vue) : ils passent avant
## la réserve gardée pour le vaisseau colon.
static func urgent_needs(ctx: Dictionary, net: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var food_margin := 2 + (int(ctx["ai"].get("food_margin", 0)) if _use(ctx) >= 1 else 0)
	if int(net.get("food", 0)) < food_margin:
		out.append("ferme_hydroponique")
	if int(net.get("energy", 0)) < 3:
		out.append("centrale_fusion")
	return out


## Bâtiments souhaités pour une revendication, du plus urgent au moins urgent :
## d'abord ce qui manque (nourriture, énergie, cristaux), puis le penchant du peuple, puis l'industrie
## (les matériaux paient les vaisseaux colons et tout le reste), et la nourriture ou l'énergie
## seulement si elles ne débordent pas déjà.
static func building_wishes(ctx: Dictionary, c: Colony, net: Dictionary) -> Array[String]:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var use := _use(ctx)
	var ai: Dictionary = ctx["ai"]
	var p := state.galaxy.get_planet(c.planet_id)
	var out := urgent_needs(ctx, net)
	# Le registre complet sait lire son goulot : quand les matériaux s'entassent, c'est l'influence
	# qui freine l'expansion (chaque revendication en coûte) ; les forums passent alors devant.
	if use >= 2 and c.is_colony() and _res(ctx, "materials") >= 250:
		out.append("forum")
	if p.deposits.has("crystals"):
		var fiefs := FactionTraits.has_fiefs(e.faction()) and use >= 1
		if fiefs or int(net.get("crystals", 0)) < 1:
			out.append("raffinerie")
	if use >= 1 and ai.has("building_bias"):
		var bias := String(ai["building_bias"])
		var plenty := {"ferme_hydroponique": "food", "centrale_fusion": "energy"}
		if not plenty.has(bias) or int(net.get(plenty[bias], 0)) < 20:
			out.append(bias)
	if c.is_colony():
		var cap := Economy.max_pop(state, p, e.id, c.buildings)
		if c.population >= cap - 1:
			out.append("habitats")
		if int(net.get("influence", 0)) < 4:
			out.append("forum")
		out.append("complexe_minier")
		if int(net.get("energy", 0)) < 10:
			out.append("centrale_fusion")
		if int(net.get("food", 0)) < 10:
			out.append("ferme_hydroponique")
	return out


## Matériaux à garder pour le prochain vaisseau colon, s'il en manque un.
static func _material_reserve(ctx: Dictionary) -> int:
	if ctx.has("reserve"):
		return ctx["reserve"]
	ctx["reserve"] = _compute_reserve(ctx)
	return ctx["reserve"]


static func _compute_reserve(ctx: Dictionary) -> int:
	var e: Empire = ctx["e"]
	var cls := colonizer_class(e)
	if cls == "" or _colonizer_count(ctx["state"], e) >= int(ctx["lv"].get("colonizers", 1)):
		return 0
	return int(GameData.ship(cls).get("cost", {}).get("materials", 0))


# --- 3. Revendications sans vaisseau -----------------------------------------------------------

static func _foothold_claims(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var use := _use(ctx)
	var max_claims := mini(int(ctx["lv"].get("max_claims", 2)), int(GameData.rules()["max_projects"]))
	var reserve_inf := int(ctx["lv"].get("reserve_influence", 0))
	for sid in EmpireReport.owned_systems(state, e.id):
		if Economy.active_projects(state, e.id) >= max_claims:
			return
		if not Economy.has_foothold(state, e.id, sid) or _forgets(ctx):
			continue
		var claim := best_claim(state, e, sid, use)
		if claim.is_empty():
			continue
		var cost := Economy.claim_cost_for(state, e.id, int(claim["planet"]), String(claim["kind"]))
		if _res(ctx, "influence") - int(cost.get("influence", 0)) < reserve_inf and int(cost.get("influence", 0)) > 0:
			continue
		if _issue(ctx, SimCommands.colonize(e.id, int(claim["planet"]), String(claim["kind"]))):
			_intent(ctx, "Développe %s" % state.galaxy.systems[sid].system_name)


# --- 4. Chantiers spatiaux ---------------------------------------------------------------------

static func _colonizer_count(state: GameState, e: Empire) -> int:
	var n := 0
	for f in Fleets.empire_fleets(state, e.id):
		for s in f.ships:
			if GameData.ship(s).get("colonizer", false):
				n += 1
	for c in _own_colonies(state, e.id):
		if c.ship_build != "" and GameData.ship(c.ship_build).get("colonizer", false):
			n += 1
	return n


static func _scout_count(state: GameState, e: Empire, scout: String) -> int:
	var n := 0
	for f in Fleets.empire_fleets(state, e.id):
		n += f.count(scout)
	for c in _own_colonies(state, e.id):
		if c.ship_build == scout:
			n += 1
	return n


## Versions mémorisées le temps d'une réflexion (elles ne changent pas d'un module à l'autre).
static func _frontier(ctx: Dictionary) -> bool:
	if not ctx.has("frontier"):
		ctx["frontier"] = _frontier_left(ctx["state"], ctx["e"])
	return ctx["frontier"]


static func _open(ctx: Dictionary) -> bool:
	if not ctx.has("open"):
		ctx["open"] = _has_open_targets(ctx["state"], ctx["e"], _use(ctx), 1)
	return ctx["open"]


## Reste-t-il des systèmes connus mais inexplorés ?
static func _frontier_left(state: GameState, e: Empire) -> bool:
	for sid in e.sorted_explored():
		for n in state.galaxy.systems[int(sid)].neighbors:
			if not e.explored.has(n):
				return true
	return false


static func _shipyards(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var use := _use(ctx)
	var cls := colonizer_class(e)
	var wanted := int(ctx["lv"].get("colonizers", 1))
	var have := _colonizer_count(state, e)
	if cls != "" and have < wanted and _has_open_targets(state, e, use, have + 1) and not _forgets(ctx):
		var yard := _best_yard(ctx, cls)
		if yard and _issue(ctx, SimCommands.build_ship(e.id, yard.planet_id, cls)):
			_intent(ctx, "Prépare une expansion")
	var scout := scout_class(e)
	var scouts := int(ctx["lv"].get("scouts", 1)) + (int(ctx["ai"].get("scouts", 0)) if use >= 1 else 0)
	if scout != "" and _scout_count(state, e, scout) < scouts and _frontier(ctx) and not _forgets(ctx):
		var yard := _best_yard(ctx, scout)
		if yard and _res(ctx, "materials") - int(GameData.ship(scout).get("cost", {}).get("materials", 0)) >= _material_reserve(ctx):
			_issue(ctx, SimCommands.build_ship(e.id, yard.planet_id, scout))


## Chantier spatial libre le plus adapté : la colonie la plus peuplée (un vaisseau-spore emporte
## de la population ; l'Essaim au registre complet préfère une colonie pleine, qui regrandit vite).
static func _best_yard(ctx: Dictionary, ship_id: String) -> Colony:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var best: Colony = null
	var best_score := -1
	for c in _own_colonies(state, e.id):
		if not c.is_colony() or c.ship_build != "":
			continue
		if Fleets.check_build_ship(state, e.id, c.planet_id, ship_id) != "":
			continue
		var score := c.population * 10
		if _use(ctx) <= 0 and int(GameData.ship(ship_id).get("pop_cost", 0)) > 0:
			score = 1000 - c.population  # la Recrue de l'Essaim vide ses colonies les plus fragiles
		if _use(ctx) >= 2 and e.faction().has("biomass"):
			var cap := Economy.max_pop(state, state.galaxy.get_planet(c.planet_id), e.id, c.buildings)
			if c.population >= cap:
				score += 1000
		if score > best_score:
			best_score = score
			best = c
	return best


# --- 5. Flottes --------------------------------------------------------------------------------

static func _fleets(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	for f in Fleets.empire_fleets(state, e.id):
		if not state.fleets.has(f.id):
			continue  # dissoute par une colonisation plus haut dans la boucle
		if Fleets.colonizer_ship(f) != "":
			_colonizer(ctx, f)
		elif f.is_idle() and _frontier(ctx) and not _forgets(ctx):
			_issue(ctx, SimCommands.set_fleet_order(e.id, f.id, Fleet.ORDER_EXPLORE))


## Un vaisseau colon : s'il est arrivé sur sa cible, il fonde ; sinon il part vers la meilleure.
static func _colonizer(ctx: Dictionary, f: Fleet) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if f.is_moving():
		# En route : on vérifie que la cible est toujours libre (un rival a pu passer avant).
		var dest := f.destination()
		var owner := state.system_owner(dest)
		if owner == -1 or owner == e.id:
			return
	elif not _forgets(ctx):
		var here := best_claim(state, e, f.system_id, _use(ctx))
		if not here.is_empty() and int(here["value"]) >= MIN_TARGET_VALUE and not Economy.has_foothold(state, e.id, f.system_id):
			# Le vaisseau colon passe avant les revendications sans vaisseau : il a déjà coûté cher.
			if _issue(ctx, SimCommands.colonize(e.id, int(here["planet"]), String(here["kind"]))):
				_intent(ctx, "Fonde %s à %s" % ["une colonie" if here["kind"] == Colony.KIND_COLONY else "un avant-poste", state.galaxy.systems[f.system_id].system_name])
			# Sinon, pas les moyens pour l'instant (influence, chantiers pleins) : on attend sur place.
			return
	else:
		return
	if not _open(ctx):
		return
	var target := colonize_target(ctx, f)
	if target.is_empty():
		return
	if int(target["system"]) == f.system_id:
		return
	if _issue(ctx, SimCommands.move_fleet(e.id, f.id, int(target["system"]))):
		_intent(ctx, "Expansion vers %s" % state.galaxy.systems[int(target["system"])].system_name)


# --- 6. et 7. Points d'extension ---------------------------------------------------------------

## Militaire : rien tant que le combat n'existe pas. Ce module recevra la défense des colonies,
## l'escorte des vaisseaux colons et les offensives, avec le même schéma (valider, appliquer).
static func _military(_ctx: Dictionary) -> void:
	pass


## Diplomatie : rien tant que les traités n'existent pas. L'Essaim Kh'thari n'y entrera jamais.
static func _diplomacy(_ctx: Dictionary) -> void:
	pass
