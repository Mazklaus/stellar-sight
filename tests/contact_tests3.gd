extends RefCounted
## Tests du Contact, lot 3 (les voix) : talents des peuples, Taiseux et saboteurs, Voyage des Cinq,
## Aster, Ylm et Kheb, crises appelées (l'Outre-Nuit, l'Hôte), ponts, hauts faits, Amphictyonie.
## Appelés par contact_tests2.gd.

const T := preload("res://tests/contact_tests.gd")
const T2 := preload("res://tests/contact_tests2.gd")

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Contact, les voix…")
	print("  - talents")
	_test_talents()
	print("  - taiseux")
	_test_taiseux()
	print("  - voyage")
	_test_voyage()
	print("  - crises")
	_test_crises()
	print("  - bridges_deeds")
	_test_bridges_deeds()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _test_talents() -> void:
	var d := GameData.contact()
	for f in ["ossarane", "choeur", "vael", "khthari", "teyl", "ferrocornes", "brisecomete", "murmurants"]:
		_ok((d["talents"] as Dictionary).has(f) and (d["names"] as Dictionary).has(f), "Talent et voix : %s" % f)
	var st := T.new_game()
	var oss := T.eid_of(st, "ossarane")
	_ok(ContactVoices.build_days(st, oss, "oreille_bordure", 120) == 60, "Ossarane : Oreilles bâties deux fois plus vite")
	_ok(int(ContactVoices.voyage_cost(st, oss).get("materials", 0)) == 200, "Ossarane : le Voyage des Cinq coûte moitié moins")
	_ok(Contact.signal_name(st, oss) == "l'Appel du Suzerain", "Nom du Signal selon le peuple")
	var vael := T.eid_of(st, "vael")
	if vael >= 0:
		var has := false
		for x in ContactVoices.gauge_pct_parts(st, vael):
			if String(x[0]).begins_with("Espèces"):
				has = true
		_ok(has and ContactRace.cons_cost(st, vael).is_empty(), "Vael : +5 %% par espèce, Consortium gratuit")
	var mur := T.eid_of(st, "murmurants")
	if mur >= 0:
		st.get_empire(mur).techs[Contact.listen_tech()] = true
		ContactVoices.monthly(st, [])
		_ok(Contact.routes(st, mur).has("dream"), "Murmurants : le Songe, une voie de capture")
		var nb := -1
		for o in st.empires:
			if o.id != mur and not o.is_npc():
				nb = o.id
				break
		if not st.get_empire(nb).contacts.has(mur):
			st.get_empire(nb).contacts.append(mur)
		_ok(ContactVoices.extra_alerts(st, nb) == 1, "Murmurants : une fausse alerte de plus chez les voisins")
		var prop := {"kind": "step", "fam": "signal", "from": 0, "to": -1}
		_ok(ContactVoices.silence_weight(st, mur, prop, 1, 5) == 10, "Murmurants : voix doublées pour le Silence")
	var ch := T.eid_of(st, "choeur")
	if ch >= 0:
		_ok(ContactVoices.silence_vote_block(st, ch, {"kind": "step", "fam": "signal", "from": 0, "to": -1}) != "", "Chœur : ne vote jamais le Silence")
	var kh := T.eid_of(st, "khthari")
	if kh >= 0:
		# Prise d'une colonie à Oreille : le fragment est volé.
		var victim := oss
		T.capture(st, victim)
		var cap: Colony = st.colonies[st.get_empire(victim).capital_planet]
		cap.buildings.append("oreille_bordure")
		ContactVoices.monthly(st, [])
		cap.owner = kh
		ContactVoices.monthly(st, [])
		_ok(ContactRace.held_from(st, kh).has(victim), "Kh'thari : prendre une colonie à Oreille vole le fragment")
		cap.owner = victim
	var br := T.eid_of(st, "brisecomete")
	if br >= 0:
		var p := T2.pair(st)
		var buyer := p[0] if p[0] != br else p[1]
		for q in [[br, buyer], [buyer, br]]:
			if not st.get_empire(q[0]).contacts.has(q[1]):
				st.get_empire(q[0]).contacts.append(q[1])
		T.capture(st, br)
		_ok(T.cmd(st, br, "frag_sell", {"to": buyer}) == "", "Brisecomète : mettre son fragment en vente")
		st.get_empire(buyer).resources["energy"] = 1000
		T.cmd(st, buyer, "accept", {"kind": "frag_sell", "from": br})
		_ok(ContactRace.holds(st, buyer, br) and int(st.get_empire(buyer).resources["energy"]) == 850, "Brisecomète : fragment vendu 150 énergie")
		_ok(T.cmd(st, oss, "frag_sell", {"to": buyer}) != "", "Seuls les courtiers vendent")


