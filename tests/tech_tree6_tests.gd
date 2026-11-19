extends RefCounted
## Tests des restes de la refonte de l'arbre de recherche (étude https://claude.ai/artifact/2M77BwzqiBMt6zXSCKCq72) :
## domaines resserrés (fusions et Maîtrises), spécialisations nouvelles, Flotte-ville II et III, modules de
## nef de l'Exode, Repli et Pli du Sablier, Œuvres lentes par ère, directives des Silencieux, coques de peuple.

var _check: Callable

const MERGED := {"tetes_chercheuses": "lentilles", "missiles_furtifs": "essaims", "accelerateurs": "artillerie", "obusiers": "canons_rail",
		"nuees_pensantes": "escadres_autonomes", "torpilles_singulieres": "canons_singularite", "defense_planetaire": "bastions",
		"boucliers_planetaires": "citadelle_planetaire", "phase_dense": "faisceaux_gamma", "forces_speciales": "blindes_assaut",
		"capsules_assaut": "equipes_prise", "plaques_ablatives": "interception", "champs_de_mines": "plates_formes_defense",
		"cites_flottantes": "habitats", "mondes_toxiques": "biomes_extremes", "holovision": "propagande", "cites_creusees": "terraformation"}


func run(check: Callable) -> void:
	_check = check
	print("Arbre de recherche (restes) : domaines resserrés, spécialisations, pièces de peuple…")
	_test_domains()
	_test_specs()
	_test_city_fleet()
	_test_exode()
	_test_sablier()
	_test_gravea()
	_test_silencieux()
	_test_hulls()
	_test_last()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _state(faction := "vael", options := {}) -> GameState:
	var o := {"ai_level": "", "insolites": "actifs"}
	o.merge(options, true)
	return GameState.create(4242, 150, 1800.0, faction, o)


func _test_domains() -> void:
	var techs: Dictionary = GameData.technologies()["technologies"]
	var counts := {}
	for tid: String in techs:
		var t: Dictionary = techs[tid]
		if t.has("pillar") or t.has("mastery") or t.has("requires") or t.has("find") or t.has("victory") or t.has("destiny_stage"):
			continue
		counts[t["domain"]] = int(counts.get(t["domain"], 0)) + 1
	for d in ["armement", "genie", "societe"]:
		_ok(int(counts.get(d, 0)) >= 25 and int(counts.get(d, 0)) <= 34, "domaine resserré : %s, %d technologies principales" % [d, int(counts.get(d, 0))])
	var bad := PackedStringArray()
	for old: String in MERGED:
		if Research.exists(old) or Research.heir_of(old) != String(MERGED[old]):
			bad.append(old)
	_ok(bad.is_empty(), "fusions : l'ancienne technologie disparaît, les sauvegardes la retrouvent chez l'héritière (%s)" % ", ".join(bad))
	# L'héritière garde ce que débloquait l'ancienne.
	_ok(int(Research.tech("bastions")["effects"].get("landing_fire_pct", 0)) == 10, "Bastions : le tir au débarquement de la Défense planétaire")
	_ok(int((Research.tech("habitats")["effects"].get("hab_set", {}) as Dictionary).get("gas_giant", 0)) == 30, "Habitats orbitaux : les géantes gazeuses des Cités flottantes")
	_ok(GameData.building("grand_theatre").get("requires_tech", []).has("propagande"), "le Grand théâtre suit l'Holovision dans la Propagande")
	_ok(Research.is_mastery("logistique_occupation") and Research.is_mastery("generaux_corps"), "deux petites technologies passent en Maîtrises")
	# Charger une sauvegarde qui connaissait l'ancienne technologie.
	var st := _state()
	var e := st.get_empire(0)
	e.techs["holovision"] = true
	var st2 := GameState.from_dict(st.to_dict())
	_ok(st2.get_empire(0).techs.has("propagande") and not st2.get_empire(0).techs.has("holovision"), "sauvegarde : l'Holovision connue devient la Propagande")


func _test_specs() -> void:
	for pair in [["bombardes", "baies"], ["agents_dormants", "legendes_vivantes"], ["adaptation_totale", "spatioports"]]:
		var g := Research.spec_group(String(pair[0]))
		_ok(g != "" and g == Research.spec_group(String(pair[1])) and Research.spec_members(g).size() == 2, "spécialisation : %s ou %s" % pair)
		_ok(Research.spec_taken({String(pair[0]): true}, String(pair[1])) == String(pair[0]), "spécialisation : choisir %s ferme %s" % pair)


