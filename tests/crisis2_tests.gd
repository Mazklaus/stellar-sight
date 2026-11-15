extends RefCounted
## Tests des crises de fin de partie, lot 2 (CrisisKinds) : Roi-Corsaire (dès l'an 15, hors « Une »,
## repaires ralliés, évasion, héritiers) ; pactes ; trêve sacrée ; Nuit lente (anneaux, production,
## Arches, Phare des Âges, étoiles qui se rallument) ; Grand Krach (contagion, inflation, commerce,
## Grande Dépression) ; mesures d'urgence ; convois ; armes du désespoir ; cicatrices ; sauvegarde.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Crises de fin de partie, lot 2…")
	_test_corsaire_roll()
	_test_corsaire()
	_test_pact()
	_test_truce()
	_test_night()
	_test_krach()
	_test_measures()
	_test_convoys_arms()
	_test_scars()
	_test_save()
	_test_menu_kinds()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 11, kinds: Array = [], extra := {}) -> GameState:
	var o := {"ai_level": "", "crises": "une", "crisis_kinds": kinds}
	o.merge(extra, true)
	return GameState.create(seed_value, 120, 1600.0, "vael", o)


func _force(st: GameState, k: String) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	Crisis.begin(st, k, added)
	var c := Crisis.cur(st)
	while String(c.get("stage", "")) == "notice":
		st.tick = int(c["steps"][int(c["step"])])
		Crisis._notice(st, added)
	return added


func _cards(st: GameState, eid: int, card: String) -> int:
	var n := 0
	for it: Dictionary in Events.inbox(st, eid):
		if String(it["card"]) == card:
			n += 1
	return n


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


func _test_corsaire_roll() -> void:
	var st := _new()
	_ok(Crisis.roll_day(st) == 5400, "le Roi-Corsaire peut se lever dès l'an 15 (fin de partie à l'an 30)")
	st.tick = 6000
	_ok(Crisis.eligible_kinds(st) == ["corsaire"], "avant la fin de partie, seul le Roi-Corsaire est possible")
	var added: Array[Dictionary] = []
	Crisis.begin(st, "corsaire", added)
	_ok(int(st.crisis["count"]) == 0, "une crise de milieu ne compte pas pour le réglage « Une »")
	var st2 := _new(11, ["recif"])
	_ok(Crisis.roll_day(st2) == 10800, "sans Roi-Corsaire autorisé, rien avant l'an 30")


func _test_corsaire() -> void:
	var st := _new(11, ["corsaire"], {"pirates": "normaux"})
	var lairs := Pirates.lair_ids(st)
	st.tick = 6000
	_force(st, "corsaire")
	_ok(Crisis.active(st), "la Horde arrive")
	var stations := 0
	var heart: Fleet = null
	for f in Crisis.stations(st):
		if Crisis.role_of(st, f.id) == Crisis.ROLE_HEART:
			heart = f
		else:
			stations += 1
	_ok(heart != null and stations >= 1, "le Trône flottant et ses Repaires de la Horde (%d)" % stations)
	var absorbed := 0
	for sid in lairs:
		if Pirates.guard_fleet(st, sid) == null:
			absorbed += 1
	_ok(lairs.is_empty() or absorbed >= 1, "les repaires ralliés ont rejoint la Horde (%d sur %d)" % [absorbed, lairs.size()])
	_ok(_cards(st, 0, "crise_pacte") == 1, "le Roi propose la soumission")
	# Évasion : le Trône tombe, le Roi s'enfuit vers un repaire.
	heart.ships.clear()
	var added: Array[Dictionary] = []
	st.tick += 1
	Crisis.on_battle(st, {"sides": [{"empire": 0, "engaged": {}, "lost": {}, "dealt": 50}, {"empire": GameState.CRISIS_ID, "engaged": {}, "lost": {}, "dealt": 5}]}, 0, added)
	var hearts := 0
	for f in Crisis.stations(st):
		if Crisis.role_of(st, f.id) == Crisis.ROLE_HEART:
			hearts += 1
	_ok(hearts == 1 and bool(Crisis.cur(st)["escaped"]) and Crisis.active(st), "il s'échappe une fois")
	for f in Crisis.stations(st):
		if Crisis.role_of(st, f.id) == Crisis.ROLE_HEART:
			f.ships.clear()
	st.tick += 1
	Crisis.on_battle(st, {"sides": [{"empire": 0, "engaged": {}, "lost": {}, "dealt": 50}, {"empire": GameState.CRISIS_ID, "engaged": {}, "lost": {}, "dealt": 5}]}, 0, added)
	Crisis._active_day(st, added)
	_ok(not Crisis.ongoing(st) and String((st.crisis["past"] as Array)[-1]["result"]) == "victoire", "pas deux fois : la Horde est vaincue")
	var guarded := 0
	for sid in Pirates.lair_ids(st):
		if Pirates.guard_fleet(st, sid) != null:
			guarded += 1
	_ok(guarded >= mini(1, lairs.size()), "ses lieutenants se partagent des repaires (%d gardés)" % guarded)


