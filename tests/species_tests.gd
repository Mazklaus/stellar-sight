extends RefCounted
## Tests de l'éditeur d'espèces côté règles (Species, SpeciesLibrary, peuples créés en partie),
## appelés par smoke_test.gd. La bibliothèque est redirigée vers un dossier de test.

const TEST_DIR := "user://test_species"

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Éditeur d'espèces…")
	_test_presets()
	_test_presets_match_officials()
	_test_rules()
	_test_ids()
	_test_library()
	_test_game()
	_test_lithoid()
	_test_synthetic()
	_test_network()
	_test_teyl_game()
	_test_syndicate()
	_test_profit()
	_test_horde()
	_test_reptile()
	_test_save()
	_cleanup()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _spec(preset: String, name := "Peuple d'essai") -> Dictionary:
	var s := Species.from_preset(preset)
	s["name"] = name
	s["short"] = name.substr(0, 12)
	s["id"] = Species.make_id(name, [])
	return s


func _test_presets() -> void:
	var expect := {"ossarane": [2, 4], "choeur": [2, 4], "vael": [4, 4], "khthari": [1, 5], "teyl": [2, 4]}
	for p in expect:
		var s := _spec(p)
		_ok(Species.check(s) == "", "modèle %s valide (%s)" % [p, Species.check(s)])
		var c := Species.cost(s)
		_ok(int(c["used"]) == expect[p][0] and int(c["budget"]) == expect[p][1],
				"modèle %s : %d/%d points (obtenu %d/%d)" % [p, expect[p][0], expect[p][1], c["used"], c["budget"]])
	var neutral := _spec("")
	_ok(Species.check(neutral) == "", "peuple neutre valide (%s)" % Species.check(neutral))
	for t: Dictionary in Species.parts()["traits"]:
		_ok(int(t["cost"]) >= -2 and int(t["cost"]) <= 2, "trait %s coté de -2 à +2" % t["id"])
		for o in t.get("opposes", []):
			_ok((Species.trait_def(String(o)).get("opposes", []) as Array).has(t["id"]), "opposition %s / %s symétrique" % [t["id"], o])
	_ok(Species.portraits("ruche").size() >= 3 and Species.portraits("humanoide").size() >= 3, "au moins 3 portraits par archétype")


## Un peuple créé depuis un modèle reprend les mécaniques de l'officiel (les chiffres restent ceux des briques).
func _test_presets_match_officials() -> void:
	var o := Species.build(_spec("ossarane"))
	_ok(int(o["fleet_speed_pct"]) == 130 and int(o["production_pct"]["crystals"]) == 150 and int(o["production_pct"]["influence"]) == 110, "Ossarane : navigateurs")
	_ok(o.has("fiefs") and int(o["combat"]["home_damage_pct"]) == 115 and int(o["combat"]["garrison_pct"]) == 150, "Ossarane : fiefs et ban")
	_ok(int(o["research"]["tag_cost_pct"]["saut"]) == 75 and String(o["home_deposit"]) == "crystals", "Ossarane : secrets de maison, cristaux")
	var c := Species.build(_spec("choeur"))
	_ok(int(c["production_pct"]["materials"]) == 125 and int(c["production_pct"]["knowledge"]) == 80 and int(c["growth_pct"]) == 80, "Chœur : forges, savoir, croissance")
	_ok(c.has("fervor") and int(c["colony_start_pop"]) == 2 and int(c["combat"]["fervor_per_kill"]) == 2, "Chœur : ferveur, pèlerins, croisade")
	var v := Species.build(_spec("vael"))
	_ok(int(v["hab_floor"]) == 60 and int(v["production_pct"]["influence"]) == 150 and v.has("rush") and int(v["contact_influence"]) == 2, "Vael : quarante peuples, assemblées, vote")
	_ok(int(v["combat"]["reinforcement_pct"]) == 130 and int(v["research"]["peace_knowledge_pct"]) == 5, "Vael : renfort, académies")
	var k := Species.build(_spec("khthari"))
	_ok(int(k["growth_pct"]) == 200 and int(k["food_upkeep_pct"]) == 150 and int(k["production_pct"]["influence"]) == 50, "Kh'thari : fécondité")
	_ok(int(k["production_pct"]["knowledge"]) == 50 and int(k["research"]["knowledge_per_biomass"]) == 2, "Kh'thari : mémoire génétique de ruche")
	_ok(bool(k["claim_influence_free"]) and (k["ships_excluded"] as Array).has("colony_ship") and (k["start_ships"] as Array).has("spore_ship"), "Kh'thari : essaimage")
	_ok(bool(k["combat"]["prey"]) and bool(k["combat"]["digest"]) and bool(k["ai"]["temperament"]["never_peace"]), "Kh'thari : faim sans traité")
	var t := Species.build(_spec("teyl"))
	var off := GameData.faction("teyl")
	_ok(t["network"] == off["network"] and t["assembly"] == off["assembly"] and String(t["diet"]) == "energy" and String(off["diet"]) == "energy", "Teyl : réseau, assemblage, énergie")
	_ok(int(t["production_pct"]["knowledge"]) == int(off["production_pct"]["knowledge"]) and int(t["production_pct"]["materials"]) == int(off["production_pct"]["materials"]) and t["hab_extra"] == off["hab_extra"], "Teyl : érudits, fonderies, châssis étanches")
	_ok(String(t["home_deposit"]) == String(off["home_deposit"]) and int(t["research"]["peace_knowledge_pct"]) == 5, "Teyl : cœur brûlant, académies")
	var humain := _spec("")
	humain["credo"] = "survie"
	_ok(int(Species.build(humain)["production_pct"]["knowledge"]) == 75, "survie sans ruche : Savoir -25 % seulement")
	_ok(Species.build(_spec("vael"))["traits"].size() >= 5, "fiche de règles générée pour l'affichage")


func _err_has(spec: Dictionary, word: String) -> bool:
	for e in Species.errors(spec):
		if e.contains(word):
			return true
	return false


