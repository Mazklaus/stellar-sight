class_name MegasTests3
extends RefCounted
## Tests des mégastructures, lot 3 : ponts avec les autres piliers (espionnage, but de guerre, Amphictyonie,
## Koinon, religion, Transcendance, économie privée, héros et cour, hauts faits et victoire).

const T := preload("res://tests/megas_tests.gd")

var _check: Callable


static func run(check: Callable) -> void:
	var t := MegasTests3.new()
	t._check = check
	print("  - spy_war")
	t._test_spy_war()
	print("  - council_faith")
	t._test_council_faith()
	print("  - transcendence_private")
	t._test_transcendence_private()
	print("  - heroes_deeds")
	t._test_heroes_deeds()
	print("  - ui")
	t._test_ui()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


## Une colonie de eid dans un système voisin libre de sa capitale ; renvoie le système (-1 si aucun).
static func outpost_near(st: GameState, eid: int) -> int:
	var home := T.home_sys(st, eid)
	for nb in st.galaxy.systems[home].neighbors:
		if st.system_owner(nb) < 0 and not st.galaxy.systems[nb].planet_ids.is_empty():
			var c := Colony.new()
			c.planet_id = st.galaxy.systems[nb].planet_ids[0]
			c.owner = eid
			c.kind = Colony.KIND_OUTPOST
			st.add_colony(c)
			return nb
	return -1


func _test_spy_war() -> void:
	var st := T.new_game()
	var foe := 1
	_ok(MegasBridges.spy_check(st, 0, foe, "saboter_chantier").contains("aucun chantier"), "sabotage : il faut un chantier en cours")
	var sid := outpost_near(st, foe)
	if sid < 0:
		_ok(true, "pas de système libre (test sauté)")
		return
	var id := T.build_full(st, foe, "reseau_veille", sid)
	var m := Megastructures.get_m(st, id)
	m["st"] = 2
	m["w"] = 50
	_ok(MegasBridges.spy_check(st, 0, foe, "saboter_chantier") == "", "sabotage possible")
	MegasBridges.spy_apply(st, 0, foe, {"id": "saboter_chantier"})
	_ok(int(m["w"]) == 50 + MegasBridges.c_int("spy", "sabotage_days", 120), "sabotage : l'étape perd 120 jours")
	m["st"] = Megastructures.stage_count("reseau_veille")
	m["w"] = 0
	_ok(MegasBridges.spy_check(st, 0, foe, "voler_plans_mega") == "", "plans à voler")
	var before := Megastructures.cost_pct(st, 0, "reseau_veille")
	MegasBridges.spy_apply(st, 0, foe, {"id": "voler_plans_mega"})
	_ok(Megastructures.cost_pct(st, 0, "reseau_veille") == before - 25, "plans volés : 25 % de moins")
	_ok(not Espionage.op_def("saboter_chantier").is_empty() and not Espionage.op_def("voler_plans_mega").is_empty(), "deux opérations d'espionnage au catalogue")
	# But de guerre.
	_ok(Wars.goal_ok(st, "mega", 0, foe), "but « Saisir la mégastructure » possible contre qui en tient une")
	_ok(not Wars.goal_ok(st, "mega", foe, 0), "impossible contre qui n'en a pas")
	_ok(MegasBridges.strike_target(st, foe, sid), "l'IA vise les grands ouvrages de ses rivaux")
	var name := MegasBridges.take_prize(st, 0, foe)
	_ok(name != "" and int(Megastructures.get_m(st, id)["o"]) == 0, "paix : le système et la mégastructure passent au vainqueur")
	var taken := false
	for x: Dictionary in st.memories:
		if String(x["kind"]) == "mega_taken":
			taken = true
	_ok(taken, "le vaincu s'en souvient")


