class_name GalaxyGenerator
extends RefCounted
## Génère une galaxie spirale procédurale à partir d'une graine.
## Même graine = même galaxie, ce qui servira aussi au multijoueur et aux sauvegardes.

const STAR_TYPES := [
	{"id": "yellow", "label": "Naine jaune", "weight": 30},
	{"id": "red", "label": "Naine rouge", "weight": 34},
	{"id": "white", "label": "Naine blanche", "weight": 12},
	{"id": "blue_giant", "label": "Géante bleue", "weight": 12},
	{"id": "neutron", "label": "Étoile à neutrons", "weight": 7},
	{"id": "black_hole", "label": "Trou noir", "weight": 5},
]

const SYLLABLES := [
	"ka", "vel", "or", "an", "tha", "ri", "zen", "mor", "sa", "ly", "dra", "xi", "nu",
	"bel", "cor", "eth", "ia", "gal", "sol", "ver", "quo", "ra", "shi", "tar", "um", "yl",
	"ost", "phe", "lun", "ae", "kor", "vy", "sel", "dun",
]


static func generate(seed_value: int, count: int = 150, radius: float = 1800.0, arms: int = 3) -> Galaxy:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var galaxy := Galaxy.new()
	galaxy.seed_value = seed_value

	var points := _scatter_points(rng, count, radius, arms)
	var used_names := {}
	for i in points.size():
		var s := StarSystem.new()
		s.id = i
		s.position = points[i]
		s.system_name = _make_name(rng, used_names)
		s.star_type = _pick_star_type(rng)
		s.planet_count = rng.randi_range(0, 7)
		galaxy.systems.append(s)

	_build_lanes(rng, galaxy, points, radius)
	return galaxy


static func star_label(star_type: String) -> String:
	for t in STAR_TYPES:
		if t["id"] == star_type:
			return t["label"]
	return star_type


## Répartit les systèmes sur un bulbe central et des bras spiraux,
## avec une distance minimale pour garder la carte lisible.
static func _scatter_points(rng: RandomNumberGenerator, count: int, radius: float, arms: int) -> PackedVector2Array:
	var points := PackedVector2Array()
	var min_dist := radius * 0.06
	var attempts := 0
	while points.size() < count and attempts < count * 300:
		attempts += 1
		var candidate := Vector2.ZERO
		if rng.randf() < 0.2:
			var core_r := sqrt(rng.randf()) * radius * 0.25
			candidate = Vector2.from_angle(rng.randf() * TAU) * core_r
		else:
			var arm := rng.randi_range(0, arms - 1)
			var t := rng.randf_range(0.12, 1.0)
			var angle := float(arm) * TAU / float(arms) + t * 3.6 + rng.randfn(0.0, 0.28)
			var arm_r := t * radius + rng.randfn(0.0, radius * 0.04)
			candidate = Vector2.from_angle(angle) * arm_r
		if _far_enough(candidate, points, min_dist):
			points.append(candidate)
	return points


static func _far_enough(candidate: Vector2, points: PackedVector2Array, min_dist: float) -> bool:
	var min_sq := min_dist * min_dist
	for p in points:
		if p.distance_squared_to(candidate) < min_sq:
			return false
	return true


## Routes de saut : triangulation de Delaunay, puis arbre couvrant minimal
## (toute la galaxie reste connectée) et quelques routes courtes en plus pour les boucles.
static func _build_lanes(rng: RandomNumberGenerator, galaxy: Galaxy, points: PackedVector2Array, radius: float) -> void:
	var tri := Geometry2D.triangulate_delaunay(points)
	var edges := {}
	for i in range(0, tri.size(), 3):
		_add_edge(edges, points, tri[i], tri[i + 1])
		_add_edge(edges, points, tri[i + 1], tri[i + 2])
		_add_edge(edges, points, tri[i + 2], tri[i])

	var sorted_edges: Array = edges.keys()
	sorted_edges.sort_custom(func(e1: Vector2i, e2: Vector2i) -> bool: return edges[e1] < edges[e2])

	var parent: Array[int] = []
	for i in points.size():
		parent.append(i)

	var extra_max_len := radius * 0.2
	for e: Vector2i in sorted_edges:
		var ra := _find_root(parent, e.x)
		var rb := _find_root(parent, e.y)
		if ra != rb:
			parent[ra] = rb
			_link(galaxy, e)
		elif edges[e] < extra_max_len and rng.randf() < 0.3:
			_link(galaxy, e)


static func _add_edge(edges: Dictionary, points: PackedVector2Array, a: int, b: int) -> void:
	var key := Vector2i(mini(a, b), maxi(a, b))
	if not edges.has(key):
		edges[key] = points[a].distance_to(points[b])


static func _find_root(parent: Array[int], i: int) -> int:
	var node := i
	while parent[node] != node:
		parent[node] = parent[parent[node]]
		node = parent[node]
	return node


static func _link(galaxy: Galaxy, e: Vector2i) -> void:
	galaxy.lanes.append(e)
	galaxy.systems[e.x].neighbors.append(e.y)
	galaxy.systems[e.y].neighbors.append(e.x)


static func _make_name(rng: RandomNumberGenerator, used: Dictionary) -> String:
	for _attempt in 30:
		var n := ""
		for _k in rng.randi_range(2, 3):
			n += SYLLABLES[rng.randi() % SYLLABLES.size()]
		n = n.substr(0, 1).to_upper() + n.substr(1)
		if not used.has(n):
			used[n] = true
			return n
	var fallback := "Système %d" % used.size()
	used[fallback] = true
	return fallback


static func _pick_star_type(rng: RandomNumberGenerator) -> String:
	var total := 0
	for t in STAR_TYPES:
		total += int(t["weight"])
	var roll := rng.randi_range(1, total)
	for t in STAR_TYPES:
		roll -= int(t["weight"])
		if roll <= 0:
			return t["id"]
	return STAR_TYPES[0]["id"]