func _test_rules() -> void:
	var s := _spec("")
	s["traits"] = ["navigateurs", "orateurs", "pluriel"]
	_ok(_err_has(s, "budget"), "budget dépassé refusé")
	s["traits"] = ["navigateurs", "casaniers"]
	_ok(_err_has(s, "excluent"), "traits opposés refusés")
	s["traits"] = ["pelerins", "prolifiques"]
	_ok(_err_has(s, "croissance"), "deux traits de croissance refusés")
	s["traits"] = ["casaniers", "distraits", "voraces", "piètres_soldats"]
	_ok(_err_has(s, "défauts"), "plafond de défauts")
	s["traits"] = ["navigateurs", "erudits", "forgerons", "tenaces", "canonniers", "lents"]
	_ok(_err_has(s, "traits au plus"), "6 traits refusés")
	var hive := _spec("khthari")
	hive["traits"] = ["maladroits"]
	_ok(_err_has(hive, "défaut refusé"), "défaut annulé par la ruche refusé")
	hive["traits"] = ["fecondite"]
	hive["gouvernement"] = "republique"
	_ok(_err_has(hive, "demande"), "archétype ruche sans esprit de ruche refusé")
	var h := _spec("")
	h["gouvernement"] = "ruche"
	_ok(_err_has(h, "incompatible") or _err_has(h, "demande"), "esprit de ruche sans corps de ruche refusé")
	h = _spec("")
	h["portrait"] = "ruche_1"
	_ok(Species.check(h) == "", "portrait libre : un humanoïde peut prendre un portrait de ruche")
	h["portrait"] = "inconnu_9"
	_ok(_err_has(h, "portrait"), "portrait inconnu refusé")
	_ok(Species.gallery("ruche").size() == Species.portraits().size() and (Species.gallery("ruche")[0]["archetypes"] as Array).has("ruche"), "galerie complète, archétype en premier")
	h = _spec("")
	h["biomes"] = ["ocean", "ocean"]
	_ok(_err_has(h, "biomes"), "deux biomes identiques refusés")
	h = _spec("")
	h["traits"] = ["navigateurs", "casaniers", "erudits"]
	h["traits"] = ["navigateurs", "orateurs", "distraits", "voraces"]
	_ok(Species.check(h) == "", "4 points + 2 défauts : valide (%s)" % Species.check(h))
	h["origine"] = "sans_heritage"
	h["traits"] = ["navigateurs", "orateurs", "erudits"]
	_ok(Species.check(h) == "", "Partis de rien donne 1 point (%s)" % Species.check(h))
	var u := Species.unlocks(_spec("ossarane"))
	_ok(not (u["victories"] as Array).is_empty() and not (u["abilities"] as Array).is_empty(), "aperçu : victoire et talent de la féodalité")
	_ok((Species.unlocks(_spec("khthari"))["ships"] as Array).has("Vaisseau-spore"), "aperçu : vaisseau-spore de la ruche")


func _test_ids() -> void:
	_ok(Species.make_id("Les Fils d'Ôrme", []) == "p_les_fils_d_orme", "identifiant tiré du nom (%s)" % Species.make_id("Les Fils d'Ôrme", []))
	_ok(Species.make_id("Essai", ["p_essai"]) == "p_essai_2", "identifiant suffixé si pris")
	_ok(not Species.is_valid_id("ossarane") and not Species.is_valid_id("p_A") and not Species.is_valid_id("p_../x"), "identifiants interdits")


func _test_library() -> void:
	SpeciesLibrary.dir = TEST_DIR
	_wipe()
	_ok(SpeciesLibrary.load_all() == 0, "bibliothèque vide")
	var s := _spec("choeur", "Chantres d'Ambre")
	_ok(SpeciesLibrary.save(s) == "", "peuple enregistré")
	_ok(FileAccess.file_exists(SpeciesLibrary.path_for(String(s["id"]))), "fichier écrit")
	GameData.clear_library_factions()
	_ok(SpeciesLibrary.load_all() == 1, "peuple rechargé d'une session à l'autre")
	_ok(GameData.all_faction_ids().has(String(s["id"])) and GameData.faction(String(s["id"]))["name"] == "Chantres d'Ambre", "peuple proposé avec les officiels")
	_ok(SpeciesLibrary.specs()[0]["traits"] == s["traits"], "spec relu à l'identique")
	# Fichier trafiqué à la main : hors budget, refusé au chargement.
	var bad := _spec("", "Tricheurs")
	bad["traits"] = ["navigateurs", "orateurs", "pluriel"]
	var f := FileAccess.open(SpeciesLibrary.path_for(String(bad["id"])), FileAccess.WRITE)
	f.store_string(JSON.stringify(bad))
	f.close()
	_ok(SpeciesLibrary.load_all() == 1 and SpeciesLibrary.rejected.size() == 1, "fichier hors règles écarté")
	_ok(SpeciesLibrary.save(bad) != "", "enregistrement hors règles refusé")
	_ok(SpeciesLibrary.delete(String(bad["id"])) and SpeciesLibrary.delete(String(s["id"])), "peuples supprimés")
	_ok(GameData.library_faction_ids().is_empty(), "bibliothèque vidée")


