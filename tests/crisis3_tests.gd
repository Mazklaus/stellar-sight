extends RefCounted
## Tests des crises de fin de partie, lot 3 : talents par couche d'espèce (CrisisAllies), gardiens qui
## chassent la crise et faune qui fuit, héros (Commandant du Front, Tueur de crise, Vétéran du Front,
## gouverneur enlevé), Devenir la crise (CrisisNemesis : Menace, paliers, guerre de tous, grand œuvre,
## voie brisée), sauvegarde. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Crises de fin de partie, lot 3…")
	_test_talents()
	_test_talent_effects()
	_test_foresight()
	_test_guardians()
	_test_heroes()
	_test_nemesis()
	_test_nemesis_broken()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(faction := "vael", kinds: Array = [], extra := {}, seed_value := 11) -> GameState:
	var o := {"ai_level": "", "crises": "une", "crisis_kinds": kinds}
	o.merge(extra, true)
	return GameState.create(seed_value, 120, 1600.0, faction, o)


func _force(st: GameState, k: String) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	Crisis.begin(st, k, added)
	var c := Crisis.cur(st)
	while String(c.get("stage", "")) == "notice":
		st.tick = int(c["steps"][int(c["step"])])
		Crisis._notice(st, added)
	return added


func _colony(st: GameState, owner: int, min_j := 2, pop := 6) -> int:
	var cap := FactionTraits.capital_system(st, owner)
	var jumps := FactionTraits.jumps_from(st.galaxy, cap)
	for s in st.galaxy.systems:
		if st.system_owner(s.id) < 0 and s.planet_ids.size() > 0 and int(jumps.get(s.id, 99)) >= min_j and int(jumps.get(s.id, 99)) <= 5 \
				and Fleets.fleets_at(st, s.id).is_empty():
			var c := Colony.new()
			c.planet_id = s.planet_ids[0]
			c.owner = owner
			c.kind = Colony.KIND_COLONY
			c.population = pop
			st.add_colony(c)
			return s.id
	return -1


func _ids(l: Array) -> String:
	var out := PackedStringArray()
	for t: Dictionary in l:
		out.append(String(t["id"]))
	return ",".join(out)


func _test_talents() -> void:
	var expect := {"teyl": "protocole", "khthari": "sourds_chant", "choeur": "presage_faille", "brisecomete": "amortisseurs",
			"ossarane": "pavillon_noir", "ferrocornes": "pavillon_noir", "murmurants": "veilleurs", "vael": ""}
	for f in expect:
		var st := _new(String(f))
		_ok(_ids(CrisisAllies.talents_of(st, 0)) == String(expect[f]), "talent de crise de %s : %s" % [f, expect[f] if expect[f] != "" else "aucun"])
	var st2 := _new("teyl")
	_ok(CrisisAllies.tal(st2, 0, "fine_pct") == 0, "sans crise, aucun talent ne joue")


func _test_talent_effects() -> void:
	# Synthétiques face à l'Inspection : pacte sans souvenir ni stabilité.
	var st := _new("teyl", ["inspection"])
	st.tick = 10800
	_force(st, "inspection")
	_ok(CrisisAllies.tal(st, 0, "fine_pct") == -50, "Protocole commun : amendes divisées par deux")
	var added: Array[Dictionary] = []
	Crisis.card_fx(st, 0, {}, {"act": "pact"}, added)
	var mem := false
	for m in st.memories:
		if int(m["about"]) == 0 and String(m["kind"]) == "crisis_pact":
			mem = true
	var stab := 0
	for p: Array in Crisis.stability_parts(st, 0):
		stab += int(p[1])
	_ok(Crisis.pacted(st, 0) and not mem and stab == 0, "se mettre en conformité ne coûte rien aux machines")
	# Ruche face au Récif : production à mi-chemin.
	var st2 := _new("khthari", ["recif"])
	st2.tick = 10800
	_force(st2, "recif")
	var sid := _colony(st2, 0, 2, 6)
	(Crisis.cur(st2)["held"] as Dictionary)[sid] = {"since": st2.tick, "seen": st2.tick, "owner": 0}
	_ok(Crisis.production_pct(st2, sid) == 65, "Sourds au chant : un monde englouti produit à 65 % au lieu de 30 (%d)" % Crisis.production_pct(st2, sid))
	# Marchands face au Krach.
	var st3 := _new("brisecomete", ["krach"])
	st3.trade["income"] = {0: {"energy": 40}}
	st3.tick = 10800
	_force(st3, "krach")
	_ok(CrisisKinds.trade_pct(st3, 0) == 75, "Amortisseurs : le commerce ne perd qu'un quart")
	st3.empires[0].resources["energy"] = 1000
	var month := int(GameData.rules()["month_days"])
	st3.tick = (st3.tick / month + 1) * month
	CrisisKinds.fleetless_day(st3, added)
	_ok(int(st3.empires[0].resources["energy"]) == 990, "Amortisseurs : inflation de 1 % au lieu de 3 (%d)" % int(st3.empires[0].resources["energy"]))
	# Peuples d'énergie et Phare des Âges.
	var st4 := _new("murmurants", ["nuit"])
	st4.tick = 10800
	_force(st4, "nuit")
	st4.empires[0].resources["energy"] = 500
	CrisisKinds.fund(st4, 0, "energy", added)
	_ok(int(Crisis.cur(st4)["fund"]) == 200, "Veilleurs du ciel : un versement compte double")
	# Féodaux et Roi-Corsaire : tribut divisé par deux.
	var st5 := _new("ossarane", ["corsaire"], {"pirates": "normaux"})
	st5.tick = 6000
	_force(st5, "corsaire")
	Crisis.card_fx(st5, 0, {}, {"act": "pact"}, added)
	st5.empires[0].resources["energy"] = 1000
	st5.tick = (st5.tick / month + 1) * month
	CrisisKinds.pacts_day(st5, added)
	_ok(int(st5.empires[0].resources["energy"]) == 950, "Tentés par le pavillon noir : tribut de 5 % (%d)" % int(st5.empires[0].resources["energy"]))


