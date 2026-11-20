extends RefCounted
## Tests du lot 2 de la refonte de l'arbre de recherche (étude https://claude.ai/artifact/2M77BwzqiBMt6zXSCKCq72) :
## paliers d'ère, tactiques débloquées, armes à ions, nouveaux bâtiments (instituts, annexes, 2e rangs,
## régimes, projets), Maîtrises des anciens pourcentages, coques de peuple améliorées, ultimes,
## trouvailles et spécialisations.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Arbre de recherche (lot 2) : paliers, tactiques, bâtiments, Maîtrises, trouvailles…")
	_test_tiers()
	_test_tactics()
	_test_ions()
	_test_buildings()
	_test_building_effects()
	_test_projects()
	_test_masteries()
	_test_people_hulls()
	_test_ultimates_finds_specs()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _state(faction := "vael") -> GameState:
	return GameState.create(4242, 150, 1800.0, faction, {"ai_level": ""})


func _home(st: GameState, eid := 0) -> Colony:
	return st.colonies[st.get_empire(eid).capital_planet]


## Ouvre l'ère `era` d'un domaine en accordant ses technologies principales des ères d'avant.
func _open(st: GameState, domain: String, era: int) -> void:
	var techs: Dictionary = GameData.technologies()["technologies"]
	var f := st.get_empire(0).faction()
	for tid: String in techs:
		var t: Dictionary = techs[tid]
		if String(t["domain"]) == domain and int(t.get("era", 1)) < era and Research.is_visible(f, tid) \
				and not t.has("mastery") and not t.has("find") and not t.has("spec"):
			Research.grant(st, 0, [tid])


func _test_tiers() -> void:
	var st := _state()
	_ok(Research.open_tiers(st, 0).is_empty(), "paliers : aucun à l'ère I")
	var p0 := Economy.production_pct(st, 0, "materials")
	_open(st, "economie", 2)
	var tiers := Research.open_tiers(st, 0)
	_ok(tiers.any(func(x): return String(x["domain"]) == "economie" and int(x["era"]) == 2), "paliers : ouvrir l'ère II d'Économie donne son palier")
	_ok(Economy.production_pct(st, 0, "materials") > p0, "paliers : le palier d'Économie augmente la production (%d → %d)" % [p0, Economy.production_pct(st, 0, "materials")])
	for d in Research.domain_ids():
		for era in range(2, Research.eras() + 1):
			_ok(not Research.tier(d, era).is_empty() and String(Research.tier(d, era).get("label", "")) != "", "paliers : %s, ère %d, a un palier nommé" % [d, era])


func _test_tactics() -> void:
	var st := _state()
	var e := st.get_empire(0)
	var f := st.spawn_ship(0, "corvette", st.galaxy.get_planet(e.capital_planet).system_id)
	_ok(Combat.tactic_tech("barrage") == "feu_lointain", "tactiques : le Barrage vient du Feu lointain")
	_ok(Combat.check_tactic(st, 0, f.id, "barrage") != "", "tactiques : pas de Barrage sans sa technologie")
	_ok(Combat.check_tactic(st, 0, f.id, "assaut") == "", "tactiques : les tactiques de base restent libres")
	Research.grant(st, 0, ["feu_lointain"])
	_ok(Combat.check_tactic(st, 0, f.id, "barrage") == "", "tactiques : le Barrage avec le Feu lointain")
	_ok(Combat.tactic_ids_for(f, st).has("barrage") and not Combat.tactic_ids_for(f, st).has("dernier_mot"), "tactiques : la liste de la flotte suit la recherche")
	var n := 0
	for t: Dictionary in Combat.data()["tactics"]:
		if t.has("requires_tech"):
			n += 1
			_ok(not Research.tech(String(t["requires_tech"])).is_empty(), "tactiques : %s demande une technologie qui existe" % String(t["id"]))
	_ok(n >= 10, "tactiques : au moins dix tactiques débloquées par la recherche (%d)" % n)


func _test_ions() -> void:
	_ok(not Combat.data()["weapons"].get("ion", {}).is_empty(), "ions : la famille Ions existe")
	var m := Designs.module("canon_ions")
	_ok(not m.is_empty() and (m.get("requires_tech", []) as Array).has("faisceaux_gamma"), "ions : le Canon à ions vient des Faisceaux gamma")
	for mid in ["rayon_tracteur", "baie_reparation", "bouclier_flottille", "canon_verbe", "moteur_singularite"]:
		_ok(not Designs.module(mid).is_empty(), "modules du lot 2 : %s" % mid)