func _test_game() -> void:
	SpeciesLibrary.dir = TEST_DIR
	var s := _spec("khthari", "Nuée de Vor")
	s["traits"] = ["fecondite", "tenaces"]
	_ok(SpeciesLibrary.save(s) == "", "ruche créée enregistrée")
	var fid := String(s["id"])
	var st := GameState.create(5, 150, 1800.0, fid, {"ai_level": ""})
	_ok(st.empires.size() == 6 and st.empires[0].faction_id == fid, "peuple créé joué par le joueur, 5 officiels en rivaux")
	_ok(st.custom_factions.has(fid), "fiche recopiée dans la partie")
	var spores := 0
	for id in st.fleets:
		if (st.fleets[id] as Fleet).owner == 0 and (st.fleets[id] as Fleet).ships.has("spore_ship"):
			spores += 1
	_ok(spores == 1, "la ruche créée part avec un vaisseau-spore")
	var ids := FactionTraits.ship_ids_for(fid)
	_ok(ids.has("spore_ship") and not ids.has("colony_ship"), "vaisseau-spore lié à l'archétype ruche")
	_ok(FactionTraits.ship_ids_for("khthari").has("spore_ship") and not FactionTraits.ship_ids_for("vael").has("spore_ship"), "officiels inchangés")
	_ok(Diplomacy.no_treaties(st, 0), "la ruche de survie ne signe rien")
	var st2 := GameState.create(5, 150, 1800.0, "", {"rivals": ["vael", fid], "spectator": true})
	_ok(st2.empires.size() == 2 and st2.empires[1].faction_id == fid, "rivaux choisis")
	var sim := Simulation.new(st2)
	sim.advance(400)
	_ok(st2.tick == 400, "une partie entre IA tourne avec un peuple créé")
	var feod := _spec("ossarane", "Maison d'Ivre")
	_ok(SpeciesLibrary.save(feod) == "", "féodalité créée enregistrée")
	var st3 := GameState.create(8, 150, 1800.0, String(feod["id"]), {"ai_level": ""})
	_ok(st3.empires[0].heir_loyalty > 0 and FactionTraits.fleet_speed_pct(st3, 0) == 130, "héritier et navigateurs pour un peuple créé")


## Archétype lithoïde : mange des matériaux, grandit lentement, habite les mondes stériles.
func _test_lithoid() -> void:
	SpeciesLibrary.dir = TEST_DIR
	var s := _spec("vael", "Concile de Basalte")
	s["archetype"] = "lithoide"
	s["portrait"] = "lithoide_2"
	_ok(Species.check(s) == "", "lithoïde valide (%s)" % Species.check(s))
	var g := s.duplicate(true)
	g["gouvernement"] = "ruche"
	_ok(_err_has(g, "incompatible") or _err_has(g, "demande"), "pas d'esprit de ruche pour des lithoïdes")
	_ok(SpeciesLibrary.save(s) == "", "lithoïde enregistré")
	var fid := String(s["id"])
	var f := GameData.faction(fid)
	_ok(FactionTraits.diet(f) == "materials" and int(f["growth_pct"]) == 75, "régime de roche et croissance lente")
	_ok(Economy.habitability("barren", f) == 50 and Economy.habitability("barren", GameData.faction("vael")) == 0, "monde stérile habitable pour lui seul")
	var st := GameState.create(5, 150, 1800.0, fid, {"ai_level": ""})
	_ok(Economy.houses_pop(st, 0, "barren") and not Economy.houses_pop(st, 1, "barren"), "il loge une population sur la roche nue")
	var cap: Colony = st.colonies[st.get_empire(0).capital_planet]
	var y := Economy.colony_yields(st, cap)
	_ok(int(y["upkeep"].get("food", 0)) == 0 and int(y["upkeep"]["materials"]) >= cap.population, "la capitale mange des matériaux, pas de nourriture")
	_ok(Economy.growth_per_day(st, cap) < int(GameData.rules()["growth_per_day"]), "la population grandit plus lentement")
	st.get_empire(0).resources["materials"] = -50
	st.get_empire(0).resources["food"] = 500
	var sim := Simulation.new(st)
	sim.advance(int(GameData.rules()["month_days"]) + 1)
	_ok(st.get_empire(0).starving, "sans matériaux, les lithoïdes ont faim")
	var st2 := GameState.create(3, 150, 1800.0, "", {"rivals": ["choeur", fid], "spectator": true})
	Simulation.new(st2).advance(1440)
	var barren := 0
	for pid in st2.colonies:
		var c: Colony = st2.colonies[pid]
		if c.owner == 1 and c.is_colony() and st2.galaxy.get_planet(pid).type == "barren":
			barren += 1
	_ok(not st2.get_empire(1).eliminated, "l'IA lithoïde survit quatre ans")
	_ok(barren > 0, "l'IA lithoïde colonise des mondes stériles (%d en 4 ans)" % barren)


## Archétype synthétique : population assemblée (matériaux, sans ralentir), énergie au lieu de nourriture,
## mondes toxiques habitables.
func _test_synthetic() -> void:
	SpeciesLibrary.dir = TEST_DIR
	var s := _spec("ossarane", "Noosphère d'Essai")
	s["archetype"] = "synthetique"
	s["portrait"] = "synthetique_1"
	_ok(Species.check(s) == "", "synthétique valide (%s)" % Species.check(s))
	_ok(SpeciesLibrary.save(s) == "", "synthétique enregistré")
	var fid := String(s["id"])
	var f := GameData.faction(fid)
	_ok(FactionTraits.diet(f) == "energy" and FactionTraits.assembly_cost(f) == 12, "régime d'énergie et chaînes d'assemblage")
	_ok(Economy.habitability("toxic", f) == 60, "monde toxique habitable")
	var st := GameState.create(5, 150, 1800.0, fid, {"ai_level": ""})
	var e := st.get_empire(0)
	var cap: Colony = st.colonies[e.capital_planet]
	var y := Economy.colony_yields(st, cap)
	_ok(int(y["upkeep"].get("food", 0)) == 0 and int(y["upkeep"]["energy"]) >= cap.population, "la capitale consomme de l'énergie, pas de nourriture")
	_ok(Economy.colony_threshold(st, cap) == Economy.growth_threshold(0), "l'assemblage ne ralentit pas quand la colonie grandit")
	# Sans matériaux, la chaîne attend ; avec, chaque habitant en coûte 12.
	e.resources["materials"] = 0
	e.resources["energy"] = 500
	var pop0 := cap.population
	var sim := Simulation.new(st)
	sim.advance(20)
	_ok(cap.population == pop0 and cap.growth >= Economy.colony_threshold(st, cap), "sans matériaux, la chaîne attend")
	e.resources["materials"] = 500
	sim.advance(30)
	_ok(cap.population > pop0 and int(e.resources["materials"]) < 500, "avec des matériaux, la chaîne reprend et les dépense")


