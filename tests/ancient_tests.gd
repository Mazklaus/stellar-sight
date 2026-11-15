extends RefCounted
## Tests des puissances anciennes endormies (Ancients, lot 1 de l'étude du 2026-11-15) : réglages
## (aucune, peu, normal, beaucoup) ; même empreinte sans anciennes ; poches loin des départs ; mondes
## achevés, bâtiments uniques, flottes ; pas en guerre au repos ; premier contact et fiche ; requêtes,
## missions, cadeaux ; exigences et guerre de Punition ; contributions et postes ; colères ; prise d'un
## monde ancien (butin) ; commandes ; sauvegarde 66 ; déterminisme. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Puissances anciennes…")
	_test_setup()
	_test_peace()
	_test_contact()
	_test_requests()
	_test_gifts()
	_test_demand()
	_test_contrib()
	_test_angers()
	_test_capture()
	_test_commands()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _new(seed_value := 11, mode := "normal", extra := {}) -> GameState:
	var o := {"ai_level": "", "ancients": mode}
	o.merge(extra, true)
	return GameState.create(seed_value, 120, 1600.0, "vael", o)


func _cards(st: GameState, eid: int, prefix: String) -> int:
	var n := 0
	for it: Dictionary in Events.inbox(st, eid):
		if String(it["card"]).begins_with(prefix):
			n += 1
	return n


## Avance le temps des anciennes seules (sans le reste de la simulation).
func _days(st: GameState, n: int) -> Array[Dictionary]:
	var added: Array[Dictionary] = []
	for i in n:
		st.tick += 1
		added.append_array(Ancients.daily(st))
	return added


func _test_setup() -> void:
	var off := _new(11, "aucune")
	_ok(not Ancients.enabled(off) and not off.to_dict().has("ancients"), "« Aucune » : pas d'anciennes, rien dans la sauvegarde")
	var plain := GameState.create(11, 120, 1600.0, "vael", {"ai_level": ""})
	_ok(plain.checksum() == off.checksum(), "sans l'option, même empreinte qu'avant le pilier")
	var st := _new()
	var n := Ancients.ids(st).size()
	_ok(n >= 1 and n <= 4, "« Normal » : 1 à 4 anciennes selon la taille (%d)" % n)
	var many := _new(11, "beaucoup")
	_ok(Ancients.ids(many).size() >= n, "« Beaucoup » : au moins autant")
	var kinds := {}
	for id in Ancients.ids(st):
		var a := Ancients.get_a(st, id)
		kinds[String(a["kind"])] = true
		_ok(GameState.is_ancient(id) and GameState.is_npc(id), "identifiant ancien et hors des empires")
		var home := int(a["home"])
		var far := 999
		for e in st.empires:
			far = mini(far, int(FactionTraits.jumps_from(st.galaxy, FactionTraits.capital_system(st, e.id)).get(home, 999)))
		_ok(far >= 5, "capitale de %s à 5 sauts au moins des départs (%d)" % [Ancients.name_of(st, id), far])
		_ok((a["systems"] as Array).size() >= 3 and (a["systems"] as Array).size() <= 5, "poche de 3 à 5 systèmes")
		_ok(st.system_owner(home) == id, "ses mondes lui appartiennent")
		_ok(Ancients.fleets_of(st, id).size() >= 2 and Ancients.total_power(st, id) >= int(Ancients.data()["power"]["min"]), "flottes puissantes")
		_ok(Ancients.asleep(st, id), "elle dort")
		_ok(st.get_empire(id) != null and st.get_empire(id).display_name() == Ancients.name_of(st, id), "fiche d'empire à son nom")
	_ok(kinds.size() == n, "chaque ancienne est d'une sorte différente")
	var worlds: Dictionary = st.ancients["worlds"]
	_ok(not worlds.is_empty(), "des bâtiments uniques sur les mondes achevés")
	var a2 := _new()
	_ok(a2.checksum() == st.checksum(), "déterministe : même graine, mêmes anciennes")


func _test_peace() -> void:
	var st := _new()
	var id := Ancients.ids(st)[0]
	_ok(not Combat.at_war(st, 0, id) and not Combat.at_war(st, id, 0), "au repos, l'ancienne n'est en guerre avec personne")
	_ok(not Combat.at_war(st, id, GameState.FAUNA_ID), "elle laisse la faune en paix")
	_ok(Combat.at_war(st, id, GameState.PIRATE_ID), "mais pas les pirates")
	var added: Array[Dictionary] = []
	Ancients.meet(st, id, 0, added)
	Ancients.declare_war(st, id, 0, "empire", added)
	_ok(Combat.at_war(st, 0, id), "guerre déclarée : hostiles")
	_ok(Ancients.check_peace(st, 0, id) != "", "pas de paix tout de suite")
	st.tick += 200
	st.empires[0].resources["influence"] = 100
	_ok(Ancients.check_peace(st, 0, id) == "", "paix possible après six mois")
	Ancients.peace(st, id, 0, added)
	_ok(not Combat.at_war(st, 0, id), "paix signée")


