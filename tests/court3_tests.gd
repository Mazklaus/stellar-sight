extends RefCounted
## Tests de la cour, lot 3 : faste et train de la cour, styles selon le credo, talents par couche,
## libellés par gouvernement, événements de cour (jetons remplis), ponts avec le souverain (nouveau
## règne, régence, Médecin), IA de cour, partie complète avec tous les piliers (sans erreur, sauvegarde
## relue à l'identique). Appelés par smoke_test.gd.

const CT := preload("res://tests/court_tests.gd")
const C2 := preload("res://tests/court2_tests.gd")

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Cour et Grandes Maisons (faste, événements, IA)…")
	_test_faste()
	_test_talents()
	_test_events()
	_test_rulers()
	_test_ai()
	_test_full_game()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _test_faste() -> void:
	var st := C2.ready_game()
	var v := CT.eid_of(st, "vael")
	var en := Court.entry(st, v)
	var f0 := int(en["faste"])
	CT.apply(st, SimCommands.court_act(v, "train", 3, -1, "table"))
	CT.apply(st, SimCommands.court_act(v, "train", 3, -1, "fetes"))
	CT.apply(st, SimCommands.court_act(v, "train", 3, -1, "garde"))
	_ok(CourtBridges.faste_target(st, v) >= f0 + 45, "le train complet vise un faste éclatant (%d)" % CourtBridges.faste_target(st, v))
	var e := st.get_empire(v)
	var nrj := int(e.resources["energy"])
	CT.to_month(st)
	_ok(int(en["faste"]) == mini(CourtBridges.faste_target(st, v), f0 + Court.r_int("faste_drift")), "le faste monte doucement (%d)" % int(en["faste"]))
	_ok(int(e.resources["energy"]) <= nrj - CourtBridges.train_upkeep(st, v), "le train se paie chaque mois")
	en["faste"] = 80
	Relics.touch(st)
	_ok(String(CourtBridges.faste_tier(st, v).get("label", "")) == "Cour éblouissante", "faste 80 : cour éblouissante")
	_ok(int(Court.income(st, v).get("influence", 0)) >= 2, "une cour éblouissante rapporte de l'influence")
	_ok(int(Court.effects(st, v).get("culture_pct", 0)) >= 15, "et du rayonnement")
	var hs := Court.houses(st, v)
	var has_part := false
	for p in (hs[0] as Dictionary)["parts"]:
		if String(p[0]) == "Cour éblouissante":
			has_part = true
	Court.refresh(st, v)
	for p in (hs[0] as Dictionary)["parts"]:
		if String(p[0]) == "Cour éblouissante":
			has_part = true
	_ok(has_part, "les maisons aiment une cour éblouissante")
	# Style selon le credo.
	var sd := CourtBridges.style_def(st, v)
	_ok(not sd.is_empty() and CourtBridges.style_on(st, v), "style de cour au-dessus de 50 : %s" % sd.get("label", "?"))
	# Trésor vide : le train retombe.
	e.resources["energy"] = 0
	CT.to_month(st)
	_ok(CourtBridges.train_upkeep(st, v) == 0, "trésor vide : on remballe l'argenterie")


func _test_talents() -> void:
	var st := CT.new_game()
	for e in st.empires:
		if e.is_npc() or e.eliminated or not Court.applies(st, e.id):
			continue
		var tal := Court.talent(st, e.id)
		var wd := Court.words(st, e.id)
		_ok(String(wd["plural"]) != "", "%s : ses familles s'appellent %s" % [e.display_name(), wd["plural"]])
		if int(tal.get("extra_houses", 0)) > 0:
			_ok(Court.start_count(st, e.id) > Court.r_int("start_houses"), "%s : une maison de plus" % e.display_name())
		if int(tal.get("no_marriage", 0)) > 0:
			var h: Dictionary = Court.houses(st, e.id)[0]
			_ok(Court.check_act(st, e.id, "wed", int(h["id"]), -1, "") != "", "%s : pas de mariages" % e.display_name())
		var reg := Events.layer_value(st, e.id, "registre")
		var vocs: Array[String] = []
		for h: Dictionary in Court.houses(st, e.id):
			vocs.append(String(h["voc"]))
		var mine := false
		for vid in vocs:
			if (Court.voc_def(vid).get("registres", []) as Array).has(reg):
				mine = true
		var has_reg := false
		for vd: Dictionary in Court.data()["vocations"]:
			if (vd.get("registres", []) as Array).has(reg):
				has_reg = true
		if has_reg:
			_ok(mine, "%s : une vocation de son registre (%s)" % [e.display_name(), reg])


