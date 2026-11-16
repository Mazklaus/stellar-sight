extends RefCounted
## Tests des hauts faits galactiques, lot 3 : Âges d'or (option), opération « Falsifier les annales »,
## victoire « Les Annales » (option), fenêtre de récompense et onglets des Chroniques, réglages de la
## Nouvelle partie, déterminisme (multijoueur). Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Hauts faits galactiques (âges d'or, ombres, victoire, interface)…")
	_test_golden()
	_test_falsify()
	_test_victory()
	_test_ui()
	_test_menu()
	_test_determinism()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(seed_value := 13, extra := {}) -> GameState:
	var o := {"ai_level": "", "deeds": "tous"}
	o.merge(extra, true)
	return GameState.create(seed_value, 120, 1600.0, "vael", o)


static func to_check(st: GameState) -> void:
	for i in 31:
		st.tick += 1
		Deeds.daily(st)
		if posmod(st.tick, Deeds.r_int("check_days")) == Deeds.r_int("offset"):
			return


func _test_golden() -> void:
	var st := new_game()
	_ok(DeedsBridges.golden_on(st), "âges d'or actifs par défaut")
	var off := new_game(13, {"golden_ages": false})
	_ok(not DeedsBridges.golden_on(off), "âges d'or désactivables")
	var g: Dictionary = Deeds.rules()["golden"]
	Deeds.add_glory(st, 0, DeedsBridges.golden_threshold(st, 0))
	var k0 := int(Research.effects(st, 0).get("production_pct", {}).get("knowledge", 0))
	st.tick = int(g["period"]) - 1
	while not DeedsBridges.in_golden(st, 0) and st.tick < int(g["period"]) + 40:
		st.tick += 1
		Deeds.daily(st)
	_ok(DeedsBridges.in_golden(st, 0), "assez de Gloire sur la décennie : âge d'or")
	_ok(not DeedsBridges.in_golden(st, 1), "pas d'âge d'or sans Gloire")
	_ok(int(Research.effects(st, 0).get("production_pct", {}).get("knowledge", 0)) == int(k0) + int(g["pct"]), "âge d'or : +10 % de Savoir")
	var parts := DeedsBridges.stability_parts(st, 0)
	_ok(not parts.is_empty() and int(parts[0][1]) == int(g["stability"]), "âge d'or : +5 stabilité")
	_ok(DeedsBridges.golden_threshold(st, 0) == int(g["base"]) + int(g["step"]), "le seuil suivant monte")
	var annal := false
	for x: Dictionary in Deeds.annals_of(st, 0):
		if String(x["k"]) == "golden":
			annal = true
	_ok(annal, "l'âge d'or entre dans les Annales")
	var until := int(DeedsBridges.golden_of(st, 0)["until"])
	while st.tick <= until + 31:
		st.tick += 1
		Deeds.daily(st)
	_ok(not DeedsBridges.in_golden(st, 0), "l'âge d'or finit au bout de cinq ans")
	_ok(int(Research.effects(st, 0).get("production_pct", {}).get("knowledge", 0)) == int(k0), "et ses effets avec lui")


func _test_falsify() -> void:
	var st := new_game()
	_ok(Espionage.op_def("falsifier_annales").get("deeds", false), "opération en données")
	Research.count_stat(st, 1, "curios", 4)
	to_check(st)
	_ok(DeedsBridges.spy_check(st, 0, 1, "falsifier_annales") == "", "falsification possible sur un haut fait en cours")
	var p0 := Deeds.pct(st, 1, "chercheur_curiosites")
	var txt := DeedsBridges.spy_apply(st, 0, 1, {"id": "falsifier_annales"})
	_ok(txt.contains("Chercheur") or txt.contains("«"), "la chronique nomme le haut fait")
	_ok(Deeds.pct(st, 1, "chercheur_curiosites") < p0, "la cible perd de l'avancée (%d -> %d %%)" % [p0, Deeds.pct(st, 1, "chercheur_curiosites")])
	DeedsBridges.spy_exposed(st, 0, 1)
	_ok(Deeds.pct(st, 1, "chercheur_curiosites") == p0, "découverte : la cible récupère sa progression")
	var off := new_game(13, {"deeds": "aucun"})
	_ok(DeedsBridges.spy_check(off, 0, 1, "falsifier_annales") != "", "pas d'opération sans hauts faits")


