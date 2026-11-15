extends SceneTree
## Lance quelques fichiers de tests seulement (la suite complète est longue dans un conteneur) :
##   TESTS=minor_tests,ancient_tests godot --headless --path . -s res://tests/_only.gd

var _failures := 0
var _checks := 0


func _initialize() -> void:
	for name in OS.get_environment("TESTS").split(",", false):
		var scr: GDScript = load("res://tests/%s.gd" % name.strip_edges())
		scr.new().run(_check)
	print("%d vérifications, %d échecs" % [_checks, _failures])
	quit(1 if _failures > 0 else 0)


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures += 1
		push_error("ÉCHEC : " + what)
		print("ÉCHEC : " + what)
