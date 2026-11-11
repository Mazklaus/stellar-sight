extends RefCounted
## Tests de la recherche : données de l'arbre, arbre propre à chaque peuple (variantes, interdits,
## hérésies), file et seuils d'ère, coûts, avancée mensuelle, effets des technologies sur l'économie,
## les flottes et le combat, contenu verrouillé, IA qui recherche, sauvegarde et déterminisme.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Recherche…")
	_test_data()
	_test_faction_trees()
	_test_queue_and_eras()
	_test_costs()
	_test_monthly_progress()
	_test_effects()
	_test_locked_content()
	_test_faction_research()
	_test_ai_research()
	_test_save_roundtrip()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _state(faction := "vael") -> GameState:
	return GameState.create(31, 150, 1800.0, faction, {"ai_level": ""})


func _test_data() -> void:
	var d := Research.data()
	_ok(Research.domain_ids() == ["armement", "genie", "economie", "societe"], "quatre domaines")
	_ok(Research.eras() == 5, "cinq ères")
	var bad := PackedStringArray()
	var techs: Dictionary = d["technologies"]
	for tid in techs:
		var t: Dictionary = techs[tid]
		if not Research.domain_ids().has(String(t.get("domain", ""))) or int(t.get("era", 0)) < 1 or int(t["era"]) > 5:
			bad.append(tid)
		for p in t.get("pre", []):
			if not techs.has(p) or int(techs[p]["era"]) > int(t["era"]):
				bad.append("%s<-%s" % [tid, p])
		if t.has("replaces") and not techs.has(t["replaces"]):
			bad.append(tid)
	_ok(bad.is_empty(), "arbre cohérent : domaines, ères, prérequis antérieurs (%s)" % ", ".join(bad))
	_ok(techs.size() >= 85, "environ 90 technologies (%d)" % techs.size())
	var refs := PackedStringArray()
	for bid in GameData.buildings():
		for t in GameData.building(bid).get("requires_tech", []):
			if not techs.has(t):
				refs.append(t)
	for sid in GameData.ship_ids():
		for t in GameData.ship(sid).get("requires_tech", []):
			if not techs.has(t):
				refs.append(t)
	_ok(refs.is_empty(), "bâtiments et vaisseaux citent des technologies qui existent (%s)" % ", ".join(refs))


func _test_faction_trees() -> void:
	var choeur := GameData.faction("choeur")
	var vael := GameData.faction("vael")
	var kh := GameData.faction("khthari")
	_ok(Research.is_visible(choeur, "scriptorium") and not Research.is_visible(choeur, "academies"), "le Chœur a le Scriptorium à la place des Académies")
	_ok(Research.is_visible(vael, "universites") and Research.is_visible(kh, "ganglions"), "Universités pour Vael, Ganglions pour l'Essaim")
	_ok(not Research.is_visible(choeur, "automatisation") and Research.is_visible(choeur, "serviteurs"), "Automatisation interdite au Chœur, Serviteurs à la place")
	_ok(Research.is_heretic(choeur, "genetique") and not Research.is_heretic(vael, "genetique"), "Génétique hérétique pour le Chœur seulement")
	_ok(not Research.is_visible(vael, "litanies") and Research.is_visible(choeur, "litanies"), "les Litanies sont réservées au credo de la foi")
	for f: Dictionary in GameData.factions():
		var n := Research.visible_ids(f).size()
		_ok(n >= 60, "%s : arbre de %d technologies" % [f["short"], n])
	# Un peuple de l'éditeur qui partage les couches d'espèce y a droit aussi.
	var custom := {"id": "test_moines", "species": {"archetype": "humanoide", "gouvernement": "theocratie", "credo": "foi", "traits": []}, "registre": "Médiéval spatial"}
	_ok(Research.is_visible(custom, "scriptorium") and Research.is_visible(custom, "litanies"), "un peuple personnalisé théocrate a le Scriptorium et les Litanies")
	_ok(not Research.is_heretic(custom, "genetique"), "l'hérésie dépend du registre, pas du nom du peuple")