## Gouvernement Conscience distribuée : bonus de Savoir par nœud relié, nœuds coupés affaiblis.
func _test_network() -> void:
	SpeciesLibrary.dir = TEST_DIR
	var s := _spec("vael", "Réseau d'Essai")
	s["gouvernement"] = "conscience"
	s["archetype"] = "synthetique"
	_ok(Species.check(s) == "", "conscience distribuée valide (%s)" % Species.check(s))
	_ok(SpeciesLibrary.save(s) == "", "conscience distribuée enregistrée")
	var fid := String(s["id"])
	var st := GameState.create(5, 150, 1800.0, fid, {"ai_level": ""})
	var e := st.get_empire(0)
	_ok(FactionTraits.network_nodes(st, 0) == 1 and FactionTraits.network_pct(st, 0) == 5, "la capitale est le premier nœud (+5 %)")
	var base := FactionTraits.production_pct(st, 0, "knowledge")
	# Une colonie voisine reliée, puis coupée par un système ennemi.
	var cap_sys := st.galaxy.get_planet(e.capital_planet).system_id
	var near: int = st.galaxy.systems[cap_sys].neighbors[0]
	var pid: int = st.galaxy.systems[near].planet_ids[0]
	var c := Colony.new()
	c.planet_id = pid
	c.owner = 0
	c.kind = Colony.KIND_COLONY
	c.population = 2
	st.colonies[pid] = c
	st.rebuild_ownership()
	_ok(c.is_established(), "colonie d'essai établie")
	_ok(FactionTraits.is_networked(st, c) and FactionTraits.network_nodes(st, 0) == 2, "la colonie voisine est un nœud")
	_ok(FactionTraits.production_pct(st, 0, "knowledge") > base, "chaque nœud ajoute du Savoir")
	var full: Dictionary = Economy.colony_yields(st, c)["gross"].duplicate()
	# Un nœud entouré de systèmes ennemis est coupé : il produit moitié moins.
	var d := FactionTraits.jumps_from(st.galaxy, cap_sys)
	var far := -1
	for sid in d:
		if int(d[sid]) < 2 or int(d[sid]) > 4 or st.galaxy.systems[sid].planet_ids.is_empty() or st.system_owner(sid) != -1:
			continue
		var ok := true
		for n in st.galaxy.systems[sid].neighbors:
			if n == cap_sys or st.galaxy.systems[n].planet_ids.is_empty() or st.system_owner(n) > 0:
				ok = false
		if ok:
			far = sid
			break
	_ok(far >= 0, "système d'essai à 2-4 sauts trouvé")
	var fc := Colony.new()
	fc.planet_id = st.galaxy.systems[far].planet_ids[0]
	fc.owner = 0
	fc.kind = Colony.KIND_COLONY
	fc.population = 2
	st.colonies[fc.planet_id] = fc
	st.rebuild_ownership()
	_ok(FactionTraits.is_networked(st, fc), "nœud lointain relié tant que la route est libre")
	var linked: Dictionary = Economy.colony_yields(st, fc)["gross"].duplicate()
	for n in st.galaxy.systems[far].neighbors:
		var foe := Colony.new()
		foe.planet_id = st.galaxy.systems[n].planet_ids[0]
		foe.owner = 1
		foe.kind = Colony.KIND_OUTPOST
		st.colonies[foe.planet_id] = foe
	st.rebuild_ownership()
	_ok(not FactionTraits.is_networked(st, fc), "des systèmes ennemis tout autour coupent le nœud")
	var cut: Dictionary = Economy.colony_yields(st, fc)["gross"]
	var halved := true
	for r in linked:
		if int(linked[r]) > 1 and int(cut.get(r, 0)) * 2 > int(linked[r]) + 1:
			halved = false
	_ok(halved, "le nœud coupé produit moitié moins (%s contre %s)" % [cut, linked])
	var g := FactionTraits.gauge(st, 0)
	_ok(bool(g["bad"]) and String(g["label"]) == "Réseau", "la jauge Réseau signale le nœud coupé (%s)" % g.get("value", ""))
	var sim := Simulation.new(GameState.create(9, 150, 1800.0, "", {"rivals": ["choeur", fid], "spectator": true}))
	sim.advance(400)
	_ok(sim.state.tick == 400, "une partie entre IA tourne avec la conscience distribuée")
	_ok(not full.is_empty(), "rendements lus")


