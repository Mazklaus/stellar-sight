extends RefCounted
## Tests du lot 5 de la refonte de l'arbre de recherche (étude https://claude.ai/artifact/2M77BwzqiBMt6zXSCKCq72) :
## peuples insolites (props 89 à 104, branche des vaisseaux vivants 78), talents de recherche propres et
## briques de l'éditeur (21, 71), Destinées en étapes (20).

var _check: Callable

const OWN := {"brouillage_piste": "exode", "nefs_elargies": "exode", "psaumes_coursives": "exode",
		"decors_holographiques": "zambalu", "chapiteau_deux": "zambalu", "haute_voltige": "zambalu",
		"lunes_sentinelles_ii": "halcyre", "croute_blindee": "halcyre", "coeur_fusion": "halcyre",
		"lignees_robustes": "kraal", "paturages_profonds": "kraal", "chant_migration": "kraal",
		"audit_prealable": "ventrelune", "rachat_levier": "ventrelune",
		"formulaires_dematerialises": "bureau", "huissiers_assermentes": "bureau",
		"protocoles_viraux": "signal", "corps_empruntes_ii": "signal",
		"reverie_profonde": "ysmer", "flotte_songe_durable": "ysmer", "ossuaires_ii": "asphodele",
		"vitrines_climatisees": "cassivel", "visites_guidees": "cassivel",
		"optique_voilee": "quietude", "elevation_douce": "quietude", "sable_fin": "sablier", "bulles_rapprochees": "sablier",
		"oeuvres_hatees": "gravea", "hibernation_profonde": "gravea",
		"cometes_semences_ii": "myrr", "cometes_semences_iii": "myrr", "spores_ralentissantes": "myrr",
		"saisons_accelerees": "vergemonde", "jardinage_patient": "vergemonde"}

const TALENTS := {"exode": "learn_sign", "halcyre": "learn_mass", "kraal": "learn_ancient", "ventrelune": "learn_share_pop",
		"bureau": "learn_norm", "ysmer": "learn_inspire", "asphodele": "learn_soul", "cassivel": "learn_piece",
		"sablier": "learn_undo", "myrr": "learn_absorb", "vergemonde": "learn_garden"}


func run(check: Callable) -> void:
	_check = check
	print("Arbre de recherche (lot 5) : peuples insolites, talents, Destinées en étapes…")
	_test_data()
	_test_talents()
	_test_editor()
	_test_tuned()
	_test_destinies()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _state(faction := "vael", options := {}) -> GameState:
	var o := {"ai_level": ""}
	o.merge(options, true)
	return GameState.create(4242, 150, 1800.0, faction, o)


func _test_data() -> void:
	var vael := GameData.faction("vael")
	for tid: String in OWN:
		var t := Research.tech(tid)
		_ok(not t.is_empty() and t.has("requires") and (t.get("effects", {}) as Dictionary).has("ins_pct"), "lot 5 : %s existe et règle une mécanique de peuple" % tid)
		_ok(Research.is_visible(GameData.faction(String(OWN[tid])), tid), "lot 5 : %s se voit chez %s" % [tid, OWN[tid]])
		_ok(not Research.is_visible(vael, tid), "lot 5 : %s ne se voit pas chez la Concorde" % tid)
		for k in t["effects"]["ins_pct"]:
			var parts := String(k).split(".")
			_ok(parts.size() == 2 and Insolites.cfg(parts[0]).has(parts[1]), "lot 5 : %s règle un réglage qui existe (%s)" % [tid, k])
	# Prop. 78 : les Kraal n'ont ni coques ni chantier, mais leurs technologies propres.
	var kraal := GameData.faction("kraal")
	_ok(not Research.is_visible(kraal, "coques_lourdes") and Research.is_visible(kraal, "chant_migration"), "prop. 78 : Kraal sans coques, avec le Chant de migration")
	_ok(GameData.building_kind("guichet_central") == "tribunal", "Bureau : le Guichet central remplace le Tribunal")


