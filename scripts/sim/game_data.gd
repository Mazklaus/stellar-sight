class_name GameData
extends RefCounted
## Données de jeu (factions, types de planètes, bâtiments, règles), lues dans res://data/*.json.
## Tout l'équilibrage vit dans ces fichiers : on ajuste les chiffres sans toucher au code,
## et le futur éditeur d'espèces écrira dans le même format.
##
## Les nombres entiers du JSON sont convertis en int : la simulation ne calcule qu'en entiers,
## pour rester identique à l'octet près sur toutes les machines (multijoueur).

const DATA_DIR := "res://data"

static var _cache := {}


static func rules() -> Dictionary:
	return _load("rules")


## Peuples officiels (data/factions.json), dans l'ordre des données.
static func factions() -> Array:
	return _load("factions")


## Peuples créés dans l'éditeur d'espèces (voir Species, SpeciesLibrary), au format de factions.json :
## - ceux de la bibliothèque du joueur (user://species/), chargés au démarrage ;
## - ceux de la partie en cours, recopiés dans la sauvegarde : ils passent avant la bibliothèque, pour
##   qu'une partie garde son peuple tel qu'il était au lancement même si le fichier a changé depuis.
static var _library_factions := {}
static var _game_factions := {}
## Augmente à chaque changement des peuples créés (bibliothèque ou partie) : Empire.faction() garde sa
## fiche tant qu'il ne bouge pas.
static var factions_gen := 0


## Fiche d'un peuple par identifiant : partie en cours, puis bibliothèque, puis officiels. {} si inconnu.
static func faction(id: String) -> Dictionary:
	if _game_factions.has(id):
		return _game_factions[id]
	if _library_factions.has(id):
		return _library_factions[id]
	# Index des peuples officiels (appelé à chaque instant par la simulation : pas de parcours de liste).
	if not _cache.has("factions_by_id"):
		var idx := {}
		for f: Dictionary in factions():
			idx[f["id"]] = f
		_cache["factions_by_id"] = idx
	return _cache["factions_by_id"].get(id, {})


## Identifiants des peuples officiels seulement.
static func faction_ids() -> Array[String]:
	var ids: Array[String] = []
	for f: Dictionary in factions():
		ids.append(String(f["id"]))
	return ids


## Peuples officiels puis peuples de la bibliothèque (triés), pour les listes de choix.
static func all_faction_ids() -> Array[String]:
	var ids := faction_ids()
	ids.append_array(library_faction_ids())
	return ids


static func library_faction_ids() -> Array[String]:
	var ids: Array[String] = []
	for k in _library_factions:
		ids.append(String(k))
	ids.sort()
	return ids


static func is_official(id: String) -> bool:
	return faction_ids().has(id)


static func register_library_faction(f: Dictionary) -> void:
	_library_factions[String(f["id"])] = f
	factions_gen += 1


static func unregister_library_faction(id: String) -> void:
	_library_factions.erase(id)
	factions_gen += 1


static func clear_library_factions() -> void:
	_library_factions.clear()
	factions_gen += 1


## Peuples créés de la partie en cours (GameState.custom_factions).
static func set_game_factions(d: Dictionary) -> void:
	_game_factions = d
	factions_gen += 1


static func clear_game_factions() -> void:
	_game_factions = {}
	factions_gen += 1


## Style des vaisseaux d'un peuple (sprites et modèles 3D d'un peuple officiel) : son identifiant
## pour un officiel, celui choisi dans l'éditeur pour un peuple créé.
static func ship_style(faction_id: String) -> String:
	return String(faction(faction_id).get("ship_style", faction_id))


## Illustration du peuple (Widgets.ArtSlot) : "faction_<id>" pour un officiel, "portrait_<portrait>"
## pour un peuple créé (portrait choisi dans l'éditeur).
static func portrait_art(faction_id: String) -> String:
	var f := faction(faction_id)
	if f.has("portrait"):
		return "portrait_" + String(f["portrait"])
	return "faction_" + faction_id