func _test_queue_and_eras() -> void:
	var st := _state()
	var e := st.get_empire(0)
	_ok(Research.check_queue(st, 0, "tour_de_babel") != "", "technologie inconnue refusée")
	_ok(Research.check_queue(st, 0, "boucliers_phase").contains("Lentilles"), "prérequis manquant expliqué")
	_ok(Research.check_queue(st, 0, "litanies") != "", "technologie d'un autre peuple refusée")
	_ok(_apply(st, SimCommands.research(0, "lentilles")), "Lentilles en file")
	_ok(_apply(st, SimCommands.research(0, "boucliers_phase")) == false, "ère 2 fermée tant qu'il manque une technologie d'ère 1")
	_ok(_apply(st, SimCommands.research(0, "canons_masse")), "Canons en file")
	_ok(_apply(st, SimCommands.research(0, "boucliers_phase")), "l'ère 2 s'ouvre avec deux technologies d'ère 1 planifiées")
	_ok(e.research_queue == ["lentilles", "canons_masse", "boucliers_phase"], "file dans l'ordre (%s)" % [e.research_queue])
	_ok(_apply(st, SimCommands.research(0, "lentilles")) == false, "pas deux fois dans la file")
	_ok(_apply(st, SimCommands.research_remove(0, "lentilles")), "retrait de la file")
	_ok(e.research_queue == ["canons_masse"], "les technologies qui en dépendaient partent avec elle (%s)" % [e.research_queue])
	e.research_progress = 30
	_ok(_apply(st, SimCommands.research(0, "lentilles", true)), "recherche en tête de file")
	_ok(e.research_queue[0] == "lentilles" and e.research_progress == 0 and int(e.research_shelf.get("canons_masse", 0)) == 30,
			"le Savoir de la recherche interrompue est mis de côté")
	_ok(_apply(st, SimCommands.research(0, "canons_masse", true)), "on revient à la recherche interrompue")
	_ok(e.research_progress == 30, "elle retrouve son Savoir investi")
	Research.grant(st, 0, ["lentilles", "canons_masse"])
	_ok(Research.era_open(e.techs, "armement", 2) and not Research.era_open(e.techs, "armement", 3), "ère 2 ouverte, ère 3 fermée")
	_ok(Research.current_era(st, 0) == 2, "ère la plus avancée : 2")
	_ok(Research.is_available(st, 0, "boucliers_phase") and not Research.is_available(st, 0, "plasma"), "disponibilités")


func _test_costs() -> void:
	var st := _state()
	var c1 := Research.cost(st, 0, "lentilles")
	var c2 := Research.cost(st, 0, "boucliers_phase")
	_ok(c1 > 0 and c2 > c1 * 2, "l'ère 2 coûte bien plus que l'ère 1 (%d, %d)" % [c1, c2])
	Research.grant(st, 0, ["canons_masse", "tetes_chercheuses"])
	_ok(Research.cost(st, 0, "lentilles") > c1, "chaque technologie connue renchérit les suivantes")
	var so := _state("ossarane")
	_ok(Research.cost(so, 0, "cartes_lignees") * 100 / Research.cost(so, 0, "capteurs") <= 76, "Ossarane : technologies de saut 25 % moins chères")
	var sc := _state("choeur")
	_ok(Research.cost(sc, 0, "medecine") > Research.cost(sc, 0, "hydroponie"), "Chœur : la société coûte plus cher")
	_ok(Research.cost(sc, 0, "genetique") > Research.cost(_state("vael"), 0, "genetique"), "Chœur : l'hérésie coûte plus cher")
	# Taille de l'empire : au-delà des colonies gratuites, chaque colonie renchérit la recherche.
	var big := _state()
	var base := Research.cost(big, 0, "lentilles")
	var n := 0
	for p in big.galaxy.planets:
		if n >= 12:
			break
		if not big.colonies.has(p.id) and p.is_habitable_type():
			var c := Colony.new()
			c.planet_id = p.id
			c.owner = 0
			c.kind = Colony.KIND_COLONY
			c.population = 1
			big.add_colony(c)
			n += 1
	_ok(Research.cost(big, 0, "lentilles") > base, "un grand empire paie sa recherche plus cher")


func _test_monthly_progress() -> void:
	var sim := Simulation.new(_state())
	var st := sim.state
	var e := st.get_empire(0)
	var income := int(Economy.empire_income(st, 0)["net"]["knowledge"])
	_ok(income > 0, "la capitale produit du Savoir (%d par mois)" % income)
	e.resources["knowledge"] = 0
	sim.submit(SimCommands.research(0, "rhetorique"))
	sim.advance(30)
	_ok(e.research_progress > 0 or e.techs.has("rhetorique"), "le Savoir du mois va à la recherche en cours")
	var guard := 0
	while not e.techs.has("rhetorique") and guard < 40:
		sim.advance(30)
		guard += 1
	_ok(e.techs.has("rhetorique") and e.research_queue.is_empty(), "Rhétorique découverte en %d mois" % (guard + 1))
	_ok(st.chronicle.any(func(c: Dictionary) -> bool: return String(c["text"]).contains("Rhétorique")), "la chronique annonce la découverte du joueur")
	# Une réserve accumulée s'écoule, mais pas d'un coup.
	_ok(Research.monthly_budget(1200, 10) == 200 and Research.monthly_budget(50, 10) == 20, "budget mensuel : deux fois le revenu, ou un douzième de la réserve")


