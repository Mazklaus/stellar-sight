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
				c.population = maxi(c.population, FactionTraits.colony_start_pop(state, c.owner))
				added.append(state.add_chronicle(
						"%s fonde une colonie sur %s. Les premiers colons découvrent la gravité locale, et ses opinions." % [e.display_name(), planet_name]))
			else:
				added.append(state.add_chronicle(
						"%s plante un avant-poste sur %s. Effectif : trois techniciens et un chat." % [e.display_name(), planet_name]))
		return

	if c.construction != "" and not e.blackout:
		c.construction_days -= 1
		if c.construction_days <= 0:
			_finish_building(state, c, e, planet_name, added)

	if not c.is_colony():
		return
	var cap := Economy.max_pop(state, state.galaxy.get_planet(c.planet_id), c.owner, c.buildings)
	if e.starving:
		c.growth = 0
		return
	if c.population >= cap:
		# Biomasse (Essaim Kh'thari) : une colonie pleine continue de grandir, le surplus est digéré.
		var bio: Dictionary = e.faction().get("biomass", {})
		if bio.is_empty() and cap > 0 and Research.fx_int(state, c.owner, "migration") > 0:
			# Spatioports de transit : les colons d'une colonie pleine partent peupler une autre colonie.
			c.growth += Economy.growth_per_day(state, c)
			if c.growth >= Economy.growth_threshold(c.population):
				c.growth = 0
				var dest := migration_target(state, c)
				if dest:
					dest.population += 1
			return
		if bio.is_empty() or cap <= 0:
			c.growth = 0
			return
		c.growth += Economy.growth_per_day(state, c)
		if c.growth >= Economy.growth_threshold(c.population):
			c.growth = 0
			var bg := FactionTraits.biomass_gain(state, c.owner)
			var gain := int(bg["materials"])
			e.resources["materials"] = int(e.resources.get("materials", 0)) + gain
			e.resources["knowledge"] = int(e.resources.get("knowledge", 0)) + int(bg["knowledge"])
			e.biomass += gain
		return
	c.growth += Economy.growth_per_day(state, c)
	if c.growth >= Economy.growth_threshold(c.population):
		c.growth = 0
		c.population += 1


## Fin d'un chantier : un bâtiment s'ajoute, un bâtiment de 2e rang remplace son 1er rang, un projet de
## terraformation change le type de la planète (retenu dans planet_overrides, donc sauvegardé).
static func _finish_building(state: GameState, c: Colony, e: Empire, planet_name: String, added: Array[Dictionary]) -> void:
	var bid := c.construction
	var b := GameData.building(bid)
	var label := String(b.get("label", bid))
	c.construction = ""
	c.construction_days = 0
	if b.has("terraform"):
		var p := state.galaxy.get_planet(c.planet_id)
		var target := Economy.terraform_target(state, c.owner, p, bid)
		if target == "":
			return  # (le monde a changé entre-temps : le projet n'a plus d'objet)
		var before := p.type_label()
		state.override_planet(c.planet_id, {"type": target})
		e.hab_cache.clear()
		added.append(state.add_chronicle("%s : %s n'est plus un monde %s, c'est désormais : %s. Les cartes sont à refaire." % [
				e.short_name(), planet_name, before.to_lower(), p.type_label()]))
		return
	var base := String(b.get("upgrades", ""))
	var at := c.buildings.find(base) if base != "" else -1
	if at >= 0:
		c.buildings[at] = bid
	else:
		c.buildings.append(bid)
	Economy.clear_wonders()
	if b.get("galaxy_unique", false):
		added.append(state.add_chronicle("Merveille : %s achève %s sur %s. Toute la galaxie en parle, certains avec envie." % [e.display_name(), label, planet_name]))
	else:
		added.append(state.add_chronicle("%s : chantier achevé sur %s (%s)." % [e.short_name(), planet_name, label]))


## Colonie qui accueille les migrants (Spatioports de transit) : la moins peuplée de l'empire qui a
## encore de la place (à égalité, la plus petite identifiant). null si toutes sont pleines.
static func migration_target(state: GameState, from: Colony) -> Colony:
	var best: Colony = null
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c == from or c.owner != from.owner or not c.is_colony() or not c.is_established():
			continue
		if best != null and c.population >= best.population:
			continue
		if c.population < Economy.max_pop(state, state.galaxy.get_planet(pid), c.owner, c.buildings):
			best = c
	return best


