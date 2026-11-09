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
## Systèmes explorés (vus au moins une fois) : id -> true. Le reste de la galaxie est dans le brouillard.
var explored: Dictionary = {}
## Empires rencontrés (identifiants, triés).
var contacts: Array[int] = []
## Vaisseaux sortis des chantiers, par classe (sert à numéroter les nouvelles flottes).
var ships_built: Dictionary = {}
## Traits de faction (voir FactionTraits) : ferveur du Chœur Éternel, dissidence des fiefs lointains
## d'Ossarane (cristaux manquants au dernier bilan), matériaux digérés en biomasse par l'Essaim.
var fervor: int = 0
var dissent: bool = false
var biomass: int = 0
## Niveau de l'IA qui dirige cet empire (voir AiLevels) ; "" = un joueur humain.
var ai_level: String = ""
## Dernière intention notable de l'IA, pour le mode spectateur. Simple affichage : jamais sauvegardée,
## jamais lue par la simulation (elle ne peut donc pas casser le déterminisme).
var ai_intent: String = ""


func is_ai() -> bool:
	return ai_level != ""


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
		"explored": sorted_explored(),
		"contacts": Array(contacts),
		"ships_built": ships_built.duplicate(),
		"fervor": fervor,
		"dissent": dissent,
		"biomass": biomass,
		"ai": ai_level,
	}


func sorted_explored() -> Array:
	var ids := explored.keys()
	ids.sort()
	return ids


static func from_dict(d: Dictionary) -> Empire:
	var e := Empire.new()
	e.id = int(d["id"])
	e.faction_id = String(d["faction"])
	for r in GameData.resource_ids():
		e.resources[r] = int(d["resources"].get(r, 0))
	e.capital_planet = int(d["capital"])
	e.starving = bool(d["starving"])
	e.blackout = bool(d["blackout"])
	for sid in d["explored"]:
		e.explored[int(sid)] = true
	for c in d["contacts"]:
		e.contacts.append(int(c))
	for k in d["ships_built"]:
		e.ships_built[String(k)] = int(d["ships_built"][k])
	e.fervor = int(d.get("fervor", 0))
	e.dissent = bool(d.get("dissent", false))
	e.biomass = int(d.get("biomass", 0))
	e.ai_level = String(d.get("ai", ""))
	return e
