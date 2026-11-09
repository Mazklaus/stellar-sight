extends SceneTree
## Banc d'essai de la guerre entre IA : parties en spectateur, puis bilan des guerres, batailles,
## sièges, conquêtes et empires disparus.
##   godot --headless --path . -s res://tools/war_bench.gd
## Variables : YEARS (défaut 8), LEVEL (défaut normal), TEMPER (défaut normal), SEEDS (ex. 3,17,99).

func _initialize() -> void:
	var years := int(OS.get_environment("YEARS")) if OS.get_environment("YEARS") != "" else 8
	var level := OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "normal"
	var temper := OS.get_environment("TEMPER") if OS.get_environment("TEMPER") != "" else "normal"
	var seeds := [3, 17, 99]
	if OS.get_environment("SEEDS") != "":
		seeds = Array(OS.get_environment("SEEDS").split(",")).map(func(s: String) -> int: return int(s))
	for sd in seeds:
		var st := GameState.create(sd, 150, 1800.0, "", {"spectator": true, "ai_level": level, "temperament": temper})
		var sim := Simulation.new(st)
		var n := {"battles": 0, "sieges": 0, "first_war": -1, "captures": 0, "dead": ""}
		sim.combat_event.connect(func(ev: Dictionary) -> void:
			if ev["type"] == "battle_ended":
				n["battles"] += 1
			elif ev["type"] == "siege_started":
				n["sieges"] += 1)
		sim.chronicle_added.connect(func(entry: Dictionary) -> void:
			var tx := String(entry["text"])
			if tx.contains("envahit"):
				n["captures"] += 1
			if tx.contains("disparaît"):
				n["dead"] += " j%d" % st.tick
			if int(n["first_war"]) < 0 and tx.contains("guerre"):
				n["first_war"] = st.tick)
		var t0 := Time.get_ticks_msec()
		sim.advance(360 * years)
		var line := "graine %d (%s, %s, %d ans, %d ms) : 1re guerre j%d, %d batailles, %d sièges, %d invasions, disparitions%s\n" % [
				sd, level, temper, years, Time.get_ticks_msec() - t0, n["first_war"], n["battles"], n["sieges"], n["captures"], n["dead"]]
		for e in st.empires:
			var t := EmpireReport.totals(st, e.id)
			var war := 0
			for f in Fleets.empire_fleets(st, e.id):
				if Combat.is_warfleet(f):
					war += f.ships.size()
			line += "   %-14s %-22s %2d sys %3d pop  %2d vaisseaux de guerre  guerres %s%s\n" % [e.short_name(), AiLevels.temperament_label(e),
					t["systems"], t["population"], war, str(e.wars), "  DISPARU" if e.eliminated else ""]
		print(line)
	quit()