## Horde : la capitale est une flotte-ville qui campe, pille, et dont il ne faut pas trop s'éloigner.
func _test_horde() -> void:
	SpeciesLibrary.dir = TEST_DIR
	var s := _spec("ossarane", "Clans d'Essai")
	s["gouvernement"] = "horde"
	_ok(Species.check(s) == "", "horde valide (%s)" % Species.check(s))
	_ok(SpeciesLibrary.save(s) == "", "horde enregistrée")
	var fid := String(s["id"])
	var st := GameState.create(5, 150, 1800.0, fid, {"ai_level": "normal", "rivals": ["vael", "choeur"]})
	var me := st.get_empire(0)
	var home: Colony = st.colonies[me.home_planet]
	var home_sys := st.galaxy.get_planet(me.home_planet).system_id
	var city := FactionTraits.city_fleet(st, 0)
	_ok(me.capital_planet == -1 and not home.buildings.has("capitale"), "aucune planète capitale, pas de palais sur le monde natal")
	_ok(city != null and city.system_id == home_sys and FactionTraits.capital_system(st, 0) == home_sys, "la flotte-ville part du monde natal et sert de capitale")
	_ok(FactionTraits.city_fleet(st, 1) == null and FactionTraits.capital_system(st, 1) == st.galaxy.get_planet(st.get_empire(1).capital_planet).system_id, "les autres gardent leur capitale")
	_ok(Combat.is_armed(city) and not Combat.is_warfleet(city), "flotte-ville armée, mais pas une flotte de guerre")
	# Ce que rapporte la flotte-ville : le palais.
	var palace: Dictionary = GameData.building("capitale")["yields"]
	_ok(int(FactionTraits.city_yields(st, 0).get("influence", 0)) == int(palace["influence"]), "la flotte-ville rapporte ce que rapporte un palais")
	# Campement : +50 % dans le système de la flotte-ville à l'arrêt.
	var camped: Dictionary = Economy.colony_yields(st, home)["gross"].duplicate()
	city.path = [st.galaxy.systems[home_sys].neighbors[0]]
	var moving: Dictionary = Economy.colony_yields(st, home)["gross"].duplicate()
	city.path = []
	var r := "materials" if int(moving.get("materials", 0)) >= int(moving.get("energy", 0)) else "energy"
	_ok(int(moving[r]) > 0 and int(camped[r]) == int(moving[r]) * 150 / 100, "campement : +50 %% (%d contre %d %s)" % [int(camped[r]), int(moving[r]), r])
	# Le clan suit la flotte : une colonie à plus de 4 sauts produit 30 % de moins.
	var d := FactionTraits.jumps_from(st.galaxy, home_sys)
	var far := -1
	for sid in d:
		if int(d[sid]) >= 6 and not st.galaxy.systems[sid].planet_ids.is_empty() and st.system_owner(sid) == -1:
			far = sid
			break
	_ok(far >= 0, "système lointain trouvé")
	var fc := Colony.new()
	fc.planet_id = st.galaxy.systems[far].planet_ids[0]
	fc.owner = 0
	fc.kind = Colony.KIND_COLONY
	fc.population = 4
	st.colonies[fc.planet_id] = fc
	st.rebuild_ownership()
	_ok(FactionTraits.far_from_clan(st, fc) and not FactionTraits.far_from_clan(st, home), "colonie lointaine repérée, le monde natal non")
	var far_y: Dictionary = Economy.colony_yields(st, fc)["gross"].duplicate()
	city.system_id = far
	_ok(not FactionTraits.far_from_clan(st, fc) and FactionTraits.far_from_clan(st, home), "la flotte-ville déplacée rapproche le clan de la colonie")
	var near_y: Dictionary = Economy.colony_yields(st, fc)["gross"]
	var sum_near := 0
	var sum_far := 0
	for k in near_y:
		sum_near += int(near_y[k])
		sum_far += int(far_y.get(k, 0))
	_ok(sum_far > 0 and sum_near > sum_far * 2, "campement contre colonie lointaine : %d contre %d" % [sum_near, sum_far])
	city.system_id = home_sys
	var g := FactionTraits.gauge(st, 0)
	_ok(String(g["label"]) == "Flotte-ville" and String(g["value"]).contains("1 loin"), "jauge Flotte-ville (%s)" % g.get("value", ""))
	_ok(Fleets.check_build_ship(st, 0, me.home_planet, "flotte_ville").contains("un seul"), "une seule flotte-ville à la fois")
	_ok(Fleets.check_build_ship(st, 1, st.get_empire(1).capital_planet, "flotte_ville") != "", "les autres peuples n'en construisent pas")
	# Pillage : une corvette à l'arrêt dans un système ennemi, en guerre.
	var foe := st.get_empire(1)
	var foe_sys := st.galaxy.get_planet(foe.capital_planet).system_id
	for a in [0, 1]:
		for b in [0, 1]:
			if a != b and not st.get_empire(a).contacts.has(b):
				st.get_empire(a).contacts.append(b)
	_ok(FactionTraits.loot_plan(st, 0).is_empty(), "pas de pillage en paix")
	Combat.start_war(st, 0, 1)
	var raider := st.spawn_ship(0, "corvette", foe_sys)
	foe.resources["materials"] = 100
	foe.resources["energy"] = 2
	var plan := FactionTraits.loot_plan(st, 0)
	_ok(plan.size() == 1 and int(plan[0]["fleet"]) == raider.id and int(plan[0]["amounts"]["materials"]) == 6 and int(plan[0]["amounts"]["energy"]) == 2,
			"pillage : 6 matériaux par vaisseau armé, dans la limite des réserves (%s)" % str(plan))
	var mat_before := int(me.resources["materials"])
	var added: Array[Dictionary] = []
	EconomySystem._monthly_traits(st, me, added)
	_ok(int(foe.resources["materials"]) == 94 and int(me.resources["materials"]) == mat_before + 6 and int(me.stats.get("looted", 0)) == 8, "le butin change de main")
	_ok(added.size() == 1 and String(added[0]["text"]).contains("pille"), "chronique du pillage (joueur humain)")
	# Conquête : la capitale d'une horde, c'est sa flotte-ville.
	var before := Victory.progress(st, 1, "conquete")["lines"] as Array
	st.fleets.erase(city.id)
	var after := Victory.progress(st, 1, "conquete")["lines"] as Array
	_ok(str(before) != str(after) and str(after).contains("1 / 2"), "flotte-ville abattue : capitale prise pour la conquête (%s)" % str(after))
	_ok(str(Victory.progress(st, 0, "conquete")["lines"]).contains("PERDUE"), "la horde sans flotte-ville a perdu sa capitale")
	g = FactionTraits.gauge(st, 0)
	_ok(bool(g["bad"]) and String(g["value"]) == "détruite" and FactionTraits.far_from_clan(st, home), "sans flotte-ville, tout le clan s'étiole")
	me.resources["materials"] = 1000
	me.resources["energy"] = 1000
	_ok(Fleets.check_build_ship(st, 0, me.home_planet, "flotte_ville") == "", "la flotte-ville se reconstruit (%s)" % Fleets.check_build_ship(st, 0, me.home_planet, "flotte_ville"))
	# Le clan survit sans planète tant que la flotte-ville vogue.
	var st2 := GameState.create(6, 150, 1800.0, fid, {"ai_level": "normal", "rivals": ["vael"]})
	for pid in st2.sorted_colony_ids():
		if st2.colonies[pid].owner == 0:
			st2.colonies.erase(pid)
	st2.rebuild_ownership()
	var added2: Array[Dictionary] = []
	CombatSystem._eliminations(st2, added2)
	_ok(not st2.get_empire(0).eliminated, "sans planète mais avec sa flotte-ville, le clan vit")
	st2.fleets.erase(FactionTraits.city_fleet(st2, 0).id)
	CombatSystem._eliminations(st2, added2)
	_ok(st2.get_empire(0).eliminated, "sans planète ni flotte-ville, le clan disparaît")
	# Sauvegarde, IA : une partie entre IA tourne, et la flotte-ville campe chez elle.
	var st3 := GameState.create(9, 150, 1800.0, "", {"rivals": ["choeur", fid], "spectator": true})
	var loaded := GameState.from_dict(st3.to_dict())
	_ok(FactionTraits.city_fleet(loaded, 1) != null and loaded.get_empire(1).capital_planet == -1, "la flotte-ville survit au rechargement")
	var sim := Simulation.new(st3)
	sim.advance(720)
	_ok(sim.state.tick == 720 and not sim.state.get_empire(1).eliminated, "une partie entre IA tourne avec une horde")
	var cf := FactionTraits.city_fleet(sim.state, 1)
	_ok(cf != null and sim.state.system_owner(cf.destination()) == 1, "l'IA garde sa flotte-ville chez elle")


