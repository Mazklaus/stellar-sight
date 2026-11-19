extends SceneTree
## Profil détaillé : fait tourner DAYS jours (90) depuis une sauvegarde (LOAD) ou une partie neuve
## (graine SEED, 3), et écrit dans OUT : coût de chaque jour, de chaque système, et, dans une copie
## instrumentée du jeu (tools/instrument_profile.py), le temps de chaque fonction de la simulation.
##   SEED=3 YEARS=12 SAVE_AT=12 SAVE_PATH=/tmp/an12.json godot --headless --path . -s res://tools/profile_game.gd
##   LOAD=/tmp/an12.json OUT=/tmp/profil.txt godot --headless --path . -s res://tools/deep_profile.gd
## Dans la copie instrumentée, les temps sont gonflés (environ ×4) et surtout ceux des toutes petites
## fonctions appelées des millions de fois : lire les parts comme des ordres de grandeur.

const PROF := "res://scripts/sim/prof_scope.gd"


func _initialize() -> void:
	var st: GameState
	var path := OS.get_environment("LOAD")
	if path != "":
		st = SaveGame.load_state(path)
		if st == null:
			printerr("Chargement impossible : %s" % SaveGame.last_error)
			quit(1)
			return
	else:
		var menu := MainMenu.new()
		menu.slots = MainMenu.default_slots()
		menu.spectator = true
		var opts := {"ai_level": menu.ai_level, "temperament": menu.temperament, "spectator": true,
			"deadline": 0, "people_victories": true}
		var seed_value := _env_int("SEED", 3)
		opts.merge(menu.empire_setup("", seed_value), true)
		opts.merge(menu.game_options(), true)
		opts["galaxy"] = menu.galaxy_settings.duplicate()
		menu.free()
		st = GameState.create(seed_value, 150, 1800.0, "", opts)
	var days := _env_int("DAYS", 90)
	var prof: Script = load(PROF) if ResourceLoader.exists(PROF) else null
	var events: Array = []
	var systems := Simulation.daily_systems(events)
	var per_sys := {}
	var per_day: Array = []
	if prof != null:
		prof.set("enabled", true)
	var t0 := Time.get_ticks_usec()
	for d in days:
		var a := Time.get_ticks_usec()
		st.tick += 1
		st.log_cache.clear()
		events.clear()
		for s in systems:
			var b := Time.get_ticks_usec()
			s[1].call(st)
			per_sys[s[0]] = int(per_sys.get(s[0], 0)) + Time.get_ticks_usec() - b
		per_day.append([st.tick, (Time.get_ticks_usec() - a) / 1000.0])
	var total := (Time.get_ticks_usec() - t0) / 1000.0
	if prof != null:
		prof.set("enabled", false)
	var f := FileAccess.open(OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "user://deep_profile.txt", FileAccess.WRITE)
	f.store_line("total %.0f ms, %d jours (%.1f ms/jour), tick final %d, colonies %d, flottes %d, instrumenté : %s" % [
		total, days, total / days, st.tick, st.colonies.size(), st.fleets.size(), "oui" if prof != null else "non"])
	f.store_line("empreinte finale %s" % st.checksum().substr(0, 16))
	f.store_line("== JOURS (les plus lents)")
	per_day.sort_custom(func(x: Array, y: Array) -> bool: return x[1] > y[1])
	for p in per_day.slice(0, 15):
		f.store_line("  jour %d (le %d du mois) : %.1f ms" % [p[0], posmod(int(p[0]), 30) + 1, p[1]])
	f.store_line("== SYSTÈMES (ms par jour)")
	var rows := _sorted(per_sys)
	for r in rows:
		f.store_line("  %-18s %8.2f" % [r[0], r[1] / 1000.0 / days])
	if prof != null:
		var stats: Dictionary = prof.get("stats")
		var fn: Array = []
		for k in stats:
			fn.append([k, stats[k][0], stats[k][1], stats[k][2]])
		for mode in [["PROPRE", 3], ["INCLUSIF", 2]]:
			f.store_line("== FONCTIONS, temps %s (appels, inclusif ms, propre ms)" % mode[0])
			fn.sort_custom(func(x: Array, y: Array) -> bool: return x[mode[1]] > y[mode[1]])
			for r in fn.slice(0, 200):
				f.store_line("  %-60s %9d %10.1f %10.1f" % [r[0], r[1], r[2] / 1000.0, r[3] / 1000.0])
	f.close()
	quit()


func _sorted(d: Dictionary) -> Array:
	var out: Array = []
	for k in d:
		out.append([k, float(d[k])])
	out.sort_custom(func(x: Array, y: Array) -> bool: return x[1] > y[1])
	return out


func _env_int(name: String, def: int) -> int:
	var v := OS.get_environment(name)
	return int(v) if v.is_valid_int() else def