func _test_effects() -> void:
	var st := _state()
	var e := st.get_empire(0)
	var home := e.capital_planet
	var before: Dictionary = Economy.empire_income(st, 0)["gross"]
	Research.grant(st, 0, ["hydroponie", "rhetorique"])
	var after: Dictionary = Economy.empire_income(st, 0)["gross"]
	_ok(int(after["food"]) > int(before["food"]) and int(after["influence"]) > int(before["influence"]), "Hydroponie et Rhétorique augmentent la production")
	var g0 := Economy.growth_per_day(st, st.colonies[home])
	Research.grant(st, 0, ["medecine"])
	_ok(Economy.growth_per_day(st, st.colonies[home]) > g0, "Médecine accélère la croissance")
	_ok(Economy.max_projects_for(st, 0) == int(GameData.rules()["max_projects"]), "fondations simultanées de base")
	Research.grant(st, 0, ["administration"])
	_ok(Economy.max_projects_for(st, 0) == int(GameData.rules()["max_projects"]) + 1, "Administration : une fondation de plus")
	# Habitabilité : les géantes gazeuses deviennent habitables avec les cités flottantes.
	var gas: Planet = null
	for p in st.galaxy.planets:
		if p.type == "gas_giant":
			gas = p
			break
	var sk := _state("khthari")
	_ok(Economy.max_pop(sk, gas, 0) == 0, "géante gazeuse inhabitable sans technologie")
	Research.grant(sk, 0, ["cites_flottantes"])
	_ok(Economy.max_pop(sk, gas, 0) > 0 and Economy.habitability_for(sk, 0, "gas_giant") == 30, "Cités flottantes : géantes gazeuses à 30 %")
	_ok(Economy.habitability_for(st, 0, "arctic") < 100, "habitabilité ordinaire")
	var h0 := Economy.habitability_for(st, 0, "desert")
	Research.grant(st, 0, ["adaptation", "biomes_extremes"])
	_ok(Economy.habitability_for(st, 0, "desert") == mini(100, h0 + 20), "Biomes extrêmes : +20 % sur les déserts")
	# Flottes : vitesse, coûts, durée, entretien, vision.
	var f := st.spawn_ship(0, "corvette", st.galaxy.get_planet(home).system_id)
	var v0 := Fleets.speed(f, st)
	var cost0 := int(Fleets.ship_cost(st, 0, "corvette")["materials"])
	var days0 := Fleets.ship_days(st, 0, "corvette")
	var up0 := Fleets.upkeep(st, 0).duplicate()
	Research.grant(st, 0, ["propulseurs", "cales_rapides", "coques_series", "capteurs"])
	_ok(Fleets.speed(f, st) > v0, "Propulseurs : flottes plus rapides")
	_ok(int(Fleets.ship_cost(st, 0, "corvette")["materials"]) < cost0, "Coques en série : vaisseaux moins chers")
	_ok(Fleets.ship_days(st, 0, "corvette") < days0, "Cales rapides : vaisseaux plus vite construits")
	Research.grant(st, 0, ["extraction", "logistique", "recyclage", "ravitaillement"])
	_ok(int(Fleets.upkeep(st, 0).get("energy", 0)) <= int(up0.get("energy", 0)), "Ravitaillement : entretien réduit")
	# Combat : dégâts par famille et protection.
	var raw := Combat.shot_damage("kinetic", 240, 1, "equilibre", 100, "croiseur", "equilibre")
	var strong := Combat.shot_damage("kinetic", 240, 1, "equilibre", 100 + 20, "croiseur", "equilibre")
	var armored := Combat.shot_damage("kinetic", 240, 1, "equilibre", 100, "croiseur", "equilibre", 0, {"armor": 40})
	_ok(strong > raw and armored < raw, "dégâts et blindage des technologies (%d, %d, %d)" % [raw, strong, armored])
	Research.grant(st, 0, ["canons_masse"])
	_ok(Combat.weapon_bonus(st, 0, "kinetic") == 20 and Combat.weapon_bonus(st, 0, "beam") == 0, "Canons à masse réactive : +20 % aux armes cinétiques seulement")
	var tr := st.spawn_ship(0, "transport", st.galaxy.get_planet(home).system_id)
	var t0 := Combat.max_troops(tr, st)
	Research.grant(st, 0, ["marines"])
	_ok(Combat.max_troops(tr, st) > t0, "Marines : plus de troupes")


