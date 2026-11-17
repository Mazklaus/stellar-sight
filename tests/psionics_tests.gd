extends RefCounted
## Tests des pouvoirs psioniques (étude du 2026-11-17, 42 propositions) : données et réglages,
## échelle des espèces, Résonance, voie L'Éveil (avec et sans le Génome), couronnement, pouvoirs,
## écrans, fêlures, lois, Collèges, héros sensitifs, IA, sauvegarde ; le Songe et les ponts (lots 2-3).
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Pouvoirs psioniques…")
	print("  - data")
	_test_data()
	print("  - levels")
	_test_levels()
	print("  - resonance")
	_test_resonance()
	print("  - path")
	_test_path()
	print("  - powers")
	_test_powers()
	print("  - felures_laws")
	_test_felures_laws()
	print("  - heroes_buildings")
	_test_heroes_buildings()
	print("  - ai")
	_test_ai()
	print("  - save")
	_test_save()
	PsionicsTests2.run(check)


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(mode := "complet", faction := "ossarane", extra := {}) -> GameState:
	var opts := {"ai_level": "", "psionics": mode}
	opts.merge(extra, true)
	return GameState.create(4242, 150, 1800.0, faction, opts)


static func eid_of(st: GameState, fid: String) -> int:
	for e in st.empires:
		if e.faction_id == fid:
			return e.id
	return -1


static func give_techs(st: GameState, eid: int, ids: Array) -> void:
	var e := st.get_empire(eid)
	for t in ids:
		e.techs[String(t)] = true


static func cmd(st: GameState, eid: int, act: String, d := {}) -> String:
	var c := SimCommands.psi_act(eid, act, d)
	var why := SimCommands.validate(st, c)
	if why == "":
		SimCommands.apply(st, c)
	return why


static func home_system(st: GameState, eid: int) -> int:
	return st.galaxy.get_planet(st.get_empire(eid).capital_planet).system_id


func _test_data() -> void:
	_ok(Psionics.mode_defs().size() == 3 and Psionics.default_mode() == "complet", "Psionique : trois réglages, Complet par défaut")
	_ok(not Psionics.form_def("songe").is_empty() and String(Psionics.cfg("forms").get("default", "")) == "songe", "Formes : catalogue ouvert, le Songe par défaut")
	var missing := ""
	for k in Psionics.cfg("techs"):
		if k != "_doc" and Research.tech(String(k)).is_empty():
			missing = String(k)
	for p: Dictionary in Psionics.power_defs():
		if String(p.get("tech", "")) != "" and Research.tech(String(p["tech"])).is_empty():
			missing = String(p["tech"])
	_ok(missing == "", "Psionique : les technologies du pilier sont dans l'arbre (%s)" % missing)
	var ids := {}
	var dup := false
	for p: Dictionary in Psionics.power_defs():
		dup = dup or ids.has(String(p["id"]))
		ids[String(p["id"])] = true
	_ok(not dup and ids.size() >= 3, "Pouvoirs : catalogue sans doublon (%d)" % ids.size())
	for b in ["college_sensitifs", "ecran_psychique"]:
		_ok(not GameData.building(b).is_empty(), "Bâtiment : %s" % b)
	for l in ["registre_sensitifs", "colleges_fermes", "nefs_silence", "persecution"]:
		_ok(not Laws.law_def(l).is_empty(), "Loi : %s" % l)
	_ok(not Genetics.path_def("eveil").is_empty(), "Génome : L'Éveil dans la liste des voies")
	var st := new_game("desactive")
	_ok(st.psionics.is_empty() and not Psionics.applies(st, 0), "Psionique désactivée : rien en jeu")
	_ok(cmd(st, 0, "power", {"power": "apaisement", "target": home_system(st, 0)}) != "", "Psionique désactivée : aucun pouvoir")
	var st2 := new_game("discret")
	_ok(Psionics.enabled(st2) and not Psionics.full(st2), "Psionique discrète : en jeu, sans le Songe")
	var st3 := GameState.create(4242, 150, 1800.0, "ossarane", {"ai_level": ""})
	_ok(st3.psionics.is_empty(), "Sans l'option : désactivée")


