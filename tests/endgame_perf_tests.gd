extends RefCounted
## Banc de fin de partie (grande passe d'optimisation, 2026-11-19) : une vraie partie de l'an 12
## (graine 3, 8 IA Normales, tous les piliers, 413 colonies), rangée compressée dans tests/data. Elle doit
## se recharger (peuples nés en cours de partie compris) et ses jours ne doivent pas redevenir lents.
## Seuils du PC ; SS_PERF_SLACK (3 dans le conteneur) les multiplie.
## Régénérer la partie quand le format ou le jeu change trop :
##   YEARS=12 SAVE_AT=12 SAVE_PATH=/tmp/an12.json godot --headless --path . -s res://tools/profile_game.gd
##   SRC=/tmp/an12.json godot --headless --path . -s res://tools/pack_endgame.gd

const SAVE := "res://tests/data/fin_de_partie.json.gz"
const DAYS := 30
## Moyenne par jour et pire jour tolérés sur un PC (ms). À resserrer à chaque lot de la passe.
const MEAN_MS := 300.0
const WORST_MS := 1600.0

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Banc de fin de partie…")
	_test_endgame()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func load_endgame() -> GameState:
	var f := FileAccess.open_compressed(SAVE, FileAccess.READ, FileAccess.COMPRESSION_GZIP)
	if f == null:
		return null
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if not parsed is Dictionary or not parsed.get("state") is Dictionary:
		return null
	var st := GameState.from_dict(parsed["state"])
	if st != null and st.checksum() != String(parsed.get("checksum", "")):
		return null
	return st


func _test_endgame() -> void:
	var st := load_endgame()
	_ok(st != null, "Fin de partie : la sauvegarde de l'an 12 se recharge (%s)" % GameState.last_error)
	if st == null:
		return
	_ok(st.colonies.size() > 300, "Fin de partie : galaxie pleine (%d colonies)" % st.colonies.size())
	var sim := Simulation.new(st)
	var total := 0.0
	var worst := 0.0
	for d in DAYS:
		var a := Time.get_ticks_usec()
		sim.step()
		var ms := (Time.get_ticks_usec() - a) / 1000.0
		total += ms
		worst = maxf(worst, ms)
	var slack := maxf(1.0, OS.get_environment("SS_PERF_SLACK").to_float())
	var mean := total / DAYS
	print("  fin de partie : %.0f ms par jour, pire jour %.0f ms (%d jours)" % [mean, worst, DAYS])
	_ok(mean < MEAN_MS * slack, "Fin de partie : jour moyen assez rapide (%.0f ms, seuil %.0f)" % [mean, MEAN_MS * slack])
	_ok(worst < WORST_MS * slack, "Fin de partie : pire jour tenable (%.0f ms, seuil %.0f)" % [worst, WORST_MS * slack])
