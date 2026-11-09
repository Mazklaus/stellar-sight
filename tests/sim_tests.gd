extends RefCounted
## Tests du noyau de simulation (déterminisme, ordres, sauvegarde), appelés par smoke_test.gd.

const TEST_SAVE := "user://saves/test_save.json"

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Noyau de simulation…")
	_test_determinism()
	_test_seeds_differ()
	_test_commands()
	_test_pause_commands()
	_test_replay()
	_test_save_load_roundtrip()
	_test_save_load_continue()
	_test_corrupted_saves()
	_test_chronicle()
	_test_performance()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


## Une partie scénarisée : mêmes ordres aux mêmes ticks.
func _scripted_run(seed_value: int, ticks: int) -> Simulation:
	var sim := Simulation.new(GameState.create(seed_value))
	for t in ticks:
		if t % 97 == 3:
			sim.submit(SimCommands.rename_system(0, (t * 7) % 150, "Colonie %d" % t))
		sim.step()
	return sim


func _test_determinism() -> void:
	var a := _scripted_run(42, 1000)
	var b := _scripted_run(42, 1000)
	_ok(a.state.tick == 1000, "1000 ticks avancés (obtenu %d)" % a.state.tick)
	_ok(a.state.checksum() == b.state.checksum(), "même graine + mêmes ordres = même empreinte")
	_ok(a.state.rng.state == b.state.rng.state, "même état du générateur aléatoire")
	# L'aléatoire global ne doit pas influencer la simulation.
	randomize()
	var _noise := randi()
	var c := _scripted_run(42, 1000)
	_ok(c.state.checksum() == a.state.checksum(), "l'aléatoire global n'influence pas la simulation")


func _test_seeds_differ() -> void:
	var a := Simulation.new(GameState.create(1))
	var b := Simulation.new(GameState.create(2))
	_ok(a.state.checksum() != b.state.checksum(), "graines différentes = empreintes différentes")
	a.advance(10)
	var before := a.state.checksum()
	a.advance(1)
	_ok(a.state.checksum() != before, "l'empreinte change à chaque tick")


func _test_commands() -> void:
	var sim := Simulation.new(GameState.create(7))
	var rejected := []
	sim.command_rejected.connect(func(_c: Dictionary, reason: String) -> void: rejected.append(reason))
	_ok(not sim.submit(SimCommands.rename_system(0, 9999, "Nulle-Part")), "ordre refusé : système inconnu")
	_ok(not sim.submit(SimCommands.rename_system(0, 3, "   ")), "ordre refusé : nom vide")
	_ok(not sim.submit(SimCommands.rename_system(0, 3, "x".repeat(SimCommands.NAME_MAX_LENGTH + 1))), "ordre refusé : nom trop long")
	_ok(not sim.submit({"type": "detruire_galaxie", "player": 0}), "ordre refusé : type inconnu")
	_ok(not sim.submit({"system": 1}), "ordre refusé : incomplet")
	_ok(rejected.size() == 5, "chaque refus est signalé (obtenu %d)" % rejected.size())

	var old_name := sim.state.galaxy.systems[3].system_name
	_ok(sim.submit(SimCommands.rename_system(0, 3, "  Nouvelle-Aube ")), "ordre valide accepté")
	_ok(sim.state.galaxy.systems[3].system_name == old_name, "l'ordre n'est pas appliqué avant la frontière de tick")
	sim.step()
	_ok(sim.state.galaxy.systems[3].system_name == "Nouvelle-Aube", "ordre appliqué au tick suivant, nom nettoyé")
	_ok(sim.command_log.size() == 1 and int(sim.command_log[0]["tick"]) == 0, "ordre journalisé avec son tick")
	_ok(sim.state.chronicle.back()["text"].contains("Nouvelle-Aube"), "le chroniqueur note le renommage")


func _test_pause_commands() -> void:
	var sim := Simulation.new(GameState.create(8))
	sim.advance(5)
	sim.submit(SimCommands.rename_system(0, 0, "Pause-Café"))
	sim.flush_commands()
	_ok(sim.state.galaxy.systems[0].system_name == "Pause-Café", "ordre appliqué pendant la pause")
	_ok(sim.state.tick == 5, "appliquer un ordre ne fait pas passer le temps")
	_ok(not sim.has_pending_commands(), "plus d'ordre en attente")


