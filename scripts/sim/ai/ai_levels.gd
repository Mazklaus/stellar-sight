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
	var pct := int(level(e.ai_level).get("production_pct", 100))
	if state.ai_scaling and pct > 100:
		# Difficulté progressive (Stellaris) : le bonus part de zéro et atteint sa pleine valeur après
		# scaling_days jours de partie.
		var ramp := maxi(1, scaling_days())
		pct = 100 + (pct - 100) * mini(state.tick, ramp) / ramp
	return pct


## Durée de la montée des bonus en difficulté progressive, en jours (data/ai.json).
static func scaling_days() -> int:
	return int(GameData.ai().get("scaling_days", 14400))


# --- Tempérament ---------------------------------------------------------------------------------
## Réglage séparé de la difficulté (comme l'agressivité des IA de Stellaris) : il change le comportement
## envers les autres empires, jamais les ressources. Le tempérament du peuple (bloc "ai"."temperament"
## de data/factions.json) le décale d'un cran, comme les traits de personnalité des IA d'Endless Space 2.
## Aujourd'hui il oriente l'expansion (frontières, systèmes disputés) ; le combat et la diplomatie
## liront la même valeur (aggression) pour décider des guerres et des traités.

static func temperament_ids() -> Array[String]:
	var out: Array[String] = []
	for t: Dictionary in GameData.ai()["temperaments"]:
		out.append(String(t["id"]))
	return out


static func default_temperament() -> String:
	return String(GameData.ai().get("default_temperament", "normal"))


static func temperament(id: String) -> Dictionary:
	for t: Dictionary in GameData.ai()["temperaments"]:
		if t["id"] == id:
			return t
	if id != default_temperament():
		return temperament(default_temperament())
	return {}


static func is_valid_temperament(id: String) -> bool:
	return temperament_ids().has(id)


## Agressivité effective d'un empire IA, de -3 (très pacifique) à 3 (très agressif) :
## le réglage de la partie plus le tempérament de son peuple.
static func aggression(e: Empire) -> int:
	var base := int(temperament(e.ai_temperament).get("aggression", 0))
	var people := int(personality(e).get("temperament", {}).get("aggression", 0))
	return clampi(base + people, -3, 3)


## Libellé pour l'interface : « Agressif (Vorace) ».
static func temperament_label(e: Empire) -> String:
	var t := String(temperament(e.ai_temperament).get("label", ""))
	var p := String(personality(e).get("temperament", {}).get("label", ""))
	return "%s (%s)" % [t, p] if p != "" else t


## Personnalité de l'IA propre à la faction (bloc "ai" de data/factions.json).
static func personality(e: Empire) -> Dictionary:
	return e.faction().get("ai", {})
