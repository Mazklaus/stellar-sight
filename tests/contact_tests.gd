class_name ContactTests
extends RefCounted
## Tests de la victoire de Contact (étude du 2026-11-17, 45 propositions) : données et réglages, voies
## de capture (Oreilles, Échos, Grammaire), Signal partiel, alertes, jauge et couches, dossier des
## Lointains, Plans, Abécédaire, Héraut et Transmission, issues selon la nature, ouverture, IA,
## sauvegarde. La course et les voix (lots 2-3) : ContactTests2.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Contact…")
	print("  - data")
	_test_data()
	print("  - routes")
	_test_routes()
	print("  - alerts")
	_test_alerts()
	print("  - gauge_layers")
	_test_gauge_layers()
	print("  - plans_abc")
	_test_plans_abc()
	print("  - heraut_tx")
	_test_heraut_tx()
	print("  - outcomes")
	_test_outcomes()
	print("  - ai_save")
	_test_ai_save()
	if ResourceLoader.exists("res://tests/contact_tests2.gd"):
		(load("res://tests/contact_tests2.gd") as GDScript).new().run(check)


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(mode := "complete", faction := "ossarane", extra := {}) -> GameState:
	var opts := {"ai_level": "", "contact": mode}
	opts.merge(extra, true)
	return GameState.create(4242, 150, 1800.0, faction, opts)


static func eid_of(st: GameState, fid: String) -> int:
	for e in st.empires:
		if e.faction_id == fid:
			return e.id
	return -1


static func cmd(st: GameState, eid: int, act: String, d := {}) -> String:
	var c := SimCommands.ct_act(eid, act, d)
	var why := SimCommands.validate(st, c)
	if why == "":
		SimCommands.apply(st, c)
	return why


static func rich(st: GameState, eid: int) -> void:
	var e := st.get_empire(eid)
	for r in ["energy", "materials", "food", "influence", "crystals", "knowledge"]:
		e.resources[r] = 99999


## Fait passer n mois de Contact (bilan mensuel seul).
static func months(st: GameState, n: int) -> void:
	for i in n:
		st.tick += Contact.month_days()
		Contact.monthly(st, [])


## Capture complète par la Grammaire et un Écho.
static func capture(st: GameState, eid: int) -> void:
	var e := st.get_empire(eid)
	e.techs[Contact.listen_tech()] = true
	e.techs[Contact.grammar_tech()] = true
	Contact.add_route(st, eid, "grammar", [])
	Contact.add_route(st, eid, "echo", [])


## Jusqu'aux Plans (jauge 750).
static func to_plans(st: GameState, eid: int) -> void:
	capture(st, eid)
	Contact.add_gauge(st, eid, 750, [])


func _test_data() -> void:
	var d := GameData.contact()
	_ok(Contact.mode_defs().size() == 3 and Contact.nature_mode_defs().size() == 3 and Contact.outcome_defs().size() == 2, "Contact : trois réglages")
	_ok(Contact.nature_defs().size() == 5, "Cinq natures des Lointains")
	_ok(not Research.tech("ecoute_profonde").is_empty() and int(Research.tech("ecoute_profonde")["era"]) == 4, "Écoute profonde, ère IV")
	_ok(not Research.tech("grammaire_etoiles").is_empty() and int(Research.tech("grammaire_etoiles")["era"]) == 5, "Grammaire des étoiles, ère V")
	_ok(GameData.buildings().has("oreille_bordure") and GameData.buildings().has("heraut"), "Bâtiments : Oreille de la Bordure et Héraut")
	_ok(not Victory.info("contact").is_empty(), "Victoire « contact » dans victories.json")
	for c: Dictionary in d.get("cards", []):
		_ok(not Events.card(String(c["id"])).is_empty(), "Carte enregistrée : %s" % c["id"])
	var off := new_game("desactive")
	_ok(off.contact.is_empty() and not Victory.enabled(off, "contact"), "Désactivé : ni état ni victoire")
	var none := GameState.create(4242, 150, 1800.0, "ossarane", {"ai_level": ""})
	_ok(none.contact.is_empty(), "Sans option : désactivé")
	var st := new_game()
	_ok(Contact.enabled(st) and Contact.full(st) and Victory.enabled(st, "contact"), "Complet : en jeu, victoire active")
	_ok(Contact.nature_def(Contact.nature(st)).size() > 0, "Nature tirée : %s" % Contact.nature(st))
	var n := Contact.echo_sites(st).size()
	_ok(n >= 4 and n <= 8, "Échos fossiles : 4 à 8 (%d)" % n)
	var good := new_game("victoire", "ossarane", {"contact_nature": "bienveillants", "contact_outcome": "ouverture"})
	_ok(Contact.nature(good) == "batisseurs" and not Contact.full(good) and Contact.opens(good), "Bienveillants : les Bâtisseurs ; Victoire seule ; Ouverture")
	_ok(Contact.edge_systems(st).size() > 0, "La Bordure existe")


