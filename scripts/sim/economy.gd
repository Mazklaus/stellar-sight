class_name Economy
extends RefCounted
## Règles de l'économie et de la colonisation : fonctions pures qui LISENT l'état.
## La simulation (EconomySystem, SimCommands) les utilise pour faire évoluer la partie,
## et l'interface pour afficher des prévisions ou expliquer un refus, avec exactement les mêmes calculs.
##
## Tout est en nombres entiers : un pourcentage s'applique par v * pct / 100 (division entière).


## Habitabilité (0 à 100 %) d'un type de planète pour une faction :
## 100 % pour le type d'origine, 80 % pour le second préféré, sinon la valeur de base du type.
static func habitability(planet_type: String, faction: Dictionary) -> int:
	var pref: Array = faction.get("preferred", [])
	if pref.size() > 0 and pref[0] == planet_type:
		return 100
	if pref.size() > 1 and pref[1] == planet_type:
		return 80
	return int(GameData.planet_type(planet_type).get("base_hab", 0))


## Population maximale d'une planète pour un empire, bâtiments compris.
static func max_pop(state: GameState, planet: Planet, empire_id: int, buildings: Array[String] = []) -> int:
	var e := state.get_empire(empire_id)
	if e == null or not planet.is_habitable_type():
		return 0
	var hab := habitability(planet.type, e.faction())
	if hab <= 0:
		return 0
	@warning_ignore("integer_division")
	var base := planet.size * int(GameData.rules()["pop_per_size"]) * hab / 100
	if base <= 0:
		return 0
	for b in buildings:
		base += int(GameData.building(b).get("max_pop", 0))
	return base


@warning_ignore("integer_division")
static func growth_per_day(state: GameState, colony: Colony) -> int:
	var e := state.get_empire(colony.owner)
	var pct := int(e.faction().get("growth_pct", 100)) if e else 100
	return int(GameData.rules()["growth_per_day"]) * pct / 100


static func growth_threshold(population: int) -> int:
	var r := GameData.rules()
	return int(r["growth_threshold_base"]) + int(r["growth_threshold_per_pop"]) * population


## Rendement mensuel brut et entretien d'une revendication, avant les bonus de faction.
## Renvoie {"gross": {res: int}, "upkeep": {res: int}}.
static func colony_yields(state: GameState, colony: Colony) -> Dictionary:
	var gross := _zero()
	var upkeep := _zero()
	if not colony.is_established():
		return {"gross": gross, "upkeep": upkeep}
	var planet := state.galaxy.get_planet(colony.planet_id)
	var ptype := GameData.planet_type(planet.type)
	var rules := GameData.rules()
	_add(upkeep, rules["claims"][colony.kind].get("upkeep", {}))
	if colony.is_colony():
		_add(gross, ptype.get("pop_yields", {}), colony.population)
		var e := state.get_empire(colony.owner)
		var food_pct := int(e.faction().get("food_upkeep_pct", 100)) if e else 100
		@warning_ignore("integer_division")
		upkeep["food"] += colony.population * int(rules["food_per_pop"]) * food_pct / 100
	else:
		_add(gross, ptype.get("outpost_yields", {}))
	for d in planet.deposits:
		_add(gross, GameData.deposit(d).get("yields", {}))
	for b in colony.buildings:
		var bd := GameData.building(b)
		_add(gross, bd.get("yields", {}))
		_add(upkeep, bd.get("upkeep", {}))
	return {"gross": gross, "upkeep": upkeep}


## Bilan mensuel d'un empire : {"gross", "upkeep", "net"}, bonus de faction appliqués au brut.
static func empire_income(state: GameState, empire_id: int) -> Dictionary:
	var gross := _zero()
	var upkeep := _zero()
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != empire_id:
			continue
		var y := colony_yields(state, c)
		_add(gross, y["gross"])
		_add(upkeep, y["upkeep"])
	var e := state.get_empire(empire_id)
	var pct: Dictionary = e.faction().get("production_pct", {}) if e else {}
	var net := _zero()
	for r in gross:
		@warning_ignore("integer_division")
		gross[r] = gross[r] * int(pct.get(r, 100)) / 100
		net[r] = gross[r] - upkeep[r]
	return {"gross": gross, "upkeep": upkeep, "net": net}


## Coût d'une revendication ("colony" ou "outpost").
static func claim_cost(kind: String) -> Dictionary:
	return GameData.rules()["claims"][kind]["cost"]


static func claim_days(kind: String) -> int:
	return int(GameData.rules()["claims"][kind]["days"])


static func can_afford(empire: Empire, cost: Dictionary) -> bool:
	for r in cost:
		if int(empire.resources.get(r, 0)) < int(cost[r]):
			return false
	return true


static func pay(empire: Empire, cost: Dictionary) -> void:
	for r in cost:
		empire.resources[r] = int(empire.resources.get(r, 0)) - int(cost[r])


