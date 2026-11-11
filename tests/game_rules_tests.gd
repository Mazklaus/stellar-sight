extends RefCounted
## Tests des règles de Nouvelle partie (lot 3) : victoires à cocher, alliés qui gagnent ensemble ou
## non, difficulté progressive, départ avancé et distance par rival, sauvegarde.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Règles de la partie…")
	_test_victories()
	_test_scaling()
	_test_distances()
	_test_advanced_start()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _state(options := {}, seed_value := 4242) -> GameState:
	var o := {"ai_level": ""}
	o.merge(options, true)
	return GameState.create(seed_value, 150, 1800.0, "vael", o)


func _home(st: GameState, e: Empire) -> Vector2:
	return st.galaxy.systems[st.galaxy.get_planet(e.home_planet).system_id].position


func _test_victories() -> void:
	var st := _state()
	_ok(Victory.enabled(st, "conquete") and Victory.enabled(st, "domination") and Victory.allies_count(st), "par défaut : conquête, domination, alliés ensemble")
	var off := _state({"victories": {"conquete": false, "allies": false}})
	_ok(not Victory.enabled(off, "conquete") and Victory.enabled(off, "domination") and not Victory.ids_for(off, 0).has("conquete"), "conquête décochée : hors jeu")
	Diplomacy.sign_treaty(st, 0, 1, Diplomacy.PEACE)
	Diplomacy.sign_treaty(st, 0, 1, Diplomacy.ALLIANCE)
	Diplomacy.sign_treaty(off, 0, 1, Diplomacy.PEACE)
	Diplomacy.sign_treaty(off, 0, 1, Diplomacy.ALLIANCE)
	_ok(Diplomacy.allied(off, 0, 1) and Victory.bloc(st, 0).size() == 2 and Victory.bloc(off, 0) == [0], "alliés : ensemble par défaut, chacun pour soi si décoché")
	_ok(Victory.domination_needed(off, 0) < Victory.domination_needed(st, 0), "chacun pour soi : pas de systèmes en plus à tenir pour l'allié")


func _test_scaling() -> void:
	var lv := {"ai_level": "legende", "ai_levels": ["", "legende", "legende", "legende"]}
	var fixed := _state(lv)
	var o := lv.duplicate()
	o["ai_scaling"] = true
	var ramp := _state(o)
	var e1 := fixed.get_empire(1)
	var r1 := ramp.get_empire(1)
	_ok(AiLevels.production_pct(fixed, 1) == 130 and AiLevels.production_pct(ramp, 1) == 100, "progressive : pas de bonus au départ (%d %%)" % AiLevels.production_pct(ramp, 1))
	_ok(int(r1.resources["materials"]) < int(e1.resources["materials"]), "progressive : pas d'avance de départ")
	ramp.tick = AiLevels.scaling_days() / 2
	var mid := AiLevels.production_pct(ramp, 1)
	ramp.tick = AiLevels.scaling_days() * 2
	_ok(mid == 115 and AiLevels.production_pct(ramp, 1) == 130, "progressive : +15 % à mi-chemin, +30 % au bout")


func _test_distances() -> void:
	var base := _state({}, 9)
	var o := {"distances": ["", "", "lointain", "proche"]}
	var st := _state(o, 9)
	var dists: Array[float] = []
	for e in base.empires.slice(1):
		dists.append(_home(base, e).distance_to(_home(base, base.empires[0])))
	dists.sort()
	var me := _home(st, st.empires[0])
	_ok(me == _home(base, base.empires[0]), "distance : votre départ ne change pas")
	_ok(is_equal_approx(_home(st, st.empires[3]).distance_to(me), dists[0]) and is_equal_approx(_home(st, st.empires[2]).distance_to(me), dists[dists.size() - 1]),
			"distance : le « proche » prend le départ le plus proche, le « lointain » le plus éloigné")
	var homes := {}
	for e in st.empires:
		homes[st.galaxy.get_planet(e.home_planet).system_id] = true
	_ok(homes.size() == st.empires.size(), "distance : un départ par empire")
	# Au hasard : tiré avec la graine (même graine, même tirage), parmi les départs existants.
	var r1 := _state({"distances": ["", "hasard", "hasard", "hasard"]}, 9)
	var r2 := _state({"distances": ["", "hasard", "hasard", "hasard"]}, 9)
	var same := true
	var picked := {}
	for i in r1.empires.size():
		same = same and r1.empires[i].home_planet == r2.empires[i].home_planet
		picked[r1.galaxy.get_planet(r1.empires[i].home_planet).system_id] = true
	_ok(same and picked.size() == r1.empires.size(), "distance au hasard : même graine, même tirage, un départ par empire")
	var draws := {}
	for sd in range(30, 42):
		var rs := _state({"distances": ["", "hasard"]}, sd)
		var bs := _state({}, sd)
		var d1 := _home(rs, rs.empires[1]).distance_to(_home(rs, rs.empires[0]))
		var all: Array[float] = []
		for e in bs.empires.slice(1):
			all.append(_home(bs, e).distance_to(_home(bs, bs.empires[0])))
		all.sort()
		draws["proche" if is_equal_approx(d1, all[0]) else ("loin" if is_equal_approx(d1, all[all.size() - 1]) else "milieu")] = true
	_ok(draws.size() >= 2, "distance au hasard : la distance change d'une graine à l'autre (%s)" % [draws.keys()])


func _test_advanced_start() -> void:
	var st := _state({"starts": ["", "avance"]}, 17)
	var base := _state({}, 17)
	var cols := func(s: GameState, id: int) -> int:
		return s.colonies.values().filter(func(c: Colony) -> bool: return c.owner == id).size()
	var fleets := func(s: GameState, id: int) -> int:
		return s.fleets.values().filter(func(f: Fleet) -> bool: return f.owner == id).size()
	_ok(cols.call(st, 1) == cols.call(base, 1) + 2 and cols.call(st, 2) == cols.call(base, 2), "départ avancé : deux colonies de plus (%d)" % cols.call(st, 1))
	_ok(fleets.call(st, 1) > fleets.call(base, 1) and int(st.get_empire(1).resources["materials"]) > int(base.get_empire(1).resources["materials"]), "départ avancé : vaisseaux et réserves en plus")
	_ok(st.get_empire(1).advanced_start and not st.get_empire(2).advanced_start, "départ avancé : marqué sur l'empire")
	var sim := Simulation.new(st)
	sim.advance(60)
	_ok(cols.call(st, 1) >= cols.call(base, 1) + 2, "départ avancé : les colonies tiennent")


func _test_save() -> void:
	var st := _state({"victories": {"domination": false, "allies": false}, "ai_scaling": true, "starts": ["avance"]}, 23)
	var back := GameState.from_dict(st.to_dict())
	_ok(back != null and back.victory_rules == st.victory_rules and back.ai_scaling and back.get_empire(0).advanced_start and back.checksum() == st.checksum(), "sauvegarde : règles de la partie retrouvées")
	var d := _state({}, 24).to_dict()
	(d["victory_rules"] as Dictionary).erase("conquete")
	(d["victory_rules"] as Dictionary).erase("allies")
	d.erase("ai_scaling")
	d["version"] = 13
	var old := GameState.from_dict(d)
	_ok(old != null and Victory.enabled(old, "conquete") and Victory.allies_count(old) and not old.ai_scaling, "ancienne sauvegarde : tout en jeu, bonus fixes")
