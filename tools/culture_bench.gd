extends SceneTree
## Banc du rayonnement culturel, sans rien changer aux règles : parties entre IA avec toutes les options
## de la Nouvelle partie par défaut, relevé annuel du Rayonnement, du Patrimoine et des paliers atteints,
## défections et vainqueur. Une ligne par empire et par an, puis un résumé par graine.
##   SEEDS=1,2 YEARS=15 godot --headless --path . -s res://tools/culture_bench.gd
## Variables : SEEDS, YEARS (défaut 15), LEVEL (défaut normal).


func _initialize() -> void:
	var years := int(OS.get_environment("YEARS")) if OS.get_environment("YEARS") != "" else 15
	var level := OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "normal"
	var seeds := [3, 17]
	if OS.get_environment("SEEDS") != "":
		seeds = Array(OS.get_environment("SEEDS").split(",")).map(func(s: String) -> int: return int(s))
	for sd in seeds:
		_run(int(sd), years, level)
	quit()


static func options(level: String) -> Dictionary:
	return {"spectator": true, "ai_level": level, "temperament": "normal", "culture": "actif", "culture_defect": "rare",
		"faiths": "actives", "peoples": "actifs", "migrations": "actives", "amphictyony": "active", "politics": Politics.default_mode(),
		"goods": String(GameData.goods()["default_mode"]), "borders": String(GameData.borders()["default_mode"]),
		"minors": Minors.default_mode(), "events": Events.default_frequency(), "curios": Curios.default_density()}


func _run(sd: int, years: int, level: String) -> void:
	var st := GameState.create(sd, 150, 1800.0, "", options(level))
	var sim := Simulation.new(st)
	var notes := {"defect": 0, "troupes": 0, "osmose": 0, "museum": 0, "wonders": 0}
	sim.chronicle_added.connect(func(entry: Dictionary) -> void:
		var t := String(entry.get("text", ""))
		if t.begins_with("Défection culturelle !"):
			notes["defect"] += 1
		elif t.begins_with("Tournée de la Troupe"):
			notes["troupes"] += 1
		elif t.find(" adopte « ") >= 0:
			notes["osmose"] += 1)
	var t0 := Time.get_ticks_msec()
	for y in years:
		sim.advance(360)
		var line := PackedStringArray()
		for e in st.empires:
			if e.eliminated:
				continue
			var best := 0
			var n4 := 0
			for b in Culture.living(st):
				if b != e.id:
					best = maxi(best, Culture.tier(st, e.id, b))
					if Culture.tier(st, e.id, b) >= 4:
						n4 += 1
			line.append("%s r%d p%d t%d i%d" % [e.faction_id.left(5), Culture.radiance(st, e.id), Culture.heritage(st, e.id), best, n4])
		print("CUL seed %d an %d : %s" % [sd, y + 1, " | ".join(line)])
		if not st.winner.is_empty():
			break
	for pid in st.colonies:
		var c: Colony = st.colonies[pid]
		for b in c.buildings:
			if b == "musee_galactique":
				notes["museum"] += 1
			elif int(GameData.building(b).get("culture_wonder", 0)) > 0:
				notes["wonders"] += 1
	print("CULSUM seed %d : %s, vainqueur %s, %.1f ms/jour" % [sd, JSON.stringify(notes), JSON.stringify(st.winner),
			float(Time.get_ticks_msec() - t0) / float(maxi(1, st.tick))])