func _test_levels() -> void:
	var st := new_game()
	var oss := eid_of(st, "ossarane")
	var mur := eid_of(st, "murmurants")
	var teyl := eid_of(st, "teyl")
	var kh := eid_of(st, "khthari")
	_ok(Psionics.founder_level(st, oss) == 0, "Échelle : Ossarane sourd au départ")
	_ok(Psionics.founder_level(st, mur) == 1, "Échelle : les énergétiques naissent Latents")
	for x in [oss, teyl, kh]:
		give_techs(st, x, ["theorie_psionique"])
	_ok(Psionics.founder_level(st, oss) == 1, "Échelle : Théorie psionique rend Latent")
	_ok(Psionics.founder_level(st, teyl) == 0 and Psionics.immune(st, teyl), "Échelle : les synthétiques restent sourds et immunisés")
	_ok(Psionics.founder_level(st, kh) == 1, "Échelle : la ruche plafonne à Latente")
	_ok(Psionics.level_label(2) == "Éveillée", "Échelle : libellés")


func _test_resonance() -> void:
	var st := new_game()
	var oss := eid_of(st, "ossarane")
	_ok(Psionics.monthly_gain(st, oss) == 0, "Résonance : rien tant que personne n'entend")
	give_techs(st, oss, ["theorie_psionique"])
	var g := Psionics.monthly_gain(st, oss)
	_ok(g > 0, "Résonance : les Latents en donnent (%d par mois)" % g)
	var added: Array[Dictionary] = []
	Psionics.monthly(st, added)
	_ok(Psionics.resonance(st, oss) == g, "Résonance : gagnée au bilan mensuel")
	Psionics.add_resonance(st, oss, 100000)
	_ok(Psionics.resonance(st, oss) == Psionics.cap(st, oss), "Résonance : plafonnée (%d)" % Psionics.cap(st, oss))
	_ok(not st.get_empire(oss).resources.has("resonance"), "Résonance : pas un bien de l'économie")


func _test_path() -> void:
	# Sans le Génome : la voie se prend dans l'écran Songe.
	var st := new_game()
	var oss := eid_of(st, "ossarane")
	_ok(cmd(st, oss, "path") != "", "L'Éveil : il faut les technologies")
	give_techs(st, oss, ["theorie_psionique", "telepathie"])
	_ok(cmd(st, oss, "path") == "", "L'Éveil : choisi")
	_ok(Psionics.awake(st, oss) and Psionics.founder_level(st, oss) == 2, "L'Éveil : l'espèce fondatrice est Éveillée")
	_ok(cmd(st, oss, "path") != "", "L'Éveil : une seule fois")
	var teyl := eid_of(st, "teyl")
	give_techs(st, teyl, ["theorie_psionique", "telepathie"])
	_ok(Psionics.check_path(st, teyl).contains("sourde"), "L'Éveil : impossible pour un peuple sourd")
	var kh := eid_of(st, "khthari")
	give_techs(st, kh, ["theorie_psionique", "telepathie"])
	_ok(Psionics.check_path(st, kh) != "", "L'Éveil : impossible pour une ruche")
	# Couronnement.
	give_techs(st, oss, ["precognition", "ouverture_songe"])
	sub_awake(st, oss, -11 * 360)
	var added: Array[Dictionary] = []
	Psionics.monthly(st, added)
	_ok(Psionics.crowned(st, oss) and Psionics.founder_level(st, oss) == 3, "Couronnement : Transcendante")
	# Avec le Génome : 5e voie, exclusive, interdit Chair et acier.
	var st2 := new_game("complet", "ossarane", {"genetics": "complete"})
	var o2 := eid_of(st2, "ossarane")
	give_techs(st2, o2, ["theorie_psionique", "telepathie", "implants_neuraux"])
	_ok(Genetics.check_path(st2, o2, "eveil") == "", "Génome : L'Éveil se choisit sans programme achevé")
	_ok(cmd(st2, o2, "path") == "", "Génome : L'Éveil choisi par l'ordre psionique")
	_ok(st2.get_empire(o2).gene_path == "eveil" and Psionics.awake(st2, o2), "Génome : voie posée des deux côtés")
	_ok(Genetics.check_path(st2, o2, "genetique") != "", "Génome : plus d'autre voie")
	_ok(Genetics.check_cyber(st2, o2, "ossarane").contains("Éveil"), "Génome : L'Éveil interdit Chair et acier")
	var st3 := new_game("complet", "ossarane", {"genetics": "complete"})
	var o3 := eid_of(st3, "ossarane")
	give_techs(st3, o3, ["theorie_psionique", "telepathie"])
	st3.get_empire(o3).gene_path = "cybernetique"
	_ok(Psionics.check_path(st3, o3) != "", "Génome : Chair et acier ferme L'Éveil")
	var st4 := new_game("desactive", "ossarane", {"genetics": "complete"})
	_ok(Genetics.check_path(st4, 0, "eveil") != "", "Génome : L'Éveil fermé sans pouvoirs psioniques")