## Un système est à portée s'il contient, ou s'il est voisin d'un système qui contient,
## une colonie ou un avant-poste ÉTABLI de l'empire. (Les vaisseaux colons viendront avec les flottes.)
static func in_range(state: GameState, empire_id: int, system_id: int) -> bool:
	var reach := {}
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner == empire_id and c.is_established():
			reach[state.galaxy.get_planet(pid).system_id] = true
	if reach.has(system_id):
		return true
	for n in state.galaxy.systems[system_id].neighbors:
		if reach.has(n):
			return true
	return false


## Nombre de colonisations en cours (pas encore fondées) d'un empire.
static func active_projects(state: GameState, empire_id: int) -> int:
	var n := 0
	for pid in state.colonies:
		var c: Colony = state.colonies[pid]
		if c.owner == empire_id and not c.is_established():
			n += 1
	return n


## "" si l'empire peut lancer cette colonisation, sinon la raison du refus (affichée telle quelle).
static func check_colonize(state: GameState, empire_id: int, planet_id: int, kind: String) -> String:
	var e := state.get_empire(empire_id)
	if e == null:
		return "empire inconnu : %d" % empire_id
	var p := state.galaxy.get_planet(planet_id)
	if p == null:
		return "planète inconnue : %d" % planet_id
	if kind != Colony.KIND_COLONY and kind != Colony.KIND_OUTPOST:
		return "type de colonisation inconnu : %s" % kind
	var existing: Colony = state.colonies.get(planet_id)
	if existing:
		var upgrade := kind == Colony.KIND_COLONY and existing.owner == empire_id \
				and existing.kind == Colony.KIND_OUTPOST
		if not upgrade:
			return "planète déjà revendiquée"
		if not existing.is_established():
			return "l'avant-poste n'est pas encore établi"
	var owner := state.system_owner(p.system_id)
	if owner != -1 and owner != empire_id:
		return "système revendiqué par %s" % state.get_empire(owner).display_name()
	if not in_range(state, empire_id, p.system_id):
		return "hors de portée : il faut une colonie ou un avant-poste établi dans ce système ou un système voisin"
	if kind == Colony.KIND_COLONY and max_pop(state, p, empire_id) < 1:
		return "planète inhabitable pour votre espèce"
	var max_projects := int(GameData.rules()["max_projects"])
	if active_projects(state, empire_id) >= max_projects:
		return "déjà %d colonisations en cours" % max_projects
	var cost := claim_cost(kind)
	if not can_afford(e, cost):
		return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)
	return ""


## "" si l'empire peut lancer ce chantier, sinon la raison du refus.
static func check_build(state: GameState, empire_id: int, planet_id: int, building_id: String) -> String:
	var e := state.get_empire(empire_id)
	if e == null:
		return "empire inconnu : %d" % empire_id
	var c: Colony = state.colonies.get(planet_id)
	if c == null or c.owner != empire_id:
		return "cette planète ne vous appartient pas"
	if not c.is_established():
		return "la colonie n'est pas encore fondée"
	var b := GameData.building(building_id)
	if b.is_empty() or not b.get("buildable", true):
		return "bâtiment inconnu : %s" % building_id
	if c.construction != "":
		return "un chantier est déjà en cours"
	if not c.is_colony() and not b.get("outpost_ok", false):
		return "impossible sur un avant-poste"
	var p := state.galaxy.get_planet(planet_id)
	var dep := String(b.get("requires_deposit", ""))
	if dep != "" and not p.deposits.has(dep):
		return "nécessite un gisement : %s" % GameData.deposit(dep).get("label", dep)
	if b.get("unique", false) and c.buildings.has(building_id):
		return "déjà construit sur cette planète"
	var used := building_slots_used(c)
	var slots := building_slots(state, c)
	if used >= slots:
		return "plus d'emplacement libre (%d/%d)" % [used, slots]
	var cost: Dictionary = b.get("cost", {})
	if not can_afford(e, cost):
		return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)
	return ""


## Emplacements : la taille de la planète pour une colonie, un seul pour un avant-poste.
## La capitale n'occupe pas d'emplacement.
static func building_slots(state: GameState, colony: Colony) -> int:
	if not colony.is_colony():
		return int(GameData.rules()["outpost_slots"])
	return state.galaxy.get_planet(colony.planet_id).size


static func building_slots_used(colony: Colony) -> int:
	var n := 0
	for b in colony.buildings:
		if GameData.building(b).get("buildable", true):
			n += 1
	return n


static func _zero() -> Dictionary:
	var d := {}
	for r in GameData.resource_ids():
		d[r] = 0
	return d


static func _add(into: Dictionary, amounts: Dictionary, times: int = 1) -> void:
	for r in amounts:
		into[r] = int(into.get(r, 0)) + int(amounts[r]) * times
