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


static func factions() -> Array:
	return _load("factions")


static func faction(id: String) -> Dictionary:
	for f: Dictionary in factions():
		if f["id"] == id:
			return f
	return {}


static func faction_ids() -> Array[String]:
	var ids: Array[String] = []
	for f: Dictionary in factions():
		ids.append(String(f["id"]))
	return ids


static func planet_types() -> Dictionary:
	return _load("planet_types")


static func planet_type(id: String) -> Dictionary:
	return planet_types().get(id, {})


static func buildings() -> Dictionary:
	return _load("buildings")


static func building(id: String) -> Dictionary:
	return buildings().get(id, {})


## Classes de vaisseaux (data/ships.json), par identifiant.
static func ships() -> Dictionary:
	return _load("ships")


static func ship(id: String) -> Dictionary:
	return ships().get(id, {})


## Identifiants des classes de vaisseaux, triés (ordre stable pour l'interface et la simulation).
static func ship_ids() -> Array[String]:
	var ids: Array[String] = []
	for k in ships():
		ids.append(String(k))
	ids.sort()
	return ids


static func deposit(id: String) -> Dictionary:
	for d: Dictionary in rules()["deposits"]:
		if d["id"] == id:
			return d
	return {}


static func resource_ids() -> Array[String]:
	var ids: Array[String] = []
	for r: Dictionary in rules()["resources"]:
		ids.append(String(r["id"]))
	return ids


static func resource_label(id: String, short := false) -> String:
	for r: Dictionary in rules()["resources"]:
		if r["id"] == id:
			return r["short"] if short else r["label"]
	return id


## Coût ou rendement lisible : {"materials": 80, "energy": 30} -> "80 Mat, 30 Én".
static func format_amounts(amounts: Dictionary, signed := false) -> String:
	var parts := PackedStringArray()
	for r in resource_ids():
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