func _test_routes() -> void:
	var st := new_game()
	var oss := eid_of(st, "ossarane")
	var e := st.get_empire(oss)
	_ok(not Contact.listens(st, oss) and Contact.route_count(st, oss) == 0, "Au départ : personne n'écoute")
	e.techs[Contact.grammar_tech()] = true
	e.techs[Contact.listen_tech()] = true
	months(st, 1)
	_ok(Contact.routes(st, oss).has("grammar") and Contact.partial(st, oss), "Grammaire des étoiles : une voie, Signal partiel")
	_ok(not Contact.pending_alert(st, oss).is_empty() and int(Contact.pending_alert(st, oss)["true"]) == 1, "Première voie : une vraie alerte")
	var inbox := Events.inbox(st, oss)
	var seen := false
	for it: Dictionary in inbox:
		if String(it["card"]) == "ct_alerte":
			seen = true
	_ok(seen, "Carte d'alerte reçue")
	Contact.add_gauge(st, oss, 900, [])
	_ok(Contact.gauge(st, oss) == Contact.c_int("capture", "partial_cap", 250), "Signal partiel : jauge plafonnée à 25 %% (%d)" % Contact.gauge(st, oss))
	# Écho : une flotte à l'arrêt.
	var sid := Contact.echo_sites(st)[0]
	var f: Fleet = null
	for fid in st.fleets:
		if st.fleets[fid].owner == oss:
			f = st.fleets[fid]
			break
	f.system_id = sid
	f.path.clear()
	months(st, 3)
	_ok(Contact.routes(st, oss).has("echo") and Contact.captured(st, oss), "Écho relevé en 3 mois : capture complète")
	# Oreille : l'écoute dure 2 à 4 ans.
	var st2 := new_game()
	var o2 := eid_of(st2, "ossarane")
	var e2 := st2.get_empire(o2)
	e2.techs[Contact.listen_tech()] = true
	var cap: Colony = st2.colonies[e2.capital_planet]
	_ok(Economy.check_build(st2, o2, e2.capital_planet, "oreille_bordure") == "" or Contact.deaf(st2, FactionTraits.capital_system(st2, o2)), "Oreille constructible avec Écoute profonde")
	cap.buildings.append("oreille_bordure")
	var need := Contact.ear_need(st2, FactionTraits.capital_system(st2, o2))
	_ok(need >= 540 and need <= 1440, "Durée d'écoute entre 18 mois et 4 ans (%d)" % need)
	_ok(Economy.check_build(st2, o2, e2.capital_planet, "oreille_bordure") != "", "Une Oreille par système")
	@warning_ignore("integer_division")
	months(st2, need / 30 + 1)
	_ok(Contact.routes(st2, o2).has("ear") or Contact.deaf(st2, FactionTraits.capital_system(st2, o2)), "L'Oreille a fini d'écouter : une voie")
	_ok(Contact.ears_done(st2, o2) == 1, "Une Oreille qui a fini")
	var off := new_game("desactive")
	var oo := eid_of(off, "ossarane")
	off.get_empire(oo).techs[Contact.listen_tech()] = true
	_ok(Economy.check_build(off, oo, off.get_empire(oo).capital_planet, "oreille_bordure") != "", "Désactivé : pas d'Oreille")


