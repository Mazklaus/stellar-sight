extends SceneTree
## Partie longue entre IA, jusqu'au bout : vérifie qu'elle ne plante ni ne bloque, relève les
## déclencheurs tardifs (chronique, annonces typées, avancée des victoires) et mesure la vitesse
## année par année, au-delà des 14 ans de tools/profile_game.gd.
##   godot --headless --path . -s res://tools/long_game.gd
## Réglages : SEED (3), YEARS (50), LEVEL (niveau d'IA, défaut du menu), OUT (fichier JSONL, une
## ligne par année + une ligne finale), SAVE_EVERY (10 : sauvegarde, rechargement et comparaison
## d'empreinte), SAVE_DIR (user://), CONTINUE (1 : la partie continue après une victoire, comme le
## joueur qui choisit « continuer » ; 0 : on s'arrête), SLOW_DAY_MS (20000 : un jour plus long est
## signalé comme blocage possible), LOAD (reprendre depuis une sauvegarde faite par ce banc : la partie
## repart de son année et va jusqu'à YEARS).

func _initialize() -> void:
	var seed_value := _env_int("SEED", 3)
	var years := _env_int("YEARS", 50)
	var save_every := maxi(1, _env_int("SAVE_EVERY", 10))
	var keep_going := _env_int("CONTINUE", 1) == 1
	var slow_day := float(_env_int("SLOW_DAY_MS", 20000))
	var save_dir := OS.get_environment("SAVE_DIR")
	if save_dir == "":
		save_dir = "user://"
	var out_path := OS.get_environment("OUT")
	var out: FileAccess = null
	if out_path != "":
		out = FileAccess.open(out_path, FileAccess.WRITE)
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
	var st: GameState
	if OS.get_environment("LOAD") != "":
		st = SaveGame.load_state(OS.get_environment("LOAD"))
	else:
		st = GameState.create(seed_value, 150, 1800.0, "", opts)
	@warning_ignore("integer_division")
	var first_year := st.tick / 360
	var factions := []
	for e in st.empires:
		factions.append({"id": e.id, "faction": e.faction_id, "name": e.display_name()})
	_emit(out, {"type": "start", "seed": seed_value, "level": opts["ai_level"], "systems": st.galaxy.systems.size(),
		"empires": factions, "victory_rules": st.victory_rules, "from_year": first_year})
	print("Partie longue : graine %d, %d empires, %d ans" % [seed_value, st.empires.size(), years])
	var events: Array = []
	var systems := Simulation.daily_systems(events)
	var win_logged := not st.winner.is_empty()
	for y in range(first_year, years):
		var year_us := {}
		var worst := 0.0
		var worst_tick := 0
		var slow: Array = []
		var chron: Array = []
		var t_year := Time.get_ticks_usec()
		for d in 360:
			var t_day := Time.get_ticks_usec()
			st.tick += 1
			st.log_cache.clear()
			events.clear()
			for s in systems:
				var a := Time.get_ticks_usec()
				var added: Array = s[1].call(st)
				year_us[s[0]] = int(year_us.get(s[0], 0)) + Time.get_ticks_usec() - a
				for entry in added:
					chron.append({"t": int(entry.get("tick", st.tick)), "k": String(entry.get("kind", "")),
						"x": String(entry.get("text", "")), "sys": s[0]})
			var day_ms := (Time.get_ticks_usec() - t_day) / 1000.0
			if day_ms > worst:
				worst = day_ms
				worst_tick = st.tick
			if day_ms > slow_day:
				slow.append([st.tick, day_ms])
		var year_ms := (Time.get_ticks_usec() - t_year) / 1000.0
		var owners := {}
		for c in st.colonies.values():
			owners[c.owner] = true
		var vic := {}
		var eras := {}
		for e in st.empires:
			if e.eliminated:
				continue
			var best := {}
			for id in e.victory:
				var p := int(e.victory[id].get("pct", 0))
				if p > 0:
					best[id] = p
			vic[str(e.id)] = best
			eras[str(e.id)] = Research.current_era(st, e.id)
		var kinds := {}
		for c in chron:
			if c["k"] != "":
				kinds[c["k"]] = int(kinds.get(c["k"], 0)) + 1
		var row := {"type": "year", "year": y + 1, "ms_per_day": year_ms / 360.0, "worst_day_ms": worst,
			"worst_tick": worst_tick, "slow_days": slow, "colonies": st.colonies.size(), "fleets": st.fleets.size(),
			"empires_alive": owners.size(), "mem_mb": OS.get_static_memory_usage() / 1048576.0,
			"systems_ms_per_day": _per_day(year_us), "victory_pct": vic, "eras": eras, "kinds": kinds,
			"chronicle": chron, "winner": st.winner, "state_sizes": _sizes(st)}
		var save_info := {}
		if (y + 1) % save_every == 0 or y + 1 == years:
			save_info = _roundtrip(st, save_dir.path_join("long_game_s%d_y%d.json" % [seed_value, y + 1]))
			row["save"] = save_info
		_emit(out, row)
		print("an %2d : %7.1f ms/jour (pire %7.0f ms) | colonies %3d flottes %4d empires %2d | %4.0f Mo | chronique %3d%s%s" % [
			y + 1, row["ms_per_day"], worst, row["colonies"], row["fleets"], owners.size(), row["mem_mb"], chron.size(),
			("" if save_info.is_empty() else " | sauvegarde %s" % ("OK" if save_info.get("ok", false) else "ÉCHEC " + str(save_info))),
			("" if st.winner.is_empty() else " | VAINQUEUR %s" % str(st.winner))])
		if not st.winner.is_empty() and not win_logged:
			win_logged = true
			if not keep_going:
				break
	_emit(out, {"type": "end", "tick": st.tick, "winner": st.winner, "checksum": st.checksum().substr(0, 16)})
	if out != null:
		out.close()
	print("Fin : tick %d, vainqueur %s, empreinte %s" % [st.tick, str(st.winner), st.checksum().substr(0, 16)])
	quit()


