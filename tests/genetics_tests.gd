extends RefCounted
## Tests de l'ingénierie des espèces (étude du 2026-11-16, 43 propositions) : données et réglages,
## programmes et marge, fiche façonnée (production, habitabilité, implants), voies d'élévation et
## Pureté, Grand Transfert, lignées, abrutissement, greffe, hybrides, ponts (héros, Nomos, cour,
## espionnage, créatures), sauvegarde. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Ingénierie des espèces…")
	print("  - data")
	_test_data()
	print("  - programs")
	_test_programs()
	print("  - fiche")
	_test_fiche()
	print("  - paths")
	_test_paths()
	print("  - purity")
	_test_purity()
	print("  - transfer")
	_test_transfer()
	print("  - lineage")
	_test_lineage()
	print("  - staple_graft")
	_test_staple_graft()
	print("  - hybrids")
	_test_hybrids()
	print("  - bridges")
	_test_bridges()
	print("  - save")
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(mode := "complete", faction := "ossarane", extra := {}) -> GameState:
	var opts := {"ai_level": "", "genetics": mode}
	opts.merge(extra, true)
	return GameState.create(4242, 150, 1800.0, faction, opts)


static func give_techs(st: GameState, eid: int, ids: Array) -> void:
	var e := st.get_empire(eid)
	for t in ids:
		e.techs[String(t)] = true


## Paie un programme jusqu'au bout (mensualités).
static func finish(st: GameState, eid: int) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	var e := st.get_empire(eid)
	for i in 12:
		e.resources["knowledge"] = 100000
		e.resources["materials"] = 100000
		Genetics.monthly_empire(st, e, added)
		if Genetics.programs(st, eid).is_empty():
			break
	return added


static func cmd(st: GameState, eid: int, act: String, d := {}) -> String:
	var c := SimCommands.gen_act(eid, act, d)
	var why := SimCommands.validate(st, c)
	if why == "":
		SimCommands.apply(st, c)
	return why


func _test_data() -> void:
	_ok(Genetics.mode_defs().size() == 3 and Genetics.default_mode() == "complete", "Génome : trois réglages, Complète par défaut")
	var ids := {}
	var dup := false
	var bad_voie := ""
	for t: Dictionary in Genetics.catalogue():
		dup = dup or ids.has(String(t["id"]))
		ids[String(t["id"])] = true
		if not (Genetics.cfg("voie_labels") as Dictionary).has(String(t["voie"])):
			bad_voie = String(t["id"])
	_ok(not dup and ids.size() >= 40, "Génome : catalogue de traits façonnés en données, sans doublon (%d)" % ids.size())
	_ok(bad_voie == "", "Génome : chaque trait a une voie connue (%s)" % bad_voie)
	var missing := ""
	for k in Genetics.cfg("techs"):
		if k != "_doc" and Research.tech(String(k)).is_empty():
			missing = String(k)
	_ok(missing == "", "Génome : les technologies du pilier sont dans l'arbre (%s)" % missing)
	var st := new_game("desactivee")
	_ok(st.genetics.is_empty() and not Genetics.applies(st, 0), "Génome désactivé : rien en jeu")
	_ok(Genetics.check(st, 0, "mod", {"fid": "ossarane", "add": ["g_robustes"]}) != "", "Génome désactivé : aucun programme")
	var st2 := new_game("simple")
	_ok(Genetics.enabled(st2) and not Genetics.full(st2), "Génome simple : en jeu, sans les options complètes")
	var st3 := new_game()
	_ok(Genetics.full(st3) and Genetics.applies(st3, 0), "Génome complet : en jeu")
	_ok(Array(Genetics.voies_of(GameData.faction("teyl"))) == ["synthetique"], "Voies : les synthétiques se reprogramment")
	_ok(Genetics.voies_of(GameData.faction("khthari")).has("castes"), "Voies : la ruche a ses castes")
	_ok(Array(Genetics.voies_of(GameData.faction("murmurants"))) == ["harmoniques"], "Voies : les énergétiques s'accordent")


