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
	var base := int(GameData.planet_type(planet_type).get("base_hab", 0))
	# Plancher de faction (Vael : une espèce pour chaque monde), seulement sur les mondes habitables.
	if base > 0:
		return maxi(base, FactionTraits.hab_floor(faction))
	# Mondes que seul ce corps peuple (lithoïdes : la roche nue).
	return FactionTraits.hab_extra(faction, planet_type)


## Habitabilité pour un empire, technologies comprises : un type rendu habitable (hab_set) prend la
## meilleure des deux valeurs, puis hab_bonus s'ajoute sur les mondes habitables qui ne sont pas le
## monde d'origine du peuple (100 % au plus).
static func habitability_for(state: GameState, empire_id: int, planet_type: String) -> int:
	var e := state.get_empire(empire_id)
	if e == null:
		return 0
	var f := e.faction()
	var hab := habitability(planet_type, f)
	var fx := Research.effects(state, empire_id)
	var set_to := int(fx.get("hab_set", {}).get(planet_type, 0))
	if set_to > hab:
		hab = maxi(set_to, FactionTraits.hab_floor(f))
	var pref: Array = f.get("preferred", [])
	if hab > 0 and (pref.is_empty() or pref[0] != planet_type):
		var bonus: Dictionary = fx.get("hab_bonus", {})
		hab = mini(100, hab + int(bonus.get(planet_type, 0)) + int(bonus.get("all", 0)))
	# Plancher des technologies tardives (Adaptation totale, Symbiose universelle), sur les mondes habitables.
	if hab > 0:
		hab = maxi(hab, mini(100, int(fx.get("hab_min", 0))))
	return hab


## Le type de planète peut-il accueillir une population de cet empire ? Les types sans population
## (géantes gazeuses) le deviennent avec une technologie qui les rend habitables (cités flottantes).
static func houses_pop(state: GameState, empire_id: int, planet_type: String) -> bool:
	if not GameData.planet_type(planet_type).get("pop_yields", {}).is_empty():
		return true
	var e := state.get_empire(empire_id)
	if e and FactionTraits.hab_extra(e.faction(), planet_type) > 0:
		return true
	return Research.fx_sub(state, empire_id, "hab_set", planet_type) > 0


## Rendement par population d'un type de planète (cités flottantes pour les types sans population).
static func pop_yields(planet_type: String) -> Dictionary:
	var pt := GameData.planet_type(planet_type)
	var y: Dictionary = pt.get("pop_yields", {})
	return y if not y.is_empty() else pt.get("city_pop_yields", {})


## Habitabilité d'un type pour la population de l'empire (0 s'il n'y loge personne). Appelée sans
## cesse par l'IA qui jauge les planètes : gardée par empire tant que ses technologies ne changent pas
## (aucun effet d'exaltation ne touche l'habitabilité).
static func _pop_hab(state: GameState, empire_id: int, planet_type: String) -> int:
	var e := state.get_empire(empire_id)
	if e == null:
		return 0
	if e.hab_cache_n != e.techs.size():
		e.hab_cache.clear()
		e.hab_cache_n = e.techs.size()
	if not e.hab_cache.has(planet_type):
		e.hab_cache[planet_type] = habitability_for(state, empire_id, planet_type) if houses_pop(state, empire_id, planet_type) else 0
	return e.hab_cache[planet_type]


## Population par taille de chaque type de planète, en % (écuménopole : 200), lue une fois.
static var _dense_types := {}


## Population maximale d'une planète pour un empire, bâtiments compris.
static func max_pop(state: GameState, planet: Planet, empire_id: int, buildings: Array[String] = []) -> int:
	var hab := _pop_hab(state, empire_id, planet.type)
	if hab <= 0:
		return 0
	@warning_ignore("integer_division")
	var base := planet.size * int(GameData.rules()["pop_per_size"]) * hab / 100
	# Écuménopole : la ville couvre tout, deux fois plus d'habitants par taille.
	if _dense_types.is_empty():
		for t in GameData.planet_types():
			_dense_types[t] = int(GameData.planet_type(t).get("pop_per_size_pct", 100))
	var dense := int(_dense_types.get(planet.type, 100))
	if dense != 100:
		@warning_ignore("integer_division")
		base = base * dense / 100
	if base <= 0:
		return 0
	for b in buildings:
		base += int(GameData.building(b).get("max_pop", 0))
	return base


@warning_ignore("integer_division")
static func growth_per_day(state: GameState, colony: Colony) -> int:
	var e := state.get_empire(colony.owner)
	if e == null:
		return int(GameData.rules()["growth_per_day"])
	var pct := int(e.faction().get("growth_pct", 100))
	pct = pct * maxi(10, 100 + Research.fx_int(state, colony.owner, "growth_pct")) / 100
	return int(GameData.rules()["growth_per_day"]) * pct / 100