## Sauvegarde, recharge et compare l'empreinte : une sauvegarde de fin de partie doit se relire à l'identique.
func _roundtrip(st: GameState, path: String) -> Dictionary:
	var a := Time.get_ticks_usec()
	var before := st.checksum()
	var err := SaveGame.save_state(st, path)
	var b := Time.get_ticks_usec()
	if err != OK:
		return {"ok": false, "error": "save %d" % err}
	var back := SaveGame.load_state(path)
	var c := Time.get_ticks_usec()
	if back == null:
		return {"ok": false, "error": "load null"}
	var after := back.checksum()
	return {"ok": before == after, "before": before.substr(0, 16), "after": after.substr(0, 16),
		"save_ms": (b - a) / 1000.0, "load_ms": (c - b) / 1000.0, "path": path}


func _per_day(us: Dictionary) -> Dictionary:
	var out := {}
	for k in us:
		out[k] = snappedf(int(us[k]) / 360.0 / 1000.0, 0.01)
	return out


## Taille des grands registres de l'état (accumulation sur la durée).
func _sizes(st: GameState) -> Dictionary:
	return {"chronicle": st.chronicle.size(), "announces": st.announces.size(), "memories": st.memories.size(),
		"battle_reports": st.battle_reports.size(), "heroes": st.heroes.size(), "operations": st.operations.size(),
		"spy_cases": st.spy_cases.size(), "proposals": st.proposals.size(), "designs": st.designs.size(),
		"quests": st.quests.size(), "relics": st.relics.size(), "digs": st.digs.size(), "lairs": st.lairs.size()}


func _emit(out: FileAccess, row: Dictionary) -> void:
	if out != null:
		out.store_line(JSON.stringify(row))
		out.flush()


func _env_int(name: String, def: int) -> int:
	var v := OS.get_environment(name)
	return int(v) if v.is_valid_int() else def
