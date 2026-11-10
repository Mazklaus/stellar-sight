extends SceneTree
## Équilibre des peuples entre IA : une partie par graine, une ligne JSON par graine (systèmes tenus
## par an, année de disparition, vainqueur). Fait pour être lancé en parallèle puis agrégé :
##   SEEDS=1,2,3 YEARS=25 godot --headless --path . -s res://tools/balance_bench.gd
##   python3 tools/balance_report.py fichier.jsonl
## Variables : SEEDS, YEARS (défaut 25), LEVEL (défaut normal), TEMPER (défaut normal).


func _initialize() -> void:
	var years := int(OS.get_environment("YEARS")) if OS.get_environment("YEARS") != "" else 25
	var level := OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "normal"
	var temper := OS.get_environment("TEMPER") if OS.get_environment("TEMPER") != "" else "normal"
	var seeds := [3, 17, 99]
	if OS.get_environment("SEEDS") != "":
		seeds = Array(OS.get_environment("SEEDS").split(",")).map(func(s: String) -> int: return int(s))
	for sd in seeds:
		var st := GameState.create(sd, 150, 1800.0, "", {"spectator": true, "ai_level": level, "temperament": temper})
		var sim := Simulation.new(st)
		var rows := {}
		for e in st.empires:
			rows[e.id] = {"faction": e.faction_id, "systems": [], "dead": -1, "first_war": -1, "pop": 0}
		var t0 := Time.get_ticks_msec()
		var y := 0
		while y < years and st.winner.is_empty():
			sim.advance(360)
			y += 1
			for e in st.empires:
				var r: Dictionary = rows[e.id]
				r["systems"].append(0 if e.eliminated else Victory.systems_held(st, e.id))
				if e.eliminated and int(r["dead"]) < 0:
					r["dead"] = y
				if int(r["first_war"]) < 0 and not e.wars.is_empty():
					r["first_war"] = y
		for e in st.empires:
			rows[e.id]["pop"] = 0 if e.eliminated else int(EmpireReport.totals(st, e.id)["population"])
		var out := {"seed": sd, "years": y, "ms": Time.get_ticks_msec() - t0, "empires": rows.values()}
		if not st.winner.is_empty():
			var w := st.winner
			out["winner"] = {"faction": st.get_empire(int(w["empire"])).faction_id, "victory": String(w["victory"]),
					"year": int(w["tick"]) / 360, "allies": w.get("allies", [])}
		print("BENCH " + JSON.stringify(out))
	quit()
