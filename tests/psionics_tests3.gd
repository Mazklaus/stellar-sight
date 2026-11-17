class_name PsionicsTests3
extends RefCounted
## Tests des pouvoirs psioniques, lot 3 (les ponts). Appelés par psionics_tests2.gd.

const T := preload("res://tests/psionics_tests.gd")

static var _check: Callable


static func run(check: Callable) -> void:
	_check = check
	print("  - lot 3 : ambre")
	_test_ambre()
	print("  - lot 3 : phare")
	_test_phare()
	print("  - lot 3 : intouchables")
	_test_null()
	print("  - lot 3 : talents")
	_test_talents()
	print("  - lot 3 : foi, cour, lignées")
	_test_faith_court_lineage()
	print("  - lot 3 : espionnage, hauts faits, créatures")
	_test_misc()


static func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func _test_ambre() -> void:
	var st := T.new_game()
	var oss := T.eid_of(st, "ossarane")
	_ok(PsionicsBridges.ambre_planets(st).size() >= 2, "Ambre : des gisements posés au lancement (%d)" % PsionicsBridges.ambre_planets(st).size())
	var st0 := T.new_game("desactive")
	_ok(PsionicsBridges.ambre_planets(st0).is_empty(), "Ambre : rien sans le pilier")
	T.give_techs(st, oss, ["theorie_psionique", "telepathie"])
	var g0 := Psionics.monthly_gain(st, oss)
	var f0: int = Psionics.felure_chance(st, oss, "lecture")[0]
	var cap := st.get_empire(oss).capital_planet
	Psionics.sub(st, "ambre")[str(cap)] = 1
	_ok(PsionicsBridges.ambre_of(st, oss) == 1 and Psionics.monthly_gain(st, oss) > g0, "Ambre : Résonance en plus")
	_ok(int(Psionics.felure_chance(st, oss, "lecture")[0]) <= f0, "Ambre : fêlures plus rares")
	Psionics.sub(st, "amb")[str(oss)] = 60
	Psionics.sub(st, "ambre").erase(str(cap))
	var w := false
	for p in Psionics.empire_stability_parts(st, oss):
		w = w or String(p[0]).contains("ambre")
	_ok(w, "Ambre : l'habitude, puis le manque")
	var d := st.to_dict()
	var st2 := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(st2 != null and PsionicsBridges.ambre_planets(st2).size() == PsionicsBridges.ambre_planets(st).size(), "Ambre : gardé dans la sauvegarde")


static func _test_phare() -> void:
	var st := T.new_game("complet", "ossarane", {"politics": "active"})
	var oss := T.eid_of(st, "ossarane")
	T.give_techs(st, oss, ["theorie_psionique", "telepathie", "navigation_songe"])
	var c: Colony = st.colonies[st.get_empire(oss).capital_planet]
	c.buildings.append("phare_songe")
	var sid := T.home_system(st, oss)
	_ok(PsionicsBridges.phare_system(st, oss) == sid and not PsionicsBridges.phare_lit(st, oss), "Phare : éteint sans tribut")
	Laws.adopt(st, oss, "nefs_silence")
	_ok(PsionicsBridges.phare_lit(st, oss), "Phare : allumé par les Nefs du Silence")
	var added: Array[Dictionary] = []
	PsionicsBridges.monthly(st, 0, added)
	var f := st.spawn_ship(oss, String(GameData.ships().keys()[0]), sid)
	_ok(PsionicsBridges.phare_pct(st, f) > 100, "Phare : vos flottes vont plus vite autour")
	_ok(Psionics.stat(st, oss, "phare") == 1 and DeedsEval.value(st, oss, "psi_phare") == 1, "Phare : haut fait « Le Phare allumé »")
	var pop0 := 0
	for pid in st.sorted_colony_ids():
		if st.colonies[pid].owner == oss:
			pop0 += st.colonies[pid].population
	PsionicsBridges.monthly(st, posmod(oss + 6, 12), added)
	var pop1 := 0
	for pid in st.sorted_colony_ids():
		if st.colonies[pid].owner == oss:
			pop1 += st.colonies[pid].population
	_ok(pop1 < pop0, "Nefs du Silence : le tribut annuel")


