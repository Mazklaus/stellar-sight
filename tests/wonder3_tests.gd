extends RefCounted
## Tests des merveilles galactiques, lot 3 : guerre (chantier suspendu, ruine après un long siège,
## but de guerre « Prendre la merveille »), espionnage (sabotage, plans volés, auscultation),
## Amphictyonie (famille Merveilles, Concours), œuvres collectives du Koinon, haut fait du Bâtisseur,
## victoire des Grands Œuvres, Patrimoine au bâtisseur. Appelés par smoke_test.gd.

const T := preload("res://tests/wonder_tests.gd")
const T2 := preload("res://tests/wonder2_tests.gd")

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Merveilles galactiques (guerre, ombres, œuvres communes)…")
	_test_blocked()
	_test_ruin()
	_test_war_goal()
	_test_spy()
	_test_amph()
	_test_koinon()
	_test_deed()
	_test_victory()
	_test_heritage()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func month(st: GameState) -> void:
	for i in 30:
		st.tick += 1
		Wonders.daily(st)


static func war(st: GameState, a: int, b: int) -> void:
	if not st.get_empire(a).contacts.has(b):
		st.get_empire(a).contacts.append(b)
		st.get_empire(b).contacts.append(a)
	Combat.start_war(st, a, b)


static func warship(_st: GameState, _eid: int) -> String:
	for sid in GameData.ships():
		if Combat.is_armed_ship(String(sid)):
			return String(sid)
	return ""


func _test_blocked() -> void:
	var st := T.new_game()
	T.rich(st, 0)
	Research.grant(st, 0, ["administration"])
	var home := st.get_empire(0).capital_planet
	T.apply(st, SimCommands.won_act(0, "start", T.W, home))
	war(st, 0, 1)
	var f := st.spawn_ship(1, warship(st, 1), st.galaxy.get_planet(home).system_id)
	var e := Wonders.build_of(st, 0, T.W)
	var pts := int(e["pts"])
	T.days(st, 10)
	_ok(int(e["pts"]) == pts, "une flotte ennemie en orbite suspend le chantier")
	st.fleets.erase(f.id)
	T.days(st, 10)
	_ok(int(e["pts"]) > pts, "elle partie, le chantier reprend")


func _test_ruin() -> void:
	var st := T.new_game()
	var home := st.get_empire(0).capital_planet
	T2.finish(st, 0, home, "palais_doleances")
	war(st, 0, 1)
	st.spawn_ship(1, warship(st, 1), st.galaxy.get_planet(home).system_id)
	for i in 7:
		month(st)
	_ok(not st.colonies[home].buildings.has("palais_doleances"), "après six mois de siège, la merveille tombe en ruine")
	_ok(WondersCatalog.ruin_of(st, "palais_doleances") == home, "elle devient une ruine restaurable")


func _test_war_goal() -> void:
	var st := T.new_game()
	_ok(Wars.goal_def("merveille").get("label", "") == "Prendre la merveille", "but de guerre « Prendre la merveille » en données")
	var other := -1
	for p in st.galaxy.planets:
		if not st.colonies.has(p.id) and p.system_id != st.galaxy.get_planet(st.get_empire(1).capital_planet).system_id and st.system_owner(p.system_id) < 0:
			other = p.id
			break
	_ok(not Wars.goal_ok(st, "merveille", 0, 1), "pas de but sans merveille hors de sa capitale")
	T2.plant(st, 1, other)
	st.rebuild_ownership()
	T2.finish(st, 1, other, "champ_mars")
	_ok(Wars.goal_ok(st, "merveille", 0, 1), "le but s'ouvre contre qui tient une merveille")
	var name := WondersBridges.take_prize(st, 0, 1)
	_ok(name != "" and (st.colonies[other] as Colony).owner == 0, "à la paix, le système de la merveille change de mains")


func _test_spy() -> void:
	var st := T.new_game()
	T.rich(st, 1)
	Research.grant(st, 1, ["administration"])
	T.apply(st, SimCommands.won_act(1, "start", T.W, st.get_empire(1).capital_planet))
	var e := Wonders.build_of(st, 1, T.W)
	e["pts"] = 10000
	var msg := WondersBridges.sabotage(st, 1, 60)
	_ok(msg != "" and int(e["pts"]) == 4000, "le sabotage vise le grand chantier (−60 jours)")
	_ok(WondersBridges.spy_check(st, 0, 1, "voler_plans") == "", "voler les plans : possible sur un chantier")
	var c0 := int(Wonders.total_cost(st, 0, T.W)["materials"])
	WondersBridges.spy_apply(st, 0, 1, {"id": "voler_plans"})
	_ok(int(Wonders.total_cost(st, 0, T.W)["materials"]) < c0, "les plans volés font baisser le coût (%d -> %d)" % [c0, int(Wonders.total_cost(st, 0, T.W)["materials"])])
	var aus := WondersBridges.spy_apply(st, 0, 1, {"id": "ausculter"})
	_ok(aus.contains("%"), "ausculter donne l'avancement exact")
	_ok(WondersBridges.auscultated(st, 0, 1), "pendant un an")
	_ok(Espionage.op_def("voler_plans").get("wonders", false), "opérations en données")


