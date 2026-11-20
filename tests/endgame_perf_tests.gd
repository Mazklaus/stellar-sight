extends RefCounted
## Banc de fin de partie (grande passe d'optimisation, 2026-11-19) : une vraie partie de l'an 12
## (graine 3, 8 IA Normales, tous les piliers, 413 colonies), rangée compressée dans tests/data. Elle doit
## se recharger (peuples nés en cours de partie compris) et ses jours ne doivent pas redevenir lents.
## Seuils du PC ; SS_PERF_SLACK (3 dans le conteneur) les multiplie.
## Régénérer la partie quand le format ou le jeu change trop :
##   YEARS=12 SAVE_AT=12 SAVE_PATH=/tmp/an12.json godot --headless --path . -s res://tools/profile_game.gd
##   SRC=/tmp/an12.json godot --headless --path . -s res://tools/pack_endgame.gd

const SAVE := "res://tests/data/fin_de_partie.json.gz"
## Partie longue (fil « Accélérer les parties longues », 2026-11-20) : graine 7 à l'an 40, 10 jours.
## Régénérer : SRC=<long_game_s7_y40.json> DST=fin_de_partie_an40.json.gz godot --headless --path . -s res://tools/pack_endgame.gd
const SAVE_40 := "res://tests/data/fin_de_partie_an40.json.gz"
const DAYS_40 := 10
const MEAN_40_MS := 600.0
const WORST_40_MS := 5000.0
const DAYS := 30
## Moyenne par jour et pire jour tolérés sur un PC (ms). Mesuré après la grande passe (2026-11-19) :
## environ 290 et 1 900 ms dans le conteneur, soit 145 et 950 sur un PC.
const MEAN_MS := 200.0
const WORST_MS := 1200.0

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Banc de fin de partie…")
	_test_endgame()
	_test_endgame_40()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func load_endgame(path := SAVE) -> GameState:
	var f := FileAccess.open_compressed(path, FileAccess.READ, FileAccess.COMPRESSION_GZIP)
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


## An 40 : la sauvegarde se recharge (bug de la file de recherche, 2026-11-20) et aucun jour ne s'emballe.
func _test_endgame_40() -> void:
	var st := load_endgame(SAVE_40)
	_ok(st != null, "Partie longue : la sauvegarde de l'an 40 se recharge (%s)" % GameState.last_error)
	if st == null:
		return
	var sim := Simulation.new(st)
	var total := 0.0
	var worst := 0.0
	for d in DAYS_40:
		var a := Time.get_ticks_usec()
		sim.step()
		var ms := (Time.get_ticks_usec() - a) / 1000.0
		total += ms
		worst = maxf(worst, ms)
	var slack := maxf(1.0, OS.get_environment("SS_PERF_SLACK").to_float())
	var mean := total / DAYS_40
	print("  an 40 : %.0f ms par jour, pire jour %.0f ms (%d jours)" % [mean, worst, DAYS_40])
	_ok(mean < MEAN_40_MS * slack, "Partie longue, an 40 : jour moyen assez rapide (%.0f ms, seuil %.0f)" % [mean, MEAN_40_MS * slack])
	_ok(worst < WORST_40_MS * slack, "Partie longue, an 40 : pire jour tenable (%.0f ms, seuil %.0f)" % [worst, WORST_40_MS * slack])
