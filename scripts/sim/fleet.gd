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
## Points de structure de chaque vaisseau, dans le même ordre que ships.
var hp: Array[int] = []
## Marques d'armes et de défenses de chaque vaisseau (aligné sur ships) : indice dans
## Empire.marks_log, l'état des marques de l'empire quand le vaisseau est sorti du chantier ou y a
## été remis à niveau. -1 : toujours à jour (anciennes sauvegardes, vaisseaux de test).
var gen: Array[int] = []
## Jours restants de remise à niveau au chantier (0 : aucune en cours).
var refit_left: int = 0
## Marque du dernier vaisseau retiré par remove_ship_hp (pour le reporter dans une autre flotte).
var last_gen: int = -1
## Troupes embarquées (équipages prêts à débarquer) : au plus Combat.max_troops(flotte).
var troops: int = 0
## Tactique de combat (data/combat.json, « tactics ») : choisie avant la bataille, comme les plans
## de bataille d'Endless Space 2.
var tactic: String = ""
var system_id: int = -1
## Systèmes restant à atteindre, dans l'ordre (vide = à l'arrêt).
var path: Array[int] = []
## Distance déjà parcourue sur la route system_id -> path[0].
var progress: int = 0
## Ordre permanent : "" (aucun, la flotte attend les ordres), ORDER_EXPLORE (exploration automatique)
## ou ORDER_PATROL (aller-retour entre les deux systèmes de `patrol`).
var standing_order: String = ""
## Patrouille : [système de départ, système d'arrivée] (vide sans patrouille).
var patrol: Array[int] = []

const ORDER_EXPLORE := "explore"
const ORDER_PATROL := "patrol"
const STANDING_ORDERS := ["", ORDER_EXPLORE, ORDER_PATROL]


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


func is_patrolling() -> bool:
	return standing_order == ORDER_PATROL and patrol.size() == 2


## À l'arrêt et sans ordre permanent : la flotte attend qu'on lui dise quoi faire.
func is_idle() -> bool:
	return not is_moving() and standing_order == ""


func count(ship_id: String) -> int:
	return ships.count(ship_id)


## Ajoute un vaisseau à sa place dans l'ordre trié ; hp < 0 : intact.
func add_ship(ship_id: String, ship_hp := -1, ship_gen := -1) -> void:
	var i := ships.bsearch(ship_id, false)
	ships.insert(i, ship_id)
	hp.insert(i, ship_hp if ship_hp >= 0 else max_hp_of(ship_id))
	gen.insert(i, ship_gen)


## Retire un vaisseau de cette classe (le plus abîmé : on garde les meilleurs).
func remove_ship(ship_id: String) -> bool:
	return remove_ship_hp(ship_id) >= 0


## Retire un vaisseau de cette classe et renvoie ses points de structure (-1 s'il n'y en a pas).
## Le plus abîmé part en premier, à égalité le premier de la liste.
func remove_ship_hp(ship_id: String) -> int:
	var best := -1
	for i in ships.size():
		if ships[i] == ship_id and (best == -1 or hp[i] < hp[best]):
			best = i
	if best < 0:
		return -1
	var h := hp[best]
	last_gen = gen[best]
	ships.remove_at(best)
	hp.remove_at(best)
	gen.remove_at(best)
	return h


## Retire le vaisseau d'indice i (détruit au combat).
func remove_at(i: int) -> void:
	ships.remove_at(i)
	hp.remove_at(i)
	gen.remove_at(i)


static func max_hp_of(ship_id: String) -> int:
	return maxi(1, int(GameData.ship(ship_id).get("hp", 50)))


## Points de structure actuels et maximum de toute la flotte.
func total_hp() -> int:
	var n := 0
	for h in hp:
		n += h
	return n


func total_max_hp() -> int:
	var n := 0
	for s in ships:
		n += max_hp_of(s)
	return n


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
		"hp": Array(hp),
		"troops": troops,
		"tactic": tactic,
		"gen": Array(gen),
		"refit": refit_left,
		"patrol": Array(patrol),
	}


static func from_dict(d: Dictionary) -> Fleet:
	var f := Fleet.new()
	f.id = int(d["id"])
	f.owner = int(d["owner"])
	f.fleet_name = String(d["name"])
	for s in d["ships"]:
		f.ships.append(String(s))
	f.ships.sort()
	var saved_hp: Array = d.get("hp", [])
	for i in f.ships.size():
		var mx := max_hp_of(f.ships[i])
		f.hp.append(clampi(int(saved_hp[i]), 1, mx) if i < saved_hp.size() else mx)
	var saved_gen: Array = d.get("gen", [])
	for i in f.ships.size():
		f.gen.append(int(saved_gen[i]) if i < saved_gen.size() else -1)
	f.refit_left = maxi(0, int(d.get("refit", 0)))
	f.troops = maxi(0, int(d.get("troops", 0)))
	f.tactic = String(d.get("tactic", ""))
	f.system_id = int(d["system"])
	for s in d["path"]:
		f.path.append(int(s))
	f.progress = int(d["progress"])
	f.standing_order = String(d.get("order", ""))  # absent des sauvegardes d'avant l'exploration auto
	if not STANDING_ORDERS.has(f.standing_order):
		f.standing_order = ""
	for s in d.get("patrol", []):
		f.patrol.append(int(s))
	if f.standing_order == ORDER_PATROL and f.patrol.size() != 2:
		f.standing_order = ""
	return f
