class_name Empire
extends RefCounted
## Un empire (joueur humain ou IA). Son identifiant est aussi celui du joueur dans les ordres.

var id: int = -1
var faction_id: String = ""
## Stocks : {"energy": int, "materials": int, ...}.
var resources: Dictionary = {}
var capital_planet: int = -1
## Pénuries constatées au dernier bilan mensuel.
var starving: bool = false
var blackout: bool = false


func faction() -> Dictionary:
	return GameData.faction(faction_id)


func display_name() -> String:
	return String(faction().get("name", faction_id))


func short_name() -> String:
	return String(faction().get("short", faction_id))


func color() -> Color:
	return Color.html(String(faction().get("color", "#ffffff")))


func to_dict() -> Dictionary:
	return {
		"id": id,
		"faction": faction_id,
		"resources": resources.duplicate(),
		"capital": capital_planet,
		"starving": starving,
		"blackout": blackout,
	}


static func from_dict(d: Dictionary) -> Empire:
	var e := Empire.new()
	e.id = int(d["id"])
	e.faction_id = String(d["faction"])
	for r in GameData.resource_ids():
		e.resources[r] = int(d["resources"].get(r, 0))
	e.capital_planet = int(d["capital"])
	e.starving = bool(d["starving"])
	e.blackout = bool(d["blackout"])
	return e