## Archétype reptilien : sang-froid (mange moins, pas de monde glaciaire) et transhumance.
func _test_reptile() -> void:
	SpeciesLibrary.dir = TEST_DIR
	var s := _spec("", "Écailles d'Essai")
	s["archetype"] = "reptilien"
	s["biomes"] = ["desert", "arctic"]
	_ok(_err_has(s, "inhabitable"), "un reptilien ne peut pas naître sur un monde glaciaire")
	s["biomes"] = ["desert", "continental"]
	s["portrait"] = "reptilien_1"
	_ok(Species.check(s) == "", "reptilien valide (%s)" % Species.check(s))
	_ok(Species.portraits("reptilien").size() >= 3, "au moins 3 portraits reptiliens")
	_ok(SpeciesLibrary.save(s) == "", "reptilien enregistré")
	var fid := String(s["id"])
	var f := GameData.faction(fid)
	_ok(int(f["food_upkeep_pct"]) == 70 and bool(f["migration"]), "sang-froid et transhumance dans la fiche")
	_ok(Economy.habitability("arctic", f) == 0 and Economy.habitability("arctic", GameData.faction("vael")) > 0, "monde glaciaire inhabitable pour lui seul")
	var st := GameState.create(5, 150, 1800.0, fid, {"ai_level": "normal", "rivals": ["vael"]})
	var me := st.get_empire(0)
	var home: Colony = st.colonies[me.home_planet]
	var up := int(Economy.colony_yields(st, home)["upkeep"].get("food", 0))
	_ok(up == home.population * int(GameData.rules()["food_per_pop"]) * 70 / 100, "chaque habitant mange 30 %% de moins (%d)" % up)
	_ok(FactionTraits.migrates(st, 0) and not FactionTraits.migrates(st, 1), "transhumance dès le départ, pour lui seul")
	# Une colonie pleine envoie ses naissances dans la colonie la moins peuplée.
	var cap_sys := st.galaxy.get_planet(me.home_planet).system_id
	var free_pid := -1
	for pid in st.galaxy.systems[cap_sys].planet_ids:
		if not st.colonies.has(pid) and Economy.habitability_for(st, 0, st.galaxy.get_planet(pid).type) > 0:
			free_pid = pid
			break
	if free_pid < 0:
		for pid in st.galaxy.systems[cap_sys].planet_ids:
			if not st.colonies.has(pid):
				free_pid = pid
				st.override_planet(pid, {"type": "desert"})
				break
	var c := Colony.new()
	c.planet_id = free_pid
	c.owner = 0
	c.kind = Colony.KIND_COLONY
	c.population = 1
	st.colonies[free_pid] = c
	st.rebuild_ownership()
	home.population = Economy.max_pop(st, st.galaxy.get_planet(home.planet_id), 0, home.buildings)
	var full := home.population
	home.growth = Economy.colony_threshold(st, home) - 1
	var added: Array[Dictionary] = []
	EconomySystem._process_colony(st, home, added)
	_ok(home.population == full and c.population == 2, "la colonie pleine peuple la plus petite (%d, %d)" % [home.population, c.population])
	var sim := Simulation.new(GameState.create(9, 150, 1800.0, "", {"rivals": ["choeur", fid], "spectator": true}))
	sim.advance(400)
	_ok(sim.state.tick == 400, "une partie entre IA tourne avec un peuple reptilien")


func _test_save() -> void:
	SpeciesLibrary.dir = TEST_DIR
	var s := _spec("vael", "Concile de Lys")
	_ok(SpeciesLibrary.save(s) == "", "république créée enregistrée")
	var fid := String(s["id"])
	var st := GameState.create(11, 150, 1800.0, fid, {"ai_level": "normal"})
	Simulation.new(st).advance(120)
	var d := st.to_dict()
	var sum := st.checksum()
	# Le peuple a disparu de la bibliothèque : la sauvegarde se recharge quand même.
	SpeciesLibrary.delete(fid)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null, "sauvegarde rechargée sans le fichier du peuple (%s)" % GameState.last_error)
	if back:
		_ok(back.get_empire(0).faction_id == fid and back.get_empire(0).display_name() == "Concile de Lys", "peuple retrouvé dans la sauvegarde")
		_ok(back.checksum() == sum, "empreinte identique après rechargement")
		Simulation.new(back).advance(30)
		_ok(back.tick == 150, "la partie rechargée continue")


func _cleanup() -> void:
	_wipe()
	SpeciesLibrary.dir = SpeciesLibrary.DEFAULT_DIR
	GameData.clear_library_factions()
	GameData.clear_game_factions()


func _wipe() -> void:
	var d := DirAccess.open(TEST_DIR)
	if d == null:
		return
	for n in d.get_files():
		d.remove(n)


## Teyl en 5e peuple officiel : proposé par défaut et joué par l'IA.
func _test_teyl_game() -> void:
	_ok(GameData.is_official("teyl") and GameData.portrait_art("teyl") == "faction_teyl", "Teyl : peuple officiel, emplacement d'illustration comme les autres")
	var sim := Simulation.new(GameState.create(11, 150, 1800.0, "", {"spectator": true, "ai_level": "normal"}))
	var tid := -1
	for e in sim.state.empires:
		if e.faction_id == "teyl":
			tid = e.id
	_ok(sim.state.empires.size() == 5 and tid >= 0, "partie par défaut : cinq peuples dont Teyl")
	sim.advance(720)
	var e := sim.state.get_empire(tid)
	var nodes := FactionTraits.network_nodes(sim.state, tid)
	_ok(not e.eliminated and nodes >= 2, "Teyl (IA) : en vie après deux ans, %d nœuds reliés" % nodes)


