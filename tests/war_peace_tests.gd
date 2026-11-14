extends RefCounted
## Tests du pilier buts de guerre et traités de paix, lot 2 : occupation avant annexion, libération,
## revenu d'occupation, lassitude par camp, statu quo (accord, imposé, automatique), occupation totale,
## camps et chef de guerre (paix séparée, butin), traité à la carte étendu (clauses, exigences
## injustifiées), registre et violations, revanchisme, sauvegarde 54. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Buts de guerre, lot 2…")
	_test_occupation()
	_test_status_quo()
	_test_victory_occupation()
	_test_total_occupation()
	_test_exhaustion()
	_test_sides()
	_test_clauses()
	_test_violation()
	_test_revanche()
	_test_save()
	Wars.data()["claims"]["max_jumps"] = 4


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 7, opts := {}) -> GameState:
	Wars.data()["claims"]["max_jumps"] = 99
	var o := {"ai_level": "", "wargoals": "actifs", "occupation": "occupation", "vassals": "actifs"}
	o.merge(opts, true)
	var st := GameState.create(seed_value, 150, 1800.0, "vael", o)
	for e in st.empires:
		if e.is_npc():
			continue
		for x in st.empires:
			if x.id != e.id and not x.is_npc() and not e.contacts.has(x.id):
				e.contacts.append(x.id)
		e.resources["influence"] = 3000
		e.resources["energy"] = 5000
		e.resources["materials"] = 5000
		if e.id != 0:
			e.ai_level = "veteran"
		var cap := FactionTraits.capital_system(st, e.id)
		var dist := FactionTraits.jumps_from(st.galaxy, cap)
		var best := -1
		for sys in st.galaxy.systems:
			if sys.planet_ids.size() > 0 and st.system_owner(sys.id) == -1 and dist.has(sys.id) \
					and (best < 0 or int(dist[sys.id]) < int(dist[best])):
				best = sys.id
		if best >= 0:
			var c := Colony.new()
			c.planet_id = st.galaxy.get_system(best).planet_ids[0]
			c.owner = e.id
			c.kind = Colony.KIND_COLONY
			c.population = 3
			st.add_colony(c)
	return st


func _majors(st: GameState) -> Array[int]:
	var out: Array[int] = []
	for e in st.empires:
		if not e.is_npc() and not Diplomacy.no_treaties(st, e.id):
			out.append(e.id)
	return out


## Un système de b qui n'est pas sa capitale.
func _fief(st: GameState, b: int) -> int:
	var cap := FactionTraits.capital_system(st, b)
	for sid in EmpireReport.owned_systems(st, b):
		if sid != cap:
			return sid
	return -1


func _war(st: GameState, a: int, b: int, cid := "agression", gid := "humiliation") -> Dictionary:
	SimCommands.apply(st, SimCommands.declare_war(a, b, cid, gid))
	var rec := Wars.war(st, a, b)
	rec["t"] = st.tick - 200
	return rec


func _test_occupation() -> void:
	var st := _new()
	var ms := _majors(st)
	var a := ms[1]
	var b := ms[2]
	var sid := _fief(st, b)
	_war(st, a, b)
	# Invasion par l'ordre : la flotte débarque, le système est occupé, pas conquis.
	var f := st.spawn_ship(a, "corvette", sid)
	f.troops = 50
	st.garrisons[sid] = 0
	var cmd := SimCommands.invade(a, f.id)
	_ok(SimCommands.validate(st, cmd) == "", "Invasion possible (%s)" % SimCommands.validate(st, cmd))
	var inc_before: Dictionary = Economy.empire_income(st, b)["gross"]
	SimCommands.apply(st, cmd)
	_ok(WarPeace.occupier(st, sid) == a and st.system_owner(sid) == b, "Invasion : le système est occupé, il reste à son propriétaire")
	_ok(Combat.garrison(st, sid) == 0 and not Combat.is_besieged(st, sid), "Occupé : plus de garnison ni de siège")
	_ok(SimCommands.validate(st, SimCommands.invade(a, f.id)) != "", "On n'occupe pas deux fois")
	var inc_after: Dictionary = Economy.empire_income(st, b)["gross"]
	_ok(int(inc_after.get("materials", 0)) < int(inc_before.get("materials", 0)) or int(inc_after.get("energy", 0)) < int(inc_before.get("energy", 0)), "Occupé : le propriétaire perd la moitié de ce qu'il produit")
	var occ_inc := WarPeace.occupation_income(st, a)
	var tot := 0
	for r in occ_inc:
		tot += int(occ_inc[r])
	_ok(tot > 0, "L'occupant touche sa part (%s)" % [occ_inc])
	_ok(Wars.score_parts(st, a, b)["parts"].any(func(x: Array) -> bool: return String(x[0]) == "Systèmes pris"), "Le système occupé compte au score")
	# Libération : le propriétaire débarque des troupes, l'occupant n'a plus de flotte armée.
	st.fleets.erase(f.id)
	var g := st.spawn_ship(b, "corvette", sid)
	g.troops = 10
	var lc := SimCommands.invade(b, g.id)
	_ok(SimCommands.validate(st, lc) == "", "Le propriétaire peut libérer (%s)" % SimCommands.validate(st, lc))
	SimCommands.apply(st, lc)
	_ok(WarPeace.occupier(st, sid) == -1 and st.system_owner(sid) == b, "Libéré : le système revient à son propriétaire")
	# Option désactivée : conquête immédiate, comme avant.
	var st2 := _new(7, {"occupation": "immediate"})
	_war(st2, a, b)
	var f2 := st2.spawn_ship(a, "corvette", sid)
	f2.troops = 50
	st2.garrisons[sid] = 0
	SimCommands.apply(st2, SimCommands.invade(a, f2.id))
	_ok(st2.system_owner(sid) == a and WarPeace.occupier(st2, sid) == -1, "Conquête immédiate : le système change de main")


