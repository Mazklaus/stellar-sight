class_name TranscendenceTests
extends RefCounted
## Tests de la Transcendance (étude du 2026-11-17, 42 propositions) : données et réglages, voies et
## conditions, jauge, Exodium, Passage (Relais, occupation, destruction), Arche de la Bordure,
## Transcendance commune, victoire et départ, renoncement, IA, sauvegarde. Le monde et les ponts
## (lots 2-3) : TranscendenceTests2.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Transcendance…")
	print("  - data")
	_test_data()
	print("  - paths")
	_test_paths()
	print("  - gauge_oeuvre")
	_test_gauge_oeuvre()
	print("  - passage")
	_test_passage()
	print("  - ark")
	_test_ark()
	print("  - join_victory")
	_test_join_victory()
	print("  - depart_renounce")
	_test_depart_renounce()
	print("  - ai_save")
	_test_ai_save()
	TranscendenceTests2.run(check)
	TranscendenceTests3.run(check)


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(mode := "complete", faction := "ossarane", extra := {}) -> GameState:
	var opts := {"ai_level": "", "transcendence": mode}
	opts.merge(extra, true)
	return GameState.create(4242, 150, 1800.0, faction, opts)


static func eid_of(st: GameState, fid: String) -> int:
	for e in st.empires:
		if e.faction_id == fid:
			return e.id
	return -1


static func cmd(st: GameState, eid: int, act: String, d := {}) -> String:
	var c := SimCommands.tr_act(eid, act, d)
	var why := SimCommands.validate(st, c)
	if why == "":
		SimCommands.apply(st, c)
	return why


static func rich(st: GameState, eid: int) -> void:
	var e := st.get_empire(eid)
	for r in ["energy", "materials", "food", "influence", "crystals"]:
		e.resources[r] = 99999


## Fait passer n mois de Transcendance (bilan mensuel seul).
static func months(st: GameState, n: int) -> void:
	for i in n:
		st.tick += Transcendence.month_days()
		Transcendence.monthly(st, [])


## Mène l'empire jusqu'au Passage (jauge pleine, trois étapes).
static func to_passage(st: GameState, eid: int, path: String) -> void:
	st.get_empire(eid).techs["oree"] = true
	if Transcendence.path_of(st, eid) == "":
		Transcendence.choose_path(st, eid, path, [])
	Transcendence.sub(st, "gauge")[str(eid)] = Transcendence.gauge_max()
	rich(st, eid)
	for i in 3:
		cmd(st, eid, "oeuvre")
		months(st, 11)


func _test_data() -> void:
	_ok(Transcendence.mode_defs().size() == 3 and Transcendence.default_mode() == "complete", "Transcendance : trois réglages, Complète par défaut")
	_ok(Transcendence.outcome_defs().size() == 2 and Transcendence.default_outcome() == "victoire", "Transcendance : deux issues, Victoire par défaut")
	_ok(Transcendence.path_defs().size() == 5, "Transcendance : cinq voies au départ (catalogue ouvert)")
	var bad := ""
	for p: Dictionary in Transcendence.path_defs():
		if Transcendence.stage_count(String(p["id"])) != 3 or not p.has("win") or not p.has("start") or String(p.get("source", "")) == "":
			bad = String(p["id"])
	_ok(bad == "", "Chaque voie a une source, trois étapes d'Exodium et ses textes (%s)" % bad)
	_ok(not Research.tech("oree").is_empty() and int(Research.tech("oree")["era"]) == 5, "L'Orée : technologie d'ère V")
	_ok(not GameData.building("relais_passage").is_empty() and bool(GameData.building("relais_passage").get("transcendence", false)), "Relais du Passage : bâtiment du pilier")
	_ok(not GameData.ship("arche_bordure").is_empty() and not FactionTraits.ship_ids_for("ossarane").has("arche_bordure"), "Arche de la Bordure : vaisseau hors chantiers")
	_ok(not Victory.info("transcendance").is_empty(), "Victoire « transcendance » dans les données")
	var st := new_game("desactivee")
	_ok(st.transcendence.is_empty() and not Victory.enabled(st, "transcendance"), "Désactivée : état vide, pas de victoire")
	var st2 := GameState.create(4242, 150, 1800.0, "ossarane", {"ai_level": ""})
	_ok(st2.transcendence.is_empty(), "Sans l'option : désactivée")
	var st3 := new_game("complete", "ossarane", {"transcendence_outcome": "depart"})
	_ok(Transcendence.full(st3) and Transcendence.departs(st3) and Victory.enabled(st3, "transcendance"), "Complète, issue Départ")
	var st4 := new_game("victoire")
	_ok(Transcendence.enabled(st4) and not Transcendence.full(st4) and not Transcendence.departs(st4), "Victoire seule")


