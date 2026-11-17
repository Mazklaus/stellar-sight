extends RefCounted
## Tests des merveilles galactiques, lot 1 (étude du 2026-11-15) : catalogue en données, modes de
## partie, vraie course (avance, mensualités, achèvement, perte et report de mise), grand chantier à
## part (un à la fois), contributions des colonies, presser le dernier quart, sites, visibilité par
## quarts, effets, sauvegarde, IA. Appelés par smoke_test.gd.

var _check: Callable

const W := "arche_semenciere"


func run(check: Callable) -> void:
	_check = check
	print("Merveilles galactiques (course et chantier)…")
	_test_data()
	_test_modes()
	_test_start()
	_test_progress()
	_test_race()
	_test_contribute()
	_test_rush()
	_test_effects()
	_test_visibility()
	_test_save()
	_test_ai()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(seed_value := 11, extra := {}) -> GameState:
	var o := {"ai_level": "", "wonders": "toutes"}
	o.merge(extra, true)
	return GameState.create(seed_value, 120, 1600.0, "vael", o)


static func rich(st: GameState, eid: int) -> void:
	for r in ["materials", "energy", "influence", "crystals", "food", "knowledge"]:
		st.get_empire(eid).resources[r] = 100000


static func apply(st: GameState, cmd: Dictionary) -> String:
	var why := SimCommands.validate(st, cmd)
	if why == "":
		SimCommands.apply(st, cmd)
	return why


static func days(st: GameState, n: int) -> void:
	for i in n:
		st.tick += 1
		Wonders.daily(st)


func _test_data() -> void:
	var ids := Wonders.all_ids()
	_ok(ids.size() >= 45, "catalogue en données (%d merveilles)" % ids.size())
	var fams := {}
	for wid in ids:
		fams[Wonders.family(wid)] = true
		_ok(GameData.building(wid).get("label", "") != "", "GameData.building retrouve %s" % wid)
	for f in ["galactique", "mega", "registre", "credo"]:
		_ok(fams.has(f), "famille %s présente" % f)
	_ok(not GameData.buildings().has("assemblee"), "les merveilles ont quitté buildings.json")
	_ok(Wonders.galaxy_unique("assemblee") and not Wonders.galaxy_unique("porte_stellaire"), "galactique unique, mégastructure par empire")


func _test_modes() -> void:
	var off := new_game(11, {"wonders": "aucune"})
	_ok(not Wonders.enabled(off), "mode Aucune : pas de merveilles")
	Research.grant(off, 0, ["administration"])
	rich(off, 0)
	_ok(SimCommands.validate(off, SimCommands.won_act(0, "start", W, off.get_empire(0).capital_planet)) != "", "lancement refusé sans merveilles")
	var dr := new_game(11, {"wonders": "tirage"})
	var n := 0
	for wid in Wonders.all_ids():
		if Wonders.in_pool(dr, wid):
			n += 1
	_ok(n > 0 and n < Wonders.all_ids().size(), "mode Tirage : une partie du catalogue (%d sur %d)" % [n, Wonders.all_ids().size()])
	var a := new_game(11, {"wonders": "tirage"})
	_ok(JSON.stringify(a.wonders.get("pool", [])) == JSON.stringify(dr.wonders.get("pool", [])), "même graine, même tirage")


func _test_start() -> void:
	var st := new_game()
	var home := st.get_empire(0).capital_planet
	rich(st, 0)
	_ok(SimCommands.validate(st, SimCommands.won_act(0, "start", W, home)).contains("technologie"), "il faut sa technologie")
	Research.grant(st, 0, ["administration"])
	var m0 := int(st.get_empire(0).resources["materials"])
	var adv := Wonders.advance_cost(st, 0, W)
	_ok(int(adv["materials"]) == int(Wonders.total_cost(st, 0, W)["materials"]) * 20 / 100, "avance de 20 %")
	_ok(apply(st, SimCommands.won_act(0, "start", W, home)) == "", "Arche semencière lancée sur la capitale")
	_ok(int(st.get_empire(0).resources["materials"]) == m0 - int(adv["materials"]), "l'avance est payée")
	var c: Colony = st.colonies[home]
	_ok(c.construction == "", "le chantier n'occupe pas la file de la colonie")
	Research.grant(st, 0, ["capteurs", "cales_rapides"])
	var why := Wonders.check_start(st, 0, home, "phare_premiere_route")
	_ok(why.contains("chantier") or why.contains("il faut"), "un grand chantier à la fois, ou site refusé (%s)" % why)
	var other := -1
	for pid in st.sorted_colony_ids():
		if pid != home and st.colonies[pid].owner == 0:
			other = pid
	if other >= 0:
		_ok(Wonders.check_start(st, 0, other, "arche_semenciere") != "", "pas deux chantiers de la même merveille")
	var e := st.get_empire(0)
	_ok(Wonders.max_builds(st, 0) == 1, "un seul grand chantier au départ")
	e.resources["materials"] = 0
	_ok(Wonders.check_start(st, 1, st.get_empire(1).capital_planet, W) != "", "un rival sans la technologie ne peut pas")


