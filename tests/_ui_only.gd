extends "res://tests/smoke_test.gd"
## Seulement l'horloge, le rapport d'empire et la scène principale de smoke_test (sans les fichiers de logique,
## qui se lancent avec _only.gd) :
##   godot --headless --path . -s res://tests/_ui_only.gd


func _initialize() -> void:
	_test_clock()
	_test_empire_report()
	await _test_main_scene()
	print("")
	if _failures == 0:
		print("OK : %d vérifications passées." % _checks)
	else:
		printerr("ÉCHEC : %d vérification(s) sur %d." % [_failures, _checks])
	quit(1 if _failures > 0 else 0)