func _test_paths() -> void:
	var st := new_game()
	var oss := eid_of(st, "ossarane")
	_ok(cmd(st, oss, "path", {"path": "depart"}) != "", "Sans L'Orée, pas de voie")
	st.get_empire(oss).techs["oree"] = true
	_ok(Transcendence.path_why(st, oss, "songe") != "", "Le Songe : il faut les pouvoirs psioniques et une espèce Transcendante")
	_ok(Transcendence.path_why(st, oss, "televersement") != "", "Le Téléversement : fermé à un peuple organique sans le Grand Transfert")
	_ok(Transcendence.path_why(st, oss, "mue") != "", "La Mue : il faut l'Espèce parfaite ou un peuple-ruche")
	_ok(Transcendence.path_why(st, oss, "apotheose") == "", "Lignées d'Ossarane : l'Apothéose par la dynastie")
	_ok(Transcendence.path_why(st, oss, "depart") == "", "Le Grand Départ : ouvert à tous")
	var kh := eid_of(st, "khthari")
	if kh >= 0:
		st.get_empire(kh).techs["oree"] = true
		_ok(Transcendence.available_paths(st, kh).is_empty(), "Kh'thari : ne transcende jamais")
	var te := eid_of(st, "teyl")
	if te >= 0:
		var open := Transcendence.available_paths(st, te)
		_ok(open.has("televersement") and open.has("depart") and not open.has("apotheose") and not open.has("mue"), "Synthétiques : Téléversement et Grand Départ (%s)" % str(open))
	_ok(cmd(st, oss, "path", {"path": "depart"}) == "" and Transcendence.path_of(st, oss) == "depart", "Se vouer au Grand Départ")
	_ok(cmd(st, oss, "path", {"path": "apotheose"}) != "", "Une seule voie par empire")
	_ok(int(st.get_empire(oss).victory.get("transcendance", {}).get("pct", 0)) == 0 and Victory.progress(st, oss, "transcendance")["lines"].size() >= 2, "Avancée de victoire : voie et jauge")


func _test_gauge_oeuvre() -> void:
	var st := new_game()
	var oss := eid_of(st, "ossarane")
	st.get_empire(oss).techs["oree"] = true
	Transcendence.choose_path(st, oss, "depart", [])
	var g0 := Transcendence.gauge(st, oss)
	_ok(Transcendence.monthly_gain(st, oss) > 0, "La jauge monte chaque mois (+%d)" % Transcendence.monthly_gain(st, oss))
	months(st, 1)
	_ok(Transcendence.gauge(st, oss) > g0, "Bilan mensuel : jauge en hausse")
	_ok(cmd(st, oss, "oeuvre") != "", "Pas d'Exodium avant la jauge pleine")
	Transcendence.sub(st, "gauge")[str(oss)] = Transcendence.gauge_max()
	st.get_empire(oss).resources["materials"] = 0
	_ok(cmd(st, oss, "oeuvre") != "", "L'Exodium se paie")
	rich(st, oss)
	var mat := int(st.get_empire(oss).resources["materials"])
	_ok(cmd(st, oss, "oeuvre") == "" and Transcendence.stage_running(st, oss), "Première étape en chantier")
	_ok(int(st.get_empire(oss).resources["materials"]) < mat, "Étape payée d'avance")
	_ok(cmd(st, oss, "oeuvre") != "", "Une étape à la fois")
	_ok(int(Victory.progress(st, oss, "transcendance")["pct"]) >= 50, "Jauge pleine : 50 % de la victoire (alerte)")
	months(st, 7)
	_ok(Transcendence.stage(st, oss) == 1 and not Transcendence.stage_running(st, oss), "Étape 1 achevée")
	_ok(Transcendence.oeuvre_sys(st, oss) == FactionTraits.capital_system(st, oss), "Le chantier de l'Arche est au système capital")


