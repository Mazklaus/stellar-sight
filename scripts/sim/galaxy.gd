class_name Galaxy
extends RefCounted
## La galaxie : systèmes et routes de saut. Donnée de simulation pure.

var seed_value: int = 0
var systems: Array[StarSystem] = []
## Chaque route relie deux identifiants de systèmes : Vector2i(a, b) avec a < b.
var lanes: Array[Vector2i] = []
## Toutes les planètes, indexées par leur identifiant.
var planets: Array[Planet] = []


func get_system(id: int) -> StarSystem:
	if id < 0 or id >= systems.size():
		return null
	return systems[id]


func get_planet(id: int) -> Planet:
	if id < 0 or id >= planets.size():
		return null
	return planets[id]


## Renvoie l'identifiant du système le plus proche de world_pos,
## ou -1 si aucun n'est à moins de max_distance.
func find_nearest(world_pos: Vector2, max_distance: float) -> int:
	var best := -1
	var best_d := max_distance * max_distance
	for s in systems:
		var d := s.position.distance_squared_to(world_pos)
		if d <= best_d:
			best_d = d
			best = s.id
	return best
