extends SceneTree
## Banc de l'ingénierie des espèces, sans rien changer aux règles : parties entre IA, ingénierie
## complète et populations mêlées, relevé annuel par empire (voie, programmes achevés, traits de
## l'espèce fondatrice, lignées, hybrides), puis un résumé par graine (vainqueur, vitesse).
##   SEEDS=3,17 YEARS=20 godot --headless --path . -s res://tools/genetics_bench.gd
## Variables : SEEDS, YEARS (défaut 20), LEVEL (défaut normal), MODE (défaut complete).


func _initialize() -> void:
	var years := int(OS.get_environment("YEARS")) if OS.get_environment("YEARS") != "" else 20
	var level := OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "normal"
	var mode := OS.get_environment("MODE") if OS.get_environment("MODE") != "" else "complete"
	var seeds := [3, 17]
	if OS.get_environment("SEEDS") != "":
		seeds = Array(OS.get_environment("SEEDS").split(",")).map(func(s: String) -> int: return int(s))
	for sd in seeds:
		_run(int(sd), years, level, mode)
	quit()


func _run(sd: int, years: int, level: String, mode: String) -> void:
	var opts := {"spectator": true, "ai_level": level, "temperament": "normal", "genetics": mode, "peoples": "actifs",
		"politics": Politics.default_mode(), "faiths": "actives"}
	var st := GameState.create(sd, 150, 1800.0, "", opts)
	var sim := Simulation.new(st)
	var t0 := Time.get_ticks_msec()
	for y in years:
		sim.advance(360)
		var line := PackedStringArray()
		for e in st.empires:
			if e.eliminated:
				continue
			line.append("%s %s p%d t%d l%d h%d" % [e.faction_id.left(5), e.gene_path if e.gene_path != "" else "-", Genetics.programs_done(st, e.id),
					Genetics.traits_of(e.faction()).size(), GeneticsBridges.lineages_of(st, e.id).size(), Genetics.stat(st, e.id, "hybrids")])
		print("GEN seed %d an %d : %s" % [sd, y + 1, " | ".join(line)])
		if not st.winner.is_empty():
			break
	print("GENSUM seed %d : vainqueur %s, %.1f ms/jour" % [sd, JSON.stringify(st.winner), float(Time.get_ticks_msec() - t0) / float(maxi(1, st.tick))])