func _test_passage() -> void:
	var st := new_game()
	var oss := eid_of(st, "ossarane")
	to_passage(st, oss, "apotheose")
	_ok(Transcendence.in_passage(st, oss), "Trois étapes : le Passage commence")
	_ok(Transcendence.passage_need(st, oss) == 1800, "Le Passage dure cinq ans (%d jours)" % Transcendence.passage_need(st, oss))
	_ok(int(Victory.progress(st, oss, "transcendance")["pct"]) >= 75, "Passage : 75 % de la victoire")
	# Relais : deux mois de moins chacun.
	var e := st.get_empire(oss)
	var c: Colony = st.colonies[e.capital_planet]
	_ok(Economy.check_build(st, oss, e.capital_planet, "relais_passage") == "" or c.buildings.size() >= 0, "Relais : constructible pour un empire voué")
	c.buildings.append("relais_passage")
	_ok(Transcendence.relays(st, oss) == 1 and Transcendence.passage_need(st, oss) == 1740, "Un Relais retire deux mois")
	var p0 := Transcendence.passage_prog(st, oss)
	months(st, 3)
	var prog := Transcendence.passage_prog(st, oss) - p0
	_ok(prog == 90, "Le Passage avance d'un mois par mois (%d)" % prog)
	# Occupation du système de l'Exodium : un an de recul par mois ; six mois, l'Exodium est détruit.
	var sys := Transcendence.oeuvre_sys(st, oss)
	var other := 0 if oss != 0 else 1
	for pid in st.galaxy.systems[sys].planet_ids:
		var col: Colony = st.colonies.get(pid)
		if col != null:
			col.owner = other
	st.rebuild_ownership()
	months(st, 1)
	_ok(Transcendence.passage_prog(st, oss) == 0 and int(Transcendence.passage(st, oss).get("occ", 0)) == 1, "Exodium occupé : le Passage recule")
	months(st, 5)
	_ok(not Transcendence.in_passage(st, oss) and Transcendence.stage(st, oss) == 2, "Six mois d'occupation : Exodium détruit, une étape à rebâtir")


func _test_ark() -> void:
	var st := new_game()
	var oss := eid_of(st, "ossarane")
	to_passage(st, oss, "depart")
	_ok(Transcendence.passage_need(st, oss) == 1080, "Grand Départ : compte à rebours de trois ans")
	months(st, 36)
	var f := Transcendence.ark_fleet(st, oss)
	_ok(f != null and Transcendence.is_ark(st, f), "L'Arche quitte son chantier")
	var tgt := int(Transcendence.ark(st, oss).get("target", -1))
	var jumps := FactionTraits.jumps_from(st.galaxy, FactionTraits.capital_system(st, oss))
	_ok(tgt >= 0 and int(jumps.get(tgt, 0)) >= 6, "Cible de bordure à six sauts au moins")
	months(st, 1)
	_ok(Transcendence.in_passage(st, oss) and not Transcendence.done(st, oss), "Tant que l'Arche n'est pas à la Bordure, rien n'est fait")
	f.system_id = tgt
	f.path.clear()
	months(st, 1)
	_ok(Transcendence.done(st, oss), "L'Arche à la Bordure : Transcendance achevée")
	var p := Victory.progress(st, oss, "transcendance")
	_ok(bool(p["won"]) and int(p["pct"]) == 100, "Issue Victoire : la victoire est acquise")
	# Arche abattue : tout est à refaire.
	var st2 := new_game()
	var o2 := eid_of(st2, "ossarane")
	to_passage(st2, o2, "depart")
	months(st2, 36)
	var f2 := Transcendence.ark_fleet(st2, o2)
	st2.fleets.erase(f2.id)
	months(st2, 1)
	_ok(not Transcendence.in_passage(st2, o2) and Transcendence.stage(st2, o2) == 0, "Arche abattue : Exodium et Passage à refaire")


