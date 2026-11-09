class_name Fleet
extends RefCounted
## Une flotte : un groupe de vaisseaux d'un même empire qui se déplace d'un bloc le long des routes de saut.
## Fait partie de l'état de partie : sauvegardée et comparée en multijoueur.
##
## Position : la flotte est au système `system_id`. Si `path` n'est pas vide, elle est en route :
## elle a quitté `system_id` vers `path[0]` et a parcouru `progress` unités de la route (entiers).

var id: int = -1
var owner: int = -1
var fleet_name: String = ""
## Classes des vaisseaux (identifiants de data/ships.json), triées.
var ships: Array[String] = []
var system_id: int = -1
## Systèmes restant à atteindre, dans l'ordre (vide = à l'arrêt).
var path: Array[int] = []
## Distance déjà parcourue sur la route system_id -> path[0].
var progress: int = 0
## Ordre permanent : "" (aucun, la flotte attend les ordres) ou ORDER_EXPLORE (exploration automatique).
var standing_order: String = ""

const ORDER_EXPLORE := "explore"
const STANDING_ORDERS := ["", ORDER_EXPLORE]


func is_moving() -> bool:
	return not path.is_empty()


## Système suivant sur le trajet (-1 à l'arrêt).
func next_system() -> int:
	return path[0] if not path.is_empty() else -1


## Destination finale (le système actuel à l'arrêt).
func destination() -> int:
	return path[-1] if not path.is_empty() else system_id


func is_exploring() -> bool:
	return standing_order == ORDER_EXPLORE


## À l'arrêt et sans ordre permanent : la flotte attend qu'on lui dise quoi faire.
func is_idle() -> bool:
	return not is_moving() and standing_order == ""


func count(ship_id: String) -> int:
	return ships.count(ship_id)


func add_ship(ship_id: String) -> void:
	ships.append(ship_id)
	ships.sort()


func remove_ship(ship_id: String) -> bool:
	var i := ships.find(ship_id)
	if i < 0:
		return false
	ships.remove_at(i)
	return true


func to_dict() -> Dictionary:
	return {
		"id": id,
		"owner": owner,
		"name": fleet_name,
		"ships": Array(ships),
		"system": system_id,
		"path": Array(path),
		"progress": progress,
		"order": standing_order,
	}


static func from_dict(d: Dictionary) -> Fleet:
	var f := Fleet.new()
	f.id = int(d["id"])
	f.owner = int(d["owner"])
	f.fleet_name = String(d["name"])
	for s in d["ships"]:
		f.ships.append(String(s))
	f.ships.sort()
	f.system_id = int(d["system"])
	for s in d["path"]:
		f.path.append(int(s))
	f.progress = int(d["progress"])
	f.standing_order = String(d.get("order", ""))  # absent des sauvegardes d'avant l'exploration auto
	if not STANDING_ORDERS.has(f.standing_order):
		f.standing_order = ""
	return f
