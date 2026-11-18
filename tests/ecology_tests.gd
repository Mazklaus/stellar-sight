class_name EcologyTests
extends RefCounted
## Tests de l'écologie et du climat des mondes (version resserrée du 2026-11-18) : données, biosphère
## des seuls mondes vivants, empreinte et absorption, équilibre et glissement, paliers (nourriture,
## stabilité, croissance), basculement et reverdissement, réserve et ingénierie, technologies,
## doctrine, terraformation, IA, sauvegarde. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Écologie et climat des mondes…")
	_test_data()
	_test_biosphere()
	_test_footprint()
	_test_drift()
	_test_tiers()
	_test_climate()
	_test_buildings()
	_test_doctrine()
	_test_terraform()
	_test_ai()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(mode := "complete") -> GameState:
	return GameState.create(4242, 150, 1800.0, "ossarane", {"ai_level": "", "ecology": mode})


static func me(st: GameState) -> Empire:
	for e in st.empires:
		if not e.is_npc():
			return e
	return null


## La capitale du joueur, rendue continentale et de taille 3 pour des comptes nets.
static func home(st: GameState) -> Colony:
	var e := me(st)
	var c: Colony = st.colonies[e.capital_planet]
	st.override_planet(c.planet_id, {"type": "continental", "size": 3})
	e.hab_cache.clear()
	c.population = 6
	c.buildings.clear()
	c.buildings.append("capitale")
	c.construction = ""
	return c


static func months(st: GameState, n: int) -> void:
	var added: Array[Dictionary] = []
	for i in n:
		Ecology.monthly(st, added)


func _test_data() -> void:
	_ok(Ecology.mode_defs().size() == 3 and Ecology.default_mode() == "complete", "trois réglages, Complète par défaut")
	_ok(Ecology.tiers().size() == 5, "cinq paliers")
	_ok(Ecology.doctrine_defs().size() == 3, "trois doctrines")
	_ok(not GameData.building("reserve_naturelle").is_empty() and not GameData.building("ingenierie_climatique").is_empty(), "Réserve et Ingénierie climatique")
	_ok(Research.tech("recycleurs_atmospheriques").get("effects", {}).has("eco_footprint_pct") and not Research.tech("ingenierie_climatique").is_empty(), "deux technologies")
	var off := new_game("desactivee")
	_ok(off.ecology.is_empty() and not Ecology.enabled(off), "désactivée : rien en jeu")
	var bare := GameState.create(4242, 150, 1800.0, "ossarane", {"ai_level": ""})
	_ok(bare.ecology.is_empty(), "GameState.create sans option : désactivée")
	for k in ["eco_tipping", "eco_shift", "eco_regreen"]:
		_ok(not Announce.kind_def(k).is_empty(), "annonce %s" % k)


func _test_biosphere() -> void:
	var st := new_game()
	var c := home(st)
	_ok(Ecology.has_biosphere(st, c.planet_id) and Ecology.health(st, c.planet_id) == 70, "monde continental : biosphère de départ 70")
	st.override_planet(c.planet_id, {"type": "barren"})
	_ok(not Ecology.has_biosphere(st, c.planet_id) and Ecology.health(st, c.planet_id) == -1, "monde stérile : pas de biosphère (-1)")
	st.override_planet(c.planet_id, {"type": "ecumenopole"})
	_ok(Ecology.health(st, c.planet_id) == -1, "écuménopole : pas de biosphère")
	st.override_planet(c.planet_id, {"type": "gaia"})
	_ok(Ecology.health(st, c.planet_id) == 100, "monde-jardin : 100")
	var off := new_game("desactivee")
	_ok(Ecology.health(off, home(off).planet_id) == -1, "désactivée : -1 partout")


func _test_footprint() -> void:
	var st := new_game()
	var c := home(st)
	var pid := c.planet_id
	_ok(Ecology.absorption(st, pid) == 12, "absorption : 4 par cran de taille")
	_ok(Ecology.footprint(st, pid) == 3 and Ecology.equilibrium(st, pid) == 70, "capitale seule : absorbée, équilibre = vitalité")
	c.buildings.append_array(["complexe_minier", "complexe_minier", "centrale_fusion"])
	# 3 + 12 + 4 = 19, 7 au-delà de 12, ×150 % = 10
	_ok(Ecology.footprint(st, pid) == 19 and Ecology.equilibrium(st, pid) == 60, "deux mines et une centrale : équilibre 60 (%d)" % Ecology.equilibrium(st, pid))
	c.population = 12  # 3 au-delà de 9
	_ok(Ecology.footprint(st, pid) == 22, "population au-delà de 3 par cran : empreinte")
	c.buildings.append("reserve_naturelle")
	_ok(Ecology.care(st, pid) == 25 and Ecology.equilibrium(st, pid) == 80, "réserve : +25 de soins")
	var tip := Ecology.tooltip(st, pid)
	_ok(tip.contains("Complexe minier ×2 : 12") and tip.contains("Soins (réserves) : +25"), "infobulle : empreinte poste par poste")


