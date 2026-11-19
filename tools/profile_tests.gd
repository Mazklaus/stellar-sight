extends SceneTree
## Durée de chaque fonction _test_* d'un ou plusieurs fichiers de tests (pour trouver les tests lents) :
##   TESTS=ai_tests,economy_tests godot --headless --path . -s res://tools/profile_tests.gd
## Lit le corps de run() pour appeler les fonctions dans le même ordre, une à une, chronométrées.
## Les fichiers en lots (ex. psionics_tests2 appelé par psionics_tests) se profilent séparément.

var _failures := 0


func _initialize() -> void:
	for name in OS.get_environment("TESTS").split(",", false):
		name = name.strip_edges()
		var path := "res://tests/%s.gd" % name
		var scr := load(path) as GDScript
		var calls := _run_calls(FileAccess.get_file_as_string(path))
		var obj = scr.new()
		if "_check" in obj:
			obj._check = _check
		var rows: Array = []
		var t_file := Time.get_ticks_usec()
		for c in calls:
			var t0 := Time.get_ticks_usec()
			if obj.has_method(c):
				obj.call(c)
			elif scr.has_method(c):
				scr.call(c)
			rows.append([c, (Time.get_ticks_usec() - t0) / 1000.0])
		rows.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
		print("%s : %.1f s" % [name, (Time.get_ticks_usec() - t_file) / 1000000.0])
		for r in rows:
			print("  %-40s %8.0f ms" % r)
	print("%d échecs" % _failures)
	quit()


## Noms des fonctions appelées dans run(), dans l'ordre.
func _run_calls(src: String) -> Array[String]:
	var out: Array[String] = []
	var inside := false
	var re := RegEx.create_from_string("^\\t(_test_\\w+)\\(\\)")
	for line in src.split("\n"):
		if line.begins_with("func run(") or line.begins_with("static func run("):
			inside = true
			continue
		if inside:
			if line != "" and not line.begins_with("\t"):
				break
			var m := re.search(line)
			if m:
				out.append(m.get_string(1))
	return out


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failures += 1
		print("ÉCHEC : " + what)
