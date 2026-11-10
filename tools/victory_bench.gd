extends SceneTree
## Parties entre IA jusqu'à la victoire (ou la date limite) : qui gagne, comment, et quand.
## Imprime tous les 5 ans l'avancée de chaque empire vers chacune de ses victoires.
##   godot --headless --path . -s res://tools/victory_bench.gd
## Variables d'environnement : SEEDS=3,17 LEVEL=normal YEARS=60 QUIET=1
const STEP_YEARS := 5


func _initialize() -> void:
	var seeds := [3, 17, 99, 42]
	if OS.get_environment("SEEDS") != "":
		seeds = Array(OS.get_environment("SEEDS").split(",")).map(func(s: String) -> int: return s.to_int())
	var level := OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "normal"
	var years := OS.get_environment("YEARS").to_int() if OS.get_environment("YEARS") != "" else 60
	var quiet := OS.get_environment("QUIET") != ""
	for sd in seeds:
		var t0 := Time.get_ticks_msec()
		var st := GameState.create(int(sd), 150, 1800.0, "", {"spectator": true, "ai_level": level, "deadline": years * 360})
		var sim := Simulation.new(st)
		var y := 0
		while st.winner.is_empty() and y < years:
			sim.advance(360 * STEP_YEARS)
			y += STEP_YEARS
			if quiet:
				continue
			print("graine %d, an %d :" % [sd, y])
			for e in st.empires:
				if e.eliminated:
					print("   %-14s disparu" % e.short_name())
					continue
				var parts := []
				for id in Victory.ids_for(st, e.id):
					if id == Victory.SCORE:
						continue
					parts.append("%s %d%%" % [id, Victory.cached_pct(st, e.id, id)])
				print("   %-14s score %4d  sys %3d  techs %3d  %s" % [e.short_name(), Victory.score(st, e.id), Victory.systems_held(st, e.id), e.techs.size(), "  ".join(parts)])
		var w := st.winner
		if w.is_empty():
			print("=> graine %d : pas de vainqueur après %d ans (%d s)" % [sd, years, (Time.get_ticks_msec() - t0) / 1000])
		else:
			print("=> graine %d : %s gagne par %s le %s (an %d) (%d s)" % [sd, st.get_empire(int(w["empire"])).short_name(), Victory.label(String(w["victory"])),
					GameCalendar.date_string(int(w["tick"])), int(w["tick"]) / 360, (Time.get_ticks_msec() - t0) / 1000])
		for e in st.empires:
			if not e.eliminated:
				for id in Victory.ids_for(st, e.id):
					if Victory.is_people(id):
						print("   %s / %s : %s" % [e.short_name(), Victory.label(id), " ; ".join(Victory.progress(st, e.id, id)["lines"])])
	quit()