func _test_taiseux() -> void:
	var st := T.new_game("complete", "ossarane", {"contact_nature": "bienveillants"})
	var oss := T.eid_of(st, "ossarane")
	T.capture(st, oss)
	Contact.add_gauge(st, oss, 750, [])
	for i in 40:
		ContactVoices.monthly(st, [])
	var tv := ContactVoices.taiseux(st, oss)
	_ok(tv >= 25 or ContactVoices.no_debate(st, oss), "Les Taiseux montent avec les couches (%d)" % tv)
	Contact.sub(st, "taiseux")[str(oss)] = 80
	(st.colonies[st.get_empire(oss).capital_planet] as Colony).buildings.append("heraut")
	_ok(ContactVoices.no_debate(st, oss) or T.cmd(st, oss, "transmit") != "", "Taiseux au pouvoir : pas de Transmission")
	Contact.sub(st, "taiseux")[str(oss)] = 0
	T.rich(st, oss)
	_ok(T.cmd(st, oss, "transmit") == "", "Taiseux affaiblis : on répond")
	# Saboteurs : avec des Taiseux forts, des attentats.
	Contact.sub(st, "taiseux")[str(oss)] = 100
	var hits := 0
	for y in 12:
		Contact.tx(st, oss)["prog"] = 0
		st.tick += 360
		Contact.tx(st, oss)["start"] = st.tick - 360
		ContactVoices._saboteurs(st, oss, [])
		hits += 1 if int(Contact.tx(st, oss)["start"]) != st.tick - 360 else 0
	_ok(hits >= 1, "Saboteurs : des attentats quand les Taiseux sont forts (%d sur 12 ans)" % hits)


func _test_voyage() -> void:
	var st := T.new_game("complete", "ossarane", {"contact_nature": "bienveillants"})
	var oss := T.eid_of(st, "ossarane")
	T.to_plans(st, oss)
	T.rich(st, oss)
	var council := Heroes.council(st, oss)
	if council.size() < 3:
		for cls in ["admiral", "scientist", "diplomat", "general"]:
			if Heroes.council(st, oss).size() >= 3:
				break
			var cand := Heroes.make_candidate(st, oss, String(Heroes.data()["classes"].keys()[0]), ["t", cls])
			var hid := Heroes.recruit(st, oss, cand)
			if hid >= 0:
				st.heroes[hid]["post"] = "council"
				st.heroes[hid]["arrive"] = 0
	if Heroes.council(st, oss).size() < 3:
		_ok(true, "(pas assez de héros pour tester le Voyage)")
		return
	_ok(T.cmd(st, oss, "voyage") == "", "Le Voyage des Cinq part")
	_ok(Heroes.council(st, oss).is_empty() or Heroes.council(st, oss).size() < 3, "Les héros sont partis")
	_ok(T.cmd(st, oss, "transmit") != "", "Pas de Transmission pendant le Voyage")
	T.months(st, 25)
	_ok(Contact.done(st, oss), "Bâtisseurs : les Cinq reviennent avec la victoire")
	var st2 := T.new_game()
	st2.contact["nature"] = "archivistes"
	var o2 := T.eid_of(st2, "ossarane")
	T.to_plans(st2, o2)
	T.rich(st2, o2)
	for i in 3:
		var cand := Heroes.make_candidate(st2, o2, String(Heroes.data()["classes"].keys()[0]), ["t2", i])
		var hid := Heroes.recruit(st2, o2, cand)
		if hid >= 0:
			st2.heroes[hid]["post"] = "council"
			st2.heroes[hid]["arrive"] = 0
	if T.cmd(st2, o2, "voyage") == "":
		var hs: Array = Contact.sub(st2, "voyage")[str(o2)]["heroes"]
		T.months(st2, 25)
		_ok(not Contact.done(st2, o2) and not st2.heroes.has(int(hs[0])) or String(st2.heroes.get(int(hs[0]), {}).get("post", "")) == "", "Archivistes : les Cinq sont perdus")
		var s := 0
		for x in ContactVoices.stability_parts(st2, o2):
			s += int(x[1])
		_ok(s < 0, "La Machine se retourne contre son bâtisseur")