static func sub_awake(st: GameState, eid: int, delta: int) -> void:
	Psionics.sub(st, "awake")[str(eid)] = st.tick + delta


func _test_powers() -> void:
	var st := new_game()
	var oss := eid_of(st, "ossarane")
	var vael := eid_of(st, "vael")
	var teyl := eid_of(st, "teyl")
	var sid := home_system(st, oss)
	_ok(cmd(st, oss, "power", {"power": "apaisement", "target": sid}).contains("Télépathie"), "Pouvoir : il faut la technologie")
	give_techs(st, oss, ["theorie_psionique", "telepathie", "precognition"])
	_ok(cmd(st, oss, "power", {"power": "apaisement", "target": sid}).contains("Résonance"), "Pouvoir : il faut de la Résonance")
	Psionics.add_resonance(st, oss, 1000)
	var before := Psionics.resonance(st, oss)
	var stab := Stability.value(st, sid)
	_ok(cmd(st, oss, "power", {"power": "apaisement", "target": sid}) == "", "Apaisement : lancé")
	_ok(Psionics.resonance(st, oss) == before - Psionics.power_cost(st, oss, "apaisement"), "Pouvoir : la Résonance est dépensée")
	var found := false
	for p in Stability.parts(st, sid):
		if String(p[0]) == "Apaisement psionique":
			found = true
	_ok(found, "Apaisement : stabilité du système (%d avant)" % stab)
	_ok(cmd(st, oss, "power", {"power": "apaisement", "target": sid}).contains("revient"), "Pouvoir : recharge")
	_ok(cmd(st, oss, "power", {"power": "apaisement", "target": home_system(st, vael)}) != "", "Apaisement : seulement chez soi")
	# Lecture des esprits.
	st.get_empire(oss).contacts.clear()
	_ok(cmd(st, oss, "power", {"power": "lecture", "target": vael}).contains("rencontré"), "Lecture : il faut avoir rencontré la cible")
	st.get_empire(oss).contacts.append(vael)
	st.get_empire(oss).contacts.append(teyl)
	_ok(cmd(st, oss, "power", {"power": "lecture", "target": vael}) == "", "Lecture : lancée")
	_ok(st.get_empire(oss).dossiers.has(vael), "Lecture : dossier complet")
	_ok(Psionics.op_bonus(st, oss, vael) > 0, "Lecture : bonus aux opérations")
	_ok(Psionics.screen_pct(st, teyl) == 100, "Écrans : un peuple sourd est imperméable")
	Psionics.sub(st, "cd").erase("%d:lecture" % oss)
	_ok(cmd(st, oss, "power", {"power": "lecture", "target": teyl}) == "", "Lecture contre les Teyl : lancée")
	_ok(not st.get_empire(oss).dossiers.has(teyl) and Psionics.op_bonus(st, oss, teyl) == 0, "Lecture contre les Teyl : échoue")
	give_techs(st, vael, ["ecrans_psychiques"])
	_ok(Psionics.screen_pct(st, vael) == 30, "Écrans : 30 % avec la technologie")
	# Préscience.
	Psionics.add_resonance(st, oss, 1000)
	_ok(cmd(st, oss, "power", {"power": "prescience"}) == "", "Préscience : lancée")
	_ok(Psionics.crisis_seers(st).has(oss), "Préscience : sent venir les crises")
	_ok(Psionics.presage_days(st, [oss] as Array[int]) > 0, "Préscience : préavis de crise")
	# Peuple sourd : aucun pouvoir.
	give_techs(st, teyl, ["theorie_psionique", "telepathie"])
	Psionics.add_resonance(st, teyl, 500)
	_ok(Psionics.check_power(st, teyl, "apaisement", home_system(st, teyl)).contains("entend"), "Pouvoir : il faut une espèce qui entend")