func _test_status_quo() -> void:
	var st := _new()
	var ms := _majors(st)
	var a := ms[1]
	var b := ms[2]
	var claimed := _fief(st, b)
	var other := -1
	# Un second système de b, sans revendication.
	for s in st.galaxy.systems:
		if s.planet_ids.size() > 0 and st.system_owner(s.id) == -1:
			var c := Colony.new()
			c.planet_id = s.planet_ids[0]
			c.owner = b
			c.kind = Colony.KIND_OUTPOST
			st.add_colony(c)
			other = s.id
			break
	Wars.claim(st, a, claimed)
	_war(st, a, b, "revendication", "conquete")
	WarPeace.invade(st, claimed, a)
	WarPeace.invade(st, other, a)
	Diplomacy.sign_treaty(st, a, b, Diplomacy.PEACE)
	_ok(st.system_owner(claimed) == a, "Statu quo : l'occupant garde le système qu'il revendique")
	_ok(st.system_owner(other) == b and WarPeace.occupier(st, other) == -1, "Statu quo : le reste revient")
	var reg := WarPeace.treaties_of(st, a)
	_ok(not reg.is_empty() and String(reg[0]["kind"]) == "statu quo" and String(reg[0]["name"]) != "", "Registre : la paix est inscrite (%s)" % (reg[0]["name"] if not reg.is_empty() else "?"))


func _test_victory_occupation() -> void:
	var st := _new()
	var ms := _majors(st)
	var a := ms[1]
	var b := ms[2]
	var sid := _fief(st, b)
	Wars.claim(st, a, sid)
	_war(st, a, b, "revendication", "conquete")
	Wars.on_battle(st, a, b, 100000)
	_ok(st.system_owner(sid) == b, "Sans occupation, le système revendiqué reste au propriétaire pendant la guerre")
	SimCommands.apply(st, SimCommands.war_act(a, "demand", b))
	_ok(not Combat.at_war(st, a, b) and st.system_owner(sid) == a, "Reddition : la propriété change au traité")
	var reg := WarPeace.treaties_of(st, b)
	_ok(not reg.is_empty() and int(reg[0]["w"]) == a and String(reg[0]["kind"]).begins_with("reddition"), "Registre : reddition inscrite au nom du vainqueur")


func _test_total_occupation() -> void:
	var st := _new()
	var ms := _majors(st)
	var a := ms[1]
	var b := ms[2]
	_war(st, a, b)
	for sid in EmpireReport.owned_systems(st, b):
		WarPeace.invade(st, sid, a)
	_ok(WarPeace._all_occupied(st, b), "Tous ses systèmes sont occupés")
	Wars.monthly(st)
	_ok(not Combat.at_war(st, a, b), "Occupation totale : reddition automatique")