func _test_city_fleet() -> void:
	var st := _state("ferrocornes")
	var cf := FactionTraits.city_fleet(st, 0)
	_ok(cf != null, "Ferrocornes : une flotte-ville")
	if cf == null:
		return
	_ok(PeopleHulls.city_battery_pct(st, 0, "flotte_ville") == 100, "sans technologie, batteries ordinaires")
	Research.grant(st, 0, ["campements_fortifies", "flotte_ville_ii"])
	_ok(PeopleHulls.city_battery_pct(st, 0, "flotte_ville") == 150 and PeopleHulls.city_battery_pct(st, 0, "corvette") == 100, "Flotte-ville II : la capitale mobile frappe 50 % plus fort")
	cf.path.clear()
	var far := -1
	for sid in st.galaxy.systems.size():
		if not Fleets.has_own_yard(st, 0, sid):
			far = sid
			break
	cf.system_id = far
	_ok(not Fleets.has_own_yard(st, 0, far), "sans chantier embarqué, pas de chantier au campement")
	Research.grant(st, 0, ["flotte_ville_iii"])
	_ok(Fleets.has_own_yard(st, 0, far), "Flotte-ville III : le campement vaut un chantier ami")
	cf.path.append((far + 1) % st.galaxy.systems.size())
	_ok(not Fleets.has_own_yard(st, 0, far), "en route, plus de chantier")


func _test_exode() -> void:
	var st := _state("exode")
	var base := InsExode.income(st, 0)
	Research.grant(st, 0, ["serres_coursives", "observatoire_proue"])
	var more := InsExode.income(st, 0)
	var anchored := 0
	for f in InsExode.nef_fleets(st, 0):
		if not f.is_moving():
			anchored += f.count(InsExode.SHIP)
	_ok(anchored > 0 and int(more.get("food", 0)) == int(base.get("food", 0)) + 2 * anchored and int(more.get("knowledge", 0)) == int(base.get("knowledge", 0)) + 2 * anchored,
			"modules de nef : chaque nef au mouillage rapporte ce que ses modules rapportent (%d nefs)" % anchored)


func _test_sablier() -> void:
	var st := _state("sablier")
	var ed := Insolites.emp(st, 0)
	ed["sand"] = 200
	var f: Fleet = null
	for x in Fleets.empire_fleets(st, 0):
		f = x
		break
	var home := f.system_id
	var other := -1
	for sid in FactionTraits.jumps_from(st.galaxy, home):
		if int(sid) != home:
			other = int(sid)
			break
	f.path.append(other)
	f.progress = 3
	_ok(SimCommands.validate(st, SimCommands.ins_act(0, "repli", {"fleet": f.id})).contains("technologie"), "Repli : il faut la Bulle de Repli")
	Research.grant(st, 0, ["sable_fin", "bulle_repli"])
	_ok(SimCommands.validate(st, SimCommands.ins_act(0, "repli", {"fleet": f.id})) == "", "Repli possible sur une flotte en route")
	SimCommands.apply(st, SimCommands.ins_act(0, "repli", {"fleet": f.id}))
	_ok(not f.is_moving() and f.system_id == home and f.progress == 0 and int(ed["sand"]) == 200 - Insolites.c_int("sablier", "bubble_sand", 30), "Repli : la flotte est revenue à son départ, le Sable payé")
	# Pli : un chantier s'achève tout de suite.
	var c: Colony = null
	for pid in st.sorted_colony_ids():
		if (st.colonies[pid] as Colony).owner == 0:
			c = st.colonies[pid]
			break
	c.construction = "ferme"
	c.construction_days = 90
	ed["bub"] = 0
	_ok(SimCommands.validate(st, SimCommands.ins_act(0, "pli", {"pid": c.planet_id})).contains("technologie"), "Pli : il faut la Bulle de Pli")
	Research.grant(st, 0, ["bulle_pli"])
	SimCommands.apply(st, SimCommands.ins_act(0, "pli", {"pid": c.planet_id}))
	_ok(c.construction_days == 1, "Pli : le chantier s'achève demain")
	_ok(SimCommands.validate(st, SimCommands.ins_act(0, "pli", {"pid": c.planet_id})).contains("recharge"), "les bulles partagent leur recharge")


func _test_gravea() -> void:
	var st := _state("gravea")
	_ok(InsGravea.work_open(st, 0, "fondre") and not InsGravea.work_open(st, 0, "refroidir"), "Œuvres par ère : Fondre d'emblée, l'étoile plus tard")
	Research.grant(st, 0, ["oeuvre_souffle", "oeuvre_orbites", "oeuvre_etoile"])
	_ok(InsGravea.work_open(st, 0, "habitable") and InsGravea.work_open(st, 0, "deplacer") and InsGravea.work_open(st, 0, "refroidir"), "les trois Œuvres d'ère s'ouvrent avec leurs technologies")


