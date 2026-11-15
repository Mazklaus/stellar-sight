extends SceneTree
## Banc du combat au sol complet entre IA : pour chaque graine, une partie spectateur de YEARS ans
## en mode « complet », puis le relevé par empire (régiments levés et vivants, batailles au sol menées,
## gagnées, tenues, retraites) et le total des systèmes pris au sol. Sert à vérifier que l'IA recrute,
## embarque et mène ses invasions jusqu'au bout.
##   SEEDS=3,17 YEARS=10 godot --headless --path . -s res://tools/ground_bench.gd
## Variables : SEEDS, YEARS (défaut 10), LEVEL (défaut normal), TEMPER (défaut belliqueux), MODE (défaut complet).


func _initialize() -> void:
	var years := int(OS.get_environment("YEARS")) if OS.get_environment("YEARS") != "" else 10
	var level := OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "normal"
	var temper := OS.get_environment("TEMPER") if OS.get_environment("TEMPER") != "" else "belliqueux"
	var mode := OS.get_environment("MODE") if OS.get_environment("MODE") != "" else "complet"
	var seeds := [3, 17]
	if OS.get_environment("SEEDS") != "":
		seeds = Array(OS.get_environment("SEEDS").split(",")).map(func(s: String) -> int: return int(s))
	for sd in seeds:
		_run(int(sd), years, level, temper, mode)
	quit()


func _run(sd: int, years: int, level: String, temper: String, mode: String) -> void:
	var st := GameState.create(sd, 150, 1800.0, "", {"spectator": true, "ai_level": level, "temperament": temper, "ground": mode})
	var sim := Simulation.new(st)
	var raised := {}
	var seen := {}
	var landings := 0
	var all_reps: Array = []
	var t0 := Time.get_ticks_msec()
	var m := 0
	while m < years * 12 and st.winner.is_empty():
		for d in 30:
			sim.advance(1)
			for r: Dictionary in st.ground.get("r", {}).values():
				if not seen.has(int(r["id"])):
					seen[int(r["id"])] = true
					raised[int(r["o"])] = int(raised.get(int(r["o"]), 0)) + 1
			for b: Dictionary in st.ground.get("b", {}).values():
				if not seen.has("b%d" % int(b["id"])):
					seen["b%d" % int(b["id"])] = true
					landings += 1
			for rep: Dictionary in st.ground.get("rep", []):
				if not seen.has("p%d" % int(rep["id"])):
					seen["p%d" % int(rep["id"])] = true
					all_reps.append(rep)
		m += 1
	var ms := Time.get_ticks_msec() - t0
	print("GRAINE %d, %d mois, %.1f ms/jour, mode %s, %d débarquements" % [sd, m, float(ms) / float(maxi(1, m * 30)), mode, landings])
	var reps := all_reps
	for e in st.empires:
		var won := 0
		var held := 0
		var retreat := 0
		var lost := 0
		for rep: Dictionary in reps:
			if int(rep["a"]) == e.id:
				match String(rep["how"]):
					"won":
						won += 1
					"retreat":
						retreat += 1
					"held":
						lost += 1
			elif int(rep["d"]) == e.id and String(rep["how"]) == "held":
				held += 1
		print("  %-14s %s  levés %3d  vivants %3d  assauts gagnés %2d  repoussés %2d  retraites %2d  défenses tenues %2d  systèmes %2d" % [
				e.faction_id, "MORT" if e.eliminated else "    ", int(raised.get(e.id, 0)), Ground.regiments_of(st, e.id).size(),
				won, lost, retreat, held, Stability.systems_of(st, e.id).size()])
	print("  batailles au sol terminées : %d" % reps.size())