func _test_foresight() -> void:
	var st := _new("choeur", ["dechirure"])
	st.tick = 10800
	var added: Array[Dictionary] = []
	Crisis.begin(st, "dechirure", added)
	var c := Crisis.cur(st)
	_ok(String(c["stage"]) == "notice" and (c.get("seers", []) as Array).has(0), "les mystiques sentent la Déchirure")
	_ok(Crisis.known(st, 0) and not Crisis.known(st, 1), "un présage pour eux seuls")
	var omen := 0
	for it: Dictionary in Events.inbox(st, 0):
		if String(it["card"]) == "crise_alerte_1":
			omen += 1
	var other := 0
	for it: Dictionary in Events.inbox(st, 1):
		if String(it["card"]) == "crise_alerte_1":
			other += 1
	_ok(omen == 1 and other == 0, "fenêtre de présage chez les mystiques, rien chez les autres")
	st.tick += 359
	Crisis._notice(st, added)
	_ok(not Crisis.active(st), "la Faille attend son heure")
	st.tick += 1
	Crisis._notice(st, added)
	_ok(Crisis.active(st) and Crisis.known(st, 1), "un an plus tard, elle s'ouvre pour tous")
	var st2 := _new("vael", ["dechirure"], {"rivals": ["ossarane", "khthari", "teyl"]})
	st2.tick = 10800
	Crisis.begin(st2, "dechirure", added)
	_ok(Crisis.active(st2), "sans mystiques, la Déchirure s'ouvre d'un coup")


func _test_guardians() -> void:
	var st := _new("vael", ["recif"], {"creatures": "normales"})
	var gids := Guardians.ids(st)
	var gid := ""
	for g in gids:
		var gd := Guardians.def(g)
		if String(Guardians.list(st)[g]["status"]) == "awake" and not bool(gd.get("pacific", false)) and not bool(gd.get("sun_eater", false)):
			gid = g
			break
	_ok(gid != "", "un gardien éveillé dans la partie (%s)" % gid)
	if gid == "":
		return
	st.tick = 10800
	_force(st, "recif")
	var gf: Fleet = st.fleets[int(Guardians.list(st)[gid]["fleet"])]
	_ok(Fauna.hostile(st, gf, GameState.CRISIS_ID), "les gardiens se battent contre la crise")
	# Une flotte de la crise s'approche de sa tanière.
	var home := int(Guardians.list(st)[gid]["sid"])
	var near := -1
	for n in st.galaxy.systems[home].neighbors:
		near = int(n)
		break
	var f: Fleet = Crisis.war_fleets(st)[0]
	f.system_id = near
	f.path.clear()
	var added: Array[Dictionary] = []
	st.tick = (st.tick / 10 + 1) * 10
	CrisisAllies.fauna_day(st, added)
	_ok(gf.is_moving() or gf.system_id == near, "le gardien sort de sa tanière et fond sur elle")
	# Un troupeau fuit.
	var herds := Fauna.herd_ids(st)
	if not herds.is_empty():
		var h: Fleet = st.fleets[herds[0]]
		h.path.clear()
		var hs := h.system_id
		f.system_id = hs
		st.tick += 10
		CrisisAllies.fauna_day(st, added)
		_ok(h.is_moving() or h.system_id != hs, "la faune fuit devant la crise")
		_ok(not Fauna.hostile(st, h, GameState.CRISIS_ID), "les troupeaux ne l'affrontent pas")


