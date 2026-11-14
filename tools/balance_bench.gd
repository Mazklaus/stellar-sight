extends SceneTree
## Équilibre des peuples entre IA : une partie par graine, une ligne JSON par graine (systèmes tenus
## par an, année de disparition, vainqueur). Fait pour être lancé en parallèle puis agrégé :
##   SEEDS=1,2,3 YEARS=25 godot --headless --path . -s res://tools/balance_bench.gd
##   python3 tools/balance_report.py fichier.jsonl
## Variables : SEEDS, YEARS (défaut 25), LEVEL (défaut normal), TEMPER (défaut normal),
## PIRATES (densité des repaires : aucun par défaut, rares, normaux, infestes), POLITICS (politique
## intérieure : aucune par défaut, active), PEOPLES (peuples mêlés : aucuns par défaut, actifs),
## AMPH (Amphictyonie : aucune par défaut, active), VICTORIES (« diplo » : sans conquête ni domination,
## pour régler la victoire diplomatique sur de longues parties).
## SPECIES : peuples créés à ajouter aux 4 officiels (éditeur d'espèces), séparés par des virgules :
## chemin d'un fichier de peuple (user://species/p_x.json ou chemin absolu) ou « preset:<officiel> »
## (peuple créé depuis le modèle d'un officiel). Banc court d'un peuple créé, cibles de l'étude
## d'équilibrage : gagner 10 à 45 % des parties, mourir avant l'an 10 dans moins de 25 % :
##   SPECIES=user://species/p_x.json SEEDS=1,2,...,24 godot --headless --path . -s res://tools/balance_bench.gd