func _test_council_faith() -> void:
	var st := T.new_game()
	_ok(Amphictyony.family_available(st, "chantiers"), "famille « Grands chantiers » de l'Amphictyonie (mégastructures complètes)")
	var cl := T.new_game("classiques")
	_ok(not Amphictyony.family_available(cl, "chantiers"), "pas en Classiques")
	_ok(not Amphictyony.family_def("chantiers").is_empty() and Amphictyony.max_level("chantiers", "b") == 3, "Patrimoine stellaire : trois degrés")
	# Opinion des credos.
	var foe := 1
	var sid := outpost_near(st, foe)
	if sid >= 0:
		T.build_full(st, foe, "forum_interstellaire", sid)
		var credo := String(FactionTraits.species(st.get_empire(0).faction()).get("credo", ""))
		var want := int((MegasBridges.cfg().get("credo_opinion", {}) as Dictionary).get(credo, 0))
		var got := 0
		for p in MegasBridges.opinion_parts(st, 0, foe):
			got += int(p[1])
		_ok(got == want, "les credos jugent les mégastructures (%s : %d)" % [credo, got])
	# Koinon : cofinancement fédéral.
	_ok(bool(Megastructures.kind_def("monde_anneau").get("federal", false)) and bool(Megastructures.kind_def("forum_interstellaire").get("federal", false)), "Forum et Monde-anneau, ouvrages fédéraux")


func _test_transcendence_private() -> void:
	var st := T.new_game()
	var sid := T.home_sys(st, 0)
	_ok(not MegasBridges.exodium_site(st, 0, sid), "pas de mégastructure : pas d'avance pour l'Exodium")
	T.build_full(st, 0, "centre_coordination", sid)
	_ok(MegasBridges.exodium_site(st, 0, sid), "une grande mégastructure achevée : site de l'Exodium, une étape d'avance")
	var ts := T.new_game("completes", "aucune", "ossarane", {"transcendence": "complete"})
	var ts_sid := T.home_sys(ts, 0)
	Transcendence.choose_path(ts, 0, "songe", [])
	if Transcendence.path_of(ts, 0) == "songe":
		T.build_full(ts, 0, "matriochka", ts_sid)
		var found := false
		for p in Transcendence.gain_parts(ts, 0):
			if String(p[0]) == "Cerveau Matriochka":
				found = true
		_ok(found, "le Cerveau Matriochka nourrit la jauge du Songe")
	# Économie privée.
	var pr := T.new_game("completes", "aucune", "ossarane", {"private": "complete"})
	var psid := T.home_sys(pr, 0)
	var id := T.build_full(pr, 0, "essaim_dyson", psid)
	var m := Megastructures.get_m(pr, id)
	m["st"] = 1
	Research.grant(pr, 0, ["essaim_dyson"])
	pr.get_empire(0).resources["materials"] = 0
	var why := T.cmd(pr, 0, "fund", {"id": id})
	_ok(why == "" or not Private.applies(pr, 0), "une compagnie finance l'étape (%s)" % why)
	if why == "":
		_ok(Megastructures.running(m) and MegasBridges.company_share(pr, m) == 25, "elle prend 25 % des rendements")


func _test_heroes_deeds() -> void:
	var st := T.new_game()
	_ok(MegasBridges.slots_bonus(st, 0) == 0, "sans cour : pas de Grand Architecte")
	_ok(not Court.minor_def("grand_architecte").is_empty(), "poste de Grand Architecte à la cour")
	_ok(not Deeds.def("kardashev_ii").is_empty() and not Deeds.def("kardashev_iii").is_empty() and not Deeds.def("premier_monde_anneau").is_empty(), "hauts faits Kardashev II, III et Premier Monde-anneau")
	var sid := T.home_sys(st, 0)
	T.build_full(st, 0, "monde_anneau", sid)
	_ok(DeedsEval.value(st, 0, "mega_rings") == 1, "mesure du Premier Monde-anneau")
	_ok(MegasBridges.great_works(st, 0) == 1, "Grands Œuvres : la mégastructure de l'ère V compte")


func _test_ui() -> void:
	var st := T.new_game()
	var sid := T.home_sys(st, 0)
	Research.grant(st, 0, ["architectes_stellaires"])
	var acts := MegasUi.system_actions(st, 0, st.galaxy.get_planet(st.get_empire(0).capital_planet), func(_c: Dictionary) -> void: pass)
	var has := false
	for a in acts:
		if String(a["text"]).contains("Ascenseur orbital"):
			has = true
	_ok(has, "écran Système : « Mégastructure : Ascenseur orbital »")
	T.build_full(st, 0, "essaim_dyson", sid)
	_ok(MegasUi.status_text(st, Megastructures.owned_by(st, 0)[0]) == "achevée", "statut lisible")