func _test_replay() -> void:
	var original := _scripted_run(1337, 600)
	var replayed := Simulation.replay(GameState.create(1337), original.command_log, 600)
	_ok(replayed.state.tick == 600, "rediffusion jusqu'au tick 600 (obtenu %d)" % replayed.state.tick)
	_ok(replayed.state.checksum() == original.state.checksum(), "rediffusion du journal = même partie")


func _test_save_load_roundtrip() -> void:
	var sim := _scripted_run(987654321, 450)
	var d := sim.state.to_dict()
	var copy := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(copy != null, "from_dict après passage en JSON (%s)" % GameState.last_error)
	if copy:
		_ok(copy.checksum() == sim.state.checksum(), "l'état survit au JSON à l'identique")
		_ok(copy.rng.state == sim.state.rng.state, "l'état 64 bits du générateur survit au JSON")
	_ok(SaveGame.save_state(sim.state, TEST_SAVE) == OK, "sauvegarde écrite (%s)" % SaveGame.last_error)
	var loaded := SaveGame.load_state(TEST_SAVE)
	_ok(loaded != null, "sauvegarde relue (%s)" % SaveGame.last_error)
	if loaded:
		_ok(loaded.checksum() == sim.state.checksum(), "sauvegarde relue à l'identique")
		_ok(loaded.galaxy.systems[3 * 7 % 150].system_name == "Colonie 3", "les systèmes renommés sont conservés")
		_ok(loaded.galaxy.lanes == sim.state.galaxy.lanes, "la galaxie est régénérée à l'identique")
	_ok(not FileAccess.file_exists(TEST_SAVE + ".tmp"), "pas de fichier temporaire laissé")


## Sauvegarder au milieu puis continuer doit donner exactement la même partie
## que de ne jamais s'être arrêté.
func _test_save_load_continue() -> void:
	var a := Simulation.new(GameState.create(2024))
	a.advance(200)
	SaveGame.save_state(a.state, TEST_SAVE)
	var loaded := SaveGame.load_state(TEST_SAVE)
	if loaded == null:
		_ok(false, "reprise : chargement (%s)" % SaveGame.last_error)
		return
	var b := Simulation.new(loaded)
	for t in 300:
		if t == 50:
			a.submit(SimCommands.rename_system(0, 10, "Escale"))
			b.submit(SimCommands.rename_system(0, 10, "Escale"))
		a.step()
		b.step()
	_ok(a.state.checksum() == b.state.checksum(), "sauvegarder puis reprendre = partie identique")


func _test_corrupted_saves() -> void:
	var sim := Simulation.new(GameState.create(5))
	sim.advance(20)
	SaveGame.save_state(sim.state, TEST_SAVE)
	var text := FileAccess.get_file_as_string(TEST_SAVE)
	_write(TEST_SAVE, text.replace("\"tick\": 20", "\"tick\": 21"))
	_ok(SaveGame.load_state(TEST_SAVE) == null and SaveGame.last_error.contains("empreinte"), "sauvegarde modifiée refusée")
	_write(TEST_SAVE, "{pas du json")
	_ok(SaveGame.load_state(TEST_SAVE) == null, "fichier illisible refusé")
	var data: Dictionary = JSON.parse_string(text)
	data["state"]["version"] = 99
	_write(TEST_SAVE, JSON.stringify(data))
	_ok(SaveGame.load_state(TEST_SAVE) == null and SaveGame.last_error.contains("version"), "version inconnue refusée")
	_ok(SaveGame.load_state("user://saves/inexistante.json") == null, "fichier absent : échec propre")
	DirAccess.remove_absolute(TEST_SAVE)


func _test_chronicle() -> void:
	var sim := Simulation.new(GameState.create(99))
	var added := []
	sim.chronicle_added.connect(func(e: Dictionary) -> void: added.append(e))
	sim.advance(2000)
	_ok(added.size() > 10, "le chroniqueur raconte des événements (obtenu %d)" % added.size())
	_ok(sim.state.chronicle.size() <= GameState.CHRONICLE_MAX, "chronique plafonnée")


func _test_performance() -> void:
	var sim := Simulation.new(GameState.create(3))
	var start := Time.get_ticks_usec()
	sim.advance(3600)
	var ms := (Time.get_ticks_usec() - start) / 1000.0
	print("  3600 ticks (10 ans de jeu) en %.1f ms" % ms)
	_ok(ms < 2000.0, "simulation assez rapide")


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()
