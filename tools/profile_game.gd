extends SceneTree
## Référence de performance : une partie type entre IA (réglages par défaut de Nouvelle partie, tous les
## piliers actifs, mode spectateur), chronométrée système par système, année par année.
##   godot --headless --path . -s res://tools/profile_game.gd
## Réglages (variables d'environnement) : SEED (3), YEARS (40), LEVEL (niveau d'IA, défaut du menu),
## SAVE_EVERY (années entre deux mesures de sauvegarde, 10), OUT (fichier JSON du résultat, facultatif),
## SAVE_AT + SAVE_PATH (sauvegarder la partie à la fin de cette année, pour tools/deep_profile.gd).
## Le pas suit la liste de Simulation.daily_systems(), la même que step() ; les signaux de chronique
## ne sont pas émis (rien n'y est branché ici).

const SAVE_TMP := "user://profile_game_tmp.json"


func _systems(events: Array) -> Array:
	return Simulation.daily_systems(events)


func _initialize() -> void:
	var seed_value := _env_int("SEED", 3)
	var years := _env_int("YEARS", 40)
	var save_every := maxi(1, _env_int("SAVE_EVERY", 10))
	var menu := MainMenu.new()
	menu.slots = MainMenu.default_slots()
	menu.spectator = true
	if OS.get_environment("LEVEL") != "":
		menu.ai_level = OS.get_environment("LEVEL")
	var opts := {"ai_level": menu.ai_level, "temperament": menu.temperament, "spectator": true,
		"deadline": 0, "people_victories": true}
	opts.merge(menu.empire_setup("", seed_value), true)
	opts.merge(menu.game_options(), true)
	opts["galaxy"] = menu.galaxy_settings.duplicate()
	menu.free()
	var t0 := Time.get_ticks_usec()
	var st := GameState.create(seed_value, 150, 1800.0, "", opts)
	var create_ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("Partie : graine %d, %d systèmes, %d empires (IA %s), création %.0f ms, mémoire %.0f Mo" % [
		seed_value, st.galaxy.systems.size(), st.empires.size(), opts["ai_level"], create_ms, _mem()])
	var events: Array = []
	var systems := _systems(events)
	var total := {}
	var by_year: Array = []
	var saves: Array = [_measure_save(st)]
	for y in years:
		var year := {}
		var worst := 0.0
		var t_year := Time.get_ticks_usec()
		for d in 360:
			var t_day := Time.get_ticks_usec()
			st.tick += 1
			st.log_cache.clear()
			events.clear()
			for s in systems:
				var a := Time.get_ticks_usec()
				s[1].call(st)
				year[s[0]] = int(year.get(s[0], 0)) + Time.get_ticks_usec() - a
			worst = maxf(worst, (Time.get_ticks_usec() - t_day) / 1000.0)
		var year_ms := (Time.get_ticks_usec() - t_year) / 1000.0
		for k in year:
			total[k] = int(total.get(k, 0)) + int(year[k])
		var owners := {}
		for c in st.colonies.values():
			owners[c.owner] = true
		var alive := owners.size()
		var row := {"year": y + 1, "ms_per_day": year_ms / 360.0, "worst_day_ms": worst, "colonies": st.colonies.size(),
			"fleets": st.fleets.size(), "empires": alive, "mem_mb": _mem(), "top": _top(year, 5)}
		by_year.append(row)
		print("an %2d : %6.2f ms/jour (pire jour %6.1f ms) | colonies %3d flottes %4d | %4.0f Mo | %s" % [
			y + 1, row["ms_per_day"], worst, row["colonies"], row["fleets"], row["mem_mb"],
			", ".join(row["top"].map(func(p: Array) -> String: return "%s %.1f" % [p[0], p[1] / 360.0 / 1000.0]))])
		if OS.get_environment("SAVE_AT") != "" and y + 1 == int(OS.get_environment("SAVE_AT")):
			SaveGame.save_state(st, OS.get_environment("SAVE_PATH"))
		if (y + 1) % save_every == 0:
			saves.append(_measure_save(st))
	var days := years * 360
	print("")
	print("Coût moyen par système sur %d ans (ms par jour) :" % years)
	for p in _top(total, systems.size()):
		print("  %-16s %7.3f" % [p[0], p[1] / float(days) / 1000.0])
	print("Sauvegardes (an, empreinte ms, instantané ms, JSON ms, taille Ko) :")
	for s in saves:
		print("  an %2d : %6.0f %6.0f %6.0f %8.0f" % [s["year"], s["checksum_ms"], s["snapshot_ms"], s["json_ms"], s["kb"]])
	print("Empreinte finale (pour vérifier qu'une optimisation ne change rien) : %s" % st.checksum().substr(0, 16))
	var out := OS.get_environment("OUT")
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify({"seed": seed_value, "level": opts["ai_level"], "empires": st.empires.size(),
			"create_ms": create_ms, "years": by_year, "total_us": total, "saves": saves}, "\t"))
		f.close()
	quit()


## Coût d'une sauvegarde : empreinte (checksum, aussi relevée tous les CHECK_DAYS en réseau),
## instantané et texte JSON.
func _measure_save(st: GameState) -> Dictionary:
	var a := Time.get_ticks_usec()
	st.checksum()
	var b := Time.get_ticks_usec()
	var snap = st.to_snapshot()
	var c := Time.get_ticks_usec()
	var text := JSON.stringify(snap, "\t", false, true)
	var d := Time.get_ticks_usec()
	return {"year": st.tick / 360, "checksum_ms": (b - a) / 1000.0, "snapshot_ms": (c - b) / 1000.0,
		"json_ms": (d - c) / 1000.0, "kb": text.length() / 1024.0}


func _top(d: Dictionary, n: int) -> Array:
	var pairs: Array = []
	for k in d:
		pairs.append([k, float(d[k])])
	pairs.sort_custom(func(a: Array, b: Array) -> bool: return a[1] > b[1])
	return pairs.slice(0, n)


func _mem() -> float:
	return OS.get_static_memory_usage() / 1048576.0


func _env_int(name: String, def: int) -> int:
	var v := OS.get_environment(name)
	return int(v) if v.is_valid_int() else def