static func growth_threshold(population: int) -> int:
	var r := GameData.rules()
	return int(r["growth_threshold_base"]) + int(r["growth_threshold_per_pop"]) * population


## Seuil de la prochaine population d'une colonie : une population assemblée (synthétiques) ne
## ralentit pas en grandissant, son seuil reste celui d'une colonie naissante.
static func colony_threshold(state: GameState, c: Colony) -> int:
	var e := state.get_empire(c.owner)
	if e and FactionTraits.assembly_cost(e.faction()) > 0:
		return growth_threshold(0)
	return growth_threshold(c.population)


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
	var fx := Research.effects(state, colony.owner)
	if colony.is_colony():
		var e := state.get_empire(colony.owner)
		var py := pop_yields(planet.type)
		# Un peuple qui ne mange pas de nourriture ne la cultive pas non plus : ce que les habitants
		# produiraient en nourriture va dans ce qu'ils mangent (lithoïdes : matériaux, synthétiques : énergie).
		var diet0 := FactionTraits.diet(e.faction()) if e else "food"
		if diet0 != "food" and py.has("food"):
			py = py.duplicate()
			py[diet0] = int(py.get(diet0, 0)) + int(py["food"])
			py.erase("food")
		_add(gross, py, colony.population)
		var food_pct := int(e.faction().get("food_upkeep_pct", 100)) if e else 100
		# Réplicateurs de matière : la population mange moins.
		@warning_ignore("integer_division")
		food_pct = food_pct * maxi(0, 100 + int(fx.get("food_upkeep_pct", 0))) / 100
		@warning_ignore("integer_division")
		var diet := FactionTraits.diet(e.faction()) if e else "food"
		upkeep[diet] = int(upkeep.get(diet, 0)) + colony.population * int(rules["food_per_pop"]) * food_pct / 100
	else:
		_add(gross, ptype.get("outpost_yields", {}))
		# Écopes et foreuses : les avant-postes des géantes, des astéroïdes et des mondes stériles.
		_add(gross, fx.get("outpost_yields", {}).get(planet.type, {}))
	# Forage du manteau : les gisements rapportent plus.
	var dep_mult := 100 + int(fx.get("deposit_pct", 0))
	for d in planet.deposits:
		var dy: Dictionary = GameData.deposit(d).get("yields", {})
		for r in dy:
			@warning_ignore("integer_division")
			gross[r] = int(gross.get(r, 0)) + int(dy[r]) * dep_mult / 100
	var knowledge_pct := 0
	# Économie d'abondance : plus d'entretien des bâtiments.
	var bld_upkeep := maxi(0, 100 + int(fx.get("building_upkeep_pct", 0)))
	for b in colony.buildings:
		var bd := GameData.building(b)
		_add(gross, bd.get("yields", {}))
		if bld_upkeep == 100:
			_add(upkeep, bd.get("upkeep", {}))
		elif bld_upkeep > 0:
			_add(upkeep, Research.scaled_amounts(bd.get("upkeep", {}), bld_upkeep - 100))
		knowledge_pct += int(bd.get("knowledge_pct", 0))
	if colony.is_colony():
		# Savoir : chaque population pense un peu (pop_per_knowledge habitants pour 1 Savoir).
		@warning_ignore("integer_division")
		gross["knowledge"] = int(gross.get("knowledge", 0)) + colony.population / maxi(1, int(rules.get("pop_per_knowledge", 2)))
	if knowledge_pct != 0:
		@warning_ignore("integer_division")
		gross["knowledge"] = int(gross["knowledge"]) * (100 + knowledge_pct) / 100
	FactionTraits.adjust_yields(state, colony, gross, upkeep)
	if Combat.is_besieged(state, planet.system_id):
		var pct := int(Combat.data().get("besieged_production_pct", 50))
		for r in gross:
			@warning_ignore("integer_division")
			gross[r] = gross[r] * pct / 100
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
	_add(upkeep, Fleets.upkeep(state, empire_id))
	gross["influence"] += FactionTraits.extra_influence(state, empire_id)
	var treaties := Diplomacy.treaty_income(state, empire_id)
	for r in treaties:
		gross[r] += int(treaties[r])
	var net := _zero()
	for r in gross:
		@warning_ignore("integer_division")
		gross[r] = gross[r] * production_pct(state, empire_id, r) / 100
		net[r] = gross[r] - upkeep[r]
	return {"gross": gross, "upkeep": upkeep, "net": net}


