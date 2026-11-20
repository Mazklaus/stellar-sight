extends SceneTree
## Range une sauvegarde (SRC, écrite par tools/profile_game.gd avec SAVE_AT) compressée pour le banc de
## fin de partie (tests/endgame_perf_tests.gd). DST : autre fichier de tests/data (défaut fin_de_partie.json.gz ;
## fin_de_partie_an40.json.gz pour la partie longue, sauvegarde écrite par tools/long_game.gd).

func _initialize() -> void:
	var text := FileAccess.get_file_as_string(OS.get_environment("SRC"))
	var dst := OS.get_environment("DST")
	if dst == "":
		dst = "fin_de_partie.json.gz"
	var f := FileAccess.open_compressed("res://tests/data/" + dst, FileAccess.WRITE, FileAccess.COMPRESSION_GZIP)
	f.store_string(text)
	f.close()
	print("rangée : %d Ko de texte" % (text.length() / 1024))
	quit()
