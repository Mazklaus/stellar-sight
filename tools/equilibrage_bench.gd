extends SceneTree
## Banc de l'étude d'équilibrage : une partie entre IA avec les réglages du menu (comme long_game),
## une ligne JSON par an et par empire (systèmes, population, exploration, flottes, score, technos),
## les jalons d'exploration (jour où chaque empire connaît 25/50/75/100 % de la carte, premier contact),
## la géométrie de la galaxie, la Menace du Fléau et la première victoire. La partie continue après.
## Repères par peuple, par an ("kpi") : mois de famine, de panne, d'Exaltation, de dissidence, repérages du
## peuple voilé, lignes de chronique reçues, tours de 30 jours où il s'est passé quelque chose ("turns")
## et tours qui ont offert une décision ("decisions" : technologie, vaisseau, colonie, flotte arrivée,
## événement, proposition) ; avancée
## de chaque victoire ("victory") et jour où chaque condition a été remplie ("met" en fin de partie).
##   SEED=3 YEARS=20 OUT=x.jsonl godot --headless --path . -s res://tools/equilibrage_bench.gd
## Variables : SEED, YEARS (20), LEVEL, SIZE (taille de galaxie du menu), STOP_ON_WIN=1,
## DISTANCES (proches, normales, vastes), TURN (tour par tour : jours par tour, 30 ou 10).

func _env_int(n: String, d: int) -> int:
	var v := OS.get_environment(n)
	return int(v) if v != "" else d


func _kpi(kpi: Dictionary, id: int) -> Dictionary:
	if not kpi.has(id):
		kpi[id] = {"starving": 0, "blackout": 0, "exalted": 0, "dissent": 0, "spotted": 0, "lines": 0, "turns": 0, "decisions": 0}
	return kpi[id]


func _emit(out: FileAccess, row: Dictionary) -> void:
	if out != null:
		out.store_line(JSON.stringify(row))
		out.flush()


