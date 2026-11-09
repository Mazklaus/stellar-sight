class_name Planet
extends RefCounted
## Une planète. Générée depuis la graine (non sauvegardée), sauf les modifications
## enregistrées dans GameState.planet_overrides (monde d'origine, et plus tard terraformation).

const ROMAN := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]

var id: int = -1
var system_id: int = -1
## Rang dans le système (0 = la plus proche de l'étoile).
var index: int = 0
var type: String = "barren"
## Taille de 1 à 5 : fixe la population maximale et le nombre d'emplacements de bâtiments.
var size: int = 1
var deposits: Array[String] = []


## Le nom suit celui du système : renommer le système renomme ses planètes.
func display_name(galaxy: Galaxy) -> String:
	return "%s %s" % [galaxy.systems[system_id].system_name, ROMAN[index] if index < ROMAN.size() else str(index + 1)]


func type_label() -> String:
	return String(GameData.planet_type(type).get("label", type))


func is_habitable_type() -> bool:
	return not GameData.planet_type(type).get("pop_yields", {}).is_empty()
