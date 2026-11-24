class_name ArtCatalog
extends RefCounted
## Recensement des emplacements d'illustration du jeu (refonte, F1 et F4). Chaque emplacement est un
## identifiant que cherche un Widgets.ArtSlot : déposer assets/art/<identifiant>.png (ou .jpg, .webp)
## remplace le tableau provisoire sans toucher au code. La liste est lue dans les données du jeu :
## une carte, une merveille ou un peuple de plus y entre tout seul.

## Écrans d'empire qui portent un en-tête illustré dans leur colonne de gauche.
const SCREENS := {"amphictyony": "Amphictyonie", "armies": "Armées", "battles": "Batailles", "chronicles": "Chroniques", "colonies": "Colonies",
		"contact": "Contact", "culture": "Rayonnement", "diplomacy": "Diplomatie", "faith": "Foi", "fleets": "Flottes", "forge": "Forge des mondes",
		"genome": "Génome", "heroes": "Panthéon", "intel": "Renseignement", "kardashev": "L'Échelle", "megas": "Mégastructures", "order": "Ordre",
		"psionics": "Psionique", "senate": "Sénat", "throne": "Trône", "trade": "Commerce", "transcendence": "Transcendance", "victory": "Victoire",
		"wonders": "Merveilles"}

## Familles dans l'ordre de la Galerie : id, libellé, rang de priorité (1 = vu à chaque partie), format.
const FAMILIES := [
	{"id": "accueil", "label": "Accueil", "rank": 1, "format": "16:9"},
	{"id": "peuples", "label": "Portraits des peuples", "rank": 1, "format": "3:4"},
	{"id": "scenes", "label": "Grandes scènes des peuples", "rank": 1, "format": "16:9"},
	{"id": "ecrans", "label": "En-têtes d'écrans", "rank": 1, "format": "2:1"},
	{"id": "mondes", "label": "Types de mondes", "rank": 1, "format": "4:3"},
	{"id": "annonces", "label": "Annonces", "rank": 1, "format": "3:1"},
	{"id": "evenements", "label": "Cartes d'événement", "rank": 2, "format": "16:9"},
	{"id": "merveilles", "label": "Merveilles", "rank": 2, "format": "16:9"},
	{"id": "megastructures", "label": "Mégastructures", "rank": 2, "format": "16:9"},
	{"id": "forge", "label": "Forge des mondes", "rank": 2, "format": "16:9"},
	{"id": "quetes", "label": "Quêtes", "rank": 2, "format": "16:9"},
	{"id": "faune", "label": "Faune de l'espace", "rank": 2, "format": "4:3"},
	{"id": "portraits", "label": "Portraits de l'éditeur de peuple", "rank": 3, "format": "3:4"},
]

static var _slots: Array = []
static var _by_id: Dictionary = {}


static func _json(file: String) -> Variant:
	var f := FileAccess.open("res://data/%s.json" % file, FileAccess.READ)
	return JSON.parse_string(f.get_as_text()) if f else {}


static func family(fid: String) -> Dictionary:
	for f: Dictionary in FAMILIES:
		if String(f["id"]) == fid:
			return f
	return {}


static func _add(fam: String, id: String, label: String, format := "") -> void:
	if id == "" or _by_id.has(id):
		return
	var s := {"id": id, "family": fam, "label": label, "format": format if format != "" else String(family(fam)["format"]), "rank": int(family(fam)["rank"])}
	_by_id[id] = s
	_slots.append(s)


## Tous les emplacements : [{"id", "family", "label", "format", "rank"}], dans l'ordre des familles.
static func slots() -> Array:
	if not _slots.is_empty():
		return _slots
	_add("accueil", "main_menu", "Fond de l'accueil")
	_add("accueil", "new_game_galaxy", "Bandeau de la galaxie (nouvelle partie)", "4:1")
	_add("accueil", "victory", "Fin de partie")
	_add("accueil", "election", "Élection", "3:4")
	var factions: Array = _json("factions")
	for f: Dictionary in factions:
		_add("peuples", GameData.portrait_art(String(f["id"])), String(f["name"]))
	_add("peuples", "faction_random", "Au hasard")
	for f: Dictionary in factions:
		_add("scenes", "faction_%s_scene" % String(f["id"]), String(f["name"]))
	for s: String in SCREENS:
		_add("ecrans", "screen_" + s, String(SCREENS[s]))
	var worlds: Dictionary = _json("planet_types")
	for k: String in worlds:
		if not k.begins_with("_"):
			_add("mondes", "planet_" + k, String((worlds[k] as Dictionary).get("label", k)))
	var kinds: Dictionary = (_json("announcements") as Dictionary).get("kinds", {})
	for k: String in kinds:
		_add("annonces", "annonces/" + k, String((kinds[k] as Dictionary).get("title", k)))
	for file: String in ["events", "ancients", "minors"]:
		for c: Dictionary in (_json(file) as Dictionary).get("cards", []):
			_add("evenements", "event_" + String(c["id"]), String(c.get("title", c["id"])))
	var wonders: Dictionary = (_json("wonders") as Dictionary).get("wonders", {})
	for k: String in wonders:
		_add("merveilles", "wonder_" + k, String((wonders[k] as Dictionary).get("label", k)))
	var megas: Dictionary = (_json("megastructures") as Dictionary).get("kinds", {})
	for k: String in megas:
		_add("megastructures", "mega_" + k, String((megas[k] as Dictionary).get("label", k)))
	var forge: Dictionary = _json("worldforge")
	for part: String in ["ops", "instant"]:
		for k: String in forge.get(part, {}):
			if not k.begins_with("_"):
				_add("forge", "forge_" + k, String((forge[part][k] as Dictionary).get("label", k)))
	var quests: Dictionary = (_json("quests") as Dictionary).get("templates", {})
	for k: String in quests:
		_add("quetes", "quest_" + k, String((quests[k] as Dictionary).get("title", k)))
	var fauna: Dictionary = (_json("creatures") as Dictionary).get("species", {})
	for k: String in fauna:
		_add("faune", "fauna_" + k, String((fauna[k] as Dictionary).get("label", k)))
	for p: Dictionary in (_json("species_parts") as Dictionary).get("portraits", []):
		_add("portraits", "portrait_" + String(p["id"]), String(p.get("label", p["id"])))
	return _slots


static func slot(id: String) -> Dictionary:
	slots()
	return _by_id.get(id, {})


## Une illustration définitive est-elle déposée pour cet emplacement ?
static func has_file(id: String) -> bool:
	return Widgets.ArtSlot.art_path(id) != ""


## [déposées, total] pour une famille ("" = tout le jeu).
static func progress(fam := "") -> Array:
	var done := 0
	var total := 0
	for s: Dictionary in slots():
		if fam == "" or String(s["family"]) == fam:
			total += 1
			if has_file(String(s["id"])):
				done += 1
	return [done, total]