func _test_heroes() -> void:
	var st := _new("vael", ["inspection"])
	st.tick = 10800
	_force(st, "inspection")
	var hid := Heroes.recruit(st, 0, Heroes.make_candidate(st, 0, "stratege", ["crise"]))
	_ok(Heroes.check_assign(st, 0, hid, "front", 0) != "", "Commandant du Front : il faut être du Front")
	var added: Array[Dictionary] = []
	Crisis.card_fx(st, 0, {}, {"act": "front"}, added)
	_ok(Heroes.check_assign(st, 0, hid, "front", 0) == "", "membre du Front : le poste s'ouvre")
	Heroes.assign(st, 0, hid, "front", 0)
	st.tick = int(st.heroes[hid]["arrive"])
	var sid := FactionTraits.capital_system(st, 0)
	var mine := st.spawn_ship(0, "corvette", sid)
	var foe := Crisis.war_fleets(st)[0]
	foe.system_id = sid
	foe.path.clear()
	var base := int(Crisis.data()["front"]["damage_pct"])
	_ok(Crisis.damage_pct(st, mine, sid) > base, "le Commandant du Front ajoute ses dégâts contre la crise (%d)" % Crisis.damage_pct(st, mine, sid))
	# Tueur de crise : l'amiral présent quand un Bureau tombe.
	var hid2 := Heroes.recruit(st, 0, Heroes.make_candidate(st, 0, "stratege", ["tueur"]))
	Heroes.assign(st, 0, hid2, "fleet", mine.id)
	st.heroes[hid2]["arrive"] = st.tick
	var b := {"fleets": [[mine.id]], "sides": [{"empire": 0, "engaged": {}, "lost": {}, "dealt": 50}, {"empire": GameState.CRISIS_ID, "engaged": {}, "lost": {}, "dealt": 5}]}
	var station: Fleet = null
	for s in Crisis.stations(st):
		if Crisis.role_of(st, s.id) == Crisis.ROLE_STATION:
			station = s
			break
	station.ships.clear()
	Crisis.on_battle(st, b, 0, added)
	_ok((st.heroes[hid2]["traits"] as Array).has("tueur_crise"), "l'amiral gagne « Tueur de crise »")
	_ok(Heroes.trait_fx(st.heroes[hid2], "crisis_damage_pct") == 20, "+20 % contre les crises")
	# Gouverneur enlevé par l'Inspection.
	var col_sid := _colony(st, 0, 2, 6)
	var hid3 := Heroes.recruit(st, 0, Heroes.make_candidate(st, 0, "intendant", ["gouv"]))
	Heroes.assign(st, 0, hid3, "system", col_sid)
	st.heroes[hid3]["arrive"] = st.tick
	Crisis.fall(st, col_sid, added)
	var h3: Dictionary = st.heroes[hid3]
	_ok(String(h3["post"]) == "" and (Heroes.is_wounded(st, h3) or Heroes.is_prisoner(h3)), "le gouverneur est « convoqué » par l'Inspection")
	# Victoire : les vétérans.
	for _round in 3:  # les Bureaux, puis le Registre central
		if not Crisis.ongoing(st):
			break
		for s in Crisis.stations(st):
			s.ships.clear()
		st.tick += 1
		Crisis.on_battle(st, b, 0, added)
		Crisis._active_day(st, added)
	_ok(not Crisis.ongoing(st) and (st.heroes[hid2]["traits"] as Array).has("veteran_front"), "à la victoire, les amiraux qui ont combattu deviennent Vétérans du Front")


