class_name RefonteTests
extends RefCounted
## Tests de la refonte de l'interface : domaines et adresses (A1), sélecteur de lentilles (A3),
## barre d'alertes (A4), points de fin de tour (A6).
##   TESTS=refonte_tests godot --headless --path . -s res://tests/_only.gd

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Refonte de l'interface…")
	_test_domains()
	_test_lenses()
	_test_alerts()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _test_domains() -> void:
	_ok(UiDomains.DOMAINS.size() == 8, "huit domaines")
	var seen := {}
	var dup := []
	for d in UiDomains.DOMAINS.size():
		_ok(String(UiDomains.DOMAINS[d]["key"]) == "F%d" % (d + 1), "le domaine %s est sur F%d" % [UiDomains.DOMAINS[d]["label"], d + 1])
		for t: Array in UiDomains.DOMAINS[d]["tabs"]:
			for a: String in t[1]:
				if seen.has(a):
					dup.append(a)
				seen[a] = true
	_ok(dup.is_empty(), "chaque adresse n'appartient qu'à un onglet (%s)" % str(dup))
	for sc: Dictionary in EmpireBar.SCREENS:
		var id := String(sc["id"])
		if id != "codex":
			_ok(UiDomains.domain_of(id) >= 0, "l'écran %s a un domaine" % id)
	for tid: Array in ChronicleScreen.TABS:
		_ok(UiDomains.domain_of("chronicles:%s" % tid[0]) >= 0, "l'onglet de chronique %s a un domaine" % tid[0])
	_ok(UiDomains.locate("order") == [0, 2] and UiDomains.locate("order:tresor") == [0, 4], "Ordre et Trésor dans Empire")
	_ok(UiDomains.domain_of("chronicles:archeo") == 1 and UiDomains.domain_of("chronicles:quests") == 6, "les Fouilles sont dans Savoir, le Journal dans Chroniques")
	_ok(UiDomains.group("trade:resources").has("trade:market") and UiDomains.group("trade:routes").size() == 1, "Marché réunit Ressources et Marché")
	_ok(UiDomains.group("megas").has("wonders") and UiDomains.domain_of("forge") == 0, "Grands chantiers réunit merveilles, mégastructures et forge")
	var st := GameState.create(11)
	_ok(UiDomains.first_of_domain(st, 0, 0) == "economy" and UiDomains.first_of_domain(st, 0, 4) == "trade:routes", "premier onglet d'Empire et de Commerce")
	_ok(UiDomains.offered(st, 0, "order:admin") == Admin.applies(st, 0) and UiDomains.offered(st, 0, "kardashev") == Kardashev.enabled(st), "un pilier hors jeu cache son onglet")


func _test_lenses() -> void:
	var seen := {}
	for fam: Array in Hud.LENS_FAMILIES:
		for l: Array in fam[1]:
			seen[String(l[0])] = true
			_ok(Hud.LENS_TIPS.has(String(l[0])), "la lentille « %s » dit ce qu'elle montre" % l[1])
	_ok(Hud.LENS_FAMILIES.size() == 5 and seen.size() == 17, "cinq familles, dix-sept lentilles (%d)" % seen.size())
	_ok(Hud.lens_label("") == "Empires" and Hud.lens_label("war") == "Guerre et occupations", "nom des lentilles")


func _test_alerts() -> void:
	var st := GameState.create(11)
	_ok(AlertBar.alerts(st, 0).is_empty() or AlertBar.alerts(st, 0)[0].has("text"), "barre d'alertes : lecture d'une partie neuve")
	_ok(AlertBar.alerts(st, 99).is_empty() and TurnChecks.todo(st, 99).is_empty(), "rien pour un empire absent")
	var me := st.get_empire(0)
	me.research_queue.clear()
	var todo := TurnChecks.todo(st, 0)
	var kinds := []
	for a: Dictionary in todo:
		kinds.append(a["kind"])
	_ok(kinds.has("research"), "fin de tour : la recherche vide est signalée (%s)" % str(kinds))
	_ok(TurnChecks.summary(todo) != "" and TurnChecks.summary([]) == "", "fin de tour : résumé en une ligne")
	st.battles[st.galaxy.get_planet(me.capital_planet).system_id] = {"sides": [{"empire": 0}, {"empire": 1}]}
	var al := AlertBar.alerts(st, 0)
	_ok(not al.is_empty() and String(al[0]["kind"]) == "battle" or (al.size() > 1 and String(al[1]["kind"]) == "battle"), "barre d'alertes : un combat chez soi est signalé")
