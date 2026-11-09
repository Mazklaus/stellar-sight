class_name EconomySystem
extends RefCounted
## Économie et colonisation, exécutées à chaque tick :
## - chaque jour : fondation des colonies, chantiers, croissance de la population ;
## - chaque mois (30 jours) : bilan des ressources de chaque empire, famines et pénuries d'énergie.
## Aucun aléatoire, uniquement des entiers, colonies parcourues dans l'ordre de leur identifiant.


## Fait avancer l'économie d'un tick. Renvoie les entrées de chronique ajoutées.
static func process(state: GameState) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	for pid in state.sorted_colony_ids():
		_process_colony(state, state.colonies[pid], added)
	if state.tick % int(GameData.rules()["month_days"]) == 0:
		for e in state.empires:
			_monthly_balance(state, e, added)
	return added


static func _process_colony(state: GameState, c: Colony, added: Array[Dictionary]) -> void:
	var e := state.get_empire(c.owner)
	var planet_name := state.galaxy.get_planet(c.planet_id).display_name(state.galaxy)
	if not c.is_established():
		c.days_left -= 1
		if c.is_established():
			if c.is_colony():
				c.population = maxi(c.population, int(GameData.rules()["colony_start_pop"]))
				added.append(state.add_chronicle(
						"%s fonde une colonie sur %s. Les premiers colons découvrent la gravité locale, et ses opinions." % [e.display_name(), planet_name]))
			else:
				added.append(state.add_chronicle(
						"%s plante un avant-poste sur %s. Effectif : trois techniciens et un chat." % [e.display_name(), planet_name]))
		return

	if c.construction != "" and not e.blackout:
		c.construction_days -= 1
		if c.construction_days <= 0:
			var label := String(GameData.building(c.construction).get("label", c.construction))
			c.buildings.append(c.construction)
			c.construction = ""
			c.construction_days = 0
			added.append(state.add_chronicle("%s : chantier achevé sur %s (%s)." % [e.short_name(), planet_name, label]))

	if not c.is_colony():
		return
	var cap := Economy.max_pop(state, state.galaxy.get_planet(c.planet_id), c.owner, c.buildings)
	if c.population >= cap or e.starving:
		c.growth = 0
		return
	c.growth += Economy.growth_per_day(state, c)
	if c.growth >= Economy.growth_threshold(c.population):
		c.growth = 0
		c.population += 1


static func _monthly_balance(state: GameState, e: Empire, added: Array[Dictionary]) -> void:
	var net: Dictionary = Economy.empire_income(state, e.id)["net"]
	for r in net:
		e.resources[r] = int(e.resources.get(r, 0)) + int(net[r])

	var was_starving := e.starving
	e.starving = e.resources["food"] < 0
	if e.starving:
		# Famine : la colonie la plus peuplée perd une population.
		var worst: Colony = null
		for pid in state.sorted_colony_ids():
			var c: Colony = state.colonies[pid]
			if c.owner == e.id and c.is_colony() and c.population > 1 \
					and (worst == null or c.population > worst.population):
				worst = c
		if worst:
			worst.population -= 1
			worst.growth = 0
		if not was_starving:
			added.append(state.add_chronicle("Famine chez %s : on rationne, les cuisiniers démissionnent en bloc." % e.display_name()))

	var was_blackout := e.blackout
	e.blackout = e.resources["energy"] < 0
	if e.blackout and not was_blackout:
		added.append(state.add_chronicle("Pénurie d'énergie chez %s : les chantiers s'arrêtent, les bougies se vendent très bien." % e.display_name()))

	# Les stocks ne descendent jamais sous zéro : le manque se paie en famine ou en chantiers arrêtés.
	for r in e.resources:
		e.resources[r] = maxi(0, int(e.resources[r]))
