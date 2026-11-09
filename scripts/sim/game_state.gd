class_name GameState
extends RefCounted
## Tout l'état d'une partie, et rien d'autre : c'est ce qu'on sauvegarde,
## ce qu'on compare entre machines en multijoueur, et la seule chose que la simulation modifie.
##
## La partie statique de la galaxie (positions, routes, types d'étoiles) n'est pas
## stockée : elle se régénère à l'identique depuis la graine. Seules les données
## qui changent en cours de partie sont sérialisées.

const FORMAT_VERSION := 1
const CHRONICLE_MAX := 50

## Message de la dernière erreur de from_dict(), pour l'affichage.
static var last_error := ""

var seed_value: int = 0
var system_count: int = 150
var galaxy_radius: float = 1800.0
## Jour de jeu courant (un tick = un jour).
var tick: int = 0
## Générateur aléatoire de la simulation. Toute décision aléatoire en cours de partie
## doit passer par lui (jamais randi() ou randf() globaux), sinon le déterminisme casse.
var rng := RandomNumberGenerator.new()
var galaxy: Galaxy
## Chronique galactique : derniers événements, du plus ancien au plus récent.
## Chaque entrée : {"tick": int, "text": String}.
var chronicle: Array[Dictionary] = []


static func create(seed_value_: int, system_count_: int = 150, galaxy_radius_: float = 1800.0) -> GameState:
	var s := GameState.new()
	s.seed_value = seed_value_
	s.system_count = system_count_
	s.galaxy_radius = galaxy_radius_
	s.galaxy = GalaxyGenerator.generate(seed_value_, system_count_, galaxy_radius_)
	# Flux aléatoire distinct de celui de la génération, dérivé de la même graine.
	s.rng.seed = hash([seed_value_, "simulation"])
	return s


func to_dict() -> Dictionary:
	var systems := []
	for sys in galaxy.systems:
		systems.append({"name": sys.system_name})
	return {
		"version": FORMAT_VERSION,
		"seed": seed_value,
		"system_count": system_count,
		"galaxy_radius": galaxy_radius,
		"tick": tick,
		# L'état du générateur tient sur 64 bits : en texte pour survivre au JSON
		# (dont les nombres sont des flottants, précis seulement jusqu'à 2^53).
		"rng_state": str(rng.state),
		"systems": systems,
		"chronicle": chronicle.duplicate(true),
	}


## Reconstruit un état à partir de to_dict(). Renvoie null si les données sont invalides
## (le détail est dans GameState.last_error).
static func from_dict(d: Dictionary) -> GameState:
	last_error = ""
	for key in ["version", "seed", "system_count", "galaxy_radius", "tick", "rng_state", "systems", "chronicle"]:
		if not d.has(key):
			last_error = "champ manquant : %s" % key
			return null
	if int(d["version"]) != FORMAT_VERSION:
		last_error = "version de format %s non prise en charge (attendu %d)" % [d["version"], FORMAT_VERSION]
		return null
	var s := GameState.create(int(d["seed"]), int(d["system_count"]), float(d["galaxy_radius"]))
	var systems: Array = d["systems"]
	if systems.size() != s.galaxy.systems.size():
		last_error = "nombre de systèmes incohérent (%d au lieu de %d)" % [systems.size(), s.galaxy.systems.size()]
		return null
	for i in systems.size():
		var entry: Dictionary = systems[i]
		s.galaxy.systems[i].system_name = String(entry.get("name", s.galaxy.systems[i].system_name))
	s.tick = int(d["tick"])
	s.rng.state = String(d["rng_state"]).to_int()
	for e: Dictionary in d["chronicle"]:
		s.chronicle.append({"tick": int(e["tick"]), "text": String(e["text"])})
	return s


## Empreinte de l'état complet. Deux machines qui ont la même empreinte au même tick
## sont synchronisées ; une différence signale une désynchronisation (ou une sauvegarde abîmée).
func checksum() -> String:
	return JSON.stringify(to_dict(), "", true, true).sha256_text()


func add_chronicle(text: String) -> Dictionary:
	var entry := {"tick": tick, "text": text}
	chronicle.append(entry)
	while chronicle.size() > CHRONICLE_MAX:
		chronicle.pop_front()
	return entry