func _test_pact() -> void:
	var st := _new(11, ["inspection"])
	st.tick = 10800
	_force(st, "inspection")
	var added: Array[Dictionary] = []
	Crisis.card_fx(st, 0, {}, {"act": "front"}, added)
	Crisis.card_fx(st, 0, {}, {"act": "pact"}, added)
	_ok(Crisis.pacted(st, 0) and not Crisis.in_front(st, 0), "pacte : l'empire quitte le Front")
	var mem := false
	for m in st.memories:
		if int(m["about"]) == 0 and String(m["kind"]) == "crisis_pact":
			mem = true
	_ok(mem, "les autres empires retiennent le pacte")
	var parts := Crisis.stability_parts(st, 0)
	var stab := 0
	for p: Array in parts:
		stab += int(p[1])
	_ok(stab == -5, "factions hostiles : stabilité -5")
	Relics.touch(st)
	_ok(Research.fx_int(st, 0, "building_cost_pct") <= -15, "conformité : chantiers subventionnés")
	var sid := _colony(st, 0, 2, 6)
	var f: Fleet = Crisis.war_fleets(st)[0]
	f.system_id = sid
	f.path.clear()
	var t := Crisis._target(st, f)
	_ok(t < 0 or st.system_owner(t) != 0, "la crise épargne qui a pactisé")


func _test_truce() -> void:
	var st := _new(11, ["recif"])
	Combat.start_war(st, 0, 1)
	st.tick = 10800
	_force(st, "recif")
	var added: Array[Dictionary] = []
	Crisis.card_fx(st, 0, {}, {"act": "front"}, added)
	Crisis.card_fx(st, 1, {}, {"act": "front"}, added)
	_ok(not Combat.at_war(st, 0, 1), "trêve sacrée : leur guerre est gelée")
	Crisis.card_fx(st, 2, {}, {"act": "front"}, added)
	Combat.start_war(st, 2, 1)
	_ok(not Crisis.in_front(st, 2) and Combat.at_war(st, 2, 1), "rompre la trêve fait quitter le Front")
	var mem := false
	for m in st.memories:
		if int(m["about"]) == 2 and String(m["kind"]) == "truce_breaker":
			mem = true
	_ok(mem, "et la galaxie s'en souvient")


func _test_night() -> void:
	var st := _new(11, ["nuit"])
	st.tick = 10800
	_force(st, "nuit")
	var c := Crisis.cur(st)
	_ok(Crisis.active(st) and CrisisKinds.dark_count(st) == 1 and Crisis.war_fleets(st).is_empty(), "la Nuit lente : une étoile éteinte, aucune flotte")
	_ok(_cards(st, 0, "crise_arches") == 1, "fenêtre des Arches")
	var added: Array[Dictionary] = []
	st.tick = int(c["night_next"])
	CrisisKinds.fleetless_day(st, added)
	_ok(CrisisKinds.dark_count(st) > 1 and int(c["ring"]) == 1, "un an plus tard, un anneau de plus s'éteint (%d)" % CrisisKinds.dark_count(st))
	var dsid := int((c["dark"] as Dictionary).keys()[0])
	_ok(Crisis.production_pct(st, dsid) == 25 and Crisis.colony_block(st, dsid) != "", "étoile éteinte : production 25 %, pas de colonie")
	# Le Phare des Âges.
	var need := int(c["need"])
	st.empires[0].resources["energy"] = need + 500
	var n := 0
	while Crisis.active(st) and n < 200:
		_ok(CrisisKinds.check_fund(st, 0, "energy") == "", "verser au Phare") if n == 0 else null
		CrisisKinds.fund(st, 0, "energy", added)
		n += 1
	_ok(not Crisis.ongoing(st) and String((st.crisis["past"] as Array)[-1]["result"]) == "victoire" and int((st.crisis["past"] as Array)[-1]["by"]) == 0, "le Phare achevé : la Nuit vaincue, le trophée au plus grand donateur")
	var after := (st.crisis.get("dark_after", {}) as Dictionary).size()
	_ok(after >= 2, "les étoiles se rallumeront lentement (%d)" % after)
	st.tick = int(st.crisis["relight"])
	CrisisKinds.traces_day(st, added)
	_ok((st.crisis["dark_after"] as Dictionary).size() < after, "un anneau se rallume chaque année")