func _test_progress() -> void:
	var st := new_game()
	var home := st.get_empire(0).capital_planet
	rich(st, 0)
	Research.grant(st, 0, ["administration"])
	apply(st, SimCommands.won_act(0, "start", W, home))
	var entry := Wonders.build_of(st, 0, W)
	var paid0 := int(entry["paid"].get("materials", 0))
	days(st, 40)
	_ok(int(entry["pts"]) >= 100 * 35, "le chantier avance chaque jour (%d pts)" % int(entry["pts"]))
	_ok(int(entry["paid"].get("materials", 0)) > paid0, "une mensualité est versée")
	st.get_empire(0).resources["materials"] = 0
	st.get_empire(0).resources["energy"] = 0
	var pts := int(entry["pts"])
	days(st, 60)
	_ok(int(entry["pts"]) < pts + 100 * 60, "sans de quoi payer la mensualité, il ralentit ou s'arrête")
	rich(st, 0)
	days(st, int(Wonders.def(W)["days"]) + 60)
	_ok(Wonders.build_of(st, 0, W).is_empty(), "chantier achevé")
	_ok(st.colonies[home].buildings.has(W), "la merveille est bâtie dans la colonie")
	_ok(Wonders.owned(st, 0).has(W), "l'empire la tient")


func _test_race() -> void:
	var st := new_game()
	rich(st, 0)
	rich(st, 1)
	Research.grant(st, 0, ["administration"])
	Research.grant(st, 1, ["administration"])
	var h0 := st.get_empire(0).capital_planet
	var h1 := st.get_empire(1).capital_planet
	_ok(apply(st, SimCommands.won_act(0, "start", W, h0)) == "", "premier empire dans la course")
	_ok(apply(st, SimCommands.won_act(1, "start", W, h1)) == "", "un rival se lance aussi : vraie course")
	var added: Array[Dictionary] = []
	Wonders.complete(st, W, 0, added)
	_ok(Wonders.builds_of(st, W).is_empty(), "le premier qui achève emporte la course")
	var carry: Dictionary = st.wonders.get("carry", {}).get("1", {})
	_ok(not carry.is_empty() and int(carry["amt"].get("materials", 0)) > 0, "le perdant garde sa mise")
	_ok(SimCommands.validate(st, SimCommands.won_act(1, "start", W, h1)).contains("bâtie"), "il ne peut plus la lancer")
	Research.grant(st, 1, ["capteurs", "cales_rapides", "senseurs_gravitationnels", "logistique", "conscription_planetaire"])
	var alt := "champ_mars"
	var a_full := Wonders.total_cost(st, 1, alt)
	var a_adv := Wonders.advance_cost(st, 1, alt)
	_ok(int(a_adv.get("materials", 0)) < int(a_full["materials"]) * 20 / 100, "la mise se reporte sur une merveille d'ère égale ou plus haute")
	st.tick += int(Wonders.r_int("carry_days")) + 10
	days(st, 31)
	_ok(st.wonders.get("carry", {}).get("1", {}).is_empty(), "passé le délai, la moitié revient et le report s'éteint")


func _test_contribute() -> void:
	var st := new_game()
	rich(st, 0)
	Research.grant(st, 0, ["administration"])
	var home := st.get_empire(0).capital_planet
	apply(st, SimCommands.won_act(0, "start", W, home))
	var near := -1
	for p in st.galaxy.planets:
		if p.system_id == st.galaxy.get_planet(home).system_id and p.id != home and not st.colonies.has(p.id):
			near = p.id
			break
	if near < 0:
		_ok(true, "pas de planète libre près de la capitale (contribution sautée)")
		return
	var c := Colony.new()
	c.planet_id = near
	c.owner = 0
	c.kind = Colony.KIND_COLONY
	c.population = 3
	st.colonies[near] = c
	_ok(SimCommands.validate(st, SimCommands.won_act(0, "contribute", W, home)) != "", "la colonie du chantier ne verse pas")
	var pts := int(Wonders.build_of(st, 0, W)["pts"])
	var why := apply(st, SimCommands.won_act(0, "contribute", W, near))
	_ok(why == "", "une colonie proche verse (%s)" % why)
	_ok(int(Wonders.build_of(st, 0, W)["pts"]) > pts, "le chantier avance d'autant")
	_ok(SimCommands.validate(st, SimCommands.won_act(0, "contribute", W, near)).contains("mois"), "une fois par mois")