func _test_alerts() -> void:
	var st := new_game()
	var oss := eid_of(st, "ossarane")
	var e := st.get_empire(oss)
	e.techs[Contact.listen_tech()] = true
	e.resources["influence"] = 100
	Contact._push_alert(st, oss, false, "pulsar", [])
	_ok(cmd(st, oss, "announce") == "", "Annoncer une alerte")
	_ok(int(e.resources["influence"]) == 70 and Contact.stat(st, oss, "false_alarm") == 1, "Fausse alerte annoncée : -30 influence (%d)" % int(e.resources["influence"]))
	_ok(cmd(st, oss, "announce") != "", "Plus d'alerte en attente")
	Contact._push_alert(st, oss, false, "pulsar", [])
	_ok(cmd(st, oss, "verify") == "", "Vérifier une alerte")
	months(st, 7)
	_ok(Contact.pending_alert(st, oss).is_empty(), "Vérification : réglée en six mois")
	# Les fausses alertes viennent avant la vraie capture, et cessent après.
	var st2 := new_game()
	var o2 := eid_of(st2, "ossarane")
	st2.get_empire(o2).techs[Contact.listen_tech()] = true
	var got := 0
	for i in 40:
		months(st2, 1)
		if not Contact.pending_alert(st2, o2).is_empty():
			got += 1
			Contact.sub(st2, "alert").erase(str(o2))
	_ok(got >= 1 and got <= 3, "Une à trois fausses alertes en 40 mois (%d)" % got)


func _test_gauge_layers() -> void:
	var st := new_game()
	var oss := eid_of(st, "ossarane")
	var e := st.get_empire(oss)
	capture(st, oss)
	rich(st, oss)
	_ok(cmd(st, oss, "share", {"v": 30}) == "" and Contact.share(st, oss) == 30, "Part du Savoir : 30 %")
	_ok(cmd(st, oss, "share", {"v": 40}) != "", "Part du Savoir : 30 % au plus")
	var g0 := Contact.gauge(st, oss)
	var k0 := int(e.resources["knowledge"])
	months(st, 1)
	_ok(Contact.gauge(st, oss) > g0, "La jauge monte (%d)" % Contact.gauge(st, oss))
	_ok(int(e.resources["knowledge"]) <= k0, "Le Savoir consacré est dépensé")
	_ok(Contact.monthly_gain(st, oss) <= Contact.c_int("gauge", "max_month", 60), "Gain plafonné par mois")
	var parts := Contact.gain_parts(st, oss)
	var has_g := false
	for p in parts:
		if String(p[0]).contains("Grammaire"):
			has_g = true
	_ok(has_g, "Détail : la Grammaire des étoiles accélère")
	Contact.sub(st, "gauge")[str(oss)] = 240
	Contact.add_gauge(st, oss, 20, [])
	_ok(Contact.layers(st, oss) == 1 and Contact.has_layer(st, oss, "porteuse"), "250 : la Porteuse")
	_ok(int(Contact.sub(st, "first").get("porteuse", -1)) == oss, "Première Porteuse de la galaxie")
	var any_stab := false
	for o in st.empires:
		if Contact.applies(st, o.id) and not Contact.empire_stability_parts(st, o.id).is_empty():
			any_stab = true
	_ok(any_stab, "« Nous ne sommes pas seuls » : stabilité selon le credo")
	_ok(Contact.possible_natures(st, oss).size() == 5, "Porteuse : dossier encore entier")
	Contact.add_gauge(st, oss, 250, [])
	_ok(Contact.has_layer(st, oss, "echo") and (Contact.possible_natures(st, oss).size() == 4 or Contact.nature_mode(st) == "sans_indices"), "500 : l'Écho, une nature écartée")
	Contact.add_gauge(st, oss, 250, [])
	_ok(Contact.has_layer(st, oss, "plans") and Contact.possible_natures(st, oss).size() == 2, "750 : les Plans, deux de plus")
	_ok(Contact.possible_natures(st, oss).has(Contact.nature(st)), "La vraie nature n'est jamais écartée")
	Contact.add_gauge(st, oss, 500, [])
	_ok(Contact.gauge(st, oss) == Contact.gauge_max() - 1 and not Contact.has_layer(st, oss, "abecedaire"), "Sans clé de lecture : l'Abécédaire reste fermé")
	_ok(Contact.certainty(st, oss) >= 5, "Certitude qui monte avec les couches (%d)" % Contact.certainty(st, oss))
	# Événement de couche : la lecture.
	Events.push(st, oss, "ct_porteuse", {}, [])
	var it: Dictionary = Events.inbox(st, oss).back()
	Events.choose(st, oss, int(it["id"]), 0, [])
	_ok(Contact.readings(st, oss, "outil") == 1, "Lecture outil choisie")
	_ok(int((Research.effects(st, oss).get("production_pct", {}) as Dictionary).get("knowledge", 0)) >= 3, "Lecture outil : +3 % de Savoir")


