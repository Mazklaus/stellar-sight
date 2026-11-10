extends SceneTree
## Récit de la chute des empires entre IA, sans rien changer aux règles : pour chaque graine, la
## géographie de départ de chaque peuple (position, routes, voisins, territoire naturel), un relevé
## mensuel (systèmes, puissance de flotte, matériaux, cristaux, dissidence, guerres) et les
## événements (guerres, sièges de la capitale, batailles, disparition et preneur de la capitale).
## Une ligne JSON par graine (« FALL {...} »), lue par tools/fall_report.py.
##   SEEDS=1,2,3 YEARS=12 godot --headless --path . -s res://tools/fall_bench.gd
## Variables : SEEDS, YEARS (défaut 12), LEVEL (défaut normal), TEMPER (défaut normal).


func _initialize() -> void:
	var years := int(OS.get_environment("YEARS")) if OS.get_environment("YEARS") != "" else 12
	var level := OS.get_environment("LEVEL") if OS.get_environment("LEVEL") != "" else "normal"
	var temper := OS.get_environment("TEMPER") if OS.get_environment("TEMPER") != "" else "normal"
	var seeds := [3, 17, 99]
	if OS.get_environment("SEEDS") != "":
		seeds = Array(OS.get_environment("SEEDS").split(",")).map(func(s: String) -> int: return int(s))
	for sd in seeds:
		_run(int(sd), years, level, temper)
	quit()


func _run(sd: int, years: int, level: String, temper: String) -> void:
	var st := GameState.create(sd, 150, 1800.0, "", {"spectator": true, "ai_level": level, "temperament": temper})
	var sim := Simulation.new(st)
	var rows := {}
	var homes := {}
	for e in st.empires:
		homes[e.id] = st.galaxy.get_planet(e.home_planet).system_id
	for e in st.empires:
		rows[e.id] = {"id": e.id, "faction": e.faction_id, "geo": _geo(st, e.id, homes), "months": [],
				"events": [], "dead": -1, "killer": "", "home_lost": -1}
	var cap_sys := homes.duplicate()
	sim.combat_event.connect(func(ev: Dictionary) -> void: _on_event(st, rows, cap_sys, ev))
	var met := {}
	sim.chronicle_added.connect(func(_entry: Dictionary) -> void: _on_contacts(st, rows, homes, met))
	var prev_wars := {}
	for e in st.empires:
		prev_wars[e.id] = []
	var m := 0
	while m < years * 12 and st.winner.is_empty():
		sim.advance(30)
		m += 1
		for e in st.empires:
			var r: Dictionary = rows[e.id]
			if e.eliminated:
				if int(r["dead"]) < 0:
					r["dead"] = m
					var taker := st.get_empire(st.system_owner(int(homes[e.id])))
					r["killer"] = taker.faction_id if taker != null else ""
				continue
			if int(r["home_lost"]) < 0 and st.system_owner(int(homes[e.id])) != e.id:
				r["home_lost"] = m
				var t2 := st.get_empire(st.system_owner(int(homes[e.id])))
				r["events"].append({"m": m, "k": "home_lost", "by": t2.faction_id if t2 != null else ""})
			if e.capital_planet >= 0:
				cap_sys[e.id] = st.galaxy.get_planet(e.capital_planet).system_id
			for w in e.wars:
				if not (prev_wars[e.id] as Array).has(w):
					r["events"].append({"m": m, "k": "war", "with": st.get_empire(w).faction_id,
							"pw_me": _power(st, e.id), "pw_them": _power(st, w),
							"sys_me": Victory.systems_held(st, e.id), "sys_them": Victory.systems_held(st, w)})
			for w in prev_wars[e.id]:
				if not e.wars.has(w):
					r["events"].append({"m": m, "k": "peace", "with": st.get_empire(w).faction_id})
			prev_wars[e.id] = e.wars.duplicate()
			r["months"].append(_sample(st, e))
	var out := {"seed": sd, "months": m, "empires": rows.values()}
	if not st.winner.is_empty():
		out["winner"] = {"faction": st.get_empire(int(st.winner["empire"])).faction_id,
				"victory": String(st.winner["victory"]), "month": int(st.winner["tick"]) / 30}
	print("FALL " + JSON.stringify(out))