func _test_amph() -> void:
	var st := T.new_game(11, {"amphictyony": "active"})
	var f := Amphictyony.family_def("merveilles")
	_ok(not f.is_empty() and Amphictyony.family_available(st, "merveilles"), "famille « Merveilles » à l'Amphictyonie")
	_ok((f["a"]["levels"][0]["bans"] as Array).has("ruin_wonder"), "Patrimoine : on ne ruine plus une merveille")
	_ok((f["a"]["levels"][2]["bans"] as Array).has("megastructure"), "Moratoire des mégastructures")
	_ok(bool(f["a"]["levels"][1].get("wonder_contest", 0)), "Concours amphictyonique")
	var off := T.new_game(11, {"amphictyony": "active", "wonders": "aucune"})
	_ok(not Amphictyony.family_available(off, "merveilles"), "sans merveilles, pas de famille")


func _test_koinon() -> void:
	var st := T.new_game(11, {"koinon": "actif"})
	if not st.koinon_on:
		_ok(true, "Koinon inactif (œuvre commune sautée)")
		return
	_ok(WondersBridges.check_collective(st, 0, "grand_oeuvre_koinon") != "", "œuvre du Koinon réservée à ses membres")
	for e in [0, 1]:
		T.rich(st, e)
		if Combat.at_war(st, 0, 1):
			Diplomacy.sign_treaty(st, 0, 1, Diplomacy.PEACE)
	if not st.get_empire(0).contacts.has(1):
		st.get_empire(0).contacts.append(1)
		st.get_empire(1).contacts.append(0)
	Diplomacy.sign_treaty(st, 0, 1, Diplomacy.ALLIANCE)
	Diplomacy._rel_w(st, 0, 1)["since"] = st.tick - int(Koinon.data()["found"]["alliance_days"])
	Diplomacy._rel_w(st, 0, 1)["trust"] = 100
	Koinon.found(st, 0, 1, String(Koinon.form_defs()[0]["id"]))
	if not Koinon.same_league(st, 0, 1):
		_ok(true, "Koinon non fondé dans ce montage (œuvre commune sautée)")
		return
	T.rich(st, 0)
	T.rich(st, 1)
	for e in [0, 1]:
		while Research.current_era(st, e) < 4:
			Research.grant_all(st, e)
	var home := st.get_empire(0).capital_planet
	var why := T.apply(st, SimCommands.won_act(0, "start", "grand_oeuvre_koinon", home))
	_ok(why == "", "un membre lance l'œuvre du Koinon (%s)" % why)
	var e0 := Wonders.build_of(st, 0, "grand_oeuvre_koinon")
	var pts := int(e0["pts"])
	why = T.apply(st, SimCommands.won_act(1, "give", "grand_oeuvre_koinon", 0))
	_ok(why == "" and int(e0["pts"]) > pts, "un autre membre y verse (%s)" % why)
	var added: Array[Dictionary] = []
	Wonders.complete(st, "grand_oeuvre_koinon", 0, added)
	var sh := WondersBridges.shares_of(st, "grand_oeuvre_koinon", home)
	_ok(sh.has("0") and sh.has("1"), "les parts de chacun sont gardées")
	_ok(Wonders.yields_of(st, home, "grand_oeuvre_koinon").is_empty(), "la colonie ne garde pas le rendement")
	var k1 := int(st.get_empire(1).resources.get("knowledge", 0))
	while posmod(st.tick, 30) != 23:
		st.tick += 1
	WondersBridges.daily(st, added)
	_ok(int(st.get_empire(1).resources.get("knowledge", 0)) > k1, "le rendement se partage au prorata")


func _test_deed() -> void:
	var st := T.new_game()
	var home := st.get_empire(0).capital_planet
	for w in ["arche_semenciere", "palais_doleances", "senat_etoiles"]:
		T2.finish(st, 0, home, w)
	var added: Array[Dictionary] = []
	st.tick = 23
	WondersBridges.daily(st, added)
	_ok(WondersBridges.builder_deed(st) == 0, "le premier à tenir 3 merveilles devient Bâtisseur")
	var got := false
	for p in Diplomacy.opinion_parts(st, 1, 0):
		got = got or String(p["label"]) == "Bâtisseur de merveilles"
	_ok(got, "les autres l'estiment")


func _test_victory() -> void:
	var st := T.new_game(11, {"victories": {"oeuvres": true}})
	_ok(Victory.enabled(st, "oeuvres") and WondersBridges.oeuvres_on(st), "victoire des Grands Œuvres en option")
	var off := T.new_game()
	_ok(not Victory.enabled(off, "oeuvres"), "décochée par défaut")
	var need := WondersBridges.oeuvres_needed(st)
	_ok(need >= 2 and need <= 5, "2 à 5 Grands Œuvres selon la taille (%d)" % need)
	T.rich(st, 0)
	while Research.current_era(st, 0) < 5:
		Research.grant_all(st, 0)
	var c1 := int(Wonders.total_cost(st, 0, "grand_oeuvre")["materials"])
	T2.finish(st, 0, st.get_empire(0).capital_planet, "grand_oeuvre")
	_ok(int(Wonders.total_cost(st, 0, "grand_oeuvre")["materials"]) > c1, "chaque Grand Œuvre coûte plus que le précédent")
	var out := Victory.progress(st, 0, "oeuvres")
	_ok(String(out.get("lines", [""])[0]).contains("Grands Œuvres"), "avancée lisible (%s)" % str(out.get("lines", [])))


func _test_heritage() -> void:
	var st := T.new_game(11, {"culture": "actif"})
	var home := st.get_empire(0).capital_planet
	T2.finish(st, 0, home, "palais_doleances")
	_ok(Wonders.builder_of(st, "palais_doleances", home) == 0, "le bâtisseur est retenu")
	(st.colonies[home] as Colony).owner = 1
	_ok(Wonders.builder_of(st, "palais_doleances", home) == 0, "il le reste après une conquête (Patrimoine)")