static func _test_null() -> void:
	var st := T.new_game("complet", "ossarane", {"genetics": "complete"})
	var oss := T.eid_of(st, "ossarane")
	var e := st.get_empire(oss)
	T.give_techs(st, oss, ["theorie_psionique", "telepathie"])
	_ok(Genetics.trait_def("g_neant").get("psionics", false), "Intouchables : le trait Néant psychique")
	_ok(Genetics.check_mod(st, oss, e.faction_id, ["g_neant"], [], "").contains("Écrans"), "Intouchables : il faut les Écrans psychiques (%s)" % Genetics.check_mod(st, oss, e.faction_id, ["g_neant"], [], ""))
	var g: Dictionary = e.genome.get(e.faction_id, {})
	g["add"] = ["g_neant"]
	e.genome[e.faction_id] = g
	e.genome_rev += 1
	_ok(Psionics.founder_level(st, oss) == 0 and Psionics.immune(st, oss), "Intouchables : sourds et immunisés")
	_ok(PsionicsBridges.null_in(st, T.home_system(st, oss)), "Intouchables : ils vivent dans leur système")
	var vael := T.eid_of(st, "vael")
	T.give_techs(st, vael, ["theorie_psionique", "telepathie", "precognition"])
	Psionics.add_resonance(st, vael, 500)
	_ok(Psionics.check_power(st, vael, "domination", T.home_system(st, oss)).contains("Intouchables"), "Intouchables : le Songe se tait dans leur système")


static func _test_talents() -> void:
	var st := T.new_game()
	_ok(bool(Psionics.talent(st, T.eid_of(st, "ossarane")).get("sure_jump", false)), "Talent Ossarane : Navigateurs du Songe")
	_ok(int(Psionics.talent(st, T.eid_of(st, "khthari")).get("screen", 0)) == 50, "Talent Kh'thari : Ombre de ruche")
	_ok(int(Psionics.talent(st, T.eid_of(st, "vael")).get("hero_pct", 0)) > 0, "Talent Vael : Destins")
	_ok(bool(Psionics.talent(st, T.eid_of(st, "choeur")).get("phare_free", false)), "Talent Chœur : Phare des fidèles")
	_ok(int(Psionics.talent(st, T.eid_of(st, "murmurants")).get("res_pct", 0)) > 0, "Talent Murmurants : Échos du Songe")
	_ok(int(Psionics.talent(st, T.eid_of(st, "ferrocornes")).get("psi_ground_pct", 0)) > 0, "Talent Ferrocornes : Hurleurs")
	_ok(bool(Psionics.talent(st, T.eid_of(st, "teyl")).get("screens_free", false)), "Talent Teyl : Sourds")
	var bc := T.eid_of(st, "brisecomete")
	_ok(bool(Psionics.talent(st, bc).get("foire", false)), "Talent Brisecomète : Médiums de foire")
	var has_foire := false
	for p: Dictionary in Psionics.powers_of(st, bc):
		has_foire = has_foire or String(p["id"]) == "foire"
	_ok(has_foire, "Foire aux visions : pouvoir des Brisecomète")
	var oss := T.eid_of(st, "ossarane")
	T.give_techs(st, oss, ["theorie_psionique", "telepathie"])
	Psionics.add_resonance(st, oss, 500)
	_ok(Psionics.check_power(st, oss, "foire", bc).contains("talent"), "Foire aux visions : pas pour les autres peuples")
	T.give_techs(st, bc, ["theorie_psionique", "telepathie"])
	Psionics.add_resonance(st, bc, 500)
	st.get_empire(bc).contacts.append(oss)
	var en := int(st.get_empire(bc).resources.get("energy", 0))
	_ok(T.cmd(st, bc, "power", {"power": "foire", "target": oss}) == "" and int(st.get_empire(bc).resources.get("energy", 0)) > en, "Foire aux visions : de l'énergie")