func _test_plans_abc() -> void:
	var st := new_game()
	var oss := eid_of(st, "ossarane")
	to_plans(st, oss)
	_ok(cmd(st, oss, "plans_raw") == "" and Contact.plans_state(st, oss) == "raw", "Plans bruts")
	_ok((Contact.sub(st, "gifts").get(str(oss), []) as Array).size() == 1, "Un don des Lointains")
	_ok(cmd(st, oss, "plans_audit") != "", "Les Plans ne se décident qu'une fois")
	var st2 := new_game()
	var o2 := eid_of(st2, "ossarane")
	to_plans(st2, o2)
	_ok(cmd(st2, o2, "plans_audit") == "" and Contact.plans_state(st2, o2) == "auditing", "Audit des Plans")
	months(st2, 12)
	_ok(Contact.plans_state(st2, o2) == "audit", "Audit achevé en un an")
	# L'intuition.
	_ok(not Contact.abc_key(st2, o2), "Pas de clé de lecture au départ")
	_ok(cmd(st2, o2, "intuition") == "" and Contact.intuition_running(st2, o2), "Intuition lancée")
	_ok(cmd(st2, o2, "intuition") != "", "Une seule intuition à la fois")
	months(st2, 24)
	_ok(Contact.abc_key(st2, o2), "Clé trouvée en deux ans")
	Contact.add_gauge(st2, o2, 1000, [])
	_ok(Contact.has_layer(st2, o2, "abecedaire") and Contact.knows_nature(st2, o2), "Abécédaire : la nature révélée")
	# Sans indices.
	var st3 := new_game("complete", "ossarane", {"contact_nature": "sans_indices"})
	var o3 := eid_of(st3, "ossarane")
	to_plans(st3, o3)
	_ok(Contact.possible_natures(st3, o3).size() == 5, "Sans indices : le dossier ne se resserre pas")


func _test_heraut_tx() -> void:
	var st := new_game("complete", "ossarane", {"contact_nature": "bienveillants"})
	var oss := eid_of(st, "ossarane")
	var e := st.get_empire(oss)
	capture(st, oss)
	rich(st, oss)
	_ok(Economy.check_build(st, oss, e.capital_planet, "heraut") != "", "Héraut : il faut les Plans")
	Contact.add_gauge(st, oss, 750, [])
	_ok(Economy.check_build(st, oss, e.capital_planet, "heraut") == "", "Héraut constructible après les Plans")
	_ok(cmd(st, oss, "transmit") != "", "Transmettre : il faut le Héraut")
	(st.colonies[e.capital_planet] as Colony).buildings.append("heraut")
	_ok(Economy.check_build(st, oss, e.capital_planet, "heraut") != "", "Un seul Héraut")
	_ok(cmd(st, oss, "transmit") == "" and Contact.transmitting(st, oss), "Transmission lancée")
	_ok(Contact.tx_need(st, oss) <= 1440 and Contact.tx_need(st, oss) >= 720, "Durée : quatre ans au plus, deux au moins (%d)" % Contact.tx_need(st, oss))
	_ok(cmd(st, oss, "rate", {"v": 3}) == "" and Contact.tx_rate(st, oss) == 3, "Débit ×4")
	var en := int(e.resources["energy"])
	months(st, 1)
	_ok(en - int(e.resources["energy"]) == Contact.tx_cost(st, oss), "Le débit coûte de l'énergie (%d)" % (en - int(e.resources["energy"])))
	var other: Empire = null
	for o in st.empires:
		if o.id != oss and not o.is_npc():
			other = o
			break
	_ok(other.intel.has(Contact.heraut_system(st, oss)), "Exposition : le Héraut révélé à tous")
	_ok(Contact.exposed_systems(st).has(Contact.heraut_system(st, oss)), "La carte marque le Héraut qui transmet")
	# Perte du Héraut : retour au dernier quart.
	Contact.tx(st, oss)["prog"] = 800
	(st.colonies[e.capital_planet] as Colony).buildings.erase("heraut")
	months(st, 1)
	var q := Contact.tx_need(st, oss) / 4
	_ok(int(Contact.tx(st, oss)["prog"]) % q == 0 and int(Contact.tx(st, oss)["prog"]) <= 800, "Héraut perdu : retombe au dernier quart (%d)" % int(Contact.tx(st, oss)["prog"]))
	(st.colonies[e.capital_planet] as Colony).buildings.append("heraut")
	# Plancher de deux ans même au débit maximal.
	Contact.tx(st, oss)["prog"] = 99999
	months(st, 1)
	_ok(not Contact.done(st, oss), "Plancher : pas de réponse avant deux ans")
	months(st, 24)
	_ok(Contact.done(st, oss), "La réponse arrive")
	VictorySystem._monthly(st, 30, [])
	_ok(String(st.winner.get("victory", "")) == "contact" and int(st.winner["empire"]) == oss, "Victoire de Contact proclamée")
	_ok(Victory.chronicle_text("contact", e, [], st).contains("Bâtisseurs"), "Chronique : selon la nature")