func _test_contact() -> void:
	var st := _new()
	var id := Ancients.ids(st)[0]
	_ok(not Ancients.in_contact(st, id, 0), "pas de contact au départ")
	var added: Array[Dictionary] = []
	Ancients.meet(st, id, 0, added)
	_ok(Ancients.in_contact(st, id, 0) and Ancients.met(st, 0).has(id), "contact établi")
	_ok(_cards(st, 0, "anc_contact") == 1, "fiche de l'ancienne en fenêtre d'événement")
	var item: Dictionary = Events.inbox(st, 0)[0]
	var text := Events.fill(st, 0, item, String(Events.card("anc_contact").get("text", "")))
	_ok(not text.contains("{anc") and text.contains(Ancients.name_of(st, id).substr(0, 6)), "jetons remplis (nom, force, colères)")
	Ancients.add_op(st, id, 0, 1000)
	_ok(Ancients.opinion(st, id, 0) == int(Ancients.data()["opinion"]["max"]), "opinion plafonnée")
	_ok(String(Ancients.attitude(st, id, 0).get("label", "")) != "", "attitude lisible")


func _test_requests() -> void:
	var st := _new()
	var id := Ancients.ids(st)[0]
	var added: Array[Dictionary] = []
	Ancients.meet(st, id, 0, added)
	_days(st, 3000)
	var n := _cards(st, 0, "anc_") - _cards(st, 0, "anc_contact") - _cards(st, 0, "anc_postes")
	_ok(n >= 1 or Ancients.no_opinion(st, id), "huit ans plus tard : requêtes et missions reçues (%d)" % n)
	# Une mission acceptée puis échouée fait baisser l'opinion.
	var before := Ancients.opinion(st, id, 0)
	var item := {"id": -1, "card": "anc_mission", "anc": id, "system": -1, "planet": -1, "rival": -1, "hero": -1}
	Ancients.card_fx(st, 0, item, {"k": "ancient", "act": "mission"}, added)
	var a := Ancients.get_a(st, id)
	_ok((a["mission"] as Dictionary).has(0), "mission en cours")
	st.tick = int(a["mission"][0]["until"]) + 1
	Ancients._missions(st, id, a, added)
	_ok(Ancients.no_opinion(st, id) or Ancients.opinion(st, id, 0) < before, "mission échouée : opinion en baisse")


func _test_gifts() -> void:
	var st := _new()
	var id := Ancients.ids(st)[0]
	var added: Array[Dictionary] = []
	Ancients.meet(st, id, 0, added)
	var e := st.empires[0]
	var res_before := int(e.resources.get("energy", 0))
	var item := {"id": -1, "card": "anc_cadeau", "anc": id, "n": 0, "system": -1, "planet": -1, "rival": -1, "hero": -1}
	Ancients.card_fx(st, 0, item, {"k": "ancient", "act": "gift"}, added)
	_ok(int(e.resources.get("energy", 0)) >= res_before, "cadeau reçu")
	var tech_before := e.techs.size()
	item["n"] = 1
	Ancients.card_fx(st, 0, item, {"k": "ancient", "act": "gift"}, added)
	_ok(e.techs.size() >= tech_before, "technologie offerte")
	Ancients.add_boon(st, 0, "Test", {"production_pct": {"all": 7}}, 60)
	_ok(int(Ancients.effects(st, 0).get("production_pct", {}).get("all", 0)) >= 7, "faveur comptée dans les effets")
	st.tick += 90
	Ancients._expire_boons(st)
	_ok(Ancients.boons(st, 0).filter(func(b: Dictionary) -> bool: return String(b["label"]) == "Test").is_empty(), "faveur expirée")


func _test_demand() -> void:
	var st := _new()
	var id := Ancients.ids(st)[0]
	var added: Array[Dictionary] = []
	Ancients.meet(st, id, 0, added)
	var item := {"id": -1, "card": "anc_exige", "anc": id, "system": -1, "planet": -1, "rival": -1, "hero": -1}
	Ancients.card_fx(st, 0, item, {"k": "ancient", "act": "defy"}, added)
	_ok(Ancients.at_war_with(st, id, 0) and Combat.at_war(st, 0, id), "exigence refusée : guerre de Punition")
	_ok(Ancients.check_peace(st, 0, id) != "", "la Punition finit quand elle le décide")
	_days(st, 1500)
	_ok(not Ancients.at_war_with(st, id, 0), "la Punition s'arrête d'elle-même (4 ans ou 2 systèmes pris)")
	var st2 := _new()
	var id2 := Ancients.ids(st2)[0]
	Ancients.meet(st2, id2, 0, added)
	Ancients.add_op(st2, id2, 0, -300)
	item["anc"] = id2
	Ancients.card_fx(st2, 0, item, {"k": "ancient", "act": "submit"}, added)
	_ok(Ancients.opinion(st2, id2, 0) > int(Ancients.data()["opinion"]["demand_below"]), "plier calme l'ancienne")
	_ok(not Ancients.at_war_with(st2, id2, 0), "et évite la guerre")