func _initialize() -> void:
	var years := int(OS.get_environment("YEARS")) if OS.get_environment("YEARS") != "" else 25
	var level := OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "normal"
	var temper := OS.get_environment("TEMPER") if OS.get_environment("TEMPER") != "" else "normal"
	var seeds := [3, 17, 99]
	if OS.get_environment("SEEDS") != "":
		seeds = Array(OS.get_environment("SEEDS").split(",")).map(func(s: String) -> int: return int(s))
	var rivals := GameData.faction_ids()
	for entry in OS.get_environment("SPECIES").split(",", false):
		var spec := {}
		if entry.begins_with("preset:"):
			spec = Species.from_preset(entry.substr(7))
			spec["name"] = "Copie de " + entry.substr(7)
			spec["short"] = spec["name"].substr(0, 16)
			spec["id"] = Species.make_id(spec["name"], rivals)
		else:
			spec = SpeciesLibrary.read_file(entry)
		var err := "fichier illisible" if spec.is_empty() else Species.check(spec)
		if err != "":
			printerr("Peuple refusé (%s) : %s" % [entry, err])
			quit(1)
			return
		GameData.register_library_faction(Species.build(spec))
		rivals.append(String(spec["id"]))
	for sd in seeds:
		var st := GameState.create(sd, 150, 1800.0, "", {"spectator": true, "ai_level": level, "temperament": temper, "rivals": rivals,
				"pirates": OS.get_environment("PIRATES") if OS.get_environment("PIRATES") != "" else "aucun",
				"politics": OS.get_environment("POLITICS") if OS.get_environment("POLITICS") != "" else "aucune",
				"peoples": OS.get_environment("PEOPLES") if OS.get_environment("PEOPLES") != "" else "aucuns",
				"faiths": OS.get_environment("FAITHS") if OS.get_environment("FAITHS") != "" else "aucunes",
				"amphictyony": OS.get_environment("AMPH") if OS.get_environment("AMPH") != "" else "aucune",
				"victories": {"conquete": false, "domination": false} if OS.get_environment("VICTORIES") == "diplo" else {}})
		var sim := Simulation.new(st)
		var rows := {}
		for e in st.empires:
			rows[e.id] = {"faction": e.faction_id, "systems": [], "dead": -1, "first_war": -1, "pop": 0}
		var t0 := Time.get_ticks_msec()
		var amph_years := []
		var y := 0
		while y < years and st.winner.is_empty():
			sim.advance(360)
			y += 1
			for e in st.empires:
				var r: Dictionary = rows[e.id]
				r["systems"].append(0 if e.eliminated else Victory.systems_held(st, e.id))
				if e.eliminated and int(r["dead"]) < 0:
					r["dead"] = y
					var taker := st.get_empire(st.system_owner(st.galaxy.get_planet(e.home_planet).system_id))
					r["killer"] = taker.faction_id if taker != null else ""
				if int(r["first_war"]) < 0 and not e.wars.is_empty():
					r["first_war"] = y
			if st.amph_on and Amphictyony.founded(st):
				var smax := 0
				for k in st.amph["share"]:
					smax = maxi(smax, int(st.amph["share"][k]))
				amph_years.append({"y": y, "m": Amphictyony.members(st).size(), "cov": AmphPower.coverage(st), "share": smax, "imp": AmphPower.imperator(st),
						"auth": AmphPower.authority(st), "life": AmphPower.life(st), "dip": (st.amph["dip"] as Dictionary).duplicate(), "chan": AmphPower.chan_on(st)})
		for e in st.empires:
			rows[e.id]["pop"] = 0 if e.eliminated else int(EmpireReport.totals(st, e.id)["population"])
			if st.peoples_on and not e.eliminated:
				rows[e.id]["peoples"] = Peoples.empire_counts(st, e.id)
				var founded := 0
				for pid in st.sorted_colony_ids():
					var c: Colony = st.colonies[pid]
					if c.owner == e.id and not c.species.is_empty() and Peoples.own_count(c) == 0:
						founded += 1
				rows[e.id]["foreign_worlds"] = founded
		if st.faith_on:
			for e in st.empires:
				if not e.eliminated:
					rows[e.id]["faith"] = Faiths.name_of(st, Faiths.state_faith(st, e.id))
		var out := {"seed": sd, "years": y, "ms": Time.get_ticks_msec() - t0, "empires": rows.values()}
		if st.faith_on:
			var fl := []
			for fid in Faiths.ids(st):
				var f := Faiths.faith(st, fid)
				fl.append({"name": Faiths.name_of(st, fid), "founder": st.get_empire(int(f["founder"])).faction_id, "via": String(f["via"]),
						"founded_year": int(f["founded"]) / 360, "followers": Faiths.followers(st, fid), "precepts": f["precepts"], "doctrines": f["doctrines"],
						"zeal": FaithWars.zeal(st, fid), "nature": FaithWars.nature(st, fid), "parent": Faiths.parent_of(st, fid),
						"schism_of": String(f.get("schism_of", ""))})
			out["faiths"] = fl
			var holy := 0
			for w in FaithWars._holy_wars(st):
				holy += 1
			var je := 0
			for k in st.faiths["je"]:
				if not String(k).begins_with("block:"):
					je += 1
			out["faith_lot2"] = {"missions": FaithWars._missions(st).size(), "holy_wars": holy, "crusades": st.faiths["crusades"].size(),
					"seen": st.faiths["seen"].size(), "prophecies": st.faiths["prophecies"].size(), "je": je, "demands": st.faiths["demands"].size()}
		if st.amph_on:
			var fams := {}
			for r in Amphictyony.active(st):
				fams[String(r["fam"])] = int(r["v"])
			var passed := 0
			for h in st.amph["hist"]:
				if bool(h["pass"]):
					passed += 1
			out["amph"] = {"founded_year": int(st.amph["founded"]) / 360 if Amphictyony.founded(st) else -1, "members": Amphictyony.members(st).size(),
					"resolutions": fams, "outlaws": Amphictyony.outlaws(st).size(), "hist": (st.amph["hist"] as Array).size(), "passed": passed,
					"queue": (st.amph["queue"] as Array).size(), "council": AmphInst.councillors(st).size(), "arbiter": AmphInst.arbiter(st),
					"works": (st.amph["done"] as Array).size(), "work_on": AmphInst.work_on(st), "coal": AmphInst.coal_on(st), "special": AmphInst.special_on(st),
					"observers": AmphInst.observers(st).size(), "favors": (st.amph["favors"] as Dictionary).size(), "aid": (st.amph["aid"] as Dictionary).size(),
					"trig": (st.amph["trig"] as Array).size(), "years": amph_years}
		if not st.winner.is_empty():
			var w := st.winner
			out["winner"] = {"faction": st.get_empire(int(w["empire"])).faction_id, "victory": String(w["victory"]),
					"year": int(w["tick"]) / 360, "allies": w.get("allies", [])}
		print("BENCH " + JSON.stringify(out))
	quit()
