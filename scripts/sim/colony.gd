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
## Vaisseau en construction au chantier spatial ("" = aucun) et jours restants.
## Le chantier spatial est indépendant de celui des bâtiments.
var ship_build: String = ""
var ship_days: int = 0
## Populations mixtes (voir Peoples) : habitants qui ne sont pas de l'espèce du propriétaire, par
## identifiant de peuple. Vide pour une colonie d'une seule espèce.
var species: Dictionary = {}
## Espèce qui fondera la colonie quand elle sera établie ("" = celle du propriétaire).
var founder: String = ""
## Intégration (0 à 100 %) de chaque espèce de la mosaïque (voir Peoples.integration ; absente = 100).
var integ: Dictionary = {}


func is_established() -> bool:
	return days_left <= 0


func is_colony() -> bool:
	return kind == KIND_COLONY


func to_dict() -> Dictionary:
	var d := {
		"planet": planet_id,
		"owner": owner,
		"kind": kind,
		"days_left": days_left,
		"population": population,
		"growth": growth,
		"buildings": Array(buildings),
		"construction": construction,
		"construction_days": construction_days,
		"ship_build": ship_build,
		"ship_days": ship_days,
	}
	if not species.is_empty():
		var sp := {}
		var keys := species.keys()
		keys.sort()
		for k in keys:
			sp[k] = int(species[k])
		d["species"] = sp
	if founder != "":
		d["founder"] = founder
	if not integ.is_empty():
		var ig := {}
		var ks := integ.keys()
		ks.sort()
		for k in ks:
			ig[k] = int(integ[k])
		d["integ"] = ig
	return d


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
	c.ship_build = String(d["ship_build"])
	c.ship_days = int(d["ship_days"])
	var sp: Dictionary = d.get("species", {})
	for k in sp:
		if int(sp[k]) > 0:
			c.species[String(k)] = int(sp[k])
	c.founder = String(d.get("founder", ""))
	var ig: Dictionary = d.get("integ", {})
	for k in ig:
		c.integ[String(k)] = int(ig[k])
	return c