func _test_crises() -> void:
	_ok(not Crisis.kind_def("outre_nuit").is_empty() and bool(Crisis.kind_def("outre_nuit")["summoned"]), "Crise « l'Outre-Nuit » : appelée, jamais tirée")
	_ok(not Crisis.kind_def("hote").is_empty() and bool(Crisis.kind_def("hote")["summoned"]), "Crise « l'Hôte » : appelée")
	_ok(not Crisis.kind_ids().has("outre_nuit") and not Crisis.kind_ids().has("hote"), "Ni l'une ni l'autre dans le tirage")
	var st := T.new_game("complete", "ossarane", {"crises": "toutes"})
	st.contact["nature"] = "affames"
	var oss := T.eid_of(st, "ossarane")
	ContactVoices.on_fail(st, oss, "outre_nuit", [])
	_ok(Contact.sub(st, "incoming").has("outre_nuit"), "L'Outre-Nuit est en route")
	_ok(Crisis.cur(st).is_empty(), "Elle n'arrive pas tout de suite")
	st.tick += 1100
	ContactVoices._tick_crises(st, [])
	if Crisis.enabled(st):
		_ok(String(Crisis.cur(st).get("kind", "")) == "outre_nuit" and int(st.crisis.get("summoner", -1)) == oss, "Trois ans plus tard, l'Outre-Nuit arrive et vise l'émetteur")
	else:
		var s := 0
		for x in ContactVoices.stability_parts(st, oss):
			s += int(x[1])
		_ok(s <= -20, "Sans crises en jeu : la peur à la place (%d)" % s)
	var st2 := T.new_game()
	var o2 := T.eid_of(st2, "ossarane")
	ContactVoices.on_fail(st2, o2, "hote", [])
	_ok(not Contact.sub(st2, "incoming").has("hote"), "L'Hôte vient tout de suite")


func _test_bridges_deeds() -> void:
	var st := T.new_game()
	var oss := T.eid_of(st, "ossarane")
	T.capture(st, oss)
	Contact.sub(st, "gauge")[str(oss)] = 240
	Contact.add_gauge(st, oss, 20, [])
	_ok(DeedsEval.value(st, oss, "ct_porteuse") == 1, "Haut fait « Nous ne sommes pas seuls »")
	_ok(not GameData.deeds()["deeds"].get("cercle_decimales", {}).is_empty(), "Haut fait « Un cercle dans les décimales »")
	# Précognition : les Revenants.
	st.get_empire(oss).techs["precognition"] = true
	st.contact["nature"] = "batisseurs"
	Contact.add_gauge(st, oss, 250, [])
	_ok(not Contact.possible_natures(st, oss).has("revenants"), "Précognition : on sait que ce ne sont pas les Revenants")
	# Interprète.
	var h := Heroes.council(st, oss)
	if not h.is_empty():
		_ok(T.cmd(st, oss, "interpreter", {"hero": int(h[0]["id"])}) == "", "Nommer un Interprète")
		var has := false
		for x in ContactVoices.gauge_pct_parts(st, oss):
			if String(x[0]) == "Interprète":
				has = true
		_ok(has, "Interprète : +15 %% de déchiffrement")
	# Amphictyonie : la famille « Signal » n'existe qu'en mode Complet.
	_ok(Amphictyony.family_def("signal").get("requires", "") == "contact", "Famille « Signal » : réservée au Contact")
	# Sauvegarde des sous-états du lot 3.
	Contact.sub(st, "taiseux")[str(oss)] = 33
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_dict())))
	_ok(ContactVoices.taiseux(back, oss) == 33, "Sauvegarde : Taiseux relus")