static func _test_faith_court_lineage() -> void:
	var st := T.new_game("complet", "ossarane", {"faiths": "actives"})
	var oss := T.eid_of(st, "ossarane")
	T.give_techs(st, oss, ["theorie_psionique", "telepathie", "precognition"])
	_ok(FaithBridges.bd()["vocations"].has("voyant"), "Foi : vocation Voyant")
	var hid := Heroes.ids_of(st, oss)
	if not hid.is_empty() and st.faith_on:
		var h: Dictionary = st.heroes[hid[0]]
		var c0 := Psionics.power_cost(st, oss, "prescience")
		h["voc"] = "voyant"
		h["post"] = "system"
		h["target"] = T.home_system(st, oss)
		h["arrive"] = 0
		_ok(Psionics.hero_power(st, h) >= 1, "Voyant : le héros entend le Songe")
		_ok(Psionics.power_cost(st, oss, "prescience") < c0, "Voyant : Préscience moins chère")
	_ok(PsionicsBridges.faith_stance(T.new_game(), 0) == "", "Foi : aucune position sans religions")
	var hv := false
	for v: Dictionary in Court.data()["vocations"]:
		hv = hv or String(v["id"]) == "souche_songe"
	_ok(hv, "Cour : la Souche du Songe")
	# Programme de lignées.
	var st2 := T.new_game()
	var o2 := T.eid_of(st2, "ossarane")
	T.give_techs(st2, o2, ["theorie_psionique", "telepathie"])
	st2.get_empire(o2).resources["influence"] = 500
	_ok(T.cmd(st2, o2, "lineage") == "", "Lignées : programme lancé")
	_ok(T.cmd(st2, o2, "lineage").contains("cours"), "Lignées : un seul à la fois")
	st2.tick = PsionicsBridges.lineage_until(st2, o2)
	var added: Array[Dictionary] = []
	PsionicsBridges.monthly(st2, 1, added)
	_ok(PsionicsBridges.lineage_until(st2, o2) == 0 and (not PsionicsDream.elu(st2, o2).is_empty() or Heroes.ids_of(st2, o2).is_empty()), "Lignées : au bout, un Élu")
	_ok(DeedsEval.value(st2, o2, "psi_elu") >= 1 or Heroes.ids_of(st2, o2).is_empty(), "Haut fait « Le premier Élu »")


static func _test_misc() -> void:
	var st := T.new_game("complet", "ossarane", {"politics": "active"})
	var oss := T.eid_of(st, "ossarane")
	var vael := T.eid_of(st, "vael")
	T.give_techs(st, oss, ["theorie_psionique", "telepathie"])
	Laws.adopt(st, oss, "registre_sensitifs")
	_ok(PsionicsBridges.encryption(st, oss) == 2, "Espionnage : le Registre chiffre")
	Psionics._add_fx(st, oss, {"id": "lecture", "until": st.tick + 100, "target": vael})
	_ok(PsionicsBridges.detect_bonus(st, oss, vael) == 2 and PsionicsBridges.detect_bonus(st, vael, oss) == 0, "Furtivité : une Lecture réussie perce les voiles")
	_ok(not Fauna.species("avatar_corrompu").is_empty() and not Fauna.species_ids().has("avatar_corrompu"), "Créatures : l'Avatar corrompu, né des plongées seulement")
	var added: Array[Dictionary] = []
	var h0 := Fauna.herd_ids(st).size()
	PsionicsDream.apply_vision(st, oss, {"id": "avatar_corrompu", "kind": "curse", "label": "Avatar corrompu", "do": "corrupt", "text": "x"}, added)
	_ok(Fauna.herd_ids(st).size() > h0, "Vision : l'Avatar corrompu rôde")
	Psionics.sub(st, "pact")[str(oss)] = {"p": "gueule", "favor": 0, "since": 0, "price": 99999, "tier": 0}
	PsionicsDream.break_pact(st, oss, added)
	_ok(DeedsEval.value(st, oss, "psi_broken") == 1, "Haut fait « Pacte rompu »")
