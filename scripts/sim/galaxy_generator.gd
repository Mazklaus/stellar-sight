class_name GalaxyGenerator
extends RefCounted
## Génère une galaxie procédurale à partir d'une graine et d'une forme (voir GalaxySettings) :
## spirale à N bras, elliptique, anneau ou amas, routes plus ou moins denses.
## Même graine et même forme = même galaxie (multijoueur, sauvegardes).

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


## shape : {"form": "spiral" | "elliptical" | "ring" | "clusters", "arms", "lane_chance", "lane_len"} ;
## vide = spirale à 3 bras, routes normales (la galaxie d'origine).
static func generate(seed_value: int, count: int = 150, radius: float = 1800.0, shape := {}) -> Galaxy:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var galaxy := Galaxy.new()
	galaxy.seed_value = seed_value

	var points := _scatter_points(rng, count, radius, shape)
	var used_names := {}
	for i in points.size():
		var s := StarSystem.new()
		s.id = i
		s.position = points[i]
		s.system_name = _make_name(rng, used_names)
		s.star_type = _pick_star_type(rng)
		s.planet_count = rng.randi_range(0, 7)
		galaxy.systems.append(s)

	_build_lanes(rng, galaxy, points, radius, float(shape.get("lane_chance", 0.3)), float(shape.get("lane_len", 0.2)))
	_make_planets(galaxy)
	return galaxy


static func star_label(star_type: String) -> String:
	for t in STAR_TYPES:
		if t["id"] == star_type:
			return t["label"]
	return star_type


## Répartit les systèmes selon la forme, avec une distance minimale pour garder la carte lisible.
## La spirale : un bulbe central et des bras. Le flux aléatoire de la spirale à 3 bras est celui
## d'origine, pour que les anciennes graines redonnent les mêmes galaxies.
static func _scatter_points(rng: RandomNumberGenerator, count: int, radius: float, shape: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	# Distance minimale à densité constante : celle d'une galaxie de 150 systèmes ramenée à ce rayon
	# (une grande galaxie a un rayon plus grand, pas des étoiles plus écartées).
	var min_dist := radius * 0.06 / sqrt(maxf(1.0, float(count)) / 150.0)
	var form := String(shape.get("form", "spiral"))
	var arms := int(shape.get("arms", 3))
	var centers := _cluster_centers(rng, count, radius) if form == "clusters" else PackedVector2Array()
	var attempts := 0
	while points.size() < count and attempts < count * 300:
		attempts += 1
		var candidate := Vector2.ZERO
		if form == "elliptical":
			# Disque aplati, plus dense au centre.
			var r := sqrt(rng.randf()) * radius
			candidate = Vector2.from_angle(rng.randf() * TAU) * r * Vector2(1.0, 0.62)
		elif form == "ring":
			var rr := rng.randf_range(0.58, 1.0) * radius
			candidate = Vector2.from_angle(rng.randf() * TAU) * rr
		elif form == "clusters":
			var c := centers[rng.randi_range(0, centers.size() - 1)]
			candidate = c + Vector2(rng.randfn(0.0, radius * 0.11), rng.randfn(0.0, radius * 0.11))
		elif rng.randf() < 0.2:
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


## Centres des amas : assez écartés les uns des autres pour laisser des vides entre eux.
static func _cluster_centers(rng: RandomNumberGenerator, count: int, radius: float) -> PackedVector2Array:
	var n := clampi(int(round(float(count) / 22.0)), 4, 18)
	var centers := PackedVector2Array()
	var gap := radius * 0.42
	var tries := 0
	while centers.size() < n and tries < 4000:
		tries += 1
		var c := Vector2.from_angle(rng.randf() * TAU) * sqrt(rng.randf()) * radius * 0.82
		if _far_enough(c, centers, gap):
			centers.append(c)
		elif tries % 500 == 0:
			gap *= 0.9
	return centers


static func _far_enough(candidate: Vector2, points: PackedVector2Array, min_dist: float) -> bool:
	var min_sq := min_dist * min_dist
	for p in points:
		if p.distance_squared_to(candidate) < min_sq:
			return false
	return true


## Routes de saut : triangulation de Delaunay, puis arbre couvrant minimal
## (toute la galaxie reste connectée) et quelques routes courtes en plus pour les boucles.
static func _build_lanes(rng: RandomNumberGenerator, galaxy: Galaxy, points: PackedVector2Array, radius: float,
		lane_chance := 0.3, lane_len := 0.2) -> void:
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

	var extra_max_len := radius * lane_len
	for e: Vector2i in sorted_edges:
		var ra := _find_root(parent, e.x)
		var rb := _find_root(parent, e.y)
		if ra != rb:
			parent[ra] = rb
			_link(galaxy, e)
		elif edges[e] < extra_max_len and rng.randf() < lane_chance:
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


## Planètes de chaque système. Chaque système a son propre flux aléatoire dérivé de la graine :
## le générateur principal n'est pas touché, donc positions, noms et routes ne changent pas.
static func _make_planets(galaxy: Galaxy) -> void:
	var types := GameData.planet_types()
	var deposits: Array = GameData.rules()["deposits"]
	for s in galaxy.systems:
		var prng := RandomNumberGenerator.new()
		prng.seed = hash([galaxy.seed_value, "planets", s.id])
		for k in s.planet_count:
			var p := Planet.new()
			p.id = galaxy.planets.size()
			p.system_id = s.id
			p.index = k
			p.type = _pick_planet_type(prng, types, s.star_type)
			var sizes: Array = types[p.type]["sizes"]
			p.size = prng.randi_range(int(sizes[0]), int(sizes[1]))
			for d: Dictionary in deposits:
				var chance := int(d["chance"]) * int(d.get("star_bonus", {}).get(s.star_type, 1))
				var roll := prng.randi_range(1, 100)
				if d.get("habitable_only", false) and not p.is_habitable_type():
					continue
				if roll <= chance:
					p.deposits.append(String(d["id"]))
			galaxy.planets.append(p)
			s.planet_ids.append(p.id)


static func _pick_planet_type(rng: RandomNumberGenerator, types: Dictionary, star_type: String) -> String:
	var total := 0
	for t in types:
		total += int(types[t]["weights"].get(star_type, 0))
	if total <= 0:
		return "barren"
	var roll := rng.randi_range(1, total)
	for t in types:
		roll -= int(types[t]["weights"].get(star_type, 0))
		if roll <= 0:
			return t
	return "barren"


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
