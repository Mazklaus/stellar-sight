extends SceneTree
## Compare les niveaux d'IA : chaque niveau joue seul contre lui-même (4 empires) pendant 5 ans,
## sur plusieurs graines, puis une partie mixte où chaque empire a un niveau différent.
##   godot --headless --path . -s res://tools/ai_bench.gd
const YEARS := 5
const SEEDS := [3, 17, 99]

func _score(st: GameState, id: int) -> String:
	var t := EmpireReport.totals(st, id)
	return "%2d sys %2d col %2d ap %3d pop" % [t["systems"], t["colonies"], t["outposts"], t["population"]]

func _initialize() -> void:
	var only := OS.get_environment("LEVELS")
	for lv in AiLevels.ids():
		if only != "" and not only.split(",").has(lv):
			continue
		var sums := {}
		for sd in SEEDS:
			var sim := Simulation.new(GameState.create(sd, 150, 1800.0, "", {"spectator": true, "ai_level": lv}))
			sim.advance(360 * YEARS)
			for e in sim.state.empires:
				var t := EmpireReport.totals(sim.state, e.id)
				sums[e.short_name()] = int(sums.get(e.short_name(), 0)) + EmpireReport.score(sim.state, e.id)
		print("%-8s score moyen par peuple : %s" % [lv, str(sums.keys().map(func(k): return "%s %d" % [k, sums[k] / SEEDS.size()]))])
	if only != "":
		quit()
		return
	var levels := AiLevels.ids()
	for sd in SEEDS:
		for rot in 4:
			var per := []
			for i in 4:
				per.append([levels[0], levels[1], levels[2], levels[-1]][(i + rot) % 4])
			var sim := Simulation.new(GameState.create(sd, 150, 1800.0, "", {"spectator": true, "ai_levels": per}))
			sim.advance(360 * YEARS)
			var line := "graine %d : " % sd
			for e in sim.state.empires:
				line += "| %s %s %s " % [e.short_name().left(6), e.ai_level.left(3), _score(sim.state, e.id)]
			print(line)
	quit()