func _test_rush() -> void:
	var st := new_game()
	rich(st, 0)
	Research.grant(st, 0, ["administration"])
	var home := st.get_empire(0).capital_planet
	apply(st, SimCommands.won_act(0, "start", W, home))
	_ok(SimCommands.validate(st, SimCommands.won_act(0, "rush", W)).contains("dernier quart"), "presser : seulement le dernier quart")
	var entry := Wonders.build_of(st, 0, W)
	entry["pts"] = int(entry["need"]) * 80 / 100
	var inf := int(st.get_empire(0).resources["influence"])
	var cost := Wonders.rush_cost(st, 0, W)
	_ok(apply(st, SimCommands.won_act(0, "rush", W)) == "", "dernier quart pressé")
	_ok(int(st.get_empire(0).resources["influence"]) == inf - cost, "contre de l'influence (%d)" % cost)
	days(st, 2)
	_ok(st.colonies[home].buildings.has(W), "la merveille s'achève")


func _test_effects() -> void:
	var st := new_game()
	rich(st, 0)
	Research.grant(st, 0, ["administration"])
	var before := Research.fx_int(st, 0, "colony_start_pop")
	var added: Array[Dictionary] = []
	apply(st, SimCommands.won_act(0, "start", W, st.get_empire(0).capital_planet))
	Wonders.complete(st, W, 0, added)
	st.relic_rev += 1
	_ok(Research.fx_int(st, 0, "colony_start_pop") > before, "ses effets s'appliquent à l'empire")
	_ok(Culture.wonder_value(st, 0, W) > 0, "toute merveille rayonne un peu")
	var card := false
	for it in added:
		card = card or String(it.get("card", "")) == "wonder_done"
	_ok(card or added.size() > 0, "l'achèvement est annoncé")


func _test_visibility() -> void:
	var st := new_game()
	rich(st, 0)
	rich(st, 1)
	Research.grant(st, 0, ["administration"])
	Research.grant(st, 1, ["administration"])
	apply(st, SimCommands.won_act(1, "start", W, st.get_empire(1).capital_planet))
	var e := Wonders.build_of(st, 1, W)
	e["pts"] = int(e["need"]) * 55 / 100
	_ok(Wonders.quarter(e) == 2, "un chantier à 55 %% se lit au 2e quart")
	var vis := Fleets.visible_systems(st, 0)
	var sid := st.galaxy.get_planet(st.get_empire(1).capital_planet).system_id
	_ok(Wonders.knows(st, 0, 1, W) == vis.has(sid), "on ne connaît un chantier rival que s'il est en vue (ou espionné)")


func _test_save() -> void:
	var st := new_game()
	rich(st, 0)
	Research.grant(st, 0, ["administration"])
	apply(st, SimCommands.won_act(0, "start", W, st.get_empire(0).capital_planet))
	days(st, 10)
	_ok(GameState.FORMAT_VERSION >= 73 and GameState.READABLE_VERSIONS.has(72), "sauvegarde 73, la 72 reste lisible")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	_ok(back != null and not Wonders.build_of(back, 0, W).is_empty(), "le chantier survit à la sauvegarde")
	_ok(back != null and back.checksum() == st.checksum(), "même empreinte après relecture")


func _test_ai() -> void:
	var sim := Simulation.new(new_game(17, {"ai_level": "normal"}))
	var st := sim.state
	for e in st.empires:
		Research.grant(st, e.id, ["administration", "capteurs", "cales_rapides"])
		rich(st, e.id)
	sim.advance(90)
	var n := 0
	for k in st.wonders.get("build", {}):
		n += (st.wonders["build"][k] as Dictionary).size()
	n += Wonders.held(st).size()
	_ok(n > 0, "l'IA lance des merveilles (%d chantiers ou merveilles)" % n)