func _test_drift() -> void:
	var st := new_game()
	var c := home(st)
	var pid := c.planet_id
	c.buildings.append_array(["mine_profonde", "mine_profonde"])  # 3 + 28 = 31, 19 au-delà, −28
	var eq := Ecology.equilibrium(st, pid)
	_ok(eq == 42 and Ecology.trend(st, pid) == -1, "industrie lourde : équilibre 42, en baisse")
	months(st, 3)
	_ok(Ecology.health(st, pid) == 67, "un point par mois")
	months(st, 40)
	_ok(Ecology.health(st, pid) == 42, "s'arrête à l'équilibre")
	# Planète abandonnée : elle se remet seule.
	st.colonies.erase(pid)
	months(st, 5)
	_ok(Ecology.health(st, pid) == 47, "sans revendication : se remet vers sa vitalité")


func _test_tiers() -> void:
	var st := new_game()
	var c := home(st)
	var pid := c.planet_id
	var sid := st.galaxy.get_planet(pid).system_id
	Ecology._set_health(st, pid, 85)
	_ok(String(Ecology.tier(st, pid)["id"]) == "florissante", "85 : Florissante")
	var g := {"food": 100, "materials": 50}
	Ecology.adjust_yields(st, c, g)
	_ok(int(g["food"]) == 115, "Florissante : +15 % nourriture")
	_ok(Ecology.stability_parts(st, sid, c.owner) == [["Biosphère florissante (%s)" % st.galaxy.get_planet(pid).display_name(st.galaxy), 5]], "Florissante : +5 stabilité")
	Ecology._set_health(st, pid, 30)
	g = {"food": 100}
	Ecology.adjust_yields(st, c, g)
	_ok(int(g["food"]) == 75 and Ecology.growth_pct(st, pid) == -25, "Dégradée : −25 % nourriture et croissance")
	_ok(int(Ecology.stability_parts(st, sid, c.owner)[0][1]) == -5, "Dégradée : −5 stabilité")
	Ecology._set_health(st, pid, 10)
	_ok(Ecology.growth_blocked(st, pid), "Effondrée : croissance arrêtée")
	var parts := Stability.parts(st, sid)
	var found := false
	for p in parts:
		found = found or String(p[0]).begins_with("Biosphère effondrée")
	_ok(found, "Effondrée : ligne dans la stabilité du système")


func _test_climate() -> void:
	var st := new_game()
	var c := home(st)
	var pid := c.planet_id
	c.buildings.append_array(["mine_profonde", "mine_profonde", "mine_profonde", "centrale_confinement"])
	Ecology._set_health(st, pid, 5)
	_ok(Ecology.equilibrium(st, pid) < 20, "équilibre effondré")
	months(st, 12)
	_ok(Ecology.sub(st, "warn").has(str(pid)), "avis au bout d'un an")
	_ok(st.galaxy.get_planet(pid).type == "continental", "pas encore basculé")
	months(st, 12)
	_ok(st.galaxy.get_planet(pid).type == "desert" and st.planet_overrides[pid]["type"] == "desert", "deux ans effondré : continental → désertique (sauvegardé)")
	# Reverdissement : désert Florissant 60 mois.
	c.buildings.clear()
	c.buildings.append_array(["capitale", "reserve_naturelle"])
	Ecology._set_health(st, pid, 95)
	var ok := true
	for i in 59:
		Ecology._set_health(st, pid, maxi(Ecology.health(st, pid), 90))  # l'ingénierie climatique la tient haut
		months(st, 1)
	ok = st.galaxy.get_planet(pid).type == "desert"
	Ecology._set_health(st, pid, 95)
	months(st, 1)
	_ok(ok and st.galaxy.get_planet(pid).type == "continental", "cinq ans Florissant : désertique → continental")
	var bio := new_game("biosphere")
	var bc := home(bio)
	Ecology._set_health(bio, bc.planet_id, 0)
	bc.buildings.append_array(["mine_profonde", "mine_profonde", "mine_profonde"])
	months(bio, 30)
	_ok(bio.galaxy.get_planet(bc.planet_id).type == "continental", "Biosphère seule : pas de basculement")


func _test_buildings() -> void:
	var st := new_game()
	var c := home(st)
	var e := me(st)
	e.resources["materials"] = 5000
	e.resources["energy"] = 5000
	_ok(Economy.check_build(st, e.id, c.planet_id, "reserve_naturelle") == "", "réserve : constructible sur un monde vivant")
	st.override_planet(c.planet_id, {"type": "barren"})
	_ok(Economy.check_build(st, e.id, c.planet_id, "reserve_naturelle").contains("monde vivant"), "réserve : refusée sur un monde mort")
	st.override_planet(c.planet_id, {"type": "continental"})
	_ok(Economy.check_build(st, e.id, c.planet_id, "ingenierie_climatique").begins_with("technologie requise"), "ingénierie : technologie requise")
	e.techs["ingenierie_climatique"] = true
	e.tech_fx_n = -1
	_ok(Economy.check_build(st, e.id, c.planet_id, "ingenierie_climatique") == "" and not Economy.takes_slot("ingenierie_climatique"), "ingénierie : projet sans emplacement")
	Ecology._set_health(st, c.planet_id, 40)
	c.construction = "ingenierie_climatique"
	c.construction_days = 1
	st.tick = 1
	EconomySystem.process(st)
	_ok(Ecology.health(st, c.planet_id) == 65 and not c.buildings.has("ingenierie_climatique"), "ingénierie achevée : +25, rien ne reste bâti")
	var off := new_game("desactivee")
	var oc := home(off)
	_ok(Economy.check_build(off, me(off).id, oc.planet_id, "reserve_naturelle").contains("pas en jeu"), "désactivée : pas de réserve")
	# Recycleurs : empreinte −30 %.
	c.buildings.append_array(["mine_profonde", "mine_profonde"])
	var before := Ecology.footprint(st, c.planet_id)
	e.techs["recycleurs_atmospheriques"] = true
	e.tech_fx_n = -1
	_ok(Ecology.footprint(st, c.planet_id) == before * 70 / 100, "recycleurs : empreinte −30 %% (%d → %d)" % [before, Ecology.footprint(st, c.planet_id)])