func _test_programs() -> void:
	var st := new_game()
	var e := st.get_empire(0)
	_ok(Genetics.margin_total(st, 0, "ossarane") == 0, "Marge : 0 au départ")
	_ok(cmd(st, 0, "mod", {"fid": "ossarane", "add": ["g_robustes"]}) != "", "Programme : il faut Génétique appliquée")
	give_techs(st, 0, ["genetique"])
	_ok(Genetics.margin_total(st, 0, "ossarane") == 1, "Marge : +1 par technologie du pilier")
	_ok(Genetics.check_mod(st, 0, "ossarane", ["g_industrieux"], [], "").contains("marge"), "Programme : marge dépassée refusée")
	_ok(Genetics.check_mod(st, 0, "ossarane", ["g_interfaces"], [], "") != "", "Programme : implants fermés sans Chair et acier")
	_ok(Genetics.check_mod(st, 0, "ossarane", ["g_ouvrieres"], [], "") != "", "Programme : castes fermées aux humanoïdes")
	_ok(Genetics.check_mod(st, 0, "ossarane", ["g_abrutis"], [], "") != "", "Programme : l'abrutissement ne s'ajoute pas comme un trait")
	_ok(Genetics.check_mod(st, 0, "ossarane", [], [], "ocean") != "", "Acclimatation : il faut la technologie")
	var cost := Genetics.mod_cost(st, 0, "ossarane", ["g_robustes"], [], "")
	_ok(cost > 120, "Programme : coût en Savoir selon la population (%d)" % cost)
	_ok(cmd(st, 0, "mod", {"fid": "ossarane", "add": ["g_robustes"]}) == "", "Programme : lancé (Robustes)")
	_ok(Genetics.programs(st, 0).size() == 1, "Programme : en cours")
	_ok(Genetics.check_mod(st, 0, "ossarane", ["g_resistants"], [], "") != "", "Programme : un seul à la fois")
	e.resources["knowledge"] = 0
	var none: Array[Dictionary] = []
	Genetics.monthly_empire(st, e, none)
	_ok(int(Genetics.programs(st, 0)[0]["paid"]) == 0, "Programme : sans Savoir en stock, rien n'avance")
	var added := finish(st, 0)
	_ok(Genetics.programs(st, 0).is_empty() and Genetics.traits_of(e.faction()).has("g_robustes"), "Programme achevé : l'espèce fondatrice est Robuste")
	_ok(not added.is_empty(), "Programme achevé : chronique")
	_ok(Genetics.margin_left(st, 0, "ossarane") == 0, "Marge : dépensée")
	_ok(Genetics.programs_done(st, 0) == 1, "Programme : compté")
	# Annuler rend la moitié.
	give_techs(st, 0, ["reprogrammation", "resequencage", "implants_neuraux"])
	_ok(Genetics.margin_total(st, 0, "ossarane") == 4, "Marge : 4 au plus par les technologies")
	_ok(cmd(st, 0, "mod", {"fid": "ossarane", "add": ["g_industrieux"]}) == "", "Programme : Industrieux lancé")
	e.resources["knowledge"] = 100000
	Genetics.monthly_empire(st, e, none)
	var paid := int(Genetics.programs(st, 0)[0]["paid"])
	var before := int(e.resources["knowledge"])
	_ok(cmd(st, 0, "cancel", {"id": int(Genetics.programs(st, 0)[0]["id"])}) == "", "Programme : annulé")
	_ok(int(e.resources["knowledge"]) == before + paid / 2, "Programme annulé : la moitié revient")
	# Défaut : regagne des points (Reséquençage).
	_ok(Genetics.check_mod(st, 0, "ossarane", ["g_genie"], [], "") != "", "Élite : réservée à la voie génétique")
	_ok(Genetics.check_mod(st, 0, "ossarane", ["g_cerveaux", "g_bras"], [], "") == "", "Traits poussés permis aux humanoïdes")
	_ok(Genetics.check_mod(st, 0, "ossarane", ["g_fertilite", "g_cerveaux", "g_bras", "g_sourires"], [], "").contains("traits"), "Plafond de traits")