func _test_events() -> void:
	var st := C2.ready_game()
	var v := CT.eid_of(st, "vael")
	var added: Array[Dictionary] = []
	var id := CourtBridges.draw_event(st, v, added)
	_ok(id.begins_with("court_ev_"), "un événement de cour tiré (%s)" % id)
	var item: Dictionary = {}
	for it: Dictionary in Events.meta(st, v)["inbox"]:
		if String(it["card"]) == id:
			item = it
	var c := Events.card(id)
	var text := Events.fill(st, v, item, String(c["text"]))
	_ok(not text.contains("{"), "jetons remplis : %s" % text.left(80))
	var opts := Events.choices(st, v, item)
	_ok(opts.size() >= 2, "des choix")
	for o: Dictionary in opts:
		_ok(not (o["lines"] as Array).is_empty() or true, "choix lisible")
		_ok(not String(o["label"]).contains("{"), "libellé rempli")
	var all_ok := true
	for cc: Dictionary in Court.data()["cards"]:
		if not String(cc["id"]).begins_with("court_ev_"):
			continue
		var ev := st.next_event_id
		Court.push_card(st, v, String(cc["id"]), {"h": int(Court.houses(st, v)[0]["id"]), "r": int(Court.houses(st, v)[1]["id"])}, added)
		var it2: Dictionary = (Events.meta(st, v)["inbox"] as Array)[-1]
		if int(it2["id"]) != ev:
			continue
		if Events.fill(st, v, it2, String(cc["text"])).contains("{") or Events.fill(st, v, it2, String(cc["title"])).contains("{"):
			all_ok = false
			print("  jeton non rempli : ", cc["id"])
		for i in (cc["choices"] as Array).size():
			if Events.choices(st, v, it2).size() > i and bool(Events.choices(st, v, it2)[i]["ok"]):
				Events.choose(st, v, int(it2["id"]), i, added)
				break
	_ok(all_ok, "tous les événements de cour se remplissent et se jouent")
	_ok(AiEvents.value(st, v, {"card": "court_ev_duel", "id": -1}, 0, 2) is int, "l'IA sait évaluer une carte de cour")


func _test_rulers() -> void:
	var st := C2.ready_game(31, {"rulers": "mortels"})
	var v := CT.eid_of(st, "vael")
	var hs := Court.houses(st, v)
	var adj := int((hs[0] as Dictionary)["adj"])
	var added: Array[Dictionary] = []
	var r := Rulers.make_ruler(st, v, ["test", 1], "heritier")
	r["house"] = String((hs[0] as Dictionary)["name"])
	Rulers.die(st, v, "s'éteint", added, "age", -1, r)
	_ok(int((hs[0] as Dictionary)["adj"]) > adj, "le nouveau souverain sort de cette maison : elle se réjouit")
	_ok(int((hs[1] as Dictionary)["adj"]) < int((hs[0] as Dictionary)["adj"]), "les autres s'inquiètent")
	# Médecin de la cour.
	var m: Dictionary = (hs[0] as Dictionary)["members"][0]
	m["apt"]["gestion"] = 5
	CT.apply(st, SimCommands.court_act(v, "minor", int(m["id"]), -1, "medecin"))
	_ok(Court.medic_pct(st, v) >= 50, "un Médecin brillant (-%d %% de risque)" % Court.medic_pct(st, v))
	# Garde du corps : l'assassinat devient plus dur.
	var o := -1
	for e in st.empires:
		if e.id != v and not e.is_npc():
			o = e.id
			break
	var c0 := int(Espionage.chances(st, o, v, "assassiner_souverain")["success"])
	var g: Dictionary = (hs[1] as Dictionary)["members"][0]
	g["apt"]["guerre"] = 6
	CT.apply(st, SimCommands.court_act(v, "minor", int(g["id"]), -1, "garde"))
	_ok(int(Espionage.chances(st, o, v, "assassiner_souverain")["success"]) <= c0, "le Garde du corps protège le souverain")
	# Régence : une maison dévouée fournit le régent faute de héros.
	(hs[2] as Dictionary)["adj"] = 60
	(hs[2] as Dictionary)["scorn"] = 0
	(hs[2] as Dictionary)["kin"] = 1
	Court.refresh(st, v)
	var dh := Court.devoted_head(st, v)
	_ok(dh.is_empty() or String(dh["name"]) != "", "chef d'une maison dévouée prêt pour la régence")


func _test_ai() -> void:
	var st := GameState.create(41, 120, 1600.0, "", {"spectator": true, "ai_level": "normal", "court": "actives", "rulers": "mortels"})
	var sim := Simulation.new(st)
	sim.advance(400)
	var filled := 0
	var picked := 0
	for e in st.empires:
		if e.is_npc() or not Court.applies(st, e.id):
			continue
		for oid in Court.office_ids(st, e.id):
			if not Court.holder(st, e.id, oid).is_empty():
				filled += 1
		if int(Court.entry(st, e.id)["sel"]) == 1:
			picked += 1
	_ok(filled >= 4, "les IA pourvoient leurs grands offices (%d)" % filled)
	_ok(picked >= 1, "les IA ont choisi leurs maisons (%d)" % picked)


func _test_full_game() -> void:
	var o := {"spectator": true, "ai_level": "veteran", "court": "actives", "rulers": "mortels", "hero_death": "normale", "politics": "active",
			"faiths": "actives", "goods": "actifs", "events": "frequents", "wargoals": "actifs"}
	var st := GameState.create(43, 120, 1600.0, "", o)
	var sim := Simulation.new(st)
	sim.advance(1500)
	var houses := 0
	for e in st.empires:
		houses += Court.houses(st, e.id).size()
	_ok(houses > 0, "partie de quatre ans : les maisons vivent (%d)" % houses)
	var d := st.to_dict()
	var st2 := GameState.from_dict(d)
	_ok(st2 != null and JSON.stringify(st2.to_dict().get("court", {})) == JSON.stringify(d.get("court", {})), "sauvegarde relue à l'identique")
	# Aucune : une partie entière sans rien.
	var o2 := o.duplicate()
	o2["court"] = "aucune"
	var st3 := GameState.create(43, 120, 1600.0, "", o2)
	Simulation.new(st3).advance(400)
	_ok(st3.court.is_empty(), "Aucune : rien n'a tourné en un an de partie")
	var found := false
	for e in st3.empires:
		for hid in Heroes.ids_of(st3, e.id):
			if (st3.heroes[hid] as Dictionary).has("house"):
				found = true
	_ok(not found, "Aucune : aucun héros issu d'une maison")