## Gouvernement Syndicat : comptoirs, colonies chères, flottes à louer.
func _test_syndicate() -> void:
	SpeciesLibrary.dir = TEST_DIR
	var s := _spec("vael", "Comptoir d'Essai")
	s["gouvernement"] = "syndicat"
	_ok(Species.check(s) == "", "syndicat valide (%s)" % Species.check(s))
	_ok(SpeciesLibrary.save(s) == "", "syndicat enregistré")
	var fid := String(s["id"])
	var st := GameState.create(5, 150, 1800.0, fid, {"ai_level": "normal", "rivals": ["vael", "choeur"]})
	var me := st.get_empire(0)
	var vael := st.get_empire(1)
	var choeur := st.get_empire(2)
	_ok(Diplomacy.has_ability(st, 0, "mercenary") and not Diplomacy.has_ability(st, 1, "mercenary"), "flottes à louer : talent du syndicat")
	# Colonies chères, comptoirs rentables.
	var cap_sys := st.galaxy.get_planet(me.capital_planet).system_id
	var free_pid := -1
	for pid in st.galaxy.systems[cap_sys].planet_ids:
		if not st.colonies.has(pid):
			free_pid = pid
			break
	_ok(free_pid >= 0, "planète libre chez soi")
	var vcost := Economy.claim_cost(Colony.KIND_COLONY)
	_ok(int(Economy.claim_cost_for(st, 0, free_pid, Colony.KIND_COLONY)["influence"]) == 2 * int(vcost["influence"]), "une vraie colonie coûte deux fois plus d'influence")
	_ok(int(Economy.claim_cost_for(st, 0, free_pid, Colony.KIND_OUTPOST)["influence"]) == int(Economy.claim_cost(Colony.KIND_OUTPOST)["influence"]), "un avant-poste coûte le prix normal")
	var post := Colony.new()
	post.planet_id = free_pid
	post.owner = 0
	post.kind = Colony.KIND_OUTPOST
	st.colonies[free_pid] = post
	st.rebuild_ownership()
	var gross: Dictionary = Economy.colony_yields(st, post)["gross"]
	var plain: Dictionary = GameData.planet_type(st.galaxy.get_planet(free_pid).type).get("outpost_yields", {})
	_ok(int(gross.get("energy", 0)) >= int(plain.get("energy", 0)) + 2, "un avant-poste est un comptoir (+2 énergie)")
	# Le contrat : Vael en guerre contre le Chœur loue nos flottes.
	for a in [0, 1, 2]:
		for b in [0, 1, 2]:
			if a != b and not st.get_empire(a).contacts.has(b):
				st.get_empire(a).contacts.append(b)
	var cmd := SimCommands.contract(0, 0, 1, 2)
	_ok(SimCommands.validate(st, cmd).contains("pas en guerre"), "pas de contrat sans guerre du client")
	Combat.start_war(st, 1, 2)
	_ok(Diplomacy.warships(st, 0) == 2, "deux corvettes au départ")
	for f in Fleets.empire_fleets(st, 0):
		if Combat.is_armed(f):
			st.fleets.erase(f.id)
	_ok(SimCommands.validate(st, cmd).contains("vaisseaux armés"), "pas de contrat sans flotte à louer")
	for i in 3:
		st.spawn_ship(0, "corvette", cap_sys)
	_ok(SimCommands.validate(st, cmd) == "", "contrat possible (%s)" % SimCommands.validate(st, cmd))
	var fee := int(Diplomacy.contract_fee(st, 0)["energy"])
	_ok(fee == 8 + 2 * 3, "prix : 8 + 2 par vaisseau armé (%d)" % fee)
	vael.resources["energy"] = 2000
	var inc_before := int(Economy.empire_income(st, 1)["net"].get("energy", 0))
	var ev := AiDiplomacy.evaluate_contract(st, 1, 0, 1, 2)
	_ok(int(ev["score"]) >= 0, "Vael (IA) accepte des renforts (%d : %s)" % [int(ev["score"]), str(ev["parts"])])
	SimCommands.apply(st, cmd)
	var c := Diplomacy.contract_of(st, 0)
	_ok(not c.is_empty() and int(c["client"]) == 1 and int(c["target"]) == 2, "contrat signé")
	_ok(Combat.at_war(st, 0, 2) and not Combat.at_war(st, 0, 1), "les mercenaires entrent en guerre contre la cible seulement")
	_ok(int(Diplomacy.treaty_income(st, 0).get("energy", 0)) == fee and int(Economy.empire_income(st, 1)["net"].get("energy", 0)) <= inc_before - fee, "le client paie, le mercenaire encaisse (%d, %d -> %d)" % [int(Diplomacy.treaty_income(st, 0).get("energy", 0)), inc_before, int(Economy.empire_income(st, 1)["net"].get("energy", 0))])
	_ok(FactionTraits.gauge(st, 0)["label"] == "Contrat" and FactionTraits.gauge(st, 0)["value"] == vael.short_name(), "jauge Contrat")
	_ok(SimCommands.validate(st, SimCommands.contract(0, 0, 2, 1)) != "", "un seul contrat à la fois")
	# Les mercenaires (IA ou non) ne font pas la paix avec leur cible en cours de contrat.
	_ok(int(AiDiplomacy.evaluate(st, 0, 2, Diplomacy.PEACE)["score"]) < 0, "pas de paix avec la cible pendant le contrat")
	# La guerre du client finit : contrat honoré, les mercenaires signent la paix avec la cible.
	Diplomacy.sign_treaty(st, 1, 2, Diplomacy.PEACE)
	Diplomacy.contract_month(st, 0)
	_ok(Diplomacy.contract_of(st, 0).is_empty() and not Combat.at_war(st, 0, 2) and Diplomacy.pact(st, 0, 2) == Diplomacy.PEACE, "fin de guerre : fin du contrat et paix avec la cible")
	_ok(Diplomacy.opinion_parts(st, 1, 0).any(func(p: Dictionary) -> bool: return String(p["label"]).contains("tenu parole")), "le client s'en souvient en bien")
	_ok(SimCommands.validate(st, cmd) != "", "repos des mercenaires entre deux contrats")
	# Un client qui ne paie plus perd ses mercenaires.
	var st2 := GameState.create(6, 150, 1800.0, fid, {"ai_level": "normal", "rivals": ["vael", "choeur"]})
	for a in [0, 1, 2]:
		for b in [0, 1, 2]:
			if a != b and not st2.get_empire(a).contacts.has(b):
				st2.get_empire(a).contacts.append(b)
	Combat.start_war(st2, 1, 2)
	for i in 2:
		st2.spawn_ship(0, "corvette", st2.galaxy.get_planet(st2.get_empire(0).capital_planet).system_id)
	Diplomacy.sign_contract(st2, 0, 1, 2)
	st2.get_empire(1).resources["energy"] = -5
	Diplomacy.contract_month(st2, 0)
	_ok(Diplomacy.contract_of(st2, 0).is_empty() and Diplomacy.opinion_parts(st2, 0, 1).any(func(p: Dictionary) -> bool: return String(p["label"]).contains("payé")), "client insolvable : contrat rompu, rancune")
	# Sauvegarde : le contrat survit au rechargement.
	Diplomacy.end_contract(st2, 0, "gone")
	var st3 := GameState.create(7, 150, 1800.0, fid, {"ai_level": "normal", "rivals": ["vael", "choeur"]})
	for a in [0, 1, 2]:
		for b in [0, 1, 2]:
			if a != b and not st3.get_empire(a).contacts.has(b):
				st3.get_empire(a).contacts.append(b)
	Combat.start_war(st3, 1, 2)
	Diplomacy.sign_contract(st3, 0, 1, 2)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st3.to_dict())))
	_ok(back != null and int(Diplomacy.contract_of(back, 0).get("target", -1)) == 2, "contrat sauvegardé et rechargé")
	# Une partie entre IA avec un syndicat : rien ne casse, et il trouve des clients.
	var sp := Simulation.new(GameState.create(9, 150, 1800.0, "", {"spectator": true, "ai_level": "normal", "rivals": ["ossarane", "choeur", fid, "vael", "khthari"]}))
	var signed := 0
	for i in 18:
		sp.advance(60)
		for e in sp.state.empires:
			if not Diplomacy.contract_of(sp.state, e.id).is_empty():
				signed += 1
	_ok(signed > 0, "partie entre IA : le syndicat trouve des clients (%d relevés sous contrat sur 18)" % signed)