## Briques de l'éditeur d'espèces (data/species_parts.json).
static func species_parts() -> Dictionary:
	return _load("species_parts")


static func planet_types() -> Dictionary:
	return _load("planet_types")


static func planet_type(id: String) -> Dictionary:
	return planet_types().get(id, {})


static func buildings() -> Dictionary:
	return _load("buildings")


static func building(id: String) -> Dictionary:
	return buildings().get(id, {})


## Classes de vaisseaux (data/ships.json), par identifiant. Les classes de combat sont des modèles
## d'origine de l'éditeur (Designs) : leurs caractéristiques sont calculées une fois depuis leur coque
## et leurs modules (data/designs.json), puis gardées en cache avec le reste.
static func ships() -> Dictionary:
	if not _cache.has("ships_built"):
		var raw: Dictionary = _load("ships")
		for sid in raw:
			var o := Designs.origin(String(sid))
			if o.is_empty():
				continue
			var computed := Designs.compute(String(o["hull"]), o.get("modules", []))
			var sd: Dictionary = raw[sid]
			for k in computed:
				if not sd.has(k) or k in Designs.STATS or k in ["weapons", "cost", "days", "upkeep", "hull"] or k in Designs.FLAGS:
					sd[k] = computed[k]
			sd["modules"] = (o.get("modules", []) as Array).duplicate()
		_cache["ships_built"] = true
	return _load("ships")


## Coques, modules et modèles d'origine de l'éditeur de vaisseaux (data/designs.json).
static func designs_data() -> Dictionary:
	return _load("designs")


## Modèles conçus en partie (voir Designs.register_all) : identifiant -> caractéristiques.
## Ils se lisent comme des classes, partout où le jeu lit GameData.ship().
static var _custom := {}


static var _ids_cache: Array[String] = []
static var _class_ids_cache: Array[String] = []


static func register_custom_ship(id: String, stats: Dictionary) -> void:
	_custom[id] = stats
	_ids_cache = []


static func clear_custom_ships() -> void:
	_custom.clear()
	_ids_cache = []


static func ship(id: String) -> Dictionary:
	if _custom.has(id):
		return _custom[id]
	# Créatures (data/creatures.json, « units ») : elles se lisent comme des classes au combat, sans
	# figurer parmi les classes que l'on construit.
	if id.begins_with("bete_"):
		var u: Dictionary = creatures().get("units", {}).get(id, {})
		return u if not u.is_empty() else guardians().get("units", {}).get(id, {})
	return ships().get(id, {})


## Identifiants des classes de vaisseaux, triés (ordre stable pour l'interface et la simulation),
## puis ceux des modèles conçus en partie, triés aussi.
## Liste gardée en cache (refaite quand un modèle est enregistré) : ne pas la modifier.
static func ship_ids() -> Array[String]:
	if _ids_cache.is_empty():
		var ids: Array[String] = class_ids().duplicate()
		var custom: Array[String] = []
		for k in _custom:
			custom.append(String(k))
		custom.sort()
		ids.append_array(custom)
		_ids_cache = ids
	return _ids_cache


## Identifiants des classes de data/ships.json seulement, triés (cache, ne pas modifier).
static func class_ids() -> Array[String]:
	if _class_ids_cache.is_empty():
		var ids: Array[String] = []
		for k in ships():
			ids.append(String(k))
		ids.sort()
		_class_ids_cache = ids
	return _class_ids_cache


static func ai() -> Dictionary:
	return _load("ai")


## Règles du combat (data/combat.json) : phases, armes, tactiques, siège.
static func combat() -> Dictionary:
	return _load("combat")


## Diplomatie (data/diplomacy.json) : traités, opinion, souvenirs, talents des peuples, IA.
static func diplomacy() -> Dictionary:
	return _load("diplomacy")


## Commerce (data/trade.json) : paliers de traité, routes, comptoirs, piraterie des routes.
static func trade() -> Dictionary:
	return _load("trade")


