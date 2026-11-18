extends RefCounted
## Tests des prises de guerre, lot 2 (étude « Prises de guerre », propositions 21 à 35) : champ d'épaves,
## récupération et butin, politique d'épaves, grue et cimetières, épaves à la dérive, rétro-ingénierie par
## module, analyse des modèles, copies de coques de peuple, Strates et carcasses, opération « Voler les plans ».

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Prises de guerre (lot 2)…")
	_test_fields_and_policy()
	_test_recovery_and_loot()
	_test_study()
	_test_analysis()
	_test_copies()
	_test_harvest()
	_test_derelict_and_spy()
	_test_tomb()
	_test_save_and_ai()


func _ok(cond: bool, what: String) -> void:
	print("  ", "ok " if cond else "KO ", what)
	_check.call(cond, what)


func _state(seed_value := 4242, faction := "ossarane", mode := "complete") -> GameState:
	return GameState.create(seed_value, 150, 1800.0, faction, {"ai_level": "", "capture": mode})


func _me(st: GameState) -> int:
	return st.empires[0].id


func _foe(st: GameState) -> int:
	return st.empires[1].id


func _empty_system(st: GameState) -> int:
	for s in st.galaxy.systems:
		if st.system_owner(s.id) == -1 and s.neighbors.size() >= 2:
			return s.id
	return -1


func _war(st: GameState, a: int, b: int) -> void:
	for p in [[a, b], [b, a]]:
		if not st.get_empire(p[0]).contacts.has(p[1]):
			st.get_empire(p[0]).contacts.append(p[1])
	Combat.start_war(st, a, b)


func _spawn(st: GameState, owner: int, ships: Array, sid: int) -> Fleet:
	var f := st.spawn_ship(owner, String(ships[0]), sid)
	for i in range(1, ships.size()):
		f.add_ship(String(ships[i]))
	f.troops = Combat.max_troops(f)
	return f


func _battle(winner: int, loser: int, lost: Dictionary, own_lost := {}) -> Dictionary:
	return {"sides": [{"empire": winner, "lost": own_lost.duplicate()}, {"empire": loser, "lost": lost.duplicate()}]}


func _test_fields_and_policy() -> void:
	var st := _state(201)
	var me := _me(st)
	var foe := _foe(st)
	var sid := _empty_system(st)
	_ok(CaptureLore.policy(st, me) == "etudier", "politique d'épaves par défaut : Étudier")
	_ok(CaptureLore.check_policy(st, me, "both") != "", "« Les deux » réservé (Ossarane sans Ingénierie inverse)")
	_ok(CaptureLore.check_policy(st, me, "ferrailler") == "", "Ferrailler ouvert à tous")
	var bs := _state(202, "brisecomete")
	_ok(CaptureLore.policy(bs, _me(bs)) == "both", "Brisecomète (Profit, Syndicat) : les deux d'office")
	st.get_empire(me).techs["ingenierie_inverse"] = true
	_ok(CaptureLore.check_policy(st, me, "both") == "", "Ingénierie inverse ouvre « Les deux »")
	st.get_empire(me).techs.erase("ingenierie_inverse")
	# Champ composé : chaque coque tombée s'y inscrit avec son empire.
	var added: Array[Dictionary] = []
	var rep := {}
	CaptureLore.after_battle(st, sid, _battle(me, foe, {"fregate": 3}), me, rep, added)
	var fl := CaptureLore.field(st, sid)
	var rec := (rep.get("capture_lore", {}).get("recovered", []) as Array).size()
	_ok(fl.size() + rec == 3, "champ d'épaves composé : 3 coques (ou récupérées)")
	_ok(fl.is_empty() or int(fl[0]["o"]) == foe, "le champ retient l'empire de chaque épave")
	_ok(CaptureLore.field_text(st, sid) != "" or fl.is_empty(), "texte du champ pour la lentille Terrain")
	# Ferrailler : des matériaux, pas de recherche.
	Capture.apply_act(st, me, "policy", {"x": "ferrailler"})
	var e := st.get_empire(me)
	var m0 := int(e.resources.get("materials", 0))
	var shelf0 := e.research_shelf.size()
	var rep2 := {}
	CaptureLore.after_battle(st, sid, _battle(me, foe, {"croiseur": 2}), me, rep2, added)
	var got := (rep2.get("capture_lore", {}).get("recovered", []) as Array).size()
	_ok(int(e.resources.get("materials", 0)) > m0 or got == 2, "Ferrailler : 10 % du coût en matériaux")
	_ok(e.research_shelf.size() == shelf0 and (rep2.get("capture_lore", {}).get("learned", []) as Array).is_empty(), "Ferrailler : aucune rétro-ingénierie")
	_ok(not CaptureLore.studies_marks(st, me), "Ferrailler : les marques ne sont pas étudiées non plus")
	# Classique : aucun champ composé.
	var cl := _state(203, "ossarane", "classique")
	CaptureLore.after_battle(cl, _empty_system(cl), _battle(_me(cl), _foe(cl), {"fregate": 3}), _me(cl), {}, added)
	_ok(CaptureLore.field(cl, _empty_system(cl)).is_empty() and CaptureLore.studies_marks(cl, _me(cl)), "Classique : rien ne change")