func _test_krach() -> void:
	var st := _new(11, ["krach"])
	st.trade["income"] = {0: {"energy": 40}, 1: {"energy": 10}}
	_ok(CrisisKinds.krach_origin(st) == 0, "le Krach part de l'empire le plus commerçant")
	st.tick = 10800
	_force(st, "krach")
	_ok(CrisisKinds.infected(st, 0) and not CrisisKinds.infected(st, 1), "il frappe d'abord cet empire")
	var inc := {0: {"energy": 40, "influence": 2}, 1: {"energy": 10}}
	CrisisKinds.adjust_trade_income(st, inc)
	_ok(int(inc[0]["energy"]) == 20 and int(inc[1]["energy"]) == 10, "commerce divisé par deux chez les touchés")
	var stab := 0
	for p: Array in Crisis.stability_parts(st, 0):
		stab += int(p[1])
	_ok(stab == -10, "chômage : stabilité -10")
	st.empires[0].resources["energy"] = 1000
	var added: Array[Dictionary] = []
	var month := int(GameData.rules()["month_days"])
	st.tick = (st.tick / month + 1) * month
	CrisisKinds.fleetless_day(st, added)
	_ok(int(st.empires[0].resources["energy"]) == 970, "inflation : -3 % des réserves d'énergie par mois")
	st.tick = int(Crisis.cur(st)["arrived"]) + 2160
	CrisisKinds.fleetless_day(st, added)
	_ok(not Crisis.ongoing(st) and String((st.crisis["past"] as Array)[-1]["result"]) == "depression", "six ans sans relance : la Grande Dépression")
	_ok(CrisisKinds.trade_pct(st, 0) == 75 and CrisisKinds.trade_pct(st, 1) == 100, "séquelles pour les touchés seulement")
	_ok(st.winner.is_empty(), "ce n'est pas une défaite commune")


func _test_measures() -> void:
	var st := _new(11, ["recif"])
	st.tick = 10800
	_force(st, "recif")
	var added: Array[Dictionary] = []
	st.tick = int(Crisis.cur(st)["arrived"]) + 60
	Crisis._measures(st, added)
	_ok(_cards(st, 0, "crise_mesure_1") == 1, "premier décret d'urgence")
	Crisis.card_fx(st, 0, {}, {"act": "measure", "label": "Économie de guerre", "fx": {"ship_days_pct": -25, "stability": -5}}, added)
	var b: Dictionary = Crisis.boons(st, 0)[-1]
	_ok(bool(b.get("end", false)) and int(b["fx"]["ship_days_pct"]) == -25, "décret valable jusqu'à la fin de la crise")
	var big := -1
	for e in st.empires:
		if CrisisKinds.is_big(st, e.id):
			big = e.id
	if big >= 0:
		Crisis.card_fx(st, big, {}, {"act": "measure", "label": "Test", "fx": {"stability": -5}}, added)
		_ok(int((Crisis.boons(st, big)[-1] as Dictionary)["fx"]["stability"]) == -8, "un grand empire en paie davantage")
	for f in Crisis.stations(st):
		f.ships.clear()
	st.tick += 1
	Crisis.on_battle(st, {"sides": [{"empire": 0, "engaged": {}, "lost": {}, "dealt": 50}, {"empire": GameState.CRISIS_ID, "engaged": {}, "lost": {}, "dealt": 5}]}, 0, added)
	Crisis._active_day(st, added)
	var left := 0
	for x: Dictionary in Crisis.boons(st, 0):
		if bool(x.get("end", false)):
			left += 1
	_ok(not Crisis.ongoing(st) and left == 0, "la crise finie, les décrets tombent")