func _test_nemesis() -> void:
	var st := _new("vael", ["recif"], {"crisis_nemesis": true})
	_ok(CrisisNemesis.enabled(st) and CrisisNemesis.who(st) < 0, "Devenir la crise : option en jeu")
	_ok(CrisisNemesis.check_ambition(st, 0) != "", "pas avant l'an 10")
	st.tick = 3600
	_ok(CrisisNemesis.check_ambition(st, 0) == "", "dès l'an 10, la voie est ouverte")
	var added: Array[Dictionary] = []
	CrisisNemesis.take(st, 0, added)
	_ok(CrisisNemesis.check_ambition(st, 1) != "", "un seul empire à la fois")
	Research.count_stat(st, 0, "conquests", 10)
	_ok(CrisisNemesis.tier(st) == 1, "conquêtes : premier palier (%d de Menace)" % int(CrisisNemesis.nem(st)["menace"]))
	Relics.touch(st)
	_ok(Research.fx_int(st, 0, "damage_pct") >= 5, "Ambition démesurée : +5 % de dégâts")
	Crisis.on_atrocity(st, 0)
	Research.count_stat(st, 0, "conquests", 13)
	_ok(CrisisNemesis.tier(st) == 2, "deuxième palier : Ombre sur la galaxie")
	var mem := false
	for m in st.memories:
		if int(m["about"]) == 0 and String(m["kind"]) == "nemesis":
			mem = true
	_ok(mem, "les autres empires s'en souviennent")
	Research.count_stat(st, 0, "conquests", 30)
	_ok(CrisisNemesis.is_scourge(st, 0), "dernier palier : le Fléau des étoiles")
	var all_war := true
	for e in st.empires:
		if e.id != 0 and not e.eliminated and not Combat.at_war(st, e.id, 0):
			all_war = false
	_ok(all_war, "point de non-retour : toute la galaxie lui déclare la guerre")
	_ok(Diplomacy.check_terms(st, 1, 0, Diplomacy.PEACE) != "", "on ne fait pas la paix avec le Fléau")
	var sid := FactionTraits.capital_system(st, 0)
	var mine := st.spawn_ship(0, "corvette", sid)
	var theirs := st.spawn_ship(1, "corvette", sid)
	_ok(Crisis.damage_pct(st, theirs, sid) == 10 and Crisis.damage_pct(st, mine, sid) == 0, "les autres le frappent 10 % plus fort")
	var need := int(CrisisNemesis.nem(st)["need"])
	st.empires[0].resources["energy"] = need + 1000
	var n := 0
	while st.winner.is_empty() and n < 100:
		_ok(CrisisNemesis.check_oeuvre(st, 0, "energy") == "", "verser au grand œuvre") if n == 0 else null
		CrisisNemesis.fund(st, 0, "energy", added)
		n += 1
	_ok(String(st.winner.get("victory", "")) == "fleau" and int(st.winner["empire"]) == 0, "le grand œuvre achevé : victoire du Fléau")
	_ok(Victory.label("fleau") == "Victoire du Fléau", "libellé de la victoire")


func _test_nemesis_broken() -> void:
	var st := _new("vael", ["recif"], {"crisis_nemesis": true})
	st.tick = 3600
	var added: Array[Dictionary] = []
	CrisisNemesis.take(st, 1, added)
	Research.count_stat(st, 1, "conquests", 12)
	_ok(CrisisNemesis.tier(st) == 1, "une IA prend la voie")
	var e := st.empires[1]
	var col: Colony = st.colonies[e.capital_planet]
	col.owner = 0
	st.rebuild_ownership()
	CrisisNemesis.daily(st, added)
	_ok(CrisisNemesis.who(st) < 0 and CrisisNemesis.check_ambition(st, 1) != "", "capitale perdue : la voie est brisée, pour toujours")
	_ok(CrisisNemesis.check_ambition(st, 2) == "", "un autre peut la prendre")
	var off := _new("vael", ["recif"])
	_ok(not CrisisNemesis.enabled(off), "sans l'option, pas de voie")


func _test_save() -> void:
	var sim := Simulation.new(_new("choeur", ["dechirure"], {"crisis_nemesis": true, "creatures": "normales"}, 13))
	var st := sim.state
	st.tick = 10800
	var added: Array[Dictionary] = []
	Crisis.begin(st, "dechirure", added)
	CrisisNemesis.take(st, 1, added)
	Research.count_stat(st, 1, "conquests", 12)
	sim.advance(400)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_snapshot())))
	_ok(back != null and back.checksum() == st.checksum(), "sauvegarde relue, même empreinte (présage, Fléau)")
	if back == null:
		return
	_ok(CrisisNemesis.who(back) == 1 and CrisisNemesis.tier(back) == CrisisNemesis.tier(st), "voie de l'Ambition relue")
	var a := Simulation.new(st)
	var b := Simulation.new(back)
	a.advance(120)
	b.advance(120)
	_ok(a.state.checksum() == b.state.checksum(), "la partie reprise continue à l'identique")