## Pourcentage total appliqué à la production brute d'une ressource : traits de faction (et ferveur),
## technologies et talent de recherche du peuple, puis bonus de difficulté des IA des niveaux hauts.
@warning_ignore("integer_division")
static func production_pct(state: GameState, empire_id: int, resource: String) -> int:
	var pct := FactionTraits.production_pct(state, empire_id, resource)
	var bonus := Research.production_bonus(state, empire_id, resource)
	if resource == "knowledge":
		bonus += FactionTraits.peace_knowledge_pct(state, empire_id)
	pct = pct * (100 + bonus) / 100
	return pct * AiLevels.production_pct(state, empire_id) / 100


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


## L'empire a pied dans le système : il y possède une colonie ou un avant-poste ÉTABLI.
## Il peut alors revendiquer les autres planètes du système sans vaisseau colon.
static func has_foothold(state: GameState, empire_id: int, system_id: int) -> bool:
	for pid in state.galaxy.systems[system_id].planet_ids:
		var c: Colony = state.colonies.get(pid)
		if c and c.owner == empire_id and c.is_established():
			return true
	return false


## Un système est à portée de colonisation si l'empire y a pied, ou si l'un de ses vaisseaux colons
## y est à l'arrêt (comme dans Endless Space 2, le vaisseau se démonte pour fonder la revendication).
static func in_range(state: GameState, empire_id: int, system_id: int) -> bool:
	return has_foothold(state, empire_id, system_id) or Fleets.colonizer_fleet(state, empire_id, system_id) != null


## La revendication de cette planète consommerait un vaisseau colon (pas encore pied dans le système).
static func needs_ship(state: GameState, empire_id: int, planet_id: int) -> bool:
	return not has_foothold(state, empire_id, state.galaxy.get_planet(planet_id).system_id)


## Coût réel d'une revendication : avec un vaisseau colon, les matériaux sont déjà dans le vaisseau.
## Les traits de faction s'appliquent ensuite (l'Essaim Kh'thari ne paie jamais d'influence).
static func claim_cost_for(state: GameState, empire_id: int, planet_id: int, kind: String) -> Dictionary:
	var cost := claim_cost(kind)
	if needs_ship(state, empire_id, planet_id):
		cost = GameData.rules()["claims"][kind].get("ship_cost", cost)
	return FactionTraits.adjust_claim_cost(state, empire_id, cost)


## Colonisations simultanées permises (règle commune + technologies d'administration).
static func max_projects_for(state: GameState, empire_id: int) -> int:
	return int(GameData.rules()["max_projects"]) + Research.fx_int(state, empire_id, "max_projects")


## Coût d'un bâtiment pour un empire (technologies de nanofabrication comprises).
static func building_cost(state: GameState, empire_id: int, building_id: String) -> Dictionary:
	return Research.scaled_amounts(GameData.building(building_id).get("cost", {}), Research.fx_int(state, empire_id, "building_cost_pct"))


## Bâtiment débloqué par les technologies de l'empire ?
static func building_unlocked(state: GameState, empire_id: int, building_id: String) -> bool:
	return Research.knows_all(state, empire_id, GameData.building(building_id).get("requires_tech", []))


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
		return "hors de portée : il faut un vaisseau colon à l'arrêt dans ce système (ou une revendication établie dans le système)"
	if kind == Colony.KIND_COLONY and max_pop(state, p, empire_id) < 1:
		return "planète inhabitable pour votre espèce"
	var max_projects := max_projects_for(state, empire_id)
	if active_projects(state, empire_id) >= max_projects:
		return "déjà %d colonisations en cours" % max_projects
	var cost := claim_cost_for(state, empire_id, planet_id, kind)
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
	if not building_unlocked(state, empire_id, building_id):
		return "technologie requise : %s" % Research.missing_text(state, empire_id, b.get("requires_tech", []))
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
	var needs := String(b.get("requires_building", ""))
	if needs != "" and not c.buildings.has(needs):
		return "nécessite d'abord : %s" % String(GameData.building(needs).get("label", needs))
	var special := check_special(state, empire_id, c, p, building_id)
	if special != "":
		return special
	if takes_slot(building_id):
		var used := building_slots_used(c)
		var slots := building_slots(state, c)
		if used >= slots:
			return "plus d'emplacement libre (%d/%d)" % [used, slots]
	var cost := building_cost(state, empire_id, building_id)
	if not can_afford(e, cost):
		return "ressources insuffisantes (il faut %s)" % GameData.format_amounts(cost)
	return ""


