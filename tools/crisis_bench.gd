extends SceneTree
## Banc des crises de fin de partie (voir Crisis) : partie entre IA, la crise lancée à l'an START,
## puis on suit son cours (systèmes tombés, libérés, puissance, Front commun) jusqu'à sa fin ou YEARS
## ans après son arrivée. Une ligne « CRISE {...} » par graine et par réglage.
##   SEEDS=3,17 KINDS=recif,inspection STRENGTHS=normale START=8 YEARS=12 godot --headless --path . -s res://tools/crisis_bench.gd
## Variables : SEEDS, KINDS (défaut les trois du lot 1), STRENGTHS (défaut normale), START (an de la
## crise, défaut 8 : plus court que l'an 30 du jeu, pour un banc qui tourne vite), YEARS (défaut 12),
## LEVEL (défaut normal).


func _env(k: String, d: String) -> String:
	return OS.get_environment(k) if OS.get_environment(k) != "" else d


func _initialize() -> void:
	var seeds := Array(_env("SEEDS", "3,17").split(",")).map(func(s: String) -> int: return int(s))
	var kinds := Array(_env("KINDS", "recif,inspection,dechirure").split(","))
	var strengths := Array(_env("STRENGTHS", "normale").split(","))
	var start := int(_env("START", "8"))
	var years := int(_env("YEARS", "12"))
	var level := _env("LEVEL", "normal")
	for sd in seeds:
		for k in kinds:
			for s in strengths:
				_run(int(sd), String(k), String(s), start, years, level)
	quit()


func _run(sd: int, k: String, strength: String, start: int, years: int, level: String) -> void:
	var t0 := Time.get_ticks_msec()
	var st := GameState.create(sd, 150, 1800.0, "", {"spectator": true, "ai_level": level, "crises": "une",
			"crisis_strength": strength, "crisis_kinds": [k], "terrain": "normal"})
	st.crisis["start"] = start * 360
	var sim := Simulation.new(st)
	var month := int(GameData.rules()["month_days"])
	var curve: Array = []
	var arrived := -1
	var limit := start * 360 + (years + 3) * 360
	while st.tick < limit:
		sim.advance(month)
		# La crise est forcée à la date (le tirage tous les deux ans est testé ailleurs).
		if st.tick >= start * 360 and not Crisis.ongoing(st) and (st.crisis["past"] as Array).is_empty():
			var added: Array[Dictionary] = []
			Crisis.begin(st, k, added)
		if Crisis.active(st):
			if arrived < 0:
				arrived = st.tick
			if (st.tick / month) % 6 == 0:
				curve.append([st.tick / 360, Crisis.held(st).size(), Crisis.total_power(st), Crisis.war_fleets(st).size(), Crisis.stations(st).size()])
		elif arrived >= 0 and not Crisis.ongoing(st):
			break
		if not st.winner.is_empty():
			break
	var past: Array = st.crisis.get("past", [])
	var res: Dictionary = past[-1] if not past.is_empty() else {}
	var front := 0
	if Crisis.active(st):
		front = (Crisis.cur(st)["front"] as Dictionary).size()
	print("CRISE " + JSON.stringify({"seed": sd, "kind": k, "str": strength, "arrived": arrived, "power": int(Crisis.cur(st).get("power", 0)),
			"result": String(res.get("result", "en cours" if Crisis.active(st) else "aucune")), "end": int(res.get("tick", st.tick)),
			"fallen": int(res.get("fallen", Crisis.cur(st).get("fallen", 0))), "freed": int(res.get("freed", Crisis.cur(st).get("freed", 0))),
			"shares": res.get("shares", Crisis.shares(st)), "front": front, "winner": st.winner, "curve": curve,
			"alive": st.empires.filter(func(e: Empire) -> bool: return not e.eliminated).size(), "secs": (Time.get_ticks_msec() - t0) / 1000}))