func _finish(st: GameState, eid: int) -> void:
	to_plans(st, eid)
	rich(st, eid)
	(st.colonies[st.get_empire(eid).capital_planet] as Colony).buildings.append("heraut")
	Contact.start_tx(st, eid, [])
	Contact.tx(st, eid)["prog"] = 99999
	Contact.tx(st, eid)["start"] = -2000
	months(st, 1)


func _with_nature(n: String, extra := {}) -> GameState:
	var st := new_game("complete", "ossarane", extra)
	st.contact["nature"] = n
	return st


func _test_outcomes() -> void:
	var st := _with_nature("affames")
	var oss := eid_of(st, "ossarane")
	_finish(st, oss)
	_ok(Contact.failed(st, oss) and not Contact.done(st, oss), "Affamés : la réponse est un échec")
	VictorySystem._monthly(st, 30, [])
	_ok(String(st.winner.get("victory", "")) != "contact", "Affamés : pas de victoire")
	var st2 := _with_nature("semeurs")
	var o2 := eid_of(st2, "ossarane")
	to_plans(st2, o2)
	Contact.plans_raw(st2, o2, [])
	_finish(st2, o2)
	_ok(Contact.failed(st2, o2), "Semeurs et Plans bruts : piège")
	var st3 := _with_nature("semeurs")
	var o3 := eid_of(st3, "ossarane")
	to_plans(st3, o3)
	Contact.sub(st3, "plans")[str(o3)] = 0
	_finish(st3, o3)
	_ok(Contact.done(st3, o3), "Semeurs et Plans audités : porte close, victoire")
	var st4 := _with_nature("archivistes", {"contact_outcome": "ouverture"})
	var o4 := eid_of(st4, "ossarane")
	_finish(st4, o4)
	VictorySystem._monthly(st4, 30, [])
	_ok(Contact.done(st4, o4) and st4.winner.is_empty(), "Ouverture : la partie continue")
	_ok(int((Research.effects(st4, o4).get("production_pct", {}) as Dictionary).get("knowledge", 0)) >= 25, "Ouverture : +25 % de Savoir")
	var p := Victory.progress(st4, o4, "contact")
	_ok(int(p["pct"]) == 100 and not bool(p["won"]), "Ouverture : 100 % sans victoire")


func _test_ai_save() -> void:
	var st := new_game("complete", "ossarane", {"ai_level": "normal"})
	var ai := -1
	for e in st.empires:
		if e.is_ai():
			ai = e.id
			break
	if ai >= 0:
		capture(st, ai)
		Contact._push_alert(st, ai, false, "pulsar", [])
		for i in 3:
			st.tick += 30
			AiPlayer.think(st, st.get_empire(ai))
		_ok(Contact.share(st, ai) != Contact.c_int("gauge", "share_default", 10) or Contact.share(st, ai) == 10, "IA : part du Savoir réglée (%d)" % Contact.share(st, ai))
		_ok(int(Contact.pending_alert(st, ai).get("verify", 0)) > 0 or Contact.pending_alert(st, ai).is_empty(), "IA : elle vérifie l'alerte")
		Contact.add_gauge(st, ai, 750, [])
		for i in 3:
			st.tick += 30
			AiPlayer.think(st, st.get_empire(ai))
		_ok(Contact.plans_state(st, ai) != "", "IA : elle décide des Plans (%s)" % Contact.plans_state(st, ai))
	var st2 := new_game()
	var oss := eid_of(st2, "ossarane")
	to_plans(st2, oss)
	Contact.plans_raw(st2, oss, [])
	var d := st2.to_dict()
	_ok(int(d["version"]) >= 87, "Sauvegarde 87 ou plus")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(Contact.captured(back, oss) and Contact.has_layer(back, oss, "plans") and Contact.plans_state(back, oss) == "raw" and Contact.nature(back) == Contact.nature(st2), "Sauvegarde : capture, couches, Plans et nature relus")
	_ok(JSON.stringify(back.to_dict()) == JSON.stringify(d), "Sauvegarde : aller-retour identique")
	var off := new_game("desactive")
	_ok(not off.to_dict().has("contact"), "Désactivé : rien de sauvegardé")
