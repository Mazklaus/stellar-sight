extends RefCounted
## Tests de la galaxie paramétrable (GalaxySettings) : réglages par défaut identiques à la galaxie
## d'origine, chaque taille et chaque forme (nombre de systèmes, galaxie reliée), densité des routes,
## placements des départs, mondes habitables garantis, sauvegarde et déterminisme.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Galaxie paramétrable…")
	_test_defaults()
	_test_sizes_and_shapes()
	_test_lanes()
	_test_placements()
	_test_guaranteed()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _state(settings: Dictionary, seed_value := 4242, faction := "ossarane", options := {}) -> GameState:
	var o := {"ai_level": "", "galaxy": settings}
	o.merge(options, true)
	return GameState.create(seed_value, 150, 1800.0, faction, o)


## Tous les systèmes sont-ils reliés par les routes ?
func _connected(g: Galaxy) -> bool:
	var seen := {0: true}
	var stack: Array[int] = [0]
	while not stack.is_empty():
		var sid: int = stack.pop_back()
		for nb in g.systems[sid].neighbors:
			if not seen.has(nb):
				seen[nb] = true
				stack.append(nb)
	return seen.size() == g.systems.size()


func _test_defaults() -> void:
	var n := GalaxySettings.normalize({"size": "nulle", "shape": 3, "guaranteed": 9})
	_ok(n["size"] == "moyenne" and n["shape"] == "spirale_3" and n["guaranteed"] == GalaxySettings.MAX_GUARANTEED, "réglages inconnus : valeurs par défaut, garantis plafonnés")
	# Les réglages par défaut redonnent la galaxie d'origine : mêmes positions, mêmes routes, mêmes départs.
	var old := GameState.create(77, 150, 1800.0, "vael", {"ai_level": ""})
	var new := _state(GalaxySettings.defaults(), 77, "vael")
	var same := old.galaxy.systems.size() == new.galaxy.systems.size() and old.galaxy.lanes == new.galaxy.lanes
	for i in old.galaxy.systems.size():
		same = same and old.galaxy.systems[i].position == new.galaxy.systems[i].position
	for i in old.empires.size():
		same = same and old.empires[i].capital_planet == new.empires[i].capital_planet
	_ok(same and old.checksum() == new.checksum(), "réglages par défaut = galaxie et départs d'origine")


func _test_sizes_and_shapes() -> void:
	for size in GalaxySettings.ids("size"):
		var st := _state({"size": size})
		var want := int(GalaxySettings.entry("size", size)["systems"])
		_ok(st.galaxy.systems.size() == want and st.system_count == want and _connected(st.galaxy), "taille %s : %d systèmes reliés (%d)" % [size, want, st.galaxy.systems.size()])
	for shape in GalaxySettings.ids("shape"):
		var t0 := Time.get_ticks_msec()
		var st := _state({"shape": shape, "size": "grande"}, 9)
		var ms := Time.get_ticks_msec() - t0
		_ok(st.galaxy.systems.size() == 230 and _connected(st.galaxy) and st.empires.size() == 4, "forme %s : 230 systèmes reliés, 4 départs (%d ms)" % [shape, ms])
	# L'anneau laisse le centre vide ; l'elliptique est aplatie.
	var ring := _state({"shape": "anneau"}, 5)
	var inner := ring.galaxy.systems.filter(func(s: StarSystem) -> bool: return s.position.length() < ring.galaxy_radius * 0.4)
	_ok(inner.is_empty(), "anneau : pas d'étoile au centre")
	var ell := _state({"shape": "elliptique"}, 5)
	var max_y := 0.0
	var max_x := 0.0
	for s in ell.galaxy.systems:
		max_y = maxf(max_y, absf(s.position.y))
		max_x = maxf(max_x, absf(s.position.x))
	_ok(max_y < max_x * 0.8, "elliptique : disque aplati (%.0f x %.0f)" % [max_x, max_y])


func _test_lanes() -> void:
	var rare := _state({"lanes": "rares"}, 12).galaxy.lanes.size()
	var normal := _state({"lanes": "normales"}, 12).galaxy.lanes.size()
	var dense := _state({"lanes": "denses"}, 12).galaxy.lanes.size()
	_ok(rare < normal and normal < dense and rare >= 149, "densité des routes : %d < %d < %d (arbre couvrant gardé)" % [rare, normal, dense])