func _test_exhaustion() -> void:
	var st := _new()
	var ms := _majors(st)
	var a := ms[1]
	var b := ms[2]
	var sid := _fief(st, b)
	Wars.claim(st, a, sid)
	var rec := _war(st, a, b, "revendication", "conquete")
	for i in 12:
		Wars.monthly(st)
	var ea := int(rec["ex"][0])
	var ed := int(rec["ex"][1])
	_ok(ea > ed and ed > 0, "Lassitude : l'agresseur qui conquiert se lasse plus vite que le défenseur (%d %% contre %d %%)" % [ea, ed])
	var before := int(rec["ex"][1])
	Wars.on_battle(st, a, b, int(rec["pw"][1]))
	_ok(int(rec["ex"][1]) > before, "Lassitude : les pertes pèsent (%d %% -> %d %%)" % [before, int(rec["ex"][1])])
	_ok(Stability.context(st, b) != null, "Stabilité calculée")
	rec["ex"][1] = 100
	_ok(WarPeace.stability_value(st, b) == -6, "Lassitude 100 % : stabilité -6")
	_ok(Wars.accept_parts(st, a, b)["parts"].any(func(x: Array) -> bool: return String(x[0]).begins_with("Sa lassitude")), "La lassitude pèse sur l'acceptation")
	Wars.monthly(st)
	_ok(int(rec["e100"][1]) >= 0, "Le jour des 100 % est noté")
	_ok(WarPeace.check_impose(st, a, b) != "", "Statu quo imposé : pas tout de suite")
	st.tick += 800
	rec["e100"][1] = st.tick - 400
	_ok(WarPeace.check_impose(st, a, b) == "", "Statu quo imposable un an après ses 100 %")
	SimCommands.apply(st, SimCommands.war_act(a, "status", b))
	_ok(not Combat.at_war(st, a, b), "Statu quo imposé : la paix")
	# Les deux à 100 % depuis un an : paix automatique.
	var st2 := _new()
	st2.tick += 800
	var r2 := _war(st2, a, b)
	r2["ex"] = [100, 100]
	r2["e100"] = [st2.tick - 400, st2.tick - 400]
	Wars.monthly(st2)
	_ok(not Combat.at_war(st2, a, b), "Deux camps épuisés depuis un an : statu quo automatique")


func _test_sides() -> void:
	var st := _new()
	var ms := _majors(st)
	var a := ms[1]
	var b := ms[2]
	var ally := ms[3]
	Diplomacy.sign_treaty(st, a, ally, Diplomacy.PEACE)
	Diplomacy.sign_treaty(st, a, ally, Diplomacy.ALLIANCE)
	_war(st, a, b)
	var r := Wars.war(st, ally, b)
	_ok(Combat.at_war(st, ally, b) and not r.is_empty() and String(r.get("lead", "")) == Diplomacy.key(a, b) and int(r.get("chief", -1)) == a, "L'allié entre en guerre dans le camp de son chef")
	r["t"] = st.tick - 200
	Wars.on_battle(st, ally, b, 100000)
	_ok(Wars.check_demand(st, ally, b).contains("chefs"), "L'allié ne négocie pas seul")
	_ok(WarPeace.check_separate(st, ally, b) == "", "Paix séparée possible")
	var inf := int(st.get_empire(ally).resources["influence"])
	SimCommands.apply(st, SimCommands.war_act(ally, "separate", b))
	_ok(not Combat.at_war(st, ally, b) and Combat.at_war(st, a, b) and int(st.get_empire(ally).resources["influence"]) == inf - 50, "Paix séparée : l'allié paie et sort, le chef continue")
	var found := false
	for m in st.memories:
		if int(m["who"]) == a and int(m["about"]) == ally and String(m["kind"]) == "separate_peace":
			found = true
	_ok(found, "Paix séparée : le chef s'en souvient")
	# La paix du chef vaut pour son camp ; butin de l'allié qui tient ses revendications.
	var st2 := _new()
	Diplomacy.sign_treaty(st2, a, ally, Diplomacy.PEACE)
	Diplomacy.sign_treaty(st2, a, ally, Diplomacy.ALLIANCE)
	var sid := _fief(st2, b)
	Wars.claim(st2, ally, sid)
	_war(st2, a, b)
	WarPeace.invade(st2, sid, ally)
	Wars.war(st2, ally, b)["t"] = st2.tick - 200
	Wars.on_battle(st2, a, b, 100000)
	Wars.apply_victory(st2, a, b)
	_ok(not Combat.at_war(st2, ally, b), "Victoire du chef : la guerre de l'allié finit aussi")
	_ok(st2.system_owner(sid) == ally, "Butin : l'allié reçoit la revendication qu'il occupait")