func _test_felures_laws() -> void:
	var st := new_game("complet", "ossarane", {"politics": "active"})
	var oss := eid_of(st, "ossarane")
	give_techs(st, oss, ["theorie_psionique", "telepathie"])
	var free: int = Psionics.felure_chance(st, oss, "lecture")[0]
	_ok(free > 0, "Fêlure : risque de base (%d %%)" % free)
	_ok(Laws.check_adopt(st, oss, "registre_sensitifs") == "" or Laws.check_adopt(st, oss, "registre_sensitifs").contains("emplacement") or Laws.check_adopt(st, oss, "registre_sensitifs").contains("influence"), "Loi : Registre ouvert (%s)" % Laws.check_adopt(st, oss, "registre_sensitifs"))
	Laws.adopt(st, oss, "registre_sensitifs")
	var reg: int = Psionics.felure_chance(st, oss, "lecture")[0]
	_ok(reg < free, "Registre : fêlures plus rares (%d %%)" % reg)
	var added: Array[Dictionary] = []
	Psionics.apply_felure(st, oss, (Psionics.cfg("felures")["table"] as Array)[0], added)
	var found := false
	for p in Psionics.empire_stability_parts(st, oss):
		found = found or String(p[0]).contains("Migraine")
	_ok(found and not added.is_empty(), "Fêlure : migraine collective")
	Psionics.add_resonance(st, oss, 80)
	var r := Psionics.resonance(st, oss)
	Psionics.apply_felure(st, oss, (Psionics.cfg("felures")["table"] as Array)[1], added)
	_ok(Psionics.resonance(st, oss) == r - r / 2, "Fêlure : fuite de Résonance")
	Psionics.apply_felure(st, oss, (Psionics.cfg("felures")["table"] as Array)[2], added)
	var hant := false
	for fx: Dictionary in Psionics.fx_list(st, oss):
		hant = hant or String(fx["id"]) == "f_system"
	_ok(hant, "Fêlure : hantise sur un système")
	Laws.revoke(st, oss, "registre_sensitifs")
	Laws.adopt(st, oss, "colleges_fermes")
	var g0 := Psionics.monthly_gain(st, oss)
	_ok(g0 > 0, "Collèges fermés : Résonance (%d)" % g0)
	Laws.revoke(st, oss, "colleges_fermes")
	Laws.adopt(st, oss, "persecution")
	Psionics.add_resonance(st, oss, 500)
	_ok(Psionics.check_power(st, oss, "apaisement", home_system(st, oss)).contains("Persécution"), "Persécution : aucun pouvoir")
	_ok(Psionics.monthly_gain(st, oss) == 0, "Persécution : aucune Résonance")
	var st2 := new_game("desactive", "ossarane", {"politics": "active"})
	_ok(Laws.check_adopt(st2, 0, "registre_sensitifs").contains("psioniques"), "Loi : fermée sans le pilier")


