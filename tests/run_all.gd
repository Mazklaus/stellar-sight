extends "res://tests/smoke_test.gd"
## Lanceur de toute la suite, en un seul processus (le moteur ne compile le jeu qu'une fois) et
## découpable en tranches à lancer en parallèle. D'habitude on passe par tools/run_tests.sh, qui
## lance une tranche par cœur et résume le tout ; à la main :
##   godot --headless --path . -s res://tests/run_all.gd                 (tout, un seul processus)
##   SHARD=2/4 godot --headless --path . -s res://tests/run_all.gd       (2e tranche sur 4)
##   TESTS=ai_tests,minor_tests godot --headless --path . -s res://tests/run_all.gd
##   TESTS=ai_tests:_test_temperament godot …                            (une seule fonction)
##
## Unités : les fichiers tests/*_tests*.gd sont découverts tout seuls (un nouveau fichier est lancé sans
## rien ajouter ici, sauf s'il est appelé par un autre fichier : le déclarer dans CHAINED). Les fichiers
## longs (plus de SPLIT_ABOVE secondes d'après les durées connues) sont coupés en une unité par fonction
## _test_* (« fichier:_test_x ») pour que les tranches s'équilibrent, à condition que leur run() ne fasse
## qu'appeler ces fonctions ; sinon le fichier reste entier. Deux unités spéciales reprennent les parties
## propres à smoke_test.gd : « _generator » (générateur de galaxie) et « _ui » (horloge, rapport
## d'empire, scène principale).
## Les tranches sont équilibrées d'après tests/test_durations.json (secondes mesurées par unité,
## réécrit par tools/run_tests.sh --update-durations) ; une unité inconnue compte pour 5 s.

## Fichiers lancés par un autre fichier de tests (ne pas les lancer deux fois).
const CHAINED := [
	"archeo_tests2", "archeo_tests3",
	"contact_tests2", "contact_tests3",
	"forge_tests2", "forge_tests3",
	"megas_tests2", "megas_tests3",
	"psionics_tests2", "psionics_tests3",
	"transcendence_tests2", "transcendence_tests3",
]
const DURATIONS := "res://tests/test_durations.json"
const UNKNOWN_WEIGHT := 5.0
const SPLIT_ABOVE := 40.0


func _initialize() -> void:
	# Une image d'abord : l'arbre de scène est alors actif, et les panneaux ajoutés par les tests
	# reçoivent leur _ready() (sinon leurs nœuds restent vides et le test s'arrête sur une erreur).
	await process_frame
	var all := _units()
	_check(all.size() > 100, "le lanceur trouve les fichiers de tests (%d unités)" % all.size())
	var units := _select(all)
	var times := {}
	var t_all := Time.get_ticks_usec()
	for u in units:
		var before := _failures
		var t0 := Time.get_ticks_usec()
		print("▶ %s" % u)
		await _run_unit(u)
		times[u] = (Time.get_ticks_usec() - t0) / 1000000.0
		var failed := _failures - before
		print("◀ %s : %.1f s%s" % [u, times[u], "" if failed == 0 else ", %d échec(s)" % failed])
	print("")
	# Ligne lue par tools/run_tests.sh (durées par unité, au format JSON).
	print("DURATIONS_JSON " + JSON.stringify(times))
	var shard := OS.get_environment("SHARD")
	print("Tranche %s : %d unités en %.1f s" % [shard if shard != "" else "1/1", units.size(), (Time.get_ticks_usec() - t_all) / 1000000.0])
	if _failures == 0:
		print("OK : %d vérifications passées." % _checks)
	else:
		printerr("ÉCHEC : %d vérification(s) sur %d." % [_failures, _checks])
		print("ÉCHEC : %d vérification(s) sur %d." % [_failures, _checks])
	quit(1 if _failures > 0 else 0)


func _run_unit(u: String) -> void:
	match u:
		"_generator":
			_test_generator()
			return
		"_ui":
			_test_clock()
			_test_empire_report()
			await _test_main_scene()
			return
	var file := u.get_slice(":", 0)
	var scr := load("res://tests/%s.gd" % file) as GDScript
	if scr == null:
		_check(false, "%s : le fichier ne se charge pas (erreur d'analyse ?)" % file)
		return
	var obj = scr.new()
	if not u.contains(":"):
		obj.run(_check)
		return
	obj._check = _check
	obj.call(u.get_slice(":", 1))


## Toutes les unités : les deux parties de smoke_test puis chaque fichier de tests non chaîné (ou ses
## fonctions, pour les fichiers longs).
func _units() -> Array[String]:
	var weights := _weights()
	var out: Array[String] = ["_generator", "_ui"]
	var names: Array[String] = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.ends_with(".gd") and f.contains("_tests") and not f.begins_with("_"):
			var n := f.get_basename()
			if not CHAINED.has(n):
				names.append(n)
	names.sort()
	for n in names:
		var w := float(weights.get(n, UNKNOWN_WEIGHT))
		var parts: Array[String] = []
		if w > SPLIT_ABOVE:
			parts = _split_calls(n)
		if parts.is_empty():
			out.append(n)
		else:
			for c in parts:
				out.append("%s:%s" % [n, c])
	return out


## Fonctions _test_* appelées par run(), dans l'ordre, si run() ne fait rien d'autre que ces appels
## (et retenir check, afficher un titre) ; sinon [] et le fichier se lance entier.
static func _split_calls(file: String) -> Array[String]:
	var src := FileAccess.get_file_as_string("res://tests/%s.gd" % file)
	var out: Array[String] = []
	var inside := false
	var call_re := RegEx.create_from_string("^\\t(_test_\\w+)\\(\\)$")
	for line in src.split("\n"):
		if line.begins_with("func run("):
			inside = true
			continue
		if not inside:
			continue
		if line.strip_edges() == "" or line.begins_with("\t#"):
			continue
		if not line.begins_with("\t"):
			break
		var m := call_re.search(line)
		if m:
			out.append(m.get_string(1))
		elif line == "\t_check = check" or line.begins_with("\tprint("):
			continue
		else:
			return []
	if not src.contains("\nvar _check: Callable"):
		return []
	return out


## Filtre TESTS (liste d'unités) puis tranche SHARD=k/N (répartition gloutonne par durée connue).
func _select(all: Array[String]) -> Array[String]:
	var only := OS.get_environment("TESTS")
	if only != "":
		var keep: Array[String] = []
		for n in only.split(",", false):
			keep.append(n.strip_edges())
		return keep
	var shard := OS.get_environment("SHARD")
	if shard == "":
		return all
	var parts := shard.split("/")
	var count := maxi(1, int(parts[1]) if parts.size() > 1 else 1)
	var k := clampi(int(parts[0]) - 1, 0, count - 1)
	var weights := _weights()
	var sorted := all.duplicate()
	sorted.sort_custom(func(a: String, b: String) -> bool:
		var wa := float(weights.get(a, UNKNOWN_WEIGHT))
		var wb := float(weights.get(b, UNKNOWN_WEIGHT))
		return wa > wb if wa != wb else a < b)
	var loads: Array[float] = []
	var buckets: Array = []
	for i in count:
		loads.append(0.0)
		buckets.append([])
	for n in sorted:
		var best := 0
		for i in count:
			if loads[i] < loads[best]:
				best = i
		loads[best] += float(weights.get(n, UNKNOWN_WEIGHT))
		buckets[best].append(n)
	var mine: Array[String] = []
	for n in buckets[k]:
		mine.append(n)
	return mine


func _weights() -> Dictionary:
	if not FileAccess.file_exists(DURATIONS):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(DURATIONS))
	return d if d is Dictionary else {}