func _test_convoys_arms() -> void:
	var st := _new(11, ["inspection"])
	st.tick = 10800
	_force(st, "inspection")
	var c := Crisis.cur(st)
	var added: Array[Dictionary] = []
	st.tick = int(c["arrived"]) + int(Crisis.data()["convoy"]["every_days"])
	CrisisKinds.convoys_day(st, added)
	_ok((c["convoys"] as Dictionary).size() == 1, "un convoi part d'un Bureau vers un autre")
	var fid := int((c["convoys"] as Dictionary).keys()[0])
	(st.fleets[fid] as Fleet).ships.clear()
	var mat := int(st.empires[1].resources.get("materials", 0))
	Crisis.on_battle(st, {"sides": [{"empire": 1, "engaged": {}, "lost": {}, "dealt": 50}, {"empire": GameState.CRISIS_ID, "engaged": {}, "lost": {}, "dealt": 5}]}, 1, added)
	_ok((c["convoys"] as Dictionary).is_empty() and int(st.empires[1].resources.get("materials", 0)) > mat, "convoi intercepté : butin pour qui l'a pris")
	Crisis.add_contrib(st, 1, 2000)
	CrisisKinds.arms_check(st, added)
	var arms := 0
	for b: Dictionary in Crisis.boons(st, 1):
		if bool(b.get("end", false)):
			arms += 1
	_ok(arms == 2, "armes du désespoir : deux armes nées des épaves")


func _test_scars() -> void:
	var st := _new(11, ["recif"])
	st.tick = 10800
	_force(st, "recif")
	var sid := _colony(st, 0, 2, 6)
	(Crisis.cur(st)["held"] as Dictionary)[sid] = {"since": st.tick, "seen": st.tick, "owner": 0}
	var added: Array[Dictionary] = []
	for f in Crisis.stations(st):
		f.ships.clear()
	st.tick += 1
	Crisis.on_battle(st, {"sides": [{"empire": 0, "engaged": {}, "lost": {}, "dealt": 50}, {"empire": GameState.CRISIS_ID, "engaged": {}, "lost": {}, "dealt": 5}]}, 0, added)
	Crisis._active_day(st, added)
	_ok(Crisis.production_pct(st, sid) == 70, "corail mort à déblayer : production 70 %")
	st.tick += 3601
	CrisisKinds.traces_day(st, added)
	_ok(Crisis.production_pct(st, sid) == 100, "dix ans plus tard, c'est oublié")


func _test_save() -> void:
	var sim := Simulation.new(_new(13, ["krach", "nuit", "inspection"]))
	var st := sim.state
	st.trade["income"] = {0: {"energy": 40}}
	st.tick = 10800
	_force(st, "nuit")
	var added: Array[Dictionary] = []
	Crisis.card_fx(st, 1, {}, {"act": "arks"}, added)
	Crisis.card_fx(st, 0, {}, {"act": "measure", "label": "T", "fx": {"stability": -1}}, added)
	st.empires[0].resources["energy"] = 500
	CrisisKinds.fund(st, 0, "energy", added)
	sim.advance(40)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_snapshot())))
	_ok(back != null and back.checksum() == st.checksum(), "sauvegarde relue, même empreinte (Nuit lente)")
	if back == null:
		return
	_ok(CrisisKinds.dark_count(back) == CrisisKinds.dark_count(st) and int(Crisis.cur(back)["fund"]) == int(Crisis.cur(st)["fund"]), "étoiles éteintes et chantier relus")
	var a := Simulation.new(st)
	var b := Simulation.new(back)
	a.advance(120)
	b.advance(120)
	_ok(a.state.checksum() == b.state.checksum(), "la partie reprise continue à l'identique")


func _test_menu_kinds() -> void:
	var m := MainMenu.new()
	m.set_crisis_kinds(["nuit", "krach", "inconnue"])
	_ok(",".join(m.crisis_kinds) == "krach,nuit", "menu : crises autorisées filtrées et triées")
	_ok(m.game_options()["crisis_kinds"] == ["krach", "nuit"], "menu : les crises autorisées passent aux règles")
	m.set_crisis_kinds(Crisis.kind_ids())
	_ok(m.crisis_kinds.is_empty(), "menu : toutes cochées = toutes")
	var st := GameState.create(5, 120, 1600.0, "vael", {"ai_level": "", "crises": "toutes", "crisis_kinds": ["nuit"]})
	_ok(st.crisis.get("kinds", []) == ["nuit"], "partie : seules les crises autorisées peuvent se lever")
	m.free()