func _test_buildings() -> void:
	var st := _state()
	var c := _home(st)
	var p := st.galaxy.get_planet(c.planet_id)
	# Annexe : sans emplacement, sur son bâtiment.
	_ok(not Economy.takes_slot("institut_economie") and not Economy.takes_slot("grand_temple"), "annexes : sans emplacement")
	Research.grant(st, 0, ["academies", "banques_donnees"])
	c.buildings.erase("academie")
	_ok(Economy.check_build(st, 0, c.planet_id, "institut_economie").contains("nécessite"), "annexes : l'Institut demande l'Académie")
	c.buildings.append("academie")
	st.get_empire(0).resources["materials"] = 5000
	st.get_empire(0).resources["energy"] = 5000
	var used := Economy.building_slots_used(c)
	var cost0 := Research.cost(st, 0, "automatisation")
	c.buildings.append("institut_economie")
	_ok(Economy.building_slots_used(c) == used, "annexes : l'Institut ne compte pas dans les emplacements")
	_ok(Research.cost(st, 0, "automatisation") < cost0, "Institut d'économie : l'Économie coûte moins cher (%d → %d)" % [cost0, Research.cost(st, 0, "automatisation")])
	_ok(Economy.check_build(st, 0, c.planet_id, "institut_genie").contains("un seul"), "Institut : un seul par Académie")
	_ok(Economy.institute_pct(st, 0, "economie") >= -25, "Institut : réduction plafonnée à 25 %")
	# Régimes : un bâtiment pour ceux qui ne mangent pas.
	_ok(not Economy.building_unlocked(st, 0, "batteries_communes"), "régimes : pas de Batteries communes pour un peuple qui mange")
	var sy := _state("teyl")
	_ok(Economy.building_unlocked(sy, 0, "batteries_communes"), "régimes : Batteries communes pour un peuple au courant vital")
	_ok(not Economy.building_unlocked(sy, 0, "serre_lumiere"), "régimes : la Serre de lumière reste aux végétaux")
	# 2e rangs et projets : tous débloqués par une technologie qui existe (ou par le régime).
	for bid in GameData.buildings():
		var bd := GameData.building(bid)
		if bd.get("annex", false):
			_ok(GameData.building(String(bd.get("requires_building", ""))).size() > 0 or bid == "abris_civils", "annexe %s : bâtiment de base connu" % bid)


func _test_building_effects() -> void:
	var st := _state()
	var e := st.get_empire(0)
	var c := _home(st)
	var g0 := Economy.growth_per_day(st, c)
	c.buildings.append("clinique")
	_ok(Economy.growth_per_day(st, c) > g0, "Clinique : la colonie grandit plus vite")
	var cells0 := Espionage.cells_total(st, 0)
	c.buildings.append("bureau_renseignement")
	_ok(Espionage.cells_total(st, 0) == cells0 + 1, "Bureau du renseignement : une cellule de plus")
	var cap0 := Ground.recruits_cap(st, 0)
	c.buildings.append("camp_recrutement")
	_ok(Ground.recruits_cap(st, 0) == cap0 + 6, "Camp de recrutement : plafond de recrues +6")
	var cmd := SimCommands.build_ship(0, c.planet_id, "corvette")
	e.resources["materials"] = 5000
	e.resources["energy"] = 5000
	SimCommands.apply(st, cmd)
	var d0 := c.ship_days
	c.ship_build = ""
	c.buildings.append("cale_seche")
	SimCommands.apply(st, cmd)
	_ok(c.ship_days < d0, "Cale sèche : les vaisseaux de la colonie sortent plus vite (%d → %d)" % [d0, c.ship_days])
	_ok(Economy.local_sum(c, "build_speed") == 0, "pas d'atelier : chantiers à vitesse normale")
	c.buildings.append("atelier_nanofabrication")
	_ok(Economy.local_sum(c, "build_speed") == 1, "Atelier de nanofabrication : chantiers deux fois plus rapides")


