class_name AiLevels
extends RefCounted
## Niveaux de difficulté des empires IA (data/ai.json) : fonctions pures.
##
## Comme dans Endless Space 2 et Galactic Civilizations, les niveaux bas jouent moins bien
## (réflexion plus lente, décisions oubliées, mécaniques de faction ignorées) sans être pénalisés,
## les niveaux du milieu jouent leur meilleur jeu sans tricher, et seuls les niveaux hauts
## reçoivent des bonus de production, affichés en clair dans le menu.
##
## faction_use : 0 = ignore les talents du peuple, 1 = les bases, 2 = tout le registre.


static func ids() -> Array[String]:
	var out: Array[String] = []
	for l: Dictionary in GameData.ai()["levels"]:
		out.append(String(l["id"]))
	return out


static func default_id() -> String:
	return String(GameData.ai().get("default_level", "normal"))


## Paramètres d'un niveau ; un identifiant inconnu donne le niveau par défaut.
static func level(id: String) -> Dictionary:
	for l: Dictionary in GameData.ai()["levels"]:
		if l["id"] == id:
			return l
	if id != default_id():
		return level(default_id())
	return {}


static func label(id: String) -> String:
	return String(level(id).get("label", id))


static func is_valid(id: String) -> bool:
	return ids().has(id)


## Bonus de production d'un empire (100 pour un humain ou un niveau sans bonus).
static func production_pct(state: GameState, empire_id: int) -> int:
	var e := state.get_empire(empire_id)
	if e == null or not e.is_ai():
		return 100
	return int(level(e.ai_level).get("production_pct", 100))


## Personnalité de l'IA propre à la faction (bloc "ai" de data/factions.json).
static func personality(e: Empire) -> Dictionary:
	return e.faction().get("ai", {})