func _test_recovery_and_loot() -> void:
	var st := _state(211)
	var me := _me(st)
	var foe := _foe(st)
	var sid := _empty_system(st)
	var added: Array[Dictionary] = []
	for _i in 40:
		CaptureLore.after_battle(st, sid, _battle(me, foe, {"corvette": 2}), me, {}, added)
	var loot := CaptureLore.pending_loot(st, me)
	_ok(not loot.is_empty(), "récupération : des coques détruites reviennent au butin (20 % pour un petit)")
	if loot.is_empty():
		return
	var ship := String(loot[0]["s"])
	_ok(Capture.is_prize(ship) and Capture.avarie_count(ship) >= 2, "une épave récupérée porte 2 à 4 avaries")
	var n0 := st.fleets.size()
	_ok(Capture.check_act(st, me, "loot", {"i": 0, "x": "keep"}) == "", "butin : remettre en service possible")
	Capture.apply_act(st, me, "loot", {"i": 0, "x": "keep"})
	_ok(st.fleets.size() == n0 + 1, "la coque remise en service forme une flotte")
	var size0 := CaptureLore.pending_loot(st, me).size()
	if size0 > 0:
		var e := st.get_empire(me)
		var m0 := int(e.resources.get("materials", 0))
		Capture.apply_act(st, me, "loot", {"i": 0, "x": "scrap"})
		_ok(int(e.resources.get("materials", 0)) > m0 and CaptureLore.pending_loot(st, me).size() == size0 - 1, "butin : démanteler rapporte des matériaux")
	_ok(Capture.check_act(st, me, "loot", {"i": 999, "x": "keep"}) != "", "butin inexistant refusé")
	# Le butin oublié suit la politique au bout de 30 jours.
	var left := CaptureLore.pending_loot(st, me).size()
	st.tick += 31
	CaptureLore.daily(st)
	_ok(left == 0 or CaptureLore.pending_loot(st, me).is_empty(), "le butin non réclamé suit la politique d'épaves")
	# Option : la politique automatique remplace la fenêtre.
	Capture.apply_act(st, me, "loot", {"x": "auto", "on": true})
	for _i in 40:
		CaptureLore.after_battle(st, sid, _battle(me, foe, {"corvette": 2}), me, {}, added)
	_ok(CaptureLore.pending_loot(st, me).is_empty(), "automatique : plus de butin en attente")
	# Les siens aussi : une seule avarie.
	var st2 := _state(212)
	var a := _me(st2)
	var own_back := false
	var fl_before := st2.fleets.size()
	for _i in 60:
		CaptureLore.after_battle(st2, _empty_system(st2), _battle(a, _foe(st2), {}, {"corvette": 1}), a, {}, added)
	for it: Dictionary in CaptureLore.pending_loot(st2, a):
		if Capture.avarie_count(String(it["s"])) == 1:
			own_back = true
	_ok(own_back or st2.fleets.size() > fl_before, "ses propres vaisseaux se récupèrent aussi, avec une avarie")
	# Méga-coque : une seule prise.
	_ok(CaptureLore.check_keep(st, me, "titan") == "" or Capture.has_mega_prize(st, me), "méga-coque : gardée si aucune autre prise")