func _test_locked_content() -> void:
	var st := _state()
	var e := st.get_empire(0)
	for r in e.resources:
		e.resources[r] = 9999
	var cap := e.capital_planet
	_ok(Economy.check_build(st, 0, cap, "academie").contains("technologie"), "Académie verrouillée au départ")
	_ok(Economy.check_build(st, 0, cap, "universite").contains("technologie"), "Université verrouillée au départ")
	_ok(Fleets.check_build_ship(st, 0, cap, "transport").contains("technologie"), "Transport verrouillé au départ")
	_ok(Fleets.check_build_ship(st, 0, cap, "corvette") == "", "les premières coques restent libres")
	Research.grant(st, 0, ["universites"])
	_ok(Economy.check_build(st, 0, cap, "universite") == "", "Université débloquée")
	_ok(Economy.check_build(st, 0, cap, "academie") != "", "la variante ne débloque pas le bâtiment commun")
	Research.grant(st, 0, ["debarquement"])
	_ok(Fleets.check_build_ship(st, 0, cap, "transport") == "", "Transport débloqué")
	_ok(Research.unlocks(e.faction(), "coques_lourdes").has(String(GameData.ship("croiseur")["label"])), "la fiche dit ce qu'une technologie débloque")
	var k0 := int(Economy.colony_yields(st, st.colonies[cap])["gross"]["knowledge"])
	st.colonies[cap].buildings.append("universite")
	_ok(int(Economy.colony_yields(st, st.colonies[cap])["gross"]["knowledge"]) >= k0 + 6, "l'Université produit du Savoir")
	# Alliances : Chancelleries des deux côtés.
	var sd := _state()
	for a in 2:
		sd.get_empire(a).contacts.append(1 - a)
	Diplomacy.sign_treaty(sd, 0, 1, Diplomacy.PEACE)
	Diplomacy._rel_w(sd, 0, 1)["since"] = sd.tick - 400
	Diplomacy._rel_w(sd, 0, 1)["truce"] = 0
	_ok(Diplomacy.check_terms(sd, 0, 1, Diplomacy.ALLIANCE).contains("Chancelleries"), "alliance impossible sans Chancelleries")
	Research.grant(sd, 0, ["chancelleries"])
	_ok(Diplomacy.check_terms(sd, 0, 1, Diplomacy.ALLIANCE).contains("chancelleries"), "il faut aussi des chancelleries en face")
	Research.grant(sd, 1, ["chancelleries"])
	_ok(Diplomacy.check_terms(sd, 0, 1, Diplomacy.ALLIANCE) == "", "alliance possible quand les deux ont des Chancelleries")


func _test_faction_research() -> void:
	# Chœur : ferveur des technologies d'armement, hérésie qui coûte de la ferveur, Exaltation.
	var sc := _state("choeur")
	var c := sc.get_empire(0)
	c.fervor = 40
	Research.complete(sc, 0, "canons_masse")
	_ok(c.fervor == 45, "Chœur : une technologie d'armement donne +5 ferveur (%d)" % c.fervor)
	Research.complete(sc, 0, "genetique")
	_ok(c.fervor == 35, "Chœur : l'hérésie retire de la ferveur (%d)" % c.fervor)
	Research.grant(sc, 0, ["litanies"])
	_ok(Research.fx_int(sc, 0, "damage_pct") == 0, "Litanies : rien hors de l'Exaltation")
	c.fervor = 80
	_ok(Research.fx_int(sc, 0, "damage_pct") == 10, "Litanies : +10 % de dégâts pendant l'Exaltation")
	var g0 := FactionTraits.sacrifice_gain(sc, 0)
	Research.grant(sc, 0, ["catechisme", "offrande_consacree"])
	_ok(FactionTraits.sacrifice_gain(sc, 0) == g0 + 10, "Offrande consacrée : +10 ferveur par offrande")
	var sk := _state("khthari")
	_ok(int(Economy.production_pct(sk, 0, "knowledge")) == 50, "Essaim : Savoir divisé par deux")
	_ok(int(FactionTraits.biomass_gain(sk, 0)["knowledge"]) == 2, "Essaim : la biomasse nourrit aussi la mémoire génétique")
	Research.grant(sk, 0, ["digestion_totale"])
	_ok(int(FactionTraits.biomass_gain(sk, 0)["materials"]) == 20, "Digestion totale : +5 matériaux par population digérée")
	# Vael : +5 % de Savoir par empire en paix, plafonné.
	var sv := _state("vael")
	var v := sv.get_empire(0)
	for o in [1, 2, 3]:
		v.contacts.append(o)
		sv.get_empire(o).contacts.append(0)
	_ok(FactionTraits.peace_knowledge_pct(sv, 0) == 0, "Vael : pas de bonus sans traité")
	Diplomacy.sign_treaty(sv, 0, 1, Diplomacy.PEACE)
	Diplomacy.sign_treaty(sv, 0, 2, Diplomacy.PEACE)
	_ok(FactionTraits.peace_knowledge_pct(sv, 0) == 10, "Vael : +5 % de Savoir par empire en paix")
	# Ossarane : vassalité.
	var so := _state("ossarane")
	_ok(Research.fx_int(so, 0, "fief_influence") == 0, "pas de vassalité au départ")
	Research.grant(so, 0, ["vassalite"])
	_ok(Research.fx_int(so, 0, "fief_influence") == 1, "Vassalité : +1 influence par fief")


