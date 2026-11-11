extends RefCounted
## Tests des fondations du multijoueur : instantané de partie avec la galaxie complète (relu sans rien
## régénérer), sauvegarde portable, comparaison d'états (StateDiff), empreinte de version (GameVersion).
## Appelés par smoke_test.gd.

const TEST_SAVE := "user://saves/test_net.json"

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Fondations du multijoueur…")
	_test_snapshot_roundtrip()
	_test_snapshot_not_regenerated()
	_test_snapshot_invalid()
	_test_save_portable()
	_test_old_format()
	_test_state_diff()
	_test_version()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _game(seed_value := 77, years := 1) -> Simulation:
	var st := GameState.create(seed_value, 150, 1800.0, "", {"spectator": true, "ai_level": "normal",
			"galaxy": {"shape": "amas", "placement": "equilibre", "guaranteed": 1}})
	var sim := Simulation.new(st)
	sim.advance(360 * years)
	return sim


func _galaxy_equal(a: Galaxy, b: Galaxy) -> bool:
	if a.systems.size() != b.systems.size() or a.planets.size() != b.planets.size() or a.lanes != b.lanes:
		return false
	for i in a.systems.size():
		var x := a.systems[i]
		var y := b.systems[i]
		if x.position != y.position or x.star_type != y.star_type or x.neighbors != y.neighbors or x.planet_ids != y.planet_ids:
			return false
	for i in a.planets.size():
		var p := a.planets[i]
		var q := b.planets[i]
		if p.system_id != q.system_id or p.index != q.index or p.type != q.type or p.size != q.size or p.deposits != q.deposits:
			return false
	return true


func _test_snapshot_roundtrip() -> void:
	var sim := _game()
	var snap := sim.state.to_snapshot()
	_ok(snap.has("galaxy") and not sim.state.to_dict().has("galaxy"), "l'instantané contient la galaxie, pas l'empreinte")
	var copy := GameState.from_dict(JSON.parse_string(JSON.stringify(snap)))
	_ok(copy != null, "instantané relu après passage en JSON (%s)" % GameState.last_error)
	if copy == null:
		return
	_ok(copy.checksum() == sim.state.checksum(), "instantané relu = même empreinte")
	_ok(_galaxy_equal(copy.galaxy, sim.state.galaxy), "instantané relu = même galaxie au bit près (positions, routes, voisins, planètes)")
	# La partie continue à l'identique depuis l'instantané, comme chez un client en multijoueur.
	var follow := Simulation.new(copy)
	sim.advance(90)
	follow.advance(90)
	_ok(follow.state.checksum() == sim.state.checksum(), "la partie continue à l'identique depuis l'instantané")


func _test_snapshot_not_regenerated() -> void:
	var st := GameState.create(5, 150, 1800.0, "ossarane", {"ai_level": ""})
	var snap := st.to_snapshot()
	# On déplace une étoile dans l'instantané : si la galaxie était régénérée, le changement serait perdu.
	var g: Dictionary = snap["galaxy"]
	var coords := Marshalls.base64_to_raw(String(g["positions"])).to_float32_array()
	coords[0] += 123.25
	g["positions"] = Marshalls.raw_to_base64(coords.to_byte_array())
	var copy := GameState.from_dict(snap)
	_ok(copy != null and copy.galaxy.systems[0].position.x == coords[0] and coords[0] != st.galaxy.systems[0].position.x,
			"la galaxie de l'instantané est reprise telle quelle, pas régénérée depuis la graine")


func _test_snapshot_invalid() -> void:
	var st := GameState.create(5, 150, 1800.0, "ossarane", {"ai_level": ""})
	var snap := st.to_snapshot()
	(snap["galaxy"] as Dictionary)["lanes"] = [[0, 99999]]
	_ok(GameState.from_dict(snap) == null and GameState.last_error == "galaxie incohérente", "galaxie incohérente refusée")
	var snap2 := st.to_snapshot()
	(snap2["galaxy"]["systems"] as Array).pop_back()
	_ok(GameState.from_dict(snap2) == null, "galaxie tronquée refusée")


func _test_save_portable() -> void:
	var sim := _game(31, 0)
	sim.advance(30)
	_ok(SaveGame.save_state(sim.state, TEST_SAVE) == OK, "sauvegarde écrite")
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TEST_SAVE))
	_ok(raw["state"].has("galaxy"), "la sauvegarde contient la galaxie complète")
	var loaded := SaveGame.load_state(TEST_SAVE)
	_ok(loaded != null and loaded.checksum() == sim.state.checksum(), "sauvegarde portable relue à l'identique (%s)" % SaveGame.last_error)
	DirAccess.remove_absolute(TEST_SAVE)


func _test_old_format() -> void:
	# Une sauvegarde d'avant la version 15 n'a pas de galaxie : on la régénère depuis la graine.
	var st := GameState.create(8, 150, 1800.0, "vael", {"ai_level": ""})
	var d := st.to_dict()
	d["version"] = 14
	var copy := GameState.from_dict(d)
	_ok(copy != null and _galaxy_equal(copy.galaxy, st.galaxy), "ancienne sauvegarde sans galaxie : régénérée depuis la graine")


func _test_state_diff() -> void:
	var sim := _game(12, 0)
	var a := sim.state.to_dict()
	var b: Dictionary = JSON.parse_string(JSON.stringify(a))
	_ok(StateDiff.differences(a, b).is_empty(), "états identiques (entiers relus en flottants par le JSON) : aucun écart")
	var res: Dictionary = b["empires"][1]["resources"]
	res["materials"] = float(res["materials"]) + 1.0
	b["tick"] = int(b["tick"]) + 1
	var diffs := StateDiff.differences(a, b)
	_ok(diffs.size() == 2, "deux écarts trouvés (%s)" % ", ".join(diffs))
	_ok(StateDiff.first_difference(a, b).begins_with("empires[1].resources.materials"), "premier écart = le plus haut dans l'état, avec son chemin")
	b.erase("winner")
	_ok(StateDiff.differences(a, b, 50).any(func(x: String) -> bool: return x.begins_with("winner : ")), "clé absente signalée")
	_ok(StateDiff.differences([1, 2], [1, 2, 3]) == [" : 2 éléments ≠ 3"], "listes de tailles différentes signalées")


func _test_version() -> void:
	var fp := GameVersion.fingerprint()
	_ok(fp.length() == 16 and fp.is_valid_hex_number(), "empreinte de version : 16 caractères hexadécimaux (%s)" % fp)
	_ok(GameVersion.compute(GameVersion.ROOTS).begins_with(fp), "empreinte stable d'un calcul à l'autre")
	_ok(GameVersion.compute(["res://data"]) != GameVersion.compute(["res://scripts/sim"]), "l'empreinte dépend des fichiers")
	_ok(GameVersion.label().contains(fp), "la version lisible montre l'empreinte")