func _test_talents() -> void:
	var seen := {}
	for fid: String in TALENTS:
		var r: Dictionary = GameData.faction(fid)["research"]
		_ok(int(r.get(String(TALENTS[fid]), 0)) > 0, "prop. 21 : %s a son talent propre (%s)" % [fid, r.get("name", "?")])
		seen[String(r.get("name", ""))] = true
	_ok(seen.size() == TALENTS.size(), "prop. 21 : onze talents différents")
	# Insolites.learn : du Savoir à l'événement, rien chez un peuple sans le talent.
	var st := _state("exode")
	var e := st.get_empire(0)
	var k0 := int(e.resources.get("knowledge", 0))
	_ok(Insolites.learn(st, 0, "learn_sign", 1) == 60 and int(e.resources["knowledge"]) == k0 + 60, "Mémoire des nefs : un signe, 60 Savoir")
	_ok(Insolites.learn(st, 0, "learn_mass", 5) == 0, "talents : rien sans le talent")


func _test_editor() -> void:
	var spec := Species.from_preset("ferrocornes")
	_ok(String(spec.get("research_talent", "")) == "butin_clan", "prop. 71 : le préréglage Ferrocornes porte son talent")
	_ok(Species.talent_choices(spec).has("butin_clan") and Species.talent_choices(spec).has("compilation"), "prop. 71 : talents proposés selon les couches")
	_ok(not Species.talent_choices(spec).has("brevets"), "prop. 71 : pas de Brevets sans Conseil d'actionnaires")
	spec["name"] = "Peuple d'essai"
	spec["short"] = "Essai"
	spec["id"] = "p_essai"
	spec["research_talent"] = "brevets"
	_ok(Species.errors(spec).size() > 0, "prop. 71 : un talent qui ne convient pas est refusé")
	spec["research_talent"] = "compilation"
	_ok(int(Species.build(spec)["research"].get("compile_per", 0)) == 2 and not (Species.build(spec)["research"] as Dictionary).has("requires"),
			"prop. 71 : le talent choisi remplace celui des couches")


func _test_tuned() -> void:
	var st := _state("kraal", {"insolites": "actifs"})
	var base := Insolites.c_int("kraal", "graze_month", 12)
	_ok(Insolites.tuned(st, 0, "kraal", "graze_month", base) == base, "réglages : rien sans technologie")
	Research.grant(st, 0, ["lignees_robustes", "paturages_profonds"])
	@warning_ignore("integer_division")
	_ok(Insolites.tuned(st, 0, "kraal", "graze_month", base) == base * 60 / 100, "Pâturages profonds : la harde broute 40 % de moins")


func _test_destinies() -> void:
	var techs: Dictionary = GameData.technologies()["technologies"]
	var n := 0
	for tid: String in techs:
		var t: Dictionary = techs[tid]
		if t.has("victory"):
			n += 1
			_ok((t.get("pre", []) as Array).has(tid + "_etape2") and Research.tech(tid + "_etape2").get("pre", []).has(tid + "_etape1"),
					"prop. 20 : %s se gagne en trois étapes" % tid)
	_ok(n == 21, "prop. 20 : 21 Destinées (%d)" % n)
	var st := _state("vael", {"people_victories": true})
	var h0 := int(Victory.progress(st, 0, "charte")["hold"])
	Research.grant(st, 0, ["charte_etape1", "charte_etape2"])
	var h1 := int(Victory.progress(st, 0, "charte")["hold"])
	_ok(h0 > 0 and h1 == h0 * 75 / 100, "Navette parlementaire : le compte à rebours de la Charte est un quart plus court (%d → %d)" % [h0, h1])
	var vael := GameData.faction("vael")
	_ok(Research.in_band(vael, "charte_etape1"), "prop. 20 : les étapes vont dans la bande Peuple")