func _test_silencieux() -> void:
	var st := _state("silencieux")
	var e := st.get_empire(0)
	var open := InsSilencieux.unlocked(st, 0)
	_ok(open.has("extraire") and (InsSilencieux.acquisitions(st, 0) >= 16) == open.has("demonter"), "Catalogue des acquisitions : directives selon le nombre de technologies acquises")
	for tid: String in GameData.technologies()["technologies"]:
		if InsSilencieux.acquisitions(st, 0) >= 20:
			break
		if not Research.tech(tid).has("requires"):
			e.techs[tid] = true
	open = InsSilencieux.unlocked(st, 0)
	_ok(open.has("optimiser") and open.has("demonter"), "assez d'acquisitions : Optimiser et Démonter s'ouvrent")
	var cap := FactionTraits.capital_system(st, 0)
	Insolites.emp(st, 0)["dir"] = {"k": "optimiser", "sid": cap, "until": st.tick + 720}
	var pid := -1
	for p in st.sorted_colony_ids():
		if (st.colonies[p] as Colony).owner == 0 and st.galaxy.get_planet(int(p)).system_id == cap:
			pid = int(p)
	_ok(pid >= 0 and InsSilencieux.colony_pct(st, pid) == Insolites.c_int("silencieux", "optimize_pct", 20), "Optimiser les chaînes : production du système en hausse")
	_ok(InsSilencieux.obstacle(st, 0) == -1, "une directive intérieure ne désigne pas d'obstacle")
	var added: Array[Dictionary] = []
	InsSilencieux.daily(st, 0, Insolites.emp(st, 0), true, added)
	_ok(String(InsSilencieux.directive(st, 0)["k"]) == "optimiser", "la directive intérieure dure : on ne la change pas parce que le système est à eux")
	Insolites.emp(st, 0)["dir"] = {"k": "demonter", "sid": cap, "until": st.tick + 720}
	_ok(InsSilencieux.salvage_pct(st, 0) == 200, "Démonter les épaves : les épaves rapportent deux fois plus")


func _test_hulls() -> void:
	var missing := PackedStringArray()
	for hid in Designs.hull_ids():
		var h := Designs.hull(hid)
		var sp: Dictionary = h.get("requires", {}).get("species", {})
		if sp.is_empty():
			continue
		var up: Dictionary = h.get("upgrade", {})
		if up.is_empty() or not Research.exists(String(up.get("tech", ""))):
			missing.append(hid)
	_ok(missing.is_empty(), "toutes les coques de peuple ont leur amélioration (%s)" % ", ".join(missing))
	_ok(PeopleHulls.upgrades_of("comptabilite_occulte").size() == 2, "Comptabilité occulte améliore l'Épave remontée et la Comète-marché")
	_ok(Research.is_visible(GameData.faction("ferrocornes"), "mues_coques") and Research.is_visible(GameData.faction("murmurants"), "accord_parfait"),
			"technologies des coques visibles chez leurs peuples (reptiliens, registre étrange)")


func _test_last() -> void:
	# Corps de mémoire : remplace la Médecine chez Asphodèle, nécropoles qui portent plus loin.
	var asph := GameData.faction("asphodele")
	_ok(Research.is_visible(asph, "corps_memoire") and Research.replaced_by(asph, "medecine") == "corps_memoire", "Corps de mémoire : remplace la Médecine chez Asphodèle")
	var st := _state("asphodele")
	var r0 := InsAsphodele._reach(st, 0).size()
	Research.grant(st, 0, ["corps_memoire"])
	_ok(InsAsphodele._reach(st, 0).size() >= r0 and Insolites.tuned(st, 0, "asphodele", "reach_jumps", 5) == 7, "Corps de mémoire : les Âmes viennent de 7 sauts")
	# Siège de la Compagnie : 2e rang de la capitale, en annexe.
	var sv := _state("ventrelune")
	var e := sv.get_empire(0)
	var cap: Colony = sv.colonies[e.capital_planet]
	_ok(Economy.check_build(sv, 0, cap.planet_id, "siege_compagnie") != "", "Siège : il faut le Rachat à effet de levier")
	Research.grant(sv, 0, ["audit_prealable", "rachat_levier"])
	for r in ["materials", "energy"]:
		e.resources[r] = 5000
	_ok(Economy.check_build(sv, 0, cap.planet_id, "siege_compagnie") == "", "Siège : s'ajoute à la capitale sans emplacement")
	cap.buildings.append("siege_compagnie")
	_ok(InsVentrelune.seat_pct(sv, 0) == 25 and cap.buildings.has("capitale"), "Siège : dividendes +25 %, la capitale reste")
	# Outils des Destinées : chaque première étape apporte un outil de sa victoire.
	var techs: Dictionary = GameData.technologies()["technologies"]
	var bare := PackedStringArray()
	for tid: String in techs:
		if techs[tid].has("victory"):
			var fx: Dictionary = Research.tech(tid + "_etape1").get("effects", {})
			if fx.size() < 2:
				bare.append(tid)
	_ok(bare.is_empty(), "outils des Destinées : chaque première étape fait plus que garder le compte (%s)" % ", ".join(bare))
	var sc := _state("vael")
	var t0 := Research.fx_int(sc, 0, "trade_income_pct")
	Research.grant(sc, 0, ["charte_etape1"])
	_ok(Research.fx_int(sc, 0, "trade_income_pct") == t0 + 15, "Avant-projet de la Charte : le commerce des signataires rapporte plus")
