extends SceneTree
## Compare deux états de partie et affiche les écarts (sauvegardes ou états d'une désynchronisation).
##   A=user://saves/a.json B=user://saves/b.json godot --headless --path . -s res://tools/state_diff.gd
## Un fichier peut être une sauvegarde (on y prend "state") ou un état brut (GameState.to_dict()).
## Variable facultative : MAX (nombre d'écarts affichés, défaut 30).


func _initialize() -> void:
	var a := _load(OS.get_environment("A"))
	var b := _load(OS.get_environment("B"))
	if a.is_empty() or b.is_empty():
		printerr("Donner deux fichiers : A=… B=…")
		quit(2)
		return
	var max_count := int(OS.get_environment("MAX")) if OS.get_environment("MAX") != "" else 30
	var diffs := StateDiff.differences(a, b, max_count)
	if diffs.is_empty():
		print("IDENTIQUES")
	else:
		print("%d écart(s)%s :" % [diffs.size(), " (au moins)" if diffs.size() >= max_count else ""])
		for d in diffs:
			print("  " + d)
	quit(0 if diffs.is_empty() else 1)


func _load(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		printerr("Fichier introuvable : %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		printerr("JSON illisible : %s" % path)
		return {}
	return parsed["state"] if parsed.get("state") is Dictionary else parsed
