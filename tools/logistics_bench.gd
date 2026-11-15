extends SceneTree
## Banc d'essai de la logistique entre IA : mêmes graines dans les trois modes, puis bilan des guerres
## et du ravitaillement (flottes étirées, coupées, à sec, dépôts bâtis, vitesse).
##   godot --headless --path . -s res://tools/logistics_bench.gd
## Variables : YEARS (défaut 8), LEVEL (défaut normal), TEMPER (défaut agressif), SEEDS (ex. 3,17,99),
## MODES (défaut aucune,simple,complete).

func _initialize() -> void:
	var years := int(OS.get_environment("YEARS")) if OS.get_environment("YEARS") != "" else 8
	var level := OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "normal"
	var temper := OS.get_environment("TEMPER") if OS.get_environment("TEMPER") != "" else "agressif"
	var seeds := [3, 17, 99]
	if OS.get_environment("SEEDS") != "":
		seeds = Array(OS.get_environment("SEEDS").split(",")).map(func(s: String) -> int: return int(s))
	var modes := ["aucune", "simple", "complete"]
	if OS.get_environment("MODES") != "":
		modes = Array(OS.get_environment("MODES").split(","))
	for sd in seeds:
		for mode in modes:
			var st := GameState.create(sd, 150, 1800.0, "", {"spectator": true, "ai_level": level, "temperament": temper, "logistics": mode})
			var sim := Simulation.new(st)
			var n := {"battles": 0, "captures": 0, "dead": 0, "cut": 0, "dry": 0, "req": 0}
			var samples := {"armed": 0, "out": 0, "cut": 0, "ex": 0}
			sim.combat_event.connect(func(ev: Dictionary) -> void:
				if ev["type"] == "battle_ended":
					n["battles"] += 1)
			sim.chronicle_added.connect(func(entry: Dictionary) -> void:
				var tx := String(entry["text"])
				if tx.contains("envahit"):
					n["captures"] += 1
				if tx.contains("disparaît"):
					n["dead"] += 1
				if tx.contains("coupée de ses arrières"):
					n["cut"] += 1
				if tx.contains("vidé ses soutes"):
					n["dry"] += 1
				if tx.contains("réquisitionne"):
					n["req"] += 1)
			var t0 := Time.get_ticks_msec()
			for m in 12 * years:
				sim.advance(30)
				for fid in st.sorted_fleet_ids():
					var f: Fleet = st.fleets[fid]
					if not Logistics.applies(st, f):
						continue
					samples["armed"] += 1
					var s := Logistics.status(st, f)
					if s == Logistics.OUT:
						samples["out"] += 1
					elif s == Logistics.CUT:
						samples["cut"] += 1
					if Logistics.exhausted(st, f):
						samples["ex"] += 1
			var ms := Time.get_ticks_msec() - t0
			var depots := 0
			for c: Colony in st.colonies.values():
				if c.buildings.has(Logistics.DEPOT):
					depots += 1
			var war_ships := 0
			for e in st.empires:
				for f in Fleets.empire_fleets(st, e.id):
					if Combat.is_warfleet(f):
						war_ships += f.ships.size()
			var a := maxi(1, int(samples["armed"]))
			print("graine %3d %-9s %5.1f ms/j | %3d batailles %3d invasions %d disparus %3d vaisseaux de guerre | hors zone %2d %% coupées %2d %% à sec %2d %% | %d coupures %d soutes vides %d réquisitions %d dépôts" % [
					sd, mode, float(ms) / (360.0 * years), n["battles"], n["captures"], n["dead"], war_ships,
					100 * int(samples["out"]) / a, 100 * int(samples["cut"]) / a, 100 * int(samples["ex"]) / a,
					n["cut"], n["dry"], n["req"], depots])
	quit()
