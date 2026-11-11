class_name GalaxySettings
extends RefCounted
## Réglages de génération de la galaxie choisis dans Nouvelle partie : taille, forme, densité des
## routes, placement des départs, mondes habitables garantis. Un dictionnaire de réglages
## {"size", "shape", "lanes", "placement", "guaranteed"} est sauvegardé avec la partie : la galaxie
## se régénère à l'identique depuis la graine et ces réglages.
## Les valeurs par défaut redonnent exactement la galaxie d'avant ces réglages (150 systèmes, spirale
## à 3 bras, départs le plus loin possible les uns des autres, aucun monde garanti), donc les bancs
## d'équilibrage gardent leurs repères.

## Tailles : nombre de systèmes et nombre d'empires conseillé (joueur compris).
const SIZES := [
	{"id": "petite", "label": "Petite", "systems": 90, "empires": 4},
	{"id": "moyenne", "label": "Moyenne", "systems": 150, "empires": 6},
	{"id": "grande", "label": "Grande", "systems": 230, "empires": 8},
	{"id": "immense", "label": "Immense", "systems": 320, "empires": 10},
	{"id": "colossale", "label": "Colossale", "systems": 420, "empires": 12},
]
## Formes : "form" choisit la façon de semer les étoiles, "arms" le nombre de bras d'une spirale.
const SHAPES := [
	{"id": "spirale_2", "label": "Spirale à 2 bras", "form": "spiral", "arms": 2},
	{"id": "spirale_3", "label": "Spirale à 3 bras", "form": "spiral", "arms": 3},
	{"id": "spirale_4", "label": "Spirale à 4 bras", "form": "spiral", "arms": 4},
	{"id": "spirale_6", "label": "Spirale à 6 bras", "form": "spiral", "arms": 6},
	{"id": "elliptique", "label": "Elliptique", "form": "elliptical",
		"desc": "Un grand disque aplati, sans bras : beaucoup de voisins, peu de goulets."},
	{"id": "anneau", "label": "Anneau", "form": "ring",
		"desc": "Les étoiles en couronne autour d'un vide : deux chemins pour aller chez l'autre."},
	{"id": "amas", "label": "Amas", "form": "clusters",
		"desc": "Des amas d'étoiles reliés par de rares routes : des goulets à tenir."},
]
## Densité des routes : part des routes courtes ajoutées à l'arbre couvrant, et leur longueur maximale
## (en part du rayon). L'arbre garde toujours toute la galaxie reliée.
const LANES := [
	{"id": "rares", "label": "Rares", "chance": 0.1, "max_len": 0.15,
		"desc": "Peu de boucles : des chemins obligés et des goulets."},
	{"id": "normales", "label": "Normales", "chance": 0.3, "max_len": 0.2, "desc": "Quelques boucles."},
	{"id": "denses", "label": "Denses", "chance": 0.65, "max_len": 0.26,
		"desc": "Beaucoup de boucles : on contourne facilement, les frontières sont poreuses."},
]
## Placement des départs.
const PLACEMENTS := [
	{"id": "standard", "label": "Standard",
		"desc": "Chaque empire part le plus loin possible des autres."},
	{"id": "equilibre", "label": "Équilibré",
		"desc": "La galaxie est partagée en secteurs, un par empire : chacun part à mi-chemin du centre et du bord, dans un système d'au moins trois planètes, avec autant de place que ses voisins."},
	{"id": "chaotique", "label": "Chaotique",
		"desc": "Départs tirés au hasard : voisins collés ou isolement, c'est la loterie."},
]
## Mondes habitables garantis à deux sauts au plus du départ (de 0 à 3).
const MAX_GUARANTEED := 3
## Rayon d'une galaxie moyenne ; il grandit avec la racine du nombre de systèmes (densité constante).
const BASE_RADIUS := 1800.0


static func defaults() -> Dictionary:
	return {"size": "moyenne", "shape": "spirale_3", "lanes": "normales", "placement": "standard", "guaranteed": 0}


## Réglages complétés et vérifiés : une valeur inconnue ou absente reprend celle par défaut.
static func normalize(settings: Variant) -> Dictionary:
	var out := defaults()
	if not settings is Dictionary:
		return out
	for key in ["size", "shape", "lanes", "placement"]:
		var v := str(settings.get(key, out[key]))
		if not _find(_table(key), v).is_empty():
			out[key] = v
	out["guaranteed"] = clampi(int(settings.get("guaranteed", 0)), 0, MAX_GUARANTEED)
	return out


static func _table(key: String) -> Array:
	match key:
		"size":
			return SIZES
		"shape":
			return SHAPES
		"lanes":
			return LANES
		"placement":
			return PLACEMENTS
	return []


static func _find(table: Array, id: String) -> Dictionary:
	for e: Dictionary in table:
		if e["id"] == id:
			return e
	return {}


static func entry(key: String, id: String) -> Dictionary:
	return _find(_table(key), id)


static func ids(key: String) -> Array[String]:
	var out: Array[String] = []
	for e: Dictionary in _table(key):
		out.append(String(e["id"]))
	return out


static func system_count(settings: Dictionary) -> int:
	return int(entry("size", String(normalize(settings)["size"]))["systems"])


static func radius(settings: Dictionary) -> float:
	return BASE_RADIUS * sqrt(float(system_count(settings)) / 150.0)


static func recommended_empires(settings: Dictionary) -> int:
	return int(entry("size", String(normalize(settings)["size"]))["empires"])


## Ce qu'il faut au générateur : forme, bras, densité des routes.
static func generator_shape(settings: Dictionary) -> Dictionary:
	var n := normalize(settings)
	var sh := entry("shape", String(n["shape"]))
	var ln := entry("lanes", String(n["lanes"]))
	return {"form": sh["form"], "arms": int(sh.get("arms", 3)), "lane_chance": float(ln["chance"]),
			"lane_len": float(ln["max_len"])}


## « 150 systèmes, spirale à 3 bras » : la légende du bloc Galaxie.
static func summary(settings: Dictionary) -> String:
	var n := normalize(settings)
	return "%d systèmes, %s" % [system_count(n), String(entry("shape", String(n["shape"]))["label"]).to_lower()]