## Credo Profit : espionnage industriel, branché sur l'espionnage commun (Espionage, talent "spy").
func _test_profit() -> void:
	SpeciesLibrary.dir = TEST_DIR
	var s := _spec("vael", "Marchands d'Essai")
	s["credo"] = "profit"
	_ok(Species.check(s) == "", "credo profit valide (%s)" % Species.check(s))
	_ok(SpeciesLibrary.save(s) == "", "credo profit enregistré")
	var fid := String(s["id"])
	var f := GameData.faction(fid)
	var spy: Dictionary = f["research"]["spy"]
	_ok(int(f["production_pct"]["knowledge"]) == 85 and int(spy["extra_cells"]) == 1 and int(spy["larcin_cost_pct"]) == 50, "Savoir -15 %, +1 cellule, larcins à moitié prix")
	var st := GameState.create(5, 150, 1800.0, fid, {"ai_level": "", "rivals": ["vael", "choeur"]})
	for a in [0, 1, 2]:
		for b in [0, 1, 2]:
			if a != b and not st.get_empire(a).contacts.has(b):
				st.get_empire(a).contacts.append(b)
	_ok(Espionage.cells_total(st, 0) == 3 and Espionage.cells_total(st, 1) == 2, "3 cellules au lieu de 2")
	_ok(int(Espionage.op_cost(st, 0, "vol_techno")["influence"]) == 20 and int(Espionage.op_cost(st, 1, "vol_techno")["influence"]) == 40, "voler une technologie : 20 influence au lieu de 40")
	_ok(Research.steal_target(st, 0, 1) == "", "rien à voler au départ (mêmes technologies)")
	# Vael apprend deux technologies que nous pourrions chercher.
	var avail: Array[String] = []
	for tid in Research.visible_ids(st.get_empire(0).faction()):
		if Research.is_available(st, 0, String(tid)) and Research.is_visible(st.get_empire(1).faction(), String(tid)) and Research.is_available(st, 1, String(tid)):
			avail.append(String(tid))
	_ok(avail.size() >= 2, "technologies cherchables trouvées (%d)" % avail.size())
	Research.grant(st, 1, avail.slice(0, 2))
	var tid := Research.steal_target(st, 0, 1)
	_ok(avail.slice(0, 2).has(tid), "cible : une technologie de Vael (%s)" % tid)
	# Réseau deux fois plus rapide chez un partenaire commercial.
	Espionage.set_cells(st, 0, 1, 1)
	var g := Espionage.growth(st, 0, 1)
	Diplomacy._rel_w(st, 0, 1)["trade"] = 1
	_ok(Espionage.growth(st, 0, 1) > g + 2, "commerce : réseau plus rapide (%d contre %d)" % [Espionage.growth(st, 0, 1), g])
	# Dividende : un réseau à 40 chez un partenaire commercial rapporte 25 % d'une technologie, tous les six mois.
	st.networks[Espionage.key(0, 1)]["inf"] = 50
	var sim := Simulation.new(st)
	var before := Research.progress_of(st, 0, tid)
	sim.advance(360)
	var n := int(st.get_empire(0).stats.get("stolen", 0))
	_ok(n == 2 or Research.knows(st, 0, tid), "deux dividendes en un an (%d)" % n)
	_ok(Research.progress_of(st, 0, tid) > before or Research.knows(st, 0, tid), "le dividende fait avancer la technologie")
	_ok(Espionage.talent(st, 1).is_empty(), "Vael n'a pas ce talent")