func _on_event(st: GameState, rows: Dictionary, cap_sys: Dictionary, ev: Dictionary) -> void:
	var m := st.tick / 30
	match String(ev["type"]):
		"siege_started":
			var owner := int(ev["owner"])
			if rows.has(owner) and int(ev["system"]) == int(cap_sys[owner]):
				rows[owner]["events"].append({"m": m, "k": "cap_siege", "by": st.get_empire(int(ev["by"])).faction_id})
		"battle_ended":
			var rep: Dictionary = ev["report"]
			var sides: Array = rep["sides"]
			var names := []
			for s: Dictionary in sides:
				names.append(st.get_empire(int(s["empire"])).faction_id)
			for s: Dictionary in sides:
				var me := int(s["empire"])
				var w := int(rep["winner"])
				rows[me]["events"].append({"m": m, "k": "battle", "sides": names,
						"res": "draw" if w < 0 else ("win" if w == me else "loss"),
						"lost": Combat.count_ships(s["lost"]), "engaged": Combat.count_ships(s["engaged"]),
						"home": st.system_owner(int(rep.get("system", -1))) == me if rep.has("system") else false})


## Premiers contacts : pour chaque nouvelle paire, ce que chacun voit de l'autre (flottes et leur
## éloignement de leur origine, ou systèmes), pour savoir qui est allé chercher qui.
func _on_contacts(st: GameState, rows: Dictionary, homes: Dictionary, met: Dictionary) -> void:
	for e in st.empires:
		for o in e.contacts:
			var key := "%d-%d" % [mini(e.id, o), maxi(e.id, o)]
			if met.has(key):
				continue
			met[key] = true
			for pair in [[e.id, int(o)], [int(o), e.id]]:
				var a: int = pair[0]
				var b: int = pair[1]
				var seen: Dictionary = st.seen_cache[a] if a < st.seen_cache.size() else {}
				var fleets := []
				for f in Fleets.empire_fleets(st, b):
					var vc := Fleets.vision_center(st, f)
					if seen.has(vc):
						fleets.append({"ships": f.ships.duplicate(), "from_home": int(FactionTraits.jumps_from(st.galaxy, int(homes[b])).get(vc, -1)),
								"to_seer": int(FactionTraits.jumps_from(st.galaxy, int(homes[a])).get(vc, -1))})
				var systems := 0
				for sid in seen:
					if st.system_owner(sid) == b:
						systems += 1
				rows[a]["events"].append({"m": st.tick / 30, "d": st.tick, "k": "contact", "with": st.get_empire(b).faction_id,
						"fleets": fleets, "systems": systems})


static func _power(st: GameState, empire_id: int) -> int:
	var p := 0
	for f in Fleets.empire_fleets(st, empire_id):
		if Combat.is_warfleet(f):
			p += Combat.fleet_power(f)
	return p


static func _sample(st: GameState, e: Empire) -> Dictionary:
	var wars := []
	for w in e.wars:
		wars.append(st.get_empire(w).faction_id)
	var cap := st.galaxy.get_planet(e.capital_planet).system_id if e.capital_planet >= 0 else -1
	return {"sys": Victory.systems_held(st, e.id), "pw": _power(st, e.id),
			"mat": int(e.resources.get("materials", 0)), "cry": int(e.resources.get("crystals", 0)),
			"inf": int(e.resources.get("influence", 0)), "dis": e.dissent, "wars": wars,
			"gar": Combat.garrison(st, cap) if cap >= 0 else 0, "techs": e.techs.size()}


## Géographie de départ : distance au centre (0 = centre, 1 = bord), routes du système d'origine,
## sauts jusqu'aux autres capitales, et « territoire naturel » : systèmes à ≤6 sauts strictement plus
## proches de notre origine que de toute autre (Voronoï en sauts).
static func _geo(st: GameState, empire_id: int, homes: Dictionary) -> Dictionary:
	var g := st.galaxy
	var h := int(homes[empire_id])
	var mine := FactionTraits.jumps_from(g, h).duplicate()
	var others := {}
	var jumps := {}
	for oid in homes:
		if int(oid) == empire_id:
			continue
		var d := FactionTraits.jumps_from(g, int(homes[oid])).duplicate()
		others[oid] = d
		jumps[st.get_empire(int(oid)).faction_id] = int(d.get(h, 999))
	var natural := 0
	var contested := 0
	for sid in mine:
		var dm := int(mine[sid])
		if dm > 6:
			continue
		var best := 999
		for oid in others:
			best = mini(best, int(others[oid].get(sid, 999)))
		if dm < best:
			natural += 1
		elif dm == best:
			contested += 1
	var maxr := 0.0
	for s in g.systems:
		maxr = maxf(maxr, s.position.length())
	return {"center": snappedf(g.systems[h].position.length() / maxf(1.0, maxr), 0.01),
			"lanes": g.systems[h].neighbors.size(), "jumps": jumps, "natural": natural, "contested": contested,
			"planets": g.systems[h].planet_count}