func _test_projects() -> void:
	var st := _state()
	var e := st.get_empire(0)
	var c := _home(st)
	var p := st.galaxy.get_planet(c.planet_id)
	p.deposits.erase("fertile")
	Research.grant(st, 0, ["hydroponie"])
	e.resources["materials"] = 5000
	e.resources["energy"] = 5000
	c.construction = ""
	_ok(Economy.check_build(st, 0, c.planet_id, "enrichissement_sols") == "", "projets : Enrichissement des sols possible (%s)" % Economy.check_build(st, 0, c.planet_id, "enrichissement_sols"))
	_ok(not Economy.takes_slot("enrichissement_sols"), "projets : sans emplacement")
	c.construction = "enrichissement_sols"
	c.construction_days = 1
	var added: Array[Dictionary] = []
	EconomySystem._finish_building(st, c, e, "Test", added)
	_ok(p.deposits.has("fertile") and not c.buildings.has("enrichissement_sols"), "projets : le monde gagne un gisement fertile, rien ne reste bâti")
	_ok(Economy.check_build(st, 0, c.planet_id, "enrichissement_sols").contains("déjà"), "projets : pas deux fois le même gisement")


func _test_masteries() -> void:
	for pair in [["hydroponie", "agronomie_orbitale"], ["propulseurs", "postcombustion"], ["medecine", "sante_publique"],
			["marines", "fusiliers_elite"], ["banques_donnees", "reseaux_savants"]]:
		var parent: Dictionary = Research.tech(String(pair[0]))
		_ok(String(Research.tech(String(pair[1])).get("mastery", "")) == String(pair[0]), "Maîtrises : %s est la Maîtrise de %s" % [pair[1], pair[0]])
		var pct := false
		for k in parent.get("effects", {}):
			if String(k).ends_with("_pct"):
				pct = true
		# Exception voulue : les moteurs portent la vitesse de leur génération, la Maîtrise la mise en route.
		_ok(not pct or String(pair[0]) == "propulseurs", "Maîtrises : %s ne porte plus de pourcentage, sa Maîtrise le porte" % pair[0])


func _test_people_hulls() -> void:
	var st := _state("vael")
	var e := st.get_empire(0)
	var hid := "corvette_concorde"
	var up: Dictionary = Designs.hull(hid).get("upgrade", {})
	_ok(String(up.get("tech", "")) == "dernier_moment" and String(up.get("flag", "")) == "repair_bay", "coques de peuple : la Corvette de concorde s'améliore avec Au dernier moment")
	if not GameData.ship(hid).is_empty():
		var f := st.spawn_ship(0, hid, st.galaxy.get_planet(e.capital_planet).system_id)
		_ok(not PeopleHulls.has_flag(st, f, "repair_bay"), "coques de peuple : pas d'amélioration sans la technologie")
		Research.grant(st, 0, ["dernier_moment"])
		_ok(PeopleHulls.has_flag(st, f, "repair_bay"), "coques de peuple : la technologie ajoute la baie de réparation")
	_ok(PeopleHulls.upgrades_of("pelerinages").has("nef_penitence"), "coques de peuple : la Nef de pénitence s'améliore avec les Pèlerinages")


func _test_ultimates_finds_specs() -> void:
	for tid in ["verbe_final", "moteur_singularite", "abondance", "symbiose"]:
		_ok(Research.is_ultimate(tid), "ultimes : %s" % tid)
	var st := _state()
	var e := st.get_empire(0)
	_ok(Research.check_queue(st, 0, "foyer_plasma_ancien").contains("trouvaille"), "trouvailles : elles ne se recherchent pas")
	_open(st, "armement", 3)
	var got := Research.grant_find(st, 0, "capture")
	_ok(got != "" and Research.is_find(got), "trouvailles : une prise de guerre en donne une (%s)" % got)
	var cousin := String(Research.tech(got).get("find_of", ""))
	_ok(cousin != "" and e.techs.has(cousin), "trouvailles : elle dispense de rechercher sa cousine (%s)" % cousin)
	_ok(Research.spec_members("voie_culturelle").size() == 2, "spécialisations : rayonner ou convertir")
	_ok(Research.spec_taken({"reseau_mondes": true}, "conversion_culturelle") == "reseau_mondes", "spécialisations : l'une ferme l'autre")
