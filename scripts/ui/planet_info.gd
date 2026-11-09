class_name PlanetInfo
extends RefCounted
## Textes d'interface sur une planète, partagés par la fiche de la galaxie et la vue système.
## Ne fait que lire l'état : les chiffres viennent des mêmes fonctions qu'utilise la simulation (Economy).


## "Colonie d'Ossarane (8 pop)", "Avant-poste de Vael en fondation", "Libre"…
static func status_line(state: GameState, p: Planet) -> String:
	var c: Colony = state.colonies.get(p.id)
	if c == null:
		return "Libre"
	var owner := state.get_empire(c.owner)
	var kind_label := "Colonie" if c.is_colony() else "Avant-poste"
	if not c.is_established():
		return "%s de %s en fondation (%d j)" % [kind_label, owner.short_name(), c.days_left]
	if c.is_colony():
		return "%s de %s (%d pop)" % [kind_label, owner.short_name(), c.population]
	return "%s de %s" % [kind_label, owner.short_name()]


## Habitabilité pour l'espèce du joueur : {"pct": 0..100, "text": String}.
static func habitability(state: GameState, p: Planet, player: int) -> Dictionary:
	var me := state.get_empire(player)
	if not p.is_habitable_type():
		return {"pct": 0, "text": "Inhabitable : avant-poste seulement"}
	if me == null:
		return {"pct": 0, "text": ""}
	var hab := Economy.habitability(p.type, me.faction())
	var cap := Economy.max_pop(state, p, player)
	if cap <= 0:
		return {"pct": hab, "text": "Inhabitable pour votre espèce"}
	return {"pct": hab, "text": "Habitable à %d %%, jusqu'à %d pop" % [hab, cap]}


static func deposit_labels(p: Planet) -> PackedStringArray:
	var deps := PackedStringArray()
	for d in p.deposits:
		deps.append(String(GameData.deposit(d).get("label", d)))
	return deps


## Détails d'une colonie : population, bâtiments, chantier, production (pour son propriétaire).
static func colony_lines(state: GameState, p: Planet, c: Colony, player: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var owner := state.get_empire(c.owner)
	var kind_label := "Colonie" if c.is_colony() else "Avant-poste"
	if not c.is_established():
		lines.append("%s de %s en fondation : %d j" % [kind_label, owner.short_name(), c.days_left])
		return lines
	if c.is_colony():
		var cap := Economy.max_pop(state, p, c.owner, c.buildings)
		@warning_ignore("integer_division")
		var growth := "" if c.population >= cap else ", croissance %d %%" % (100 * c.growth / Economy.growth_threshold(c.population))
		lines.append("%s de %s : %d/%d pop%s" % [kind_label, owner.short_name(), c.population, cap, growth])
	else:
		lines.append("%s de %s" % [kind_label, owner.short_name()])
	if not c.buildings.is_empty():
		var names := PackedStringArray()
		for b in c.buildings:
			names.append(String(GameData.building(b).get("label", b)))
		lines.append("Bâtiments (%d/%d) : %s" % [Economy.building_slots_used(c), Economy.building_slots(state, c), ", ".join(names)])
	else:
		lines.append("Bâtiments : 0/%d" % Economy.building_slots(state, c))
	if c.construction != "":
		lines.append("Chantier : %s (%d j)" % [GameData.building(c.construction).get("label", c.construction), c.construction_days])
	if c.owner == player:
		lines.append("Par mois (avant bonus) : %s" % GameData.format_amounts(net_yields(state, c), true))
	return lines


static func net_yields(state: GameState, c: Colony) -> Dictionary:
	var y := Economy.colony_yields(state, c)
	var net := {}
	for r in y["gross"]:
		net[r] = int(y["gross"][r]) - int(y["upkeep"][r])
	return net
