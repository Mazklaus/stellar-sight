extends SceneTree
## Banc de l'étude d'équilibrage : une partie entre IA avec les réglages du menu (comme long_game),
## une ligne JSON par an et par empire (systèmes, population, exploration, flottes, score, technos),
## les jalons d'exploration (jour où chaque empire connaît 25/50/75/100 % de la carte, premier contact),
## la géométrie de la galaxie, la Menace du Fléau et la première victoire. La partie continue après.
##   SEED=3 YEARS=20 OUT=x.jsonl godot --headless --path . -s res://tools/equilibrage_bench.gd
## Variables : SEED, YEARS (20), LEVEL, SIZE (taille de galaxie du menu), STOP_ON_WIN=1.

func _env_int(n: String, d: int) -> int:
	var v := OS.get_environment(n)
	return int(v) if v != "" else d


func _emit(out: FileAccess, row: Dictionary) -> void:
	if out != null:
		out.store_line(JSON.stringify(row))
		out.flush()


func _initialize() -> void:
	var seed_value := _env_int("SEED", 3)
	var years := _env_int("YEARS", 20)
	var out: FileAccess = null
	if OS.get_environment("OUT") != "":
		out = FileAccess.open(OS.get_environment("OUT"), FileAccess.WRITE)
	var menu := MainMenu.new()
	menu.slots = MainMenu.default_slots()
	menu.spectator = true
	if OS.get_environment("LEVEL") != "":
		menu.ai_level = OS.get_environment("LEVEL")
	if OS.get_environment("SIZE") != "":
		menu.galaxy_settings["size"] = OS.get_environment("SIZE")
	var opts := {"ai_level": menu.ai_level, "temperament": menu.temperament, "spectator": true,
		"deadline": 0, "people_victories": true}
	opts.merge(menu.empire_setup("", seed_value), true)
	opts.merge(menu.game_options(), true)
	opts["galaxy"] = menu.galaxy_settings.duplicate()
	menu.free()
	var st := GameState.create(seed_value, 150, 1800.0, "", opts)
	var g := st.galaxy
	var n_sys := g.systems.size()
	# Géométrie : longueur des routes, sauts et distance entre mondes d'origine.
	var lanes: Array = []
	for ln in g.lanes:
		lanes.append(Fleets.lane_length(g, ln.x, ln.y))
	lanes.sort()
	var homes := []
	for e in st.empires:
		homes.append(g.get_planet(e.home_planet).system_id if e.home_planet >= 0 else -1)
	var facs := []
	for e in st.empires:
		facs.append({"id": e.id, "faction": e.faction_id, "home": homes[e.id] if e.id < homes.size() else -1})
	_emit(out, {"type": "start", "seed": seed_value, "systems": n_sys, "lanes": lanes, "empires": facs, "galaxy": opts["galaxy"]})
	var events: Array = []
	var systems := Simulation.daily_systems(events)
	var marks := {}
	var contact := {}
	var win_logged := false
	var nem_logged := -1
	for y in years:
		var t0 := Time.get_ticks_msec()
		for d in 360:
			st.tick += 1
			st.log_cache.clear()
			events.clear()
			for s in systems:
				s[1].call(st)
			if st.tick % 10 == 0:
				for e in st.empires:
					if e.eliminated:
						continue
					var pct := e.explored.size() * 100 / n_sys
					for m in [25, 50, 75, 100]:
						var k := "%d:%d" % [e.id, m]
						if pct >= m and not marks.has(k):
							marks[k] = st.tick
					if not e.contacts.is_empty() and not contact.has(e.id):
						contact[e.id] = st.tick
			if not win_logged and not st.winner.is_empty():
				win_logged = true
				_emit(out, {"type": "win", "tick": st.tick, "winner": st.winner,
					"faction": st.get_empire(int(st.winner["empire"])).faction_id})
				if _env_int("STOP_ON_WIN", 0) == 1:
					break
		var rows := []
		for e in st.empires:
			if e.eliminated:
				rows.append({"id": e.id, "dead": true})
				continue
			var tot := EmpireReport.totals(st, e.id)
			var ships := 0
			var fleets := 0
			for f in st.fleets.values():
				if f.owner == e.id:
					fleets += 1
					ships += f.ships.size()
			rows.append({"id": e.id, "sys": Victory.systems_held(st, e.id), "pop": int(tot.get("population", 0)),
				"expl": e.explored.size(), "score": Victory.score(st, e.id), "techs": e.techs.size(),
				"warships": Diplomacy.warships(st, e.id), "ships": ships, "fleets": fleets, "wars": e.wars.size(),
				"contacts": e.contacts.size(), "res": e.resources.duplicate()})
		var nm := {}
		if CrisisNemesis.enabled(st) and CrisisNemesis.who(st) >= 0:
			nm = {"who": CrisisNemesis.who(st), "menace": int(CrisisNemesis.nem(st).get("menace", 0)), "tier": CrisisNemesis.tier(st)}
		_emit(out, {"type": "year", "year": y + 1, "ms_per_day": (Time.get_ticks_msec() - t0) / 360.0,
			"colonies": st.colonies.size(), "fleets": st.fleets.size(), "empires": rows, "nemesis": nm})
		if win_logged and _env_int("STOP_ON_WIN", 0) == 1:
			break
	_emit(out, {"type": "end", "tick": st.tick, "marks": marks, "contact": contact, "winner": st.winner})
	quit()