func _initialize() -> void:
	var seed_value := _env_int("SEED", 3)
	var years := _env_int("YEARS", 20)
	var out: FileAccess = null
	if OS.get_environment("OUT") != "":
		out = FileAccess.open(OS.get_environment("OUT"), FileAccess.WRITE)
	var menu := MainMenu.new()
	menu.slots = MainMenu.default_slots()
	menu.spectator = true
	# EMPIRES=n (moins de huit) : n peuples tirés au hasard parmi les huit principaux, avec la graine
	# (étude d'équilibrage, F5 et F7). empire_setup("") n'a pas de joueur : n places, n empires.
	var n_env := _env_int("EMPIRES", 0)
	if n_env > 0 and n_env < menu.slots.size():
		menu.insolites_mode = "aucun"
		menu.slots = []
		for _i in n_env:
			menu.slots.append(MainMenu.new_slot(MainMenu.RANDOM_FACTION))
	# INSOLITE=<peuple> REPLACE=<0 à 7> : le peuple insolite prend la place d'un des huit principaux
	# (étude d'équilibrage, H2 : un banc par insolite, à tour de rôle à la place de chacun).
	var ins_env := OS.get_environment("INSOLITE")
	if ins_env != "" and not GameData.faction(ins_env).is_empty():
		menu.slots[posmod(_env_int("REPLACE", 0), menu.slots.size())]["faction"] = ins_env
	if OS.get_environment("LEVEL") != "":
		menu.ai_level = OS.get_environment("LEVEL")
	if OS.get_environment("SIZE") != "":
		menu.galaxy_settings["size"] = OS.get_environment("SIZE")
	var opts := {"ai_level": menu.ai_level, "temperament": menu.temperament, "spectator": true,
		"deadline": 0, "people_victories": true}
	opts.merge(menu.empire_setup("", seed_value), true)
	opts.merge(menu.game_options(), true)
	opts["galaxy"] = menu.galaxy_settings.duplicate()
	if OS.get_environment("DISTANCES") != "":
		opts["galaxy"]["distances"] = OS.get_environment("DISTANCES")
	if OS.get_environment("TURN") != "":
		opts["turn_days"] = _env_int("TURN", 0)
	menu.free()
	var st := GameState.create(seed_value, 150, 1800.0, "", opts)
	var g := st.galaxy
	var n_emp := st.empires.size()
	var n_sys := g.systems.size()
	# Géométrie : longueur des routes, sauts et distance entre mondes d'origine.
	var lanes: Array = []
	for ln in g.lanes:
		lanes.append(Fleets.lane_length(g, ln.x, ln.y))
	lanes.sort()
	var homes := []
	for e in st.empires:
		homes.append(g.get_planet(e.home_planet).system_id if e.home_planet >= 0 else -1)
	var facs := []
	for e in st.empires:
		facs.append({"id": e.id, "faction": e.faction_id, "home": homes[e.id] if e.id < homes.size() else -1})
	_emit(out, {"type": "start", "seed": seed_value, "systems": n_sys, "lanes": lanes, "empires": facs, "galaxy": opts["galaxy"]})
	var events: Array = []
	var systems := Simulation.daily_systems(events)
	var marks := {}
	var contact := {}
	var win_logged := false
	# Repères par peuple (B9), cumulés sur l'année : mois de famine, d'Exaltation (ferveur >= 60), de dissidence,
	# jours où le peuple voilé a été repéré, lignes de chronique reçues, tours de 30 jours avec au moins une ligne.
	var kpi := {}
	var last_spot := {}
	var turn_seen := {}
	var dec_sig := {}
	var met := {}
	for y in years:
		var t0 := Time.get_ticks_msec()
		for d in 360:
			st.tick += 1
			st.log_cache.clear()
			events.clear()
			for s in systems:
				s[1].call(st)
			for ev in events:
				if not (ev is Dictionary):
					continue
				for e in st.empires:
					if ev.has("who") and not (e.id in ev["who"]):
						continue
					_kpi(kpi, e.id)["lines"] += 1
					turn_seen[e.id] = true
			for e in st.empires:
				if e.spotted_tick != int(last_spot.get(e.id, -1)):
					last_spot[e.id] = e.spotted_tick
					_kpi(kpi, e.id)["spotted"] += 1
			if st.tick % 30 == 0:
				for e in st.empires:
					if e.eliminated:
						continue
					var k := _kpi(kpi, e.id)
					k["starving"] += 1 if e.starving else 0
					k["blackout"] += 1 if e.blackout else 0
					k["exalted"] += 1 if e.fervor >= 60 else 0
					k["dissent"] += 1 if e.dissent else 0
					k["turns"] += 1 if turn_seen.has(e.id) else 0
					# Repère « jamais deux tours vides » (C3) : le mois a-t-il offert une décision ? Technologie
					# finie, vaisseau sorti des chantiers, colonie de plus, flotte arrivée, événement ou proposition.
					var built := 0
					for sb in e.ships_built.values():
						built += int(sb)
					var arrived := 0
					for f in Fleets.empire_fleets(st, e.id):
						if not f.is_moving():
							arrived += f.id * 1000 + f.system_id
					var props := 0
					for p in st.proposals:
						if int(p["to"]) == e.id:
							props += 1
					var sig := [e.techs.size(), built, Victory.systems_held(st, e.id), arrived, Events.inbox(st, e.id).size(), props]
					if dec_sig.has(e.id) and dec_sig[e.id] != sig:
						k["decisions"] += 1
					dec_sig[e.id] = sig
					for vid in e.victory:
						var mk := "%d:%s" % [e.id, vid]
						if int(e.victory[vid].get("pct", 0)) >= 100 and not met.has(mk):
							met[mk] = st.tick
				turn_seen.clear()
			if st.tick % 10 == 0:
				for e in st.empires:
					if e.eliminated:
						continue
					var pct := e.explored.size() * 100 / n_sys
					for m in [25, 50, 75, 100]:
						var k := "%d:%d" % [e.id, m]
						if pct >= m and not marks.has(k):
							marks[k] = st.tick
					if not e.contacts.is_empty() and not contact.has(e.id):
						contact[e.id] = st.tick
			while n_emp < st.empires.size():
				var ne: Empire = st.empires[n_emp]
				var last: Array = []
				for ci in range(maxi(0, st.chronicle.size() - 5), st.chronicle.size()):
					last.append(String(st.chronicle[ci]["text"]))
				_emit(out, {"type": "born", "tick": st.tick, "id": ne.id, "faction": ne.faction_id, "name": ne.display_name(),
					"sys": Victory.systems_held(st, ne.id), "chronicle": last})
				n_emp += 1
			if not win_logged and not st.winner.is_empty():
				win_logged = true
				_emit(out, {"type": "win", "tick": st.tick, "winner": st.winner,
					"faction": st.get_empire(int(st.winner["empire"])).faction_id})
				if _env_int("STOP_ON_WIN", 0) == 1:
					break
		var rows := []
		for e in st.empires:
			if e.eliminated:
				rows.append({"id": e.id, "dead": true})
				continue
			var tot := EmpireReport.totals(st, e.id)
			var ships := 0
			var fleets := 0
			for f in st.fleets.values():
				if f.owner == e.id:
					fleets += 1
					ships += f.ships.size()
			var allies := 0
			for o in st.empires:
				if o.id != e.id and not o.eliminated and Diplomacy.allied(st, e.id, o.id):
					allies += 1
			var vic := {}
			for vid in e.victory:
				vic[vid] = int(e.victory[vid].get("pct", 0))
			rows.append({"id": e.id, "kpi": _kpi(kpi, e.id).duplicate(), "allies": allies, "victory": vic, "sys": Victory.systems_held(st, e.id), "pop": int(tot.get("population", 0)),
				"expl": e.explored.size(), "surv": e.surveyed.size(), "score": Victory.score(st, e.id), "techs": e.techs.size(),
				"warships": Diplomacy.warships(st, e.id), "ships": ships, "fleets": fleets, "wars": e.wars.size(),
				"contacts": e.contacts.size(), "res": e.resources.duplicate()})
		kpi.clear()
		var nm := {}
		if CrisisNemesis.enabled(st) and CrisisNemesis.who(st) >= 0:
			nm = {"who": CrisisNemesis.who(st), "menace": int(CrisisNemesis.nem(st).get("menace", 0)), "tier": CrisisNemesis.tier(st),
				"conq": (CrisisNemesis.nem(st).get("conq", []) as Array).size(), "since": int(CrisisNemesis.nem(st).get("since", 0))}
		var megas_n := 0
		var megas_ruins := 0
		for m: Dictionary in Megastructures.all_sorted(st):
			if Megastructures.is_ruin(m):
				megas_ruins += 1
			else:
				megas_n += 1
		_emit(out, {"type": "year", "year": y + 1, "ms_per_day": (Time.get_ticks_msec() - t0) / 360.0,
			"colonies": st.colonies.size(), "fleets": st.fleets.size(), "empires": rows, "nemesis": nm,
			"megas": megas_n, "mega_ruins": megas_ruins})
		if win_logged and _env_int("STOP_ON_WIN", 0) == 1:
			break
	_emit(out, {"type": "end", "tick": st.tick, "marks": marks, "contact": contact, "met": met, "winner": st.winner})
	quit()
