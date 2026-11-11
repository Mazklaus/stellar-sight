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
	var expect := {"ossarane": [2, 4], "choeur": [2, 4], "vael": [4, 4], "khthari": [1, 5]}
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
	_ok(_err_has(h, "portrait"), "portrait de ruche refusé pour un humanoïde")
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
	_ok(st.empires.size() == 5 and st.empires[0].faction_id == fid, "peuple créé joué par le joueur, 4 officiels en rivaux")
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