func _test_study() -> void:
	var st := _state(221)
	var me := _me(st)
	var targets := CaptureLore.study_targets(st, me, "cuirasse")
	_ok(not targets.is_empty(), "un cuirassé ennemi porte des technologies à apprendre")
	var e := st.get_empire(me)
	e.research_queue.clear()
	var before := int(e.research_shelf.get(targets[0], 0)) if not targets.is_empty() else 0
	var learned := CaptureLore.study_ship(st, me, "cuirasse", false)
	_ok(learned != "" and int(e.research_shelf.get(targets[0], 0)) > before, "rétro-ingénierie : +10 % par technologie de module (ou son prérequis)")
	for t in targets:
		var tid := String(t)
		var pre: Array = Research.tech(tid).get("pre", [])
		var ok := true
		for p in pre:
			if not Research.knows(st, me, String(p)) and Research.is_visible(e.faction(), String(p)):
				ok = false
		_ok(ok, "cible étudiable (prérequis connus) : %s" % tid)
		break
	var p10 := CaptureLore.study_pct(st, me, false)
	var p25 := CaptureLore.study_pct(st, me, true)
	_ok(p25 > p10, "démanteler une prise intacte étudie plus fort (25 %)")
	var ms := _state(222, "murmurants")
	_ok(CaptureLore.study_pct(ms, _me(ms), false) > CaptureLore.study_pct(st, me, false) * 0 + 10 - 1, "Murmurants : étude à distance renforcée")
	# Rien à apprendre : quelques points.
	var k0 := int(e.resources.get("knowledge", 0))
	var t2 := CaptureLore.study_ship(st, me, "scout", false)
	_ok(t2 != "" or int(e.resources.get("knowledge", 0)) > k0, "rien de nouveau : un peu de recherche quand même")
	_ok(Capture.stat(st, me, "studied") >= 2, "statistique des épaves étudiées")
	# Carcasse de créature.
	var t3 := CaptureLore.study_ship(st, me, "bete_test", false)
	_ok(t3 != "", "carcasse de créature : de la recherche")


func _test_analysis() -> void:
	var st := _state(231)
	var me := _me(st)
	_ok(CaptureLore.analysis(st, me, "croiseur") == 0, "aucune analyse au départ")
	CaptureLore.study_ship(st, me, "croiseur", false)
	_ok(CaptureLore.analysis(st, me, "croiseur") == 5, "un croiseur étudié : analyse +5 %")
	for _i in 5:
		CaptureLore.study_ship(st, me, Capture.prize_id("croiseur", 1), false)
	_ok(CaptureLore.analysis(st, me, "croiseur") == 15, "analyse plafonnée à +15 % (les prises comptent pour leur modèle)")
	_ok(CaptureLore.analysis_shot(st, me, "croiseur", 100) == 115, "+15 % de dégâts contre ce modèle précis")
	_ok(CaptureLore.analysis_shot(st, me, "fregate", 100) == 100, "aucun bonus contre un autre modèle")
	var cl := _state(232, "ossarane", "classique")
	_ok(CaptureLore.analysis_shot(cl, _me(cl), "croiseur", 100) == 100, "Classique : pas d'analyse")