## Emplacements : la taille de la planète pour une colonie, un seul pour un avant-poste.
## La capitale n'occupe pas d'emplacement (ni les projets comme la terraformation).
static func building_slots(state: GameState, colony: Colony) -> int:
	if not colony.is_colony():
		return int(GameData.rules()["outpost_slots"]) + Research.fx_int(state, colony.owner, "outpost_slots")
	var size := state.galaxy.get_planet(colony.planet_id).size
	if size >= 3:
		size += Research.fx_int(state, colony.owner, "building_slots")
	return size + Research.fx_int(state, colony.owner, "building_slots_all")


## Règles des bâtiments tardifs : 2e rang (upgrades), projets de terraformation, population ou taille
## minimale, un par système (Préfecture), un par empire (mégastructures), un dans la galaxie (merveilles).
static func check_special(state: GameState, empire_id: int, c: Colony, p: Planet, building_id: String) -> String:
	var b := GameData.building(building_id)
	var base := String(b.get("upgrades", ""))
	if base != "" and not c.buildings.has(base):
		return "remplace un bâtiment de 1er rang : %s" % String(GameData.building(base).get("label", base))
	if b.has("terraform"):
		if not c.is_colony():
			return "seulement sur une colonie"
		var target := terraform_target(state, empire_id, p, building_id)
		if target == "":
			return "impossible sur ce monde (%s)" % p.type_label()
	var min_pop := int(b.get("min_pop", 0))
	if min_pop > 0 and c.population < min_pop:
		return "il faut %d population (%d)" % [min_pop, c.population]
	var min_size := int(b.get("min_size", 0))
	if min_size > 0 and p.size < min_size:
		return "il faut une planète de taille %d ou plus" % min_size
	if b.get("per_system", false):
		for pid in state.galaxy.systems[p.system_id].planet_ids:
			var o: Colony = state.colonies.get(pid)
			if o and (o.buildings.has(building_id) or o.construction == building_id):
				return "déjà une %s dans ce système" % String(b.get("label", building_id)).to_lower()
	if b.get("empire_unique", false) or b.get("galaxy_unique", false):
		var galaxy := bool(b.get("galaxy_unique", false))
		for pid in state.colonies:
			var o: Colony = state.colonies[pid]
			if (galaxy or o.owner == empire_id) and (o.buildings.has(building_id) or o.construction == building_id):
				if not galaxy:
					return "une seule par empire : déjà bâtie ou en chantier"
				return "merveille déjà bâtie ou en chantier chez %s" % (state.get_empire(o.owner).display_name() if o.owner != empire_id else "vous")
	return ""


## Le bâtiment prend-il un emplacement ? Pas les bâtiments de 2e rang (ils remplacent le 1er rang),
## ni les projets (terraformation).
static func takes_slot(building_id: String) -> bool:
	var b := GameData.building(building_id)
	return not b.has("upgrades") and not b.get("project", false)


## Type de planète obtenu par un projet de terraformation ("" s'il ne s'applique pas à ce monde) :
## "preferred2" = le second monde préféré du peuple, sinon un type fixe (gaia, ecumenopole).
static func terraform_target(state: GameState, empire_id: int, p: Planet, building_id: String) -> String:
	var b := GameData.building(building_id)
	if not b.get("terraform_from", []).has(p.type):
		return ""
	var target := String(b.get("terraform", ""))
	if target == "preferred2":
		var e := state.get_empire(empire_id)
		var pref: Array = e.faction().get("preferred", []) if e else []
		if pref.size() < 2 or pref.has(p.type):
			return ""
		target = String(pref[1])
	if target == p.type or GameData.planet_type(target).is_empty():
		return ""
	return target


## Merveilles et mégastructures tenues : "building_id#planète" -> propriétaire. L'opinion et le score
## les consultent sans cesse : recalculé une fois par mois, ou dès qu'un chantier s'achève
## (une planète conquise change de mains au plus tard au mois suivant).
static var _wonders_tick := -1
static var _wonders_state: GameState = null
static var _wonders := {}


## À appeler quand un bâtiment notable change (chantier achevé, planète conquise) dans le même jour.
static func clear_wonders() -> void:
	_wonders_tick = -1


static func wonders(state: GameState) -> Dictionary:
	@warning_ignore("integer_division")
	var month := state.tick / int(GameData.rules()["month_days"])
	if _wonders_tick != month or _wonders_state != state:
		_wonders.clear()
		for pid in state.sorted_colony_ids():
			var c: Colony = state.colonies[pid]
			for b in c.buildings:
				var bd := GameData.building(b)
				if bd.get("galaxy_unique", false) or bd.has("score") or bd.has("opinion"):
					_wonders[b + "#" + str(pid)] = c.owner
		_wonders_tick = month
		_wonders_state = state
	return _wonders


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