func _test_victory() -> void:
	var st := new_game(13, {"victories": {"annales": true}})
	_ok(Victory.enabled(st, "annales"), "victoire des Annales en option")
	_ok(not Victory.enabled(new_game(), "annales"), "décochée par défaut")
	_ok(not Victory.enabled(new_game(13, {"deeds": "aucun", "victories": {"annales": true}}), "annales"), "pas de victoire des Annales sans hauts faits")
	var need := DeedsBridges.annales_needed(st)
	_ok(need * 3 >= Deeds.pool(st).size() and need > 0, "un tiers des hauts faits en jeu (%d)" % need)
	var out := Victory.progress(st, 0, "annales")
	_ok(not bool(out["cond"]) and String(out["lines"][0]).contains("Hauts faits"), "avancée lisible")
	var n := 0
	for id in Deeds.pool(st):
		if n >= need:
			break
		Deeds._m(st, "won")[String(id)] = {"by": [0], "day": st.tick}
		n += 1
	Deeds.add_glory(st, 0, 1000)
	out = Victory.progress(st, 0, "annales")
	_ok(bool(out["cond"]), "condition remplie : le compte à rebours avance")
	_ok(int(Victory.info("annales").get("hold_days", 0)) == 720, "à tenir deux ans")


func _test_ui() -> void:
	var st := new_game()
	_ok(ChronicleScreen.tabs(st).has("deeds") and ChronicleScreen.tabs(st).has("annals"), "onglets Hauts faits et Annales dans les Chroniques")
	_ok(not ChronicleScreen.tabs(new_game(13, {"deeds": "aucun"})).has("deeds"), "pas d'onglet sans hauts faits")
	Research.count_stat(st, 0, "guardians")
	to_check(st)
	var panel := DeedPanel.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(panel)
	if panel._title == null:
		panel._ready()  # arbre pas encore prêt pendant _initialize
	var item: Dictionary = Deeds.inbox(st, 0)[0]
	panel.open(st, 0, item)
	_ok(panel.is_open() and panel.choice_buttons.size() == (item["ch"] as Array).size(), "fenêtre de haut fait : un bouton par récompense")
	_ok(panel._title.text == Deeds.label("tueur_de_gardien"), "la fenêtre nomme le haut fait")
	var got := []
	panel.choice_made.connect(func(iid: int, idx: int) -> void: got.append([iid, idx]))
	(panel.choice_buttons[0] as Button).pressed.emit()
	_ok(got.size() == 1 and int(got[0][0]) == int(item["id"]), "un clic envoie le choix")
	panel.close()
	_ok(not panel.is_open(), "la fenêtre se ferme")
	panel.queue_free()


func _test_menu() -> void:
	var m := MainMenu.new()
	_ok(m.deeds == "tous" and m.golden_ages, "Nouvelle partie : hauts faits « Tous » et âges d'or par défaut")
	_ok(not bool(m.victories.get("annales", true)), "victoire des Annales décochée par défaut")
	var o := m.game_options()
	_ok(String(o["deeds"]) == "tous" and bool(o["golden_ages"]), "réglages transmis à la partie")
	var d := m.default_settings()
	_ok(d.has("deeds") and d.has("golden_ages"), "réglages par défaut complets")
	m.free()


func _test_determinism() -> void:
	var a := new_game(21)
	var b := new_game(21)
	for st in [a, b]:
		Research.count_stat(st, 0, "guardians")
		Research.count_stat(st, 1, "curios", 6)
		to_check(st)
	_ok(JSON.stringify(Deeds.to_dict(a)) == JSON.stringify(Deeds.to_dict(b)), "même partie, mêmes hauts faits (déterminisme)")
	var item: Dictionary = Deeds.inbox(a, 0)[0]
	var cmd := SimCommands.deed_choose(0, int(item["id"]), 0)
	_ok(SimCommands.validate(a, cmd) == "" and SimCommands.validate(b, cmd) == "", "commande de choix valide sur les deux machines")
	SimCommands.apply(a, cmd)
	SimCommands.apply(b, cmd)
	_ok(JSON.stringify(a.get_empire(0).resources) == JSON.stringify(b.get_empire(0).resources), "même récompense appliquée")
	_ok(SimCommands.validate(a, SimCommands.deed_choose(1, int(item["id"]), 0)) != "", "on ne choisit pas la récompense d'un autre")