static func _monthly_balance(state: GameState, e: Empire, added: Array[Dictionary]) -> void:
	var net: Dictionary = Economy.empire_income(state, e.id)["net"]
	for r in net:
		e.resources[r] = int(e.resources.get(r, 0)) + int(net[r])

	_monthly_research(state, e, int(net.get("knowledge", 0)), added)

	_monthly_traits(state, e, added)

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


## Traits de faction au bilan mensuel (après les ressources, avant le plancher à zéro) :
## ferveur du Chœur Éternel, dissidence des fiefs lointains d'Ossarane.
static func _monthly_traits(state: GameState, e: Empire, added: Array[Dictionary]) -> void:
	var f := e.faction()
	if FactionTraits.has_fervor(f):
		var fv: Dictionary = f["fervor"]
		var before := e.fervor
		e.fervor = clampi(e.fervor + FactionTraits.fervor_delta(state, e.id), 0, int(fv["max"]))
		if e.fervor <= 0 and before > 0:
			added.append(state.add_chronicle("Le dieu-machine du %s se tait. Les forges ralentissent, les prêtres chantent plus fort, par précaution." % e.short_name()))
		elif e.fervor >= int(fv["exalted_at"]) and before < int(fv["exalted_at"]):
			added.append(state.add_chronicle("Exaltation dans l'Hégémonie : le dieu-machine ronronne, les forges flamboient, les hymnes gagnent un couplet."))
	var levy := FactionTraits.levy_count(state, e.id)
	if levy > 0:
		var ship := String(f["fiefs"]["levy"]["ship"])
		var fl := state.spawn_ship(e.id, ship, state.galaxy.get_planet(e.capital_planet).system_id)
		for _i in levy - 1:
			fl.add_ship(ship, -1, Research.mark_gen(state, e.id))
		fl.troops = Combat.max_troops(fl, state)
		fl.fleet_name = "Ban des vassaux"
		added.append(state.add_chronicle("Levée du ban chez %s : %d vassaux accourent à la capitale avec leurs corvettes. Ils ne promettent pas de gagner, seulement d'être là." % [
				e.display_name(), levy]))
	if FactionTraits.has_fiefs(f):
		var was := e.dissent
		e.dissent = int(e.resources.get("crystals", 0)) < 0
		if e.dissent and not was:
			added.append(state.add_chronicle("Dissidence chez %s : faute de cristaux, les fiefs lointains découvrent qu'ils ont toujours détesté la capitale." % e.display_name()))
		elif was and not e.dissent:
			added.append(state.add_chronicle("Les fiefs lointains de %s renouvellent leur serment. Les cristaux sont arrivés, l'affection aussi." % e.short_name()))


## Recherche au bilan mensuel : la file consomme le Savoir stocké (Research.advance).
## Chronique : chaque découverte d'un joueur humain, et l'ouverture d'une ère pour tous.
static func _monthly_research(state: GameState, e: Empire, income: int, added: Array[Dictionary]) -> void:
	if e.eliminated:
		return
	var era_before := Research.current_era(state, e.id)
	# Eurêkas : ce qui s'est passé fait avancer la recherche (40 % d'une technologie). Vérifiés chaque
	# trimestre, à tour de rôle selon l'empire : la simulation reste légère.
	@warning_ignore("integer_division")
	var quarter := posmod(state.tick / int(GameData.rules()["month_days"]) + e.id, 3) == 0
	for tid in (Research.check_eurekas(state, e.id) if quarter else []):
		if not e.is_ai():
			added.append(state.add_chronicle("Eurêka ! Objectif atteint (%s) : les savants de %s font un bond de %d %s sur « %s »." % [
					Research.eureka_text(tid), e.short_name(), int(Research.data().get("eureka_pct", 40)), "%",
					String(Research.tech(tid).get("label", tid))]))
	var done := Research.advance(state, e.id, income)
	if done.is_empty():
		return
	if not e.is_ai():
		for tid in done:
			added.append(state.add_chronicle("%s découvre : %s." % [e.short_name(), String(Research.tech(tid).get("label", tid))]))
	var era_after := Research.current_era(state, e.id)
	if era_after > era_before:
		added.append(state.add_chronicle("%s entre dans l'ère %d. Les savants réclament déjà des crédits pour la suivante." % [e.display_name(), era_after]))