func _test_ai_research() -> void:
	var sim := Simulation.new(GameState.create(77, 150, 1800.0, "", {"spectator": true, "ai_level": "normal", "rivals": ["ossarane", "choeur", "vael", "khthari"]}))
	sim.advance(30 * 30)
	var st := sim.state
	var counts := PackedStringArray()
	var all_research := true
	var labs := 0
	for e in st.empires:
		counts.append("%s %d" % [e.short_name(), e.techs.size()])
		if e.techs.size() < 3 and not e.eliminated:
			all_research = false
		for t in e.techs:
			if Research.is_heretic(e.faction(), String(t)):
				all_research = false
		for pid in st.colonies:
			var c: Colony = st.colonies[pid]
			if c.owner == e.id:
				for b in c.buildings:
					if int(GameData.building(b).get("yields", {}).get("knowledge", 0)) > 0:
						labs += 1
	_ok(all_research, "les IA recherchent, sans hérésie (%s)" % ", ".join(counts))
	_ok(labs > 0, "les IA bâtissent leurs bâtiments de recherche (%d)" % labs)
	# Une IA belliqueuse penche vers l'armement, une pacifique vers la société.
	var a := GameState.create(78, 150, 1800.0, "", {"spectator": true, "ai_level": "veteran", "temperaments": ["belliqueux", "pacifique", "normal", "normal"]})
	var ctx_war := {"state": a, "e": a.empires[0], "lv": AiLevels.level("veteran"), "ai": AiLevels.personality(a.empires[0]), "salt": 0, "intent": ""}
	var ctx_peace := {"state": a, "e": a.empires[1], "lv": AiLevels.level("veteran"), "ai": AiLevels.personality(a.empires[1]), "salt": 0, "intent": ""}
	var ww := AiPlayer.research_weights(ctx_war)
	var wp := AiPlayer.research_weights(ctx_peace)
	_ok(int(ww["armement"]) - int(ww["societe"]) > int(wp["armement"]) - int(wp["societe"]), "le tempérament oriente la recherche")
	# Déterminisme : deux parties identiques font les mêmes recherches.
	var s1 := Simulation.new(GameState.create(79, 150, 1800.0, "", {"spectator": true, "ai_level": "recrue"}))
	var s2 := Simulation.new(GameState.create(79, 150, 1800.0, "", {"spectator": true, "ai_level": "recrue"}))
	s1.advance(600)
	s2.advance(600)
	_ok(s1.state.checksum() == s2.state.checksum(), "recherche des IA déterministe")


func _test_save_roundtrip() -> void:
	var sim := Simulation.new(_state("choeur"))
	var st := sim.state
	Research.grant(st, 0, ["hydroponie", "litanies"])
	sim.submit(SimCommands.research(0, "fusion_compacte"))
	sim.flush_commands()
	sim.submit(SimCommands.research(0, "raffinage"))
	sim.flush_commands()
	st.get_empire(0).research_progress = 17
	st.get_empire(0).research_shelf["extraction"] = 9
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	var e := back.get_empire(0)
	_ok(e.techs.has("litanies") and e.research_queue == ["fusion_compacte", "raffinage"] and e.research_progress == 17
			and int(e.research_shelf.get("extraction", 0)) == 9, "la recherche survit à la sauvegarde")
	_ok(back.checksum() == st.checksum(), "même empreinte après rechargement")


func _apply(st: GameState, cmd: Dictionary) -> bool:
	if SimCommands.validate(st, cmd) != "":
		return false
	SimCommands.apply(st, cmd)
	return true
