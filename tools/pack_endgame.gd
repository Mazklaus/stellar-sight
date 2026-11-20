extends SceneTree
## Range une sauvegarde (SRC, écrite par tools/profile_game.gd avec SAVE_AT) compressée pour le banc de
## fin de partie (tests/endgame_perf_tests.gd).

func _initialize() -> void:
	var text := FileAccess.get_file_as_string(OS.get_environment("SRC"))
	var f := FileAccess.open_compressed("res://tests/data/fin_de_partie.json.gz", FileAccess.WRITE, FileAccess.COMPRESSION_GZIP)
	f.store_string(text)
	f.close()
	print("rangée : %d Ko de texte" % (text.length() / 1024))
	quit()