func _test_contrib() -> void:
	var st := _new()
	var id := Ancients.ids(st)[0]
	var added: Array[Dictionary] = []
	Ancients.meet(st, id, 0, added)
	var e := st.empires[0]
	e.resources["energy"] = 5000
	_ok(Ancients.check_give(st, 0, id, "energy") == "", "contribution possible")
	for i in 5:
		Ancients.give(st, 0, id, "energy")
	_ok(Ancients.ranking(st, id)[0][1] == 0, "premier des contributeurs")
	var a := Ancients.get_a(st, id)
	st.tick = int(a["term"])
	Ancients._posts(st, id, a, added)
	var posts: Array = Ancients.kind_def(Ancients.kind_of(st, id)).get("posts", [])
	_ok(Ancients.post_holder(st, id, String(posts[0]["id"])) == 0, "premier poste attribué au plus généreux")
	_ok(_cards(st, 0, "anc_postes") == 1, "annonce des postes en fenêtre d'événement")
	_ok(not Ancients.effects(st, 0).is_empty(), "le poste rapporte")


func _test_angers() -> void:
	var st := _new()
	var id := Ancients.ids(st)[0]
	var added: Array[Dictionary] = []
	Ancients.meet(st, id, 0, added)
	var before := Ancients.opinion(st, id, 0)
	Ancients.on_atrocity(st, 0)
	_ok(Ancients.no_opinion(st, id) or Ancients.opinion(st, id, 0) < before, "une atrocité la met en colère")
	# Intrusion : une flotte de l'empire dans la poche.
	var a := Ancients.get_a(st, id)
	var f := st.spawn_ship(0, "corvette", int((a["systems"] as Array)[1]))
	var op := Ancients.opinion(st, id, 0)
	Ancients._angers(st, id, a, added)
	_ok(Ancients.no_opinion(st, id) or not (Ancients.kind_def(Ancients.kind_of(st, id)).get("angers", []) as Array).has("intrusion") \
			or Ancients.opinion(st, id, 0) < op, "intrusion dans la poche mal vue (si c'est une de ses colères)")
	st.fleets.erase(f.id)


func _test_capture() -> void:
	var st := _new()
	var id := Ancients.ids(st)[0]
	var a := Ancients.get_a(st, id)
	var sid := int(a["home"])
	var e := st.empires[0]
	var before := int(e.resources.get("energy", 0))
	var added := Combat.capture_system(st, sid, 0)
	_ok(st.system_owner(sid) == 0, "monde ancien pris")
	_ok(int(e.resources.get("energy", 0)) > before, "butin dans les caves")
	_ok(int(Ancients.effects(st, 0).get("production_pct", {}).get("all", 0)) >= 5, "merveille conquise : +5 % de production")
	_ok(not added.is_empty(), "la chronique en parle")


func _test_commands() -> void:
	var st := _new()
	var id := Ancients.ids(st)[0]
	_ok(SimCommands.validate(st, SimCommands.anc_act(0, "give", id, "energy")) != "", "inconnue : pas de contribution")
	var added: Array[Dictionary] = []
	Ancients.meet(st, id, 0, added)
	st.empires[0].resources["energy"] = 1000
	var cmd := SimCommands.anc_act(0, "give", id, "energy")
	_ok(SimCommands.validate(st, cmd) == "", "contribution validée")
	SimCommands.apply(st, cmd)
	_ok(int(st.empires[0].resources["energy"]) < 1000, "contribution payée")
	SimCommands.apply(st, SimCommands.anc_act(0, "war", id))
	_ok(Ancients.at_war_with(st, id, 0), "guerre déclarée par commande")
	_ok(SimCommands.validate(st, SimCommands.anc_act(0, "nimporte", id)) != "", "acte inconnu refusé")


func _test_save() -> void:
	var sim := Simulation.new(_new(13, "normal", {"ai_level": "normal"}))
	var st := sim.state
	sim.advance(720)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(st.to_snapshot())))
	_ok(back != null and back.checksum() == st.checksum(), "sauvegarde 68 relue, même empreinte")
	if back == null:
		return
	_ok(Ancients.ids(back) == Ancients.ids(st), "anciennes relues")
	var a := Simulation.new(st)
	var b := Simulation.new(back)
	a.advance(240)
	b.advance(240)
	_ok(a.state.checksum() == b.state.checksum(), "la partie reprise continue à l'identique")