## Écart relatif entre la plus petite et la plus grande distance d'un départ à son plus proche voisin.
func _spread(st: GameState) -> Array[float]:
	var nearest: Array[float] = []
	for e in st.empires:
		var p := st.galaxy.systems[st.galaxy.get_planet(e.capital_planet).system_id].position
		var best := INF
		for o in st.empires:
			if o != e:
				best = minf(best, p.distance_to(st.galaxy.systems[st.galaxy.get_planet(o.capital_planet).system_id].position))
		nearest.append(best)
	return nearest


func _test_placements() -> void:
	var rivals := ["choeur", "vael", "khthari", "ossarane", "choeur", "vael", "khthari"]
	for placement in GalaxySettings.ids("placement"):
		var st := _state({"placement": placement, "size": "grande"}, 31, "ossarane", {"rivals": rivals, "duplicates": true})
		var homes := {}
		for e in st.empires:
			homes[st.galaxy.get_planet(e.capital_planet).system_id] = true
		_ok(st.empires.size() == 8 and homes.size() == 8, "départs %s : 8 empires, 8 systèmes différents" % placement)
	# Équilibré : chacun dans son secteur, à mi-distance du centre, système d'au moins 3 planètes.
	var bal := _state({"placement": "equilibre", "size": "grande"}, 31, "ossarane", {"rivals": rivals, "duplicates": true})
	var ok := true
	for e in bal.empires:
		var s := bal.galaxy.systems[bal.galaxy.get_planet(e.capital_planet).system_id]
		var r := s.position.length() / bal.galaxy_radius
		ok = ok and s.planet_count >= 3 and r > 0.3 and r < 0.92
	var near := _spread(bal)
	_ok(ok and near.min() > bal.galaxy_radius * 0.2, "équilibré : départs à mi-chemin, assez espacés (plus proche voisin %.0f)" % near.min())
	# Même graine, mêmes départs.
	var again := _state({"placement": "chaotique"}, 3)
	var again2 := _state({"placement": "chaotique"}, 3)
	_ok(again.checksum() == again2.checksum(), "départs chaotiques : même graine, même partie")


func _test_guaranteed() -> void:
	for k in [0, 2, 3]:
		var st := _state({"guaranteed": k, "placement": "chaotique"}, 21)
		var ok := true
		for e in st.empires:
			var home_sys := st.galaxy.get_planet(e.capital_planet).system_id
			var preferred: Array = e.faction()["preferred"]
			var near := {}
			var frontier: Array[int] = [home_sys]
			var seen := {home_sys: true}
			for _hop in 2:
				var next: Array[int] = []
				for sid in frontier:
					for nb in st.galaxy.systems[sid].neighbors:
						if not seen.has(nb):
							seen[nb] = true
							next.append(nb)
							near[nb] = true
				frontier = next
			var have := 0
			for sid in near:
				for pid in st.galaxy.systems[sid].planet_ids:
					if preferred.has(st.galaxy.planets[pid].type) and not st.colonies.has(pid):
						have += 1
			ok = ok and have >= k
		_ok(ok, "%d monde(s) garanti(s) de son type près de chaque départ" % k)


func _test_save() -> void:
	var st := _state({"size": "petite", "shape": "amas", "lanes": "denses", "placement": "equilibre", "guaranteed": 2}, 55)
	var back := GameState.from_dict(st.to_dict())
	_ok(back != null and back.galaxy_settings == st.galaxy_settings and back.galaxy.systems.size() == 90 and back.checksum() == st.checksum(), "sauvegarde : réglages et galaxie retrouvés à l'identique")
	# Une sauvegarde sans réglages (version 13 et avant) redonne la galaxie d'origine.
	var d := GameState.create(56, 150, 1800.0, "vael", {"ai_level": ""}).to_dict()
	d.erase("galaxy_settings")
	var old := GameState.from_dict(d)
	_ok(old != null and old.galaxy_settings == GalaxySettings.defaults(), "ancienne sauvegarde : galaxie par défaut")
