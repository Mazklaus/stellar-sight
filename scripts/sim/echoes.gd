class_name Echoes
extends RefCounted
## Registre Cosmique : les Échos. Une perception non linéaire du temps (document de game design :
## « règles partiellement cachées, perception non linéaire du temps », ressource « Échos ») :
## - les échos s'accumulent chaque mois (un fond, plus un par colonie peuplée), jusqu'à un plafond ;
## - Replier le temps : dépenser des échos pour faire avancer d'un coup un chantier d'une colonie
##   (bâtiment ou vaisseau) ; c'est agir sur plusieurs tours à la fois ;
## - Préscience : les flottes étrangères qui font route vers un système de l'empire sont visibles dès
##   leur départ, où qu'elles soient.
## Règles dans le champ "echoes" de la fiche (couche registre de data/species_parts.json).
##
## Inspiration : les Naalu de Twilight Imperium, qui voient l'avenir et jouent toujours en premier
## (capacités « Telepathic » et « Foresight », d'après des guides de joueurs) ; le reste est propre au jeu.

const BUILDING := "building"
const SHIP := "ship"


static func has(faction: Dictionary) -> bool:
	return faction.has("echoes")


static func cfg(state: GameState, empire_id: int) -> Dictionary:
	var e := state.get_empire(empire_id)
	return {} if e == null else e.faction().get("echoes", {})


## Échos gagnés ce mois-ci.
static func monthly_gain(state: GameState, empire_id: int) -> int:
	var c := cfg(state, empire_id)
	if c.is_empty():
		return 0
	var n := 0
	for pid in state.colonies:
		var col: Colony = state.colonies[pid]
		if col.owner == empire_id and col.is_colony() and col.is_established():
			n += 1
	return int(c.get("per_month", 0)) + int(c.get("per_colony", 0)) * n


static func monthly(state: GameState) -> void:
	for e in state.empires:
		if e.eliminated or not has(e.faction()):
			continue
		e.echoes = mini(int(e.faction()["echoes"].get("max", 100)), e.echoes + monthly_gain(state, e.id))


static func fold_cost(state: GameState, empire_id: int) -> int:
	return int(cfg(state, empire_id).get("fold_cost", 0))


static func fold_days(state: GameState, empire_id: int) -> int:
	return int(cfg(state, empire_id).get("fold_days", 0))


static func check_fold(state: GameState, empire_id: int, planet_id: int, what: String) -> String:
	var e := state.get_empire(empire_id)
	if e == null:
		return "empire inconnu : %d" % empire_id
	if not has(e.faction()):
		return "votre peuple vit le temps dans l'ordre, comme tout le monde"
	if what != BUILDING and what != SHIP:
		return "chantier inconnu : %s" % what
	var c: Colony = state.colonies.get(planet_id)
	if c == null or c.owner != empire_id:
		return "cette planète ne vous appartient pas"
	if (what == BUILDING and c.construction == "") or (what == SHIP and c.ship_build == ""):
		return "aucun chantier en cours"
	if e.echoes < fold_cost(state, empire_id):
		return "échos insuffisants (il en faut %d)" % fold_cost(state, empire_id)
	return ""


## Replie le temps sur un chantier (conditions vérifiées) : il avance de fold_days jours.
static func fold(state: GameState, empire_id: int, planet_id: int, what: String) -> void:
	var e := state.get_empire(empire_id)
	var c: Colony = state.colonies[planet_id]
	e.echoes -= fold_cost(state, empire_id)
	var d := fold_days(state, empire_id)
	if what == BUILDING:
		c.construction_days = maxi(1, c.construction_days - d)
	else:
		c.ship_days = maxi(1, c.ship_days - d)
	Research.count_stat(state, empire_id, "folds")
	state.add_chronicle("Sur %s, le chantier se souvient de jours qui n'ont pas encore eu lieu. Les ouvriers, eux, ne se souviennent de rien." % [
			state.galaxy.get_planet(planet_id).display_name(state.galaxy)], Espionage.private_to(state, [empire_id]))


## Préscience : viewer voit-il cette flotte étrangère parce qu'elle vient vers lui ?
static func foresees(state: GameState, viewer: int, fleet: Fleet) -> bool:
	if viewer < 0 or fleet.owner == viewer or not fleet.is_moving():
		return false
	if not bool(cfg(state, viewer).get("foresight", false)):
		return false
	return state.system_owner(fleet.destination()) == viewer


static func gauge(state: GameState, empire_id: int) -> Dictionary:
	var e := state.get_empire(empire_id)
	var c: Dictionary = e.faction()["echoes"]
	return {"label": "Échos", "value": "%d" % e.echoes, "delta": monthly_gain(state, empire_id),
			"tip": "Échos %d / %d (+%d par mois : %d de fond, %d par colonie peuplée)\nReplier le temps : %d échos, un chantier avance de %d jours.\nPréscience : les flottes qui font route vers vos systèmes sont visibles dès leur départ." % [
				e.echoes, int(c.get("max", 100)), monthly_gain(state, empire_id), int(c.get("per_month", 0)), int(c.get("per_colony", 0)),
				fold_cost(state, empire_id), fold_days(state, empire_id)]}