func _test_doctrine() -> void:
	var st := new_game()
	var c := home(st)
	var e := me(st)
	_ok(Ecology.doctrine(st, e.id) == "equilibre", "Équilibre par défaut")
	_ok(SimCommands.validate(st, SimCommands.eco_act(e.id, "doctrine", {"id": "extraction"})) == "", "doctrine : changement permis")
	SimCommands.apply(st, SimCommands.eco_act(e.id, "doctrine", {"id": "extraction"}))
	_ok(Ecology.doctrine(st, e.id) == "extraction" and Ecology.footprint_pct(st, e.id) == 150, "Extraction : empreinte +50 %")
	var g := {"materials": 100, "energy": 100, "food": 100}
	Ecology._set_health(st, c.planet_id, 70)
	Ecology.adjust_yields(st, c, g)
	_ok(int(g["materials"]) == 110 and int(g["energy"]) == 110 and int(g["food"]) == 100, "Extraction : +10 % matériaux et énergie")
	_ok(SimCommands.validate(st, SimCommands.eco_act(e.id, "doctrine", {"id": "preservation"})).contains("jours"), "doctrine : attente de 5 ans")
	st.tick += 1800
	SimCommands.apply(st, SimCommands.eco_act(e.id, "doctrine", {"id": "preservation"}))
	_ok(Ecology.footprint_pct(st, e.id) == 60, "Préservation : empreinte −40 %")


func _test_terraform() -> void:
	var st := new_game()
	var c := home(st)
	var e := me(st)
	Ecology._set_health(st, c.planet_id, 15)
	c.construction = "monde_jardin"
	c.construction_days = 1
	st.tick = 1
	EconomySystem.process(st)
	_ok(st.galaxy.get_planet(c.planet_id).type == "gaia" and Ecology.health(st, c.planet_id) == 100, "monde-jardin : biosphère à 100")
	st.override_planet(c.planet_id, {"type": "desert"})
	Ecology._set_health(st, c.planet_id, 15)
	Ecology.on_terraform(st, c.planet_id)
	_ok(Ecology.health(st, c.planet_id) == 60, "terraformation : biosphère à 60")
	st.override_planet(c.planet_id, {"type": "ecumenopole"})
	Ecology.on_terraform(st, c.planet_id)
	_ok(Ecology.health(st, c.planet_id) == -1 and not Ecology.sub(st, "bio").has(str(c.planet_id)), "écuménopole : biosphère supprimée")
	e.hab_cache.clear()


func _test_ai() -> void:
	var st := new_game()
	var c := home(st)
	var e := me(st)
	var ctx := {"state": st, "e": e}
	Ecology._set_health(st, c.planet_id, 25)
	var w: Array[String] = ["complexe_minier", "forum"]
	var out := Ecology.ai_filter(ctx, c, w)
	_ok(out[0] == "reserve_naturelle" and out[1] == "ingenierie_climatique", "IA : réserve puis ingénierie sur un monde qui souffre")
	_ok(out.has("complexe_minier"), "IA : pas de monde mort, l'industrie reste")
	var off := new_game("desactivee")
	_ok(Ecology.ai_filter({"state": off, "e": me(off)}, home(off), w) == w, "désactivée : rien ne change")


func _test_save() -> void:
	var st := new_game()
	var c := home(st)
	var e := me(st)
	Ecology._set_health(st, c.planet_id, 33)
	Ecology.sub(st, "doc")[str(e.id)] = "preservation"
	Ecology.sub(st, "low")[str(c.planet_id)] = 3
	var d := st.to_dict()
	_ok(int(d["version"]) == GameState.FORMAT_VERSION and GameState.FORMAT_VERSION >= 94 and d.has("ecology"), "Sauvegarde 94")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and JSON.stringify(back.to_dict()) == JSON.stringify(d), "Sauvegarde : aller-retour identique")
	_ok(back != null and Ecology.health(back, c.planet_id) == 33 and Ecology.doctrine(back, e.id) == "preservation", "Sauvegarde : biosphère et doctrine")
	var off := new_game("desactivee")
	_ok(not off.to_dict().has("ecology"), "désactivée : rien dans la sauvegarde")
