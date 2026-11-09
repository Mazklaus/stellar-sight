class_name PlanetInfo
extends RefCounted
## Textes d'interface sur une planète, partagés par la fiche de la galaxie et la vue système.
## Ne fait que lire l'état : les chiffres viennent des mêmes fonctions qu'utilise la simulation (Economy).

## Couleur de chaque ressource dans l'interface.
const RESOURCE_COLORS := {
	"energy": Color(1.0, 0.84, 0.3), "materials": Color(0.95, 0.55, 0.3), "food": Color(0.5, 0.88, 0.4),
	"influence": Color(0.75, 0.55, 1.0), "crystals": Color(0.4, 0.9, 1.0),
}
## Couleur de chaque disponibilité (voir availability()).
const AVAILABILITY_COLORS := {
	"owned": Color(1.0, 0.82, 0.3), "foreign": Color(1.0, 0.5, 0.45), "founding": Color(1.0, 0.82, 0.3, 0.8),
	"colonizable": Color(0.45, 0.95, 0.55), "outpost": Color(0.6, 0.78, 1.0), "out_of_range": Color(0.6, 0.62, 0.7),
	"claimed": Color(1.0, 0.5, 0.45),
}


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


## Version courte pour les listes : "libre", "Vael · 8 pop", "fondation · 30 j"…
## Le nom du propriétaire est omis quand c'est viewer (la couleur suffit à le reconnaître).
static func short_status(state: GameState, p: Planet, viewer := -1) -> String:
	var c: Colony = state.colonies.get(p.id)
	if c == null:
		return "libre"
	var owner := "" if c.owner == viewer else state.get_empire(c.owner).short_name() + " · "
	if not c.is_established():
		return "%sfondation · %d j" % [owner, c.days_left]
	if c.is_colony():
		return "%s%d pop" % [owner, c.population]
	return "%savant-poste" % owner


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


## Potentiel de la planète pour chaque ressource, de 0 à 5 (affiché en barres).
## Indicatif : rendement par population, rendement d'avant-poste et gisements.
static func potential(p: Planet) -> Dictionary:
	var t := GameData.planet_type(p.type)
	var pop: Dictionary = t.get("pop_yields", {})
	var outpost: Dictionary = t.get("outpost_yields", {})
	var out := {}
	for r in GameData.resource_ids():
		var v := int(pop.get(r, 0)) * 2 + int(outpost.get(r, 0))
		for d in p.deposits:
			v += int(GameData.deposit(d).get("yields", {}).get(r, 0)) * 2
		out[r] = clampi(v, 0, 5)
	return out


static func potential_label(v: int) -> String:
	if v <= 0:
		return "nul"
	if v <= 2:
		return "faible"
	if v <= 3:
		return "bon"
	return "excellent"


## Ce que la planète représente pour le joueur, en un mot : {"text", "kind"}.
## kind : "owned", "foreign", "founding", "colonizable", "outpost", "out_of_range", "claimed".
static func availability(state: GameState, p: Planet, player: int) -> Dictionary:
	var c: Colony = state.colonies.get(p.id)
	if c:
		var mine := c.owner == player
		if not c.is_established():
			return {"text": "En fondation (%d j)" % c.days_left, "kind": "founding"}
		var what := "Colonisée" if c.is_colony() else "Avant-poste"
		return {"text": what if mine else "%s (%s)" % [what, state.get_empire(c.owner).short_name()], "kind": "owned" if mine else "foreign"}
	var owner := state.system_owner(p.system_id)
	if owner != -1 and owner != player:
		return {"text": "Revendiquée", "kind": "claimed"}
	if not Economy.in_range(state, player, p.system_id):
		return {"text": "Hors de portée", "kind": "out_of_range"}
	if Economy.max_pop(state, p, player) > 0:
		return {"text": "Colonisable", "kind": "colonizable"}
	return {"text": "Avant-poste possible", "kind": "outpost"}