func _test_fiche() -> void:
	var st := new_game()
	var e := st.get_empire(0)
	give_techs(st, 0, ["genetique", "reprogrammation", "resequencage", "acclimatation_glandulaire", "implants_neuraux"])
	var mat0 := int(e.faction().get("production_pct", {}).get("materials", 100))
	var g := Genetics.preview_genome({}, ["g_industrieux", "g_adaptables"], [], "ocean")
	Genetics._set_genome(st, e, "ossarane", g)
	_ok(int(e.faction()["production_pct"]["materials"]) == mat0 * 115 / 100, "Fiche : Industrieux +15 % de matériaux")
	_ok((e.faction()["preferred"] as Array)[1] == "ocean" and (e.faction()["preferred"] as Array)[0] == "desert", "Fiche : second biome changé, monde natal intact")
	var base_hab := Economy.habitability("arctic", GameData.faction("ossarane"))
	var hab := Economy.habitability_for(st, 0, "arctic")
	_ok(base_hab <= 0 or hab >= mini(100, base_hab + 10), "Fiche : Adaptables +10 d'habitabilité (%d -> %d)" % [base_hab, hab])
	_ok(GameData.faction("ossarane").get("production_pct", {}).get("materials", 100) == mat0, "Fiche : le peuple de base reste intact")
	var shown := false
	for t: Dictionary in e.faction()["traits"]:
		shown = shown or String(t["name"]) == "Industrieux"
	_ok(shown, "Fiche : le trait façonné s'affiche")
	# Retirer un trait ajouté : la fiche revient.
	Genetics._set_genome(st, e, "ossarane", Genetics.preview_genome(e.genome["ossarane"], [], ["g_industrieux"], ""))
	_ok(int(e.faction()["production_pct"].get("materials", 100)) == mat0, "Fiche : retirer un trait façonné rend la fiche")
	# Implants : entretien en énergie.
	Genetics._set_genome(st, e, "ossarane", {"cyber": true, "add": ["g_interfaces", "g_yeux"]})
	_ok(bool(e.faction().get("cyber", false)), "Cybernétique : la fiche le porte")
	_ok(Genetics.implant_upkeep(e.faction(), 20) == 4, "Implants : 1 énergie pour 10 habitants par implant")
	var c: Colony = st.colonies[e.capital_planet]
	var up := int(Economy.colony_yields(st, c)["upkeep"].get("energy", 0))
	Genetics._set_genome(st, e, "ossarane", {})
	var up0 := int(Economy.colony_yields(st, c)["upkeep"].get("energy", 0))
	_ok(up > up0, "Implants : entretien dans le bilan de la colonie (%d > %d)" % [up, up0])
	# Retirer un trait de l'éditeur demande le Reséquençage.
	_ok(Genetics.check_mod(st, 0, "ossarane", [], ["navigateurs"], "") == "" or Genetics.trait_cost("navigateurs") <= 0, "Reséquençage : retirer un trait de création")
	# Cyber : programme d'entrée.
	_ok(cmd(st, 0, "cyber", {"fid": "ossarane"}) == "", "Chair et acier : programme lancé")
	finish(st, 0)
	_ok(bool(e.faction().get("cyber", false)) and Genetics.trait_cap(st, 0, "ossarane") == 6, "Chair et acier : un trait de plus au plafond")
	_ok(Genetics.check_mod(st, 0, "ossarane", ["g_interfaces"], [], "") == "", "Chair et acier : implants permis")


