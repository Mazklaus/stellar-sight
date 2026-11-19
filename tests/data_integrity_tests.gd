extends RefCounted
## Les données du jeu (data/*.json, gardées en mémoire par GameData) ne doivent jamais changer pendant
## une partie. Piège déjà rencontré : Array(x) sur un tableau des données (ou sur un tableau typé de
## l'état) renvoie le MÊME tableau, et un pop_back() ou un sort() dessus modifie les données ; la partie
## suivante de la session, ou une partie rechargée, ne joue plus pareil (désynchronisation en réseau).
## Ici : deux ans entre IA avec tous les piliers des réglages par défaut, puis chaque fichier de données
## chargé est comparé à sa version sur le disque. Les ajouts sont permis (le jeu complète certaines fiches
## au chargement, ex. caractéristiques calculées des coques, trophées non constructibles) : seule une
## valeur du disque changée ou retirée compte. Appelés par tests/run_all.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Intégrité des données en partie…")
	_test_victory_path_keeps_prereqs()
	_test_data_unchanged()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


## Régression : AiPlayer.victory_path vidait la liste « pre » de la technologie visée (pop_back sur
## Array(t["pre"]), le même tableau que celui des données).
func _test_victory_path_keeps_prereqs() -> void:
	var st := GameState.create(5, 150, 1800.0, "", {"spectator": true, "ai_level": "normal"})
	var e := st.empires[0]
	var before := JSON.stringify(Research.tech("noosphere").get("pre", []))
	var targets: Array[String] = ["noosphere"]
	var path := AiPlayer.victory_path(st, e, targets)
	_ok(not path.is_empty() and JSON.stringify(Research.tech("noosphere").get("pre", [])) == before,
			"le chemin de victoire de l'IA laisse intacts les prérequis de la Noosphère (%s)" % before)


func _test_data_unchanged() -> void:
	var menu := MainMenu.new()
	menu.slots = MainMenu.default_slots()
	var opts := {"ai_level": "normal", "spectator": true}
	opts.merge(menu.empire_setup("", 31), true)
	opts.merge(menu.game_options(), true)
	menu.free()
	var sim := Simulation.new(GameState.create(31, 150, 1800.0, "", opts))
	sim.advance(720)
	var changed: Array[String] = []
	var compared := 0
	for name in GameData._cache.keys():
		var path := "%s/%s.json" % [GameData.DATA_DIR, name]
		if not FileAccess.file_exists(path):
			continue  # index ou fiches calculées, pas un fichier de données
		compared += 1
		var disk: Variant = GameData._to_ints(JSON.parse_string(FileAccess.get_file_as_string(path)))
		var where := _first_change(disk, GameData._cache[name], String(name))
		if where != "":
			changed.append(where)
	_ok(compared >= 20, "assez de fichiers de données comparés (%d)" % compared)
	_ok(changed.is_empty(), "deux ans de partie ne modifient aucune donnée du jeu (modifiées : %s)" % ", ".join(changed))


## Premier endroit où une valeur du disque a changé ou disparu en mémoire ("" si aucun) ; les clés
## ajoutées en mémoire sont ignorées.
func _first_change(disk: Variant, mem: Variant, path: String) -> String:
	if disk is Dictionary:
		if not mem is Dictionary:
			return path
		for k in disk:
			if not (mem as Dictionary).has(k):
				return "%s.%s (retiré)" % [path, k]
			var w := _first_change(disk[k], mem[k], "%s.%s" % [path, k])
			if w != "":
				return w
		return ""
	if disk is Array:
		if not mem is Array or (mem as Array).size() != (disk as Array).size():
			return path
		for i in (disk as Array).size():
			var w := _first_change(disk[i], mem[i], "%s[%d]" % [path, i])
			if w != "":
				return w
		return ""
	if (disk is int or disk is float) and (mem is int or mem is float):
		return "" if is_equal_approx(float(disk), float(mem)) else path
	return "" if typeof(disk) == typeof(mem) and disk == mem else path
