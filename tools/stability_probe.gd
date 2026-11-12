extends SceneTree
## Sonde de la stabilité entre IA (étude « Pirates et stabilité ») : par graine et par année, systèmes,
## stabilité d'empire, systèmes par palier, sécessions, mondes libres. Une ligne JSON par graine :
##   SEEDS=1,2 YEARS=20 godot --headless --path . -s res://tools/stability_probe.gd
## Variables : SEEDS, YEARS (défaut 20), LEVEL (défaut normal).


func _initialize() -> void:
	var years := int(OS.get_environment("YEARS")) if OS.get_environment("YEARS") != "" else 20
	var level := OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "normal"
	var seeds := [3]
	if OS.get_environment("SEEDS") != "":
		seeds = Array(OS.get_environment("SEEDS").split(",")).map(func(s: String) -> int: return int(s))
	for sd in seeds:
		var st := GameState.create(sd, 150, 1800.0, "", {"spectator": true, "ai_level": level})
		var sim := Simulation.new(st)
		var secessions := {}
		sim.chronicle_added.connect(func(en: Dictionary) -> void:
			var t := String(en["text"])
			if t.begins_with("Sécession !") or t.contains("redevient sauvage"):
				for e in st.empires:
					if t.contains(e.display_name()):
						secessions[e.faction_id] = int(secessions.get(e.faction_id, 0)) + 1)
		var t0 := Time.get_ticks_msec()
		var rows := []
		for y in years:
			sim.advance(360)
			var yr := {"year": y + 1}
			for e in st.empires:
				if e.eliminated:
					continue
				var tiers := {}
				for sid in Stability.systems_of(st, e.id):
					var t := Stability.tier_id(st, sid)
					tiers[t] = int(tiers.get(t, 0)) + 1
				yr[e.faction_id] = {"sys": Stability.systems_of(st, e.id).size(), "stab": Stability.empire_value(st, e.id), "tiers": tiers}
			rows.append(yr)
			if not st.winner.is_empty():
				break
		var free := 0
		for k in st.colonies:
			if GameState.is_npc(st.colonies[k].owner):
				free += 1
		print(JSON.stringify({"seed": sd, "ms": Time.get_ticks_msec() - t0, "secessions": secessions, "free_claims": free, "rows": rows}))
	quit()