func _test_paths() -> void:
	var st := new_game()
	var e := st.get_empire(0)
	give_techs(st, 0, ["genetique", "reprogrammation", "resequencage", "implants_neuraux"])
	_ok(Genetics.check_path(st, 0, "genetique") != "", "Voie d'élévation : il faut 3 programmes")
	st.genetics["done"]["0"] = 3
	_ok(Genetics.check_path(st, 0, "purete") != "", "Pureté : se jure avant tout programme")
	var g0 := int(e.faction().get("growth_pct", 100))
	_ok(cmd(st, 0, "path", {"path": "genetique"}) == "", "Voie génétique choisie")
	_ok(int(e.faction().get("growth_pct", 100)) == g0 * 125 / 100, "Voie génétique : +25 % de croissance")
	_ok(Genetics.margin_total(st, 0, "ossarane") == 6, "Voie génétique : +2 de marge")
	_ok(Genetics.check_mod(st, 0, "ossarane", ["g_genie"], [], "") == "", "Voie génétique : traits d'élite")
	_ok(cmd(st, 0, "path", {"path": "cybernetique"}) != "", "Voie d'élévation : pour de bon")
	var st2 := new_game()
	give_techs(st2, 0, ["genetique", "implants_neuraux"])
	st2.genetics["done"]["0"] = 3
	_ok(cmd(st2, 0, "path", {"path": "cybernetique"}) == "", "Voie cybernétique choisie")
	_ok(bool(st2.get_empire(0).faction().get("cyber", false)), "Voie cybernétique : l'espèce devient cybernétique")
	_ok(Genetics.cost_pct(st2, 0, "cybernetique") <= -50, "Voie cybernétique : programmes à moitié prix")


func _test_purity() -> void:
	var st := new_game("complete", "ossarane", {"politics": "active"})
	var e := st.get_empire(0)
	var strong0 := int(e.faction()["production_pct"]["crystals"])
	_ok(cmd(st, 0, "path", {"path": "purete"}) == "", "Pureté jurée")
	_ok(int(e.faction()["production_pct"]["crystals"]) == strong0 * 110 / 100, "Pureté : +10 % sur le point fort")
	var parts := Genetics.empire_stability_parts(st, 0)
	_ok(parts.size() == 1 and int(parts[0][1]) == 5, "Pureté : +5 de stabilité")
	give_techs(st, 0, ["genetique"])
	_ok(Genetics.check_mod(st, 0, "ossarane", ["g_robustes"], [], "").contains("Pureté"), "Pureté : aucun programme")
	_ok(cmd(st, 0, "renounce") == "", "Pureté reniée")
	parts = Genetics.empire_stability_parts(st, 0)
	_ok(parts.size() == 1 and int(parts[0][1]) == -20, "Pureté reniée : crise de stabilité")
	_ok(Genetics.check_path(st, 0, "purete") != "", "Pureté reniée : plus de serment")
	_ok(int(e.faction()["production_pct"]["crystals"]) == strong0, "Pureté reniée : le bonus tombe")


func _test_transfer() -> void:
	var st := new_game()
	var e := st.get_empire(0)
	give_techs(st, 0, ["genetique", "evolution_dirigee", "matrices_conscience"])
	st.genetics["done"]["0"] = 3
	_ok(Genetics.check_transfer(st, 0, "ossarane") != "", "Grand Transfert : il faut la voie synthétique")
	_ok(cmd(st, 0, "path", {"path": "synthetique"}) == "", "Voie synthétique choisie")
	_ok(Genetics.max_programs(st, 0) == 2, "Évolution dirigée : deux programmes à la fois")
	_ok(cmd(st, 0, "transfer", {"fid": "ossarane"}) == "", "Grand Transfert lancé")
	finish(st, 0)
	_ok(String(FactionTraits.species(e.faction()).get("archetype", "")) == "synthetique", "Grand Transfert : l'espèce devient synthétique")
	_ok(FactionTraits.diet(e.faction()) != "food", "Grand Transfert : plus de nourriture")
	_ok(Genetics.resource_for(st, 0, "ossarane") == "materials", "Après le Transfert : programmes en matériaux")
	_ok(Genetics.voies_of(e.faction()).has("synthetique"), "Après le Transfert : reprogrammation")
	_ok(Genetics.stat(st, 0, "founder_transfer") == 1, "Grand Transfert : compté pour les hauts faits")


