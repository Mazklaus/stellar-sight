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
