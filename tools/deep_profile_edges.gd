extends SceneTree
## Profil détaillé avec arêtes appelant > appelé. LOAD, DAYS, OUT (json).
const PROF := "res://scripts/sim/prof_scope.gd"

func _initialize() -> void:
	var st: GameState = SaveGame.load_state(OS.get_environment("LOAD"))
	if st == null:
		printerr("Chargement impossible : %s" % SaveGame.last_error)
		quit(1)
		return
	var days := int(OS.get_environment("DAYS")) if OS.get_environment("DAYS") != "" else 60
	var prof: Script = load(PROF) if ResourceLoader.exists(PROF) else null
	var events: Array = []
	var systems := Simulation.daily_systems(events)
	var per_sys := {}
	var per_day: Array = []
	var counts := _counts(st)
	if prof != null:
		prof.set("enabled", true)
	var t0 := Time.get_ticks_usec()
	for d in days:
		var a := Time.get_ticks_usec()
		st.tick += 1
		st.log_cache.clear()
		events.clear()
		var row := {}
		for s in systems:
			var b := Time.get_ticks_usec()
			s[1].call(st)
			var dt := Time.get_ticks_usec() - b
			per_sys[s[0]] = int(per_sys.get(s[0], 0)) + dt
			if dt > 2000:
				row[s[0]] = dt / 1000.0
		per_day.append({"tick": st.tick, "dom": posmod(int(st.tick), 30) + 1, "ms": (Time.get_ticks_usec() - a) / 1000.0, "sys": row})
	var total := (Time.get_ticks_usec() - t0) / 1000.0
	if prof != null:
		prof.set("enabled", false)
	var out := {"total_ms": total, "days": days, "tick": st.tick, "counts": counts, "counts_end": _counts(st),
		"checksum": st.checksum().substr(0, 16), "per_sys_ms_day": {}, "per_day": per_day, "instrumented": prof != null}
	for k in per_sys:
		out["per_sys_ms_day"][k] = per_sys[k] / 1000.0 / days
	if prof != null:
		out["stats"] = prof.get("stats")
		out["edges"] = prof.get("edges")
	var f := FileAccess.open(OS.get_environment("OUT"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("fini %.0f ms" % total)
	quit()

func _counts(st: GameState) -> Dictionary:
	var ships := 0
	for fl in st.fleets.values():
		if "ships" in fl:
			ships += fl.ships.size()
	var alive := 0
	var npc := 0
	for e in st.empires:
		if not e.eliminated:
			alive += 1
	var d := {"colonies": st.colonies.size(), "fleets": st.fleets.size(), "ships": ships, "empires": st.empires.size(), "alive": alive,
		"systems": st.galaxy.systems.size(), "tick": st.tick}
	for k in ["megastructures", "megas", "regiments", "heroes", "wars", "treaties", "trade_routes", "routes", "memories", "portals", "operations", "designs", "chronicle", "announces", "battle_reports", "proposals", "quests", "relics", "pops", "armies", "stations", "minors", "pirates", "lairs", "herds", "creatures"]:
		if k in st:
			var v: Variant = st.get(k)
			if v is Dictionary or v is Array:
				d[k] = v.size()
	return d