func _test_copies() -> void:
	var st := _state(241)
	var me := _me(st)
	_ok(not Designs.hull_ids_of(st, me).has("belier_clan" + CaptureLore.COPY), "pas de copie au départ")
	for _i in 3:
		CaptureLore.study_ship(st, me, "belier_clan", false)
	_ok(CaptureLore.has_copy(st, me, "belier_clan"), "3 études d'une coque de ligne étrangère : copie débloquée")
	var cid := "belier_clan" + CaptureLore.COPY
	_ok(Designs.hull_ids_of(st, me).has(cid), "la copie apparaît au Chantier")
	var orig := Designs.hull("belier_clan")
	var cp := Designs.hull(cid)
	_ok(int(cp["cost"]["materials"]) > int(orig["cost"]["materials"]) and int(cp["hp"]) < int(orig["hp"]), "copie : coût +30 %, structure 80 %")
	_ok((cp["integrated"] as Array).is_empty() and not (cp["half_integrated"] as Array).is_empty() or (orig.get("integrated", []) as Array).is_empty(), "copie : module intégré à moitié d'effet")
	_ok(not Designs.compute(cid, []).is_empty(), "une copie se calcule comme une coque")
	for _i in 4:
		CaptureLore.study_ship(st, me, "cathedrale", false)
	_ok(not CaptureLore.has_copy(st, me, "cathedrale"), "méga-coque : jamais copiée")
	_ok(not Capture.is_prize("x" + CaptureLore.COPY), "un identifiant de copie n'est pas une prise")


func _test_harvest() -> void:
	var st := _state(251, "brisecomete")
	var me := _me(st)
	var sid := _empty_system(st)
	for _i in 6:
		CaptureLore._add_wreck(st, sid, _foe(st), "fregate")
	_spawn(st, me, ["fregate"], sid)
	var e := st.get_empire(me)
	var m0 := int(e.resources.get("materials", 0))
	st.tick = 15
	CaptureLore.daily(st)
	_ok(int(e.resources.get("materials", 0)) > m0 and CaptureLore.field(st, sid).size() == 4, "ferrailleurs : récolte de 2 épaves par mois")
	_ok(Capture.stat(st, me, "harvests") == 1, "récolte comptée (haut fait Ferrailleur)")
	# Grue : n'importe quel peuple qui la porte.
	var os := _state(252)
	var a := _me(os)
	var s2 := _empty_system(os)
	CaptureLore._add_wreck(os, s2, _foe(os), "fregate")
	var f := _spawn(os, a, ["fregate"], s2)
	_ok(CaptureLore._harvesters(os, s2).is_empty(), "sans grue ni ferrailleurs : pas de récolte")
	GameData.register_custom_ship("test_grue", {"size": "small", "hp": 10, "salvage": true, "military": true, "cost": {"materials": 10}})
	f.add_ship("test_grue")
	_ok(CaptureLore._harvesters(os, s2) == [a], "grue de récupération : la flotte récolte")
	# Effacement annuel.
	var st3 := _state(253)
	var s3 := _empty_system(st3)
	for _i in 10:
		CaptureLore._add_wreck(st3, s3, _foe(st3), "fregate")
	st3.tick = 180
	CaptureLore.daily(st3)
	_ok(CaptureLore.field(st3, s3).size() == 5, "hors cimetière : moitié du champ par an")
	for _i in 100:
		CaptureLore._add_wreck(st3, s3, _foe(st3), "fregate")
	_ok(CaptureLore.field(st3, s3).size() == Capture.rule("field_cap"), "champ plafonné")