static func goods() -> Dictionary:
	return _load("goods")


## Identifiants des ressources stratégiques (Goods) : elles vivent dans le stock de l'empire comme les
## autres, mais restent hors des bilans et des barres (resource_ids ne les liste pas).
static func strategic_ids() -> Array[String]:
	if not _cache.has("strategic_ids"):
		var ids: Array[String] = []
		for d: Dictionary in goods()["strategic"]:
			ids.append(String(d["id"]))
		_cache["strategic_ids"] = ids
	return _cache["strategic_ids"]


## Toutes les ressources d'un stock : les six de base puis les stratégiques.
static func stock_ids() -> Array[String]:
	var ids := resource_ids()
	ids.append_array(strategic_ids())
	return ids


## Stabilité des systèmes (data/stability.json).
static func stability() -> Dictionary:
	return _load("stability")


## Pirates (data/pirates.json) : repaires, raids, tribut, contrats, primes.
static func pirates() -> Dictionary:
	return _load("pirates")


static func creatures() -> Dictionary:
	return _load("creatures")


static func guardians() -> Dictionary:
	return _load("guardians")


static func events() -> Dictionary:
	return _load("events")


static func relics() -> Dictionary:
	return _load("relics")


static func quests() -> Dictionary:
	return _load("quests")


static func politics() -> Dictionary:
	return _load("politics")


## Espionnage (data/espionage.json) : cellules, réseaux, paliers, sondes.
static func espionage() -> Dictionary:
	return _load("espionage")


## Héros (data/heroes.json) : classes, postes, traits, renom, galerie de portraits.
static func heroes() -> Dictionary:
	return _load("heroes")


## Technologies (data/technologies.json) : domaines, ères, coûts, arbre.
static func technologies() -> Dictionary:
	return _load("technologies")


## Conditions de victoire (data/victories.json) : classiques, de peuple, date limite, score.
static func victories() -> Dictionary:
	return _load("victories")


static func deposit(id: String) -> Dictionary:
	if not _cache.has("deposits_by_id"):
		var idx := {}
		for d: Dictionary in rules()["deposits"]:
			if not idx.has(d["id"]):
				idx[d["id"]] = d
		_cache["deposits_by_id"] = idx
	return _cache["deposits_by_id"].get(id, {})


static func resource_ids() -> Array[String]:
	var ids: Array[String] = []
	for r: Dictionary in rules()["resources"]:
		ids.append(String(r["id"]))
	return ids


static func resource_label(id: String, short := false) -> String:
	for r: Dictionary in rules()["resources"]:
		if r["id"] == id:
			return r["short"] if short else r["label"]
	for r: Dictionary in goods()["strategic"]:
		if r["id"] == id:
			return r["short"] if short else r["label"]
	return id


## Coût ou rendement lisible : {"materials": 80, "energy": 30} -> "80 Mat, 30 Én".
static func format_amounts(amounts: Dictionary, signed := false) -> String:
	var parts := PackedStringArray()
	for r in stock_ids():
		var v := int(amounts.get(r, 0))
		if v != 0:
			parts.append(("%+d %s" if signed else "%d %s") % [v, resource_label(r, true)])
	return ", ".join(parts) if not parts.is_empty() else "rien"


static func _load(name: String) -> Variant:
	if not _cache.has(name):
		var path := "%s/%s.json" % [DATA_DIR, name]
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed == null:
			push_error("Données de jeu illisibles : %s" % path)
			parsed = {}
		_cache[name] = _to_ints(parsed)
	return _cache[name]


static func _to_ints(v: Variant) -> Variant:
	if v is float and is_equal_approx(v, roundf(v)):
		return int(v)
	if v is Array:
		var out := []
		for x in v:
			out.append(_to_ints(x))
		return out
	if v is Dictionary:
		var out := {}
		for k in v:
			out[k] = _to_ints(v[k])
		return out
	return v
