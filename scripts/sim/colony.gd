class_name Colony
extends RefCounted
## Une revendication sur une planète : colonie (avec population) ou avant-poste (sans).
## Fait partie de l'état de partie : sauvegardée et comparée en multijoueur.

const KIND_COLONY := "colony"
const KIND_OUTPOST := "outpost"

var planet_id: int = -1
var owner: int = -1
var kind: String = KIND_COLONY
## Jours restants avant la fondation (0 = établie).
var days_left: int = 0
var population: int = 0
## Progression vers la prochaine population (voir Economy.growth_threshold).
var growth: int = 0
var buildings: Array[String] = []
## Bâtiment en construction ("" = aucun) et jours restants.
var construction: String = ""
var construction_days: int = 0


func is_established() -> bool:
	return days_left <= 0


func is_colony() -> bool:
	return kind == KIND_COLONY


func to_dict() -> Dictionary:
	return {
		"planet": planet_id,
		"owner": owner,
		"kind": kind,
		"days_left": days_left,
		"population": population,
		"growth": growth,
		"buildings": Array(buildings),
		"construction": construction,
		"construction_days": construction_days,
	}


static func from_dict(d: Dictionary) -> Colony:
	var c := Colony.new()
	c.planet_id = int(d["planet"])
	c.owner = int(d["owner"])
	c.kind = String(d["kind"])
	c.days_left = int(d["days_left"])
	c.population = int(d["population"])
	c.growth = int(d["growth"])
	for b in d["buildings"]:
		c.buildings.append(String(b))
	c.construction = String(d["construction"])
	c.construction_days = int(d["construction_days"])
	return c