func _test_clauses() -> void:
	var st := _new()
	var ms := _majors(st)
	var a := ms[1]
	var b := ms[2]
	_war(st, a, b, "agression", "humiliation")
	var just := Vassals.price(st, b, {"dmz": true}, a)
	var unj := Vassals.price(st, b, {"koinon": true} if Koinon.league_of(st, b) >= 0 else {"pass": true}, a)
	_ok(just == 15, "Zone démilitarisée justifiée par l'humiliation : prix 15 (%d)" % just)
	_ok(unj == 2 * (20 if Koinon.league_of(st, b) >= 0 else 10), "Exigence injustifiée : prix doublé (%d)" % unj)
	_ok(Vassals.check_terms_set(st, a, b, {"dmz": true, "fleet": true}) == "", "Clauses du traité étendu acceptées")
	_ok(Vassals.check_terms_set(st, a, b, {"koinon": true}) != "" or Koinon.league_of(st, b) >= 0, "Sortie du Koinon : seulement s'il en a un")
	Wars.on_battle(st, a, b, 100000)
	Vassals.apply_terms(st, a, b, {"dmz": true, "fleet": true, "pass": true})
	_ok(not Combat.at_war(st, a, b), "Conditions acceptées : la paix")
	var reg := WarPeace.treaties_of(st, b)
	_ok(not reg.is_empty() and String(reg[0]["kind"]) == "conditions" and (reg[0]["cl"] as Dictionary).has("dmz") and (reg[0]["cl"] as Dictionary).has("fleet"), "Registre : clauses et échéances")
	_ok(not WarPeace.clause_active(st, a, b, "dmz").is_empty(), "Zone démilitarisée en vigueur")
	var capped := WarPeace.fleet_capped(st, b)
	_ok(capped == (Vassals.power_pct(st, b, a) > 50), "Limite de flotte : selon le rapport de forces (%d %%)" % Vassals.power_pct(st, b, a))
	var found := false
	for m in st.memories:
		if int(m["who"]) == b and int(m["about"]) == a and String(m["kind"]) == "unjust_demand":
			found = true
	_ok(found, "Exigence injustifiée (passage) : le vaincu s'en souvient")


func _test_violation() -> void:
	var st := _new()
	var ms := _majors(st)
	var a := ms[1]
	var b := ms[2]
	_war(st, a, b)
	Wars.data()["treaty"]["dmz_jumps"] = 99  # galaxie de test : voisins éloignés
	Vassals.apply_terms(st, a, b, {"dmz": true})
	Wars.data()["treaty"]["dmz_jumps"] = 2
	var t: Dictionary = WarPeace.treaties_of(st, b)[0]
	var zone: Array = t["dmz"]
	_ok(not zone.is_empty(), "Zone démilitarisée : %d systèmes" % zone.size())
	if zone.is_empty():
		return
	st.spawn_ship(b, "corvette", int(zone[0]))
	WarPeace.monthly(st)
	_ok(int(t["cl"]["dmz"]) == -2, "Flotte en zone démilitarisée : clause violée")
	_ok(Wars.casus_list(st, a, b).has("represailles"), "Violation : la victime gagne le motif Représailles")


func _test_revanche() -> void:
	var st := _new()
	var ms := _majors(st)
	var a := ms[1]
	var b := ms[2]
	var sid := _fief(st, b)
	Wars.claim(st, a, sid)
	_war(st, a, b, "revendication", "conquete")
	var g0 := Combat.garrison_max(st, FactionTraits.capital_system(st, b))
	var p0 := Economy.production_pct(st, b, "materials")
	Wars.on_battle(st, a, b, 100000)
	Wars.apply_victory(st, a, b)
	var rp := WarPeace.revanche_pct(st, b)
	_ok(rp > 0 and rp <= 20, "Revanchisme : bonus après cession (%d %%)" % rp)
	_ok(Economy.production_pct(st, b, "materials") > p0, "Revanchisme : production en hausse")
	_ok(Combat.garrison_max(st, FactionTraits.capital_system(st, b)) >= g0, "Revanchisme : garnisons renforcées")
	st.tick += 5 * GameCalendar.DAYS_PER_YEAR
	_ok(WarPeace.revanche_pct(st, b) < rp, "Revanchisme : il s'estompe avec les années")


func _test_save() -> void:
	var st := _new()
	var ms := _majors(st)
	var a := ms[1]
	var b := ms[2]
	_war(st, a, b)
	WarPeace.invade(st, _fief(st, b), a)
	var ms2 := ms[3]
	_war(st, a, ms2)
	Vassals.apply_terms(st, a, ms2, {"dmz": true})
	var d: Dictionary = JSON.parse_string(JSON.stringify(st.to_snapshot()))
	_ok(int(d["version"]) >= 54, "Sauvegarde : version 54 ou plus")
	var back := GameState.from_dict(d)
	_ok(WarPeace.occ_on(back) and WarPeace.occupier(back, _fief(st, b)) == a, "Sauvegarde : occupation gardée")
	_ok(WarPeace.treaties_of(back, ms2).size() == WarPeace.treaties_of(st, ms2).size(), "Sauvegarde : registre gardé")
	_ok(back.checksum() == st.checksum(), "Sauvegarde : même empreinte après relecture")