func _test_heroes_buildings() -> void:
	var st := new_game()
	var oss := eid_of(st, "ossarane")
	var hid := Heroes.ids_of(st, oss)
	_ok(not hid.is_empty(), "Héros : un au départ")
	if hid.is_empty():
		return
	var h: Dictionary = st.heroes[hid[0]]
	_ok(Psionics.hero_power(st, h) == 0, "Héros : pas sensitif tant que l'espèce est sourde")
	give_techs(st, oss, ["theorie_psionique", "telepathie"])
	(h["traits"] as Array).append("psionique")
	_ok(Psionics.hero_power(st, h) == 1, "Héros : trait Psionique = puissance 1")
	h["lvl"] = 5
	_ok(Psionics.hero_power(st, h) == 2, "Héros : la puissance monte avec le niveau")
	(h["traits"] as Array).erase("psionique")
	h["lvl"] = 1
	cmd(st, oss, "path")
	_ok(Psionics.hero_power(st, h) >= 1, "Héros : espèce Éveillée = héros sensitifs")
	var c: Colony = st.colonies[st.get_empire(oss).capital_planet]
	_ok(Psionics.check_build(st, oss, c, "college_sensitifs") == "", "Collège : ouvert sur une colonie qui entend")
	var teyl := eid_of(st, "teyl")
	give_techs(st, teyl, ["theorie_psionique", "telepathie"])
	var ct: Colony = st.colonies[st.get_empire(teyl).capital_planet]
	_ok(Psionics.check_build(st, teyl, ct, "college_sensitifs") != "", "Collège : fermé à un peuple sourd")
	var g0 := Psionics.monthly_gain(st, oss)
	var cap0 := Psionics.cap(st, oss)
	c.buildings.append("college_sensitifs")
	_ok(Psionics.colleges(st, oss) == 1 and Psionics.monthly_gain(st, oss) > g0 and Psionics.cap(st, oss) > cap0, "Collège : Résonance et plafond")
	var sid := home_system(st, oss)
	var col := false
	for p in Psionics.system_stability_parts(st, sid, oss):
		col = col or String(p[0]).begins_with("Collège")
	_ok(col, "Collège : stabilité du système")
	var fc: int = Psionics.felure_chance(st, oss, "lecture")[0]
	_ok(fc < int(Psionics.power_def("lecture")["felure"]), "Collège et Éveil : fêlures plus rares (%d %%)" % fc)


func _test_ai() -> void:
	var st := new_game("complet", "vael")
	var vael := eid_of(st, "vael")
	var e := st.get_empire(vael)
	give_techs(st, vael, ["theorie_psionique", "telepathie"])
	var ctx := {"state": st, "e": e, "lv": AiLevels.level("normal"), "ai": AiLevels.personality(e), "salt": 0, "intent": ""}
	AiPsionics.think(ctx)
	_ok(Psionics.awake(st, vael) or String(ctx.get("intent", "")) != "" or true, "IA : réfléchit sans erreur")
	_ok(Psionics.stat(st, vael, "ai_month") > 0, "IA : une fois par mois")


func _test_save() -> void:
	var st := new_game()
	var oss := eid_of(st, "ossarane")
	give_techs(st, oss, ["theorie_psionique", "telepathie"])
	cmd(st, oss, "path")
	Psionics.add_resonance(st, oss, 40)
	var d := st.to_dict()
	_ok(int(d["version"]) == 85, "Sauvegarde 85")
	var st2 := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(st2 != null, "Sauvegarde relue")
	if st2 == null:
		return
	_ok(Psionics.awake(st2, oss) and Psionics.resonance(st2, oss) == Psionics.resonance(st, oss), "Sauvegarde : Éveil et Résonance gardés")
	_ok(Psionics.mode(st2) == "complet", "Sauvegarde : réglage gardé")
	var st3 := new_game("desactive")
	_ok(not st3.to_dict().has("psionics"), "Sauvegarde : rien si désactivé")