func _test_lineage() -> void:
	var st := new_game("complete", "ossarane", {"peoples": "actifs"})
	var e := st.get_empire(0)
	give_techs(st, 0, ["genetique", "reprogrammation", "resequencage"])
	var c: Colony = st.colonies[e.capital_planet]
	c.population = maxi(c.population, 8)
	_ok(GeneticsBridges.check_lineage(st, 0, "ossarane", [], []) != "", "Lignée : doit différer")
	_ok(cmd(st, 0, "lineage", {"fid": "ossarane", "add": ["g_doues"]}) == "", "Lignée lancée (Doués)")
	finish(st, 0)
	var lins := GeneticsBridges.lineages_of(st, 0)
	_ok(lins.size() == 1, "Lignée créée")
	if lins.is_empty():
		return
	var lid := lins[0]
	_ok(not GameData.faction(lid).is_empty() and st.custom_factions.has(lid), "Lignée : une fiche de plus dans la partie")
	_ok(int(c.species.get(lid, 0)) > 0, "Lignée : des habitants l'ont rejointe")
	_ok(Peoples.status(st, 0, lid) == "citoyens", "Lignée : même statut que son espèce")
	_ok(Genetics.traits_of(GameData.faction(lid)).has("g_doues"), "Lignée : porte son trait")
	_ok(not Genetics.traits_of(e.faction()).has("g_doues"), "Lignée : l'espèce mère ne change pas")
	# L'espèce change : la lignée suit.
	Genetics._set_genome(st, e, "ossarane", {"add": ["g_robustes"]})
	_ok(Genetics.traits_of(GameData.faction(lid)).has("g_robustes"), "Lignée : suit le génome de son espèce")
	var st2 := new_game("simple", "ossarane", {"peoples": "actifs"})
	give_techs(st2, 0, ["genetique"])
	_ok(GeneticsBridges.check_lineage(st2, 0, "ossarane", ["g_robustes"], []) != "", "Lignées : réglage complet seulement")


func _other_species(st: GameState, c: Colony, fid: String, n: int) -> void:
	c.population += n
	c.species[fid] = int(c.species.get(fid, 0)) + n
	Peoples.refresh(st)


func _test_staple_graft() -> void:
	var st := new_game("complete", "ossarane", {"peoples": "actifs"})
	var e := st.get_empire(0)
	give_techs(st, 0, ["genetique", "resequencage"])
	var c: Colony = st.colonies[e.capital_planet]
	_other_species(st, c, "choeur", 10)
	_ok(Genetics.species_of(st, 0).has("choeur"), "Espèces de l'empire : le Chœur qui vit chez nous")
	_ok(GeneticsBridges.check_staple(st, 0, "choeur").contains("assujettis"), "Abrutissement : assujettis seulement")
	st.peoples["status"]["0"] = {"choeur": "assujettis"}
	_ok(GeneticsBridges.check_staple(st, 0, "choeur") == "", "Abrutissement : possible sur des assujettis")
	_ok(cmd(st, 0, "staple", {"fid": "choeur"}) == "", "Abrutissement lancé")
	finish(st, 0)
	_ok(Genetics.traits_of(Genetics.fiche(st, 0, "choeur")).has("g_abrutis"), "Abrutissement : les assujettis sont abrutis")
	_ok(not Genetics.traits_of(GameData.faction("choeur")).has("g_abrutis"), "Abrutissement : le Chœur des autres empires ne change pas")
	var choeur_eid := -1
	for o in st.empires:
		if o.faction_id == "choeur":
			choeur_eid = o.id
	if choeur_eid >= 0:
		var hurt := false
		for m in st.memories:
			hurt = hurt or (int(m["who"]) == choeur_eid and String(m["kind"]) == "gen_profanation")
		_ok(hurt, "Profanation de notre sang : l'empire du Chœur s'en souvient")
	# Greffe : le Chœur excelle en matériaux (125 %).
	var gain := GeneticsBridges.graft_gain(st, 0, "choeur")
	var strong := int(Genetics.fiche(st, 0, "choeur")["production_pct"]["materials"])
	_ok(int(gain.get("materials", 0)) == (strong - 100) / 2, "Greffe : moitié du point fort (%s)" % str(gain))
	var mat0 := int(e.faction().get("production_pct", {}).get("materials", 100))
	var pop0 := int(c.species.get("choeur", 0))
	_ok(cmd(st, 0, "graft", {"fid": "choeur"}) == "", "Greffe faite")
	_ok(int(c.species.get("choeur", 0)) == pop0 - 2, "Greffe : 2 habitants sacrifiés")
	_ok(int(e.faction()["production_pct"]["materials"]) == mat0 * (100 + (strong - 100) / 2) / 100, "Greffe : le point fort du donneur, à moitié")
	_ok(cmd(st, 0, "graft", {"fid": "choeur"}) != "", "Greffe : une fois par espèce")
	_ok(GeneticsBridges.graft_price(st, 0) == 4, "Greffe : la suivante coûte 4 habitants")


