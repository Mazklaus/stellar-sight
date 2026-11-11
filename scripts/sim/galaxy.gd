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


## Galaxie complète, pour l'envoyer telle quelle (multijoueur, sauvegardes portables) au lieu de la
## régénérer depuis la graine : la génération passe par des sinus et cosinus dont le dernier chiffre
## peut différer d'un système d'exploitation à l'autre (Windows, Linux), ce qui suffirait à donner une
## autre galaxie. Les positions sont rangées au bit près (flottants 32 bits encodés en base64).
func to_dict() -> Dictionary:
	var coords := PackedFloat32Array()
	var sys_list := []
	for s in systems:
		coords.append(s.position.x)
		coords.append(s.position.y)
		sys_list.append([s.star_type, s.planet_count])
	var lane_list := []
	for l in lanes:
		lane_list.append([l.x, l.y])
	var planet_list := []
	for p in planets:
		planet_list.append([p.system_id, p.index, p.type, p.size, Array(p.deposits)])
	return {
		"seed": seed_value,
		"positions": Marshalls.raw_to_base64(coords.to_byte_array()),
		"systems": sys_list,
		"lanes": lane_list,
		"planets": planet_list,
	}


## Reconstruit une galaxie écrite par to_dict(). Les noms des systèmes viennent de l'état (ils peuvent
## être renommés en cours de partie). Renvoie null si les données sont incohérentes.
static func from_dict(d: Dictionary) -> Galaxy:
	var g := Galaxy.new()
	g.seed_value = int(d.get("seed", 0))
	var coords := Marshalls.base64_to_raw(String(d.get("positions", ""))).to_float32_array()
	var sys_list: Array = d.get("systems", [])
	if coords.size() != sys_list.size() * 2:
		return null
	for i in sys_list.size():
		var row: Array = sys_list[i]
		var s := StarSystem.new()
		s.id = i
		s.position = Vector2(coords[2 * i], coords[2 * i + 1])
		s.star_type = String(row[0])
		s.planet_count = int(row[1])
		g.systems.append(s)
	# Les voisins dans l'ordre des routes, comme à la génération (les trajets en dépendent).
	for l: Array in d.get("lanes", []):
		var a := int(l[0])
		var b := int(l[1])
		if g.get_system(a) == null or g.get_system(b) == null:
			return null
		g.lanes.append(Vector2i(a, b))
		g.systems[a].neighbors.append(b)
		g.systems[b].neighbors.append(a)
	for row: Array in d.get("planets", []):
		var p := Planet.new()
		p.id = g.planets.size()
		p.system_id = int(row[0])
		if g.get_system(p.system_id) == null:
			return null
		p.index = int(row[1])
		p.type = String(row[2])
		p.size = int(row[3])
		for dep in row[4]:
			p.deposits.append(String(dep))
		g.planets.append(p)
		g.systems[p.system_id].planet_ids.append(p.id)
	return g