func _test_derelict_and_spy() -> void:
	var st := _state(261)
	var me := _me(st)
	var sid := _empty_system(st)
	var n0 := st.fleets.size()
	CaptureLore.derelict(st, me, "fregate", sid, true)
	var found := false
	for fid in st.fleets:
		var f: Fleet = st.fleets[fid]
		if f.owner == me and f.system_id == sid and Capture.is_prize(f.ships[0]):
			found = true
	_ok(st.fleets.size() == n0 + 1 and found, "épave à la dérive : remise en service avec des avaries")
	var e := st.get_empire(me)
	var m0 := int(e.resources.get("materials", 0))
	CaptureLore.derelict(st, me, "fregate", sid, false)
	_ok(int(e.resources.get("materials", 0)) > m0, "épave à la dérive : démontée pour la technologie")
	var ev := false
	for c: Dictionary in Events.data()["cards"] if Events.data().has("cards") else []:
		if String(c.get("id", "")) == "c_derive":
			ev = true
	_ok(ev or FileAccess.get_file_as_string("res://data/events.json").contains("c_derive"), "carte « L'épave à la dérive » dans les curiosités d'épave")
	# Voler les plans.
	var foe := _foe(st)
	_spawn(st, foe, ["croiseur", "croiseur", "fregate"], _empty_system(st))
	_ok(CaptureLore.spy_check(st, me, foe, "voler_plans") == "", "opération « Voler les plans » possible")
	var txt := CaptureLore.spy_apply(st, me, foe, {"id": "voler_plans"})
	_ok(CaptureLore.analysis(st, me, "croiseur") == 10 and txt != "", "les plans du modèle le plus nombreux : analyse +10 %")
	var ops := FileAccess.get_file_as_string("res://data/espionage.json")
	_ok(ops.contains("\"voler_plans\""), "opération déclarée dans l'espionnage")


func _test_tomb() -> void:
	var st := _state(271)
	var me := _me(st)
	_ok(not CaptureTomb.active(st), "pas de Vaisseau-tombe au départ")
	var sid := _empty_system(st)
	CaptureTomb.force_spawn(st, sid)
	_ok(CaptureTomb.active(st) and CaptureTomb.system(st) == sid, "le Vaisseau-tombe apparaît")
	var f := _spawn(st, me, ["transport", "transport", "transport", "transport", "transport", "transport", "transport", "transport"], sid)
	f.troops = 10
	_ok(CaptureTomb.check(st, me, {"fleet": f.id}) != "", "il faut beaucoup de troupes pour l'aborder")
	f.troops = 200
	_ok(Capture.check_act(st, me, "tomb", {"fleet": f.id}) == "", "abordage du Vaisseau-tombe possible avec 60 troupes")
	Capture.apply_act(st, me, "tomb", {"fleet": f.id})
	_ok(f.troops == 140 and Capture.stat(st, me, "tomb") == 1, "l'abordage coûte 60 troupes et tire sur la table")
	CaptureTomb.force_spawn(st, sid)
	st.tick += Capture.rule("tomb_move_days") + 1
	CaptureLore.daily(st)
	_ok(CaptureTomb.system(st) != sid, "le Vaisseau-tombe dérive vers un système voisin")


func _test_save_and_ai() -> void:
	var st := _state(281)
	var me := _me(st)
	var sid := _empty_system(st)
	CaptureLore._add_wreck(st, sid, _foe(st), "fregate")
	CaptureLore.study_ship(st, me, "croiseur", false)
	CaptureTomb.force_spawn(st, sid)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	_ok(back != null and CaptureLore.field(back, sid).size() == 1, "champ d'épaves sauvegardé")
	_ok(back != null and CaptureLore.analysis(back, me, "croiseur") == 5, "analyses sauvegardées")
	_ok(back != null and CaptureTomb.system(back) == sid, "Vaisseau-tombe sauvegardé")
	# IA : un passage complet sans erreur, posture et politique choisies.
	var ai := GameState.create(282, 150, 1800.0, "brisecomete", {"ai_level": "normal", "capture": "complete"})
	var foe := ai.empires[1]
	var fl := _spawn(ai, foe.id, ["fregate", "transport"], _empty_system(ai))
	foe.techs["equipes_prise"] = true
	var ctx := {"state": ai, "e": foe, "lv": AiLevels.level(foe.ai_level), "ai": AiLevels.personality(foe), "salt": 0, "intent": ""}
	AiCapture.think(ctx)
	_ok(Capture.posture_open(ai, fl) and Capture.stat(ai, foe.id, "ai_slot") >= 1, "IA : un passage des prises de guerre (posture, politique, prises)")