func _test_hybrids() -> void:
	var st := new_game("complete", "ossarane", {"peoples": "actifs"})
	var e := st.get_empire(0)
	var c: Colony = st.colonies[e.capital_planet]
	_other_species(st, c, "brisecomete", 6)
	var added: Array[Dictionary] = []
	GeneticsBridges._make_hybrid(st, e, c, "ossarane", "brisecomete", added)
	var hid := ""
	for k in c.species:
		if String(k).find("~H~") > 0:
			hid = String(k)
	_ok(hid != "" and not GameData.faction(hid).is_empty(), "Hybride : une espèce de plus, avec sa fiche")
	if hid != "":
		_ok(Genetics.margin_total(st, 0, hid) == Genetics.margin_total(st, 0, "ossarane") + 1, "Hybride : un point de marge en plus")
		_ok(int(GameData.faction(hid)["production_pct"].get("crystals", 100)) == 150, "Hybride : le meilleur des deux parents")
	_ok(Genetics.stat(st, 0, "hybrids") == 1, "Hybride : compté")


func _test_bridges() -> void:
	var st := new_game()
	var e := st.get_empire(0)
	var life0 := Heroes.life_years(st, 0)
	Genetics._set_genome(st, e, "ossarane", {"add": ["g_longevifs"]})
	_ok(Heroes.life_years(st, 0) == life0 + 15 or life0 <= 0, "Héros : Longévifs vivent 15 ans de plus")
	Genetics._set_genome(st, e, "ossarane", {"add": ["g_memoire"], "cyber": true})
	_ok(Genetics.hero_xp_bonus(st, 0) == 50, "Héros : Mémoire étendue +50 % d'expérience")
	# Créatures : échantillons.
	_ok(GeneticsBridges.on_creature_killed(st, 0, 1) == "g_peau_vide", "Créature abattue : échantillon")
	_ok(GeneticsBridges.on_creature_killed(st, 0, 1) == "", "Créature : un échantillon par sorte")
	give_techs(st, 0, ["genetique", "reprogrammation"])
	Genetics._set_genome(st, e, "ossarane", {})
	_ok(Genetics.check_mod(st, 0, "ossarane", ["g_peau_vide"], [], "") == "", "Échantillon : trait unique permis")
	# Espionnage.
	var o := st.empires[1]
	o.genome[o.faction_id] = {"add": ["g_doues"]}
	o.genome_rev += 1
	_ok(GeneticsBridges.steal_genome(st, 0, 1, ["t"]) == "g_doues", "Voler un génome : trait volé")
	GeneticsBridges.contaminate(st, 0)
	_ok(GeneticsBridges.contaminated(st, 0), "Contaminer les cuves : programmes arrêtés")
	# Talents.
	var st2 := new_game("complete", "ferrocornes")
	_ok(int(Genetics.talent(st2, 0).get("free_biome", 0)) == 1, "Talent : la mue des Ferrocornes")
	var st3 := new_game("complete", "teyl")
	_ok(Genetics.cost_pct(st3, 0, "synthetique") <= -50, "Talent : code ouvert des Teyl")
	_ok(Genetics.resource_for(st3, 0, "teyl") == "materials", "Synthétiques : programmes en matériaux")
	# Nomos : famille Génome dans le catalogue.
	_ok(not Amphictyony.family_def("genome").is_empty(), "Nomos : famille Génome")
	# Fléaux, combat au sol, régiments clonés.
	Genetics._set_genome(st, e, "ossarane", {"add": ["g_resistants", "g_robustes"]})
	_ok(Genetics.plague_loss(st, 0, 4) == 2, "Fléaux : Résistants perdent moitié moins")
	_ok(Genetics.ground_pct(st, 0, "") == 125, "Combat au sol : Robustes +25 %")
	var t0 := Ground.type_ids()[0]
	var d0 := Ground.recruit_days(st, 0, t0)
	e.gene_path = "genetique"
	_ok(Genetics.clone_days_pct(st, 0) == -50 and Ground.recruit_days(st, 0, t0) < d0, "Régiments clonés : recrutement deux fois plus rapide")
	e.gene_path = ""
	# Furtivité, échos, biomasse.
	Genetics._set_genome(st, e, "ossarane", {"add": ["g_yeux", "g_savoureux"], "cyber": true})
	_ok(Genetics.detect_bonus(st, 0) == 1, "Furtivité : Yeux-senseurs +1 de détection")
	_ok(Genetics.savoury_pct(st, 0) == 150, "Biomasse : un peuple Savoureux rend 50 % de plus")
	# Codex des origines, hauts faits.
	_ok(not Relics.def("codex_origines").is_empty(), "Relique : Codex des origines")
	_ok(DeedsEval.value(st, 0, "gen_traits") >= 0, "Hauts faits : mesures du génome")
	# Lois et préceptes.
	_ok(not Laws.law_def("charte_genome").is_empty() and not Laws.law_def("eugenisme_etat").is_empty() and not Laws.law_def("sanctuaire_genome").is_empty(), "Lois : Charte du génome, Eugénisme d'État, Sanctuaire du génome")
	_ok(not Faiths.precept_def("saintete_chair").is_empty() and not Faiths.precept_def("chair_argile").is_empty(), "Préceptes : Sainteté de la chair, La chair est argile")
	var st4 := new_game("desactivee", "ossarane", {"faiths": "actives"})
	_ok(Faiths._precept_free(st4, "x", "chair_argile") != "", "Préceptes du génome : seulement avec le pilier")
	# Espionnage : opérations en données.
	_ok(not Espionage.op_def("voler_genome").is_empty() and not Espionage.op_def("contaminer_cuves").is_empty(), "Espionnage : Voler un génome, Contaminer les cuves")
	_ok(GeneticsBridges.spy_check(st, 0, 1, "contaminer_cuves") != "", "Contaminer les cuves : il faut un programme en cours")
	# IA : façonne quand elle peut.
	var st5 := new_game("complete", "vael")
	give_techs(st5, 0, ["genetique", "reprogrammation"])
	_ok(AiGenetics.best_trait(st5, 0, "vael") != "", "IA : choisit un trait à façonner (%s)" % AiGenetics.best_trait(st5, 0, "vael"))
	# Disabled state is never re-enabled by a read.
	var st6 := new_game("desactivee")
	Genetics.stat(st6, 0, "programs")
	GeneticsBridges.contaminated(st6, 0)
	_ok(st6.genetics.is_empty(), "Pilier désactivé : une lecture ne le rallume pas")


func _test_save() -> void:
	var st := new_game("complete", "ossarane", {"peoples": "actifs"})
	var e := st.get_empire(0)
	give_techs(st, 0, ["genetique"])
	Genetics._set_genome(st, e, "ossarane", {"add": ["g_robustes"], "bio": "ocean"})
	e.gene_path = "genetique"
	cmd(st, 0, "mod", {"fid": "ossarane", "add": ["g_resistants"]})
	var d := st.to_dict()
	_ok(int(d["version"]) == 84, "Sauvegarde 84")
	var st2 := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(st2 != null, "Sauvegarde relue")
	if st2 == null:
		return
	var e2 := st2.get_empire(0)
	_ok(Genetics.traits_of(e2.faction()).has("g_robustes") and e2.gene_path == "genetique", "Sauvegarde : génome et voie gardés")
	_ok(Genetics.programs(st2, 0).size() == 1, "Sauvegarde : programme en cours gardé")
	_ok(Genetics.mode(st2) == "complete", "Sauvegarde : réglage gardé")
	var st3 := new_game("desactivee")
	_ok(not st3.to_dict().has("genetics"), "Sauvegarde : rien si désactivé")