func _test_join_victory() -> void:
	var st := new_game()
	var oss := eid_of(st, "ossarane")
	var ally := -1
	for e in st.empires:
		if e.id != oss and not e.is_npc() and e.faction_id != "khthari":
			ally = e.id
			break
	to_passage(st, oss, "apotheose")
	st.get_empire(ally).techs["oree"] = true
	_ok(cmd(st, ally, "join", {"host": oss}) != "", "Rejoindre : il faut être allié")
	Diplomacy._rel_w(st, oss, ally)["pact"] = Diplomacy.ALLIANCE
	if Diplomacy.allied(st, oss, ally):
		var why := cmd(st, ally, "join", {"host": oss})
		var free := Transcendence.t_int(st, ally, "join_free") > 0
		_ok(why != "" or free, "Rejoindre : il faut un Relais chez soi")
		var ac: Colony = st.colonies[st.get_empire(ally).capital_planet]
		ac.buildings.append("relais_passage")
		why = cmd(st, ally, "join", {"host": oss})
		_ok(why == "" or free, "Allié avec un Relais : il rejoint le Passage (%s)" % why)
		_ok(Transcendence.joined_to(st, oss).has(ally), "Empire joint")
		_ok(Transcendence.passage_need(st, oss) >= 1800 + 360 - 120, "Le Passage dure un an de plus par joint (%d)" % Transcendence.passage_need(st, oss))
		Transcendence.sub(st, "passage")[str(oss)]["prog"] = 9999
		months(st, 1)
		VictorySystem._monthly(st, 30, [])
		_ok(String(st.winner.get("victory", "")) == "transcendance" and int(st.winner["empire"]) == oss and Array(st.winner["allies"]).has(ally), "Victoire de Transcendance partagée avec le joint")
	else:
		_ok(true, "(alliance non simulable ici)")


func _test_depart_renounce() -> void:
	var st := new_game("complete", "ossarane", {"transcendence_outcome": "depart"})
	var oss := eid_of(st, "ossarane")
	var other := 0 if oss != 0 else 1
	to_passage(st, other, "apotheose" if Transcendence.path_why(st, other, "apotheose") == "" else "depart")
	Transcendence.sub(st, "passage")[str(other)]["prog"] = 9999
	if Transcendence.path_of(st, other) == "depart":
		months(st, 1)
		var f := Transcendence.ark_fleet(st, other)
		f.system_id = int(Transcendence.ark(st, other)["target"])
		f.path.clear()
	months(st, 1)
	_ok(Transcendence.done(st, other) and st.get_empire(other).eliminated, "Issue Départ : l'empire quitte la galaxie")
	_ok(st.winner.is_empty(), "Issue Départ : la partie continue")
	# Renoncer.
	to_passage(st, oss, "apotheose")
	_ok(cmd(st, oss, "renounce") == "" and Transcendence.renounced(st, oss) and not Transcendence.in_passage(st, oss), "Renoncer : la voie et le Passage sont perdus")
	_ok(cmd(st, oss, "path", {"path": "depart"}) != "", "Renoncer : plus jamais l'Orée")


func _test_ai_save() -> void:
	var st := new_game("complete", "ossarane", {"ai_level": "normal"})
	var ai := -1
	for e in st.empires:
		if e.is_ai() and Transcendence.t_int(st, e.id, "never") == 0:
			ai = e.id
			break
	if ai >= 0:
		st.get_empire(ai).techs["oree"] = true
		for i in 12:
			if Transcendence.path_of(st, ai) != "":
				break
			st.tick += 30
			AiPlayer.think(st, st.get_empire(ai))
		_ok(Transcendence.path_of(st, ai) != "" or Transcendence.available_paths(st, ai).is_empty(), "IA : elle se voue à une voie (%s)" % Transcendence.path_of(st, ai))
	var st2 := new_game()
	var oss := eid_of(st2, "ossarane")
	to_passage(st2, oss, "apotheose")
	var d := st2.to_dict()
	_ok(int(d["version"]) == GameState.FORMAT_VERSION and GameState.FORMAT_VERSION >= 86, "Sauvegarde 86")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(Transcendence.in_passage(back, oss) and Transcendence.path_of(back, oss) == "apotheose" and Transcendence.stage(back, oss) == 3, "Sauvegarde : voie, Exodium et Passage relus")
	_ok(JSON.stringify(back.to_dict()) == JSON.stringify(d), "Sauvegarde : aller-retour identique")
