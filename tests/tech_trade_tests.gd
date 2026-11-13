extends RefCounted
## Tests du commerce, lot 3A (TechTrade, AiTechTrade) : accords de recherche (conditions, paiement,
## bond de Savoir, annulation par la guerre), licences de technologie (conditions, Savoir et prix,
## pas de revente), diffusion le long des routes, propositions aux joueurs, IA et sauvegarde 38.
## Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Accords de recherche, licences de technologie et diffusion…")
	_test_pact()
	_test_licence()
	_test_diffusion()
	_test_save()
	_test_ai()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _state() -> GameState:
	var st := GameState.create(4242, 150, 1800.0, "vael", {"ai_level": ""})
	for e in st.empires:
		e.resources["energy"] = 5000
		Research.grant(st, e.id, ["chancelleries"])
	return st


func _meet(st: GameState, a: int, b: int) -> void:
	for p in [[a, b], [b, a]]:
		var e := st.get_empire(int(p[0]))
		if not e.contacts.has(int(p[1])):
			e.contacts.append(int(p[1]))
			e.contacts.sort()


func _apply(st: GameState, cmd: Dictionary) -> String:
	var why := SimCommands.validate(st, cmd)
	if why == "":
		SimCommands.apply(st, cmd)
	return why


func _peace(st: GameState, a := 0, b := 1, trade := false) -> void:
	_meet(st, a, b)
	Diplomacy.sign_treaty(st, a, b, Diplomacy.PEACE)
	if trade:
		Diplomacy.sign_treaty(st, a, b, Diplomacy.TRADE)


func _months(st: GameState, n: int) -> void:
	for i in n:
		st.tick += 30
		TechTrade.monthly(st)


func _test_pact() -> void:
	var st := _state()
	_ok(_apply(st, SimCommands.research_pact(0, 1)) != "", "pas d'accord sans contact ni paix")
	_peace(st)
	var why := _apply(st, SimCommands.research_pact(0, 1))
	_ok(why.contains("an de paix"), "il faut un an de paix (%s)" % why)
	st.tick += 360
	var cost := TechTrade.pact_cost(st, 0, 1)
	_ok(_apply(st, SimCommands.research_pact(0, 1)) == "", "après un an, on propose l'accord")
	var offers := TechTrade.offers_to(st, 1)
	_ok(offers.size() == 1 and String(offers[0]["kind"]) == "pact", "le joueur d'en face reçoit la proposition")
	_ok(_apply(st, SimCommands.research_pact(0, 1)) != "", "pas deux fois la même proposition")
	_ok(_apply(st, SimCommands.tech_answer(1, int(offers[0]["id"]), true)) == "", "il accepte")
	_ok(int(st.get_empire(0).resources["energy"]) == 5000 - cost and int(st.get_empire(1).resources["energy"]) == 5000 - cost, "chacun paie %d énergie" % cost)
	_ok(not TechTrade.pact_between(st, 0, 1).is_empty(), "l'accord est en cours")
	var e := st.get_empire(0)
	e.research_queue.clear()
	var k0 := int(e.resources.get("knowledge", 0))
	_months(st, 35)
	_ok(not TechTrade.pact_between(st, 0, 1).is_empty() and int(e.resources.get("knowledge", 0)) == k0, "rien avant trois ans")
	_months(st, 2)
	_ok(TechTrade.pact_between(st, 0, 1).is_empty(), "au bout de trois ans, l'accord se termine")
	_ok(int(e.resources.get("knowledge", 0)) == k0 + TechTrade.pact_bonus(st, 0), "et rapporte %d Savoir" % TechTrade.pact_bonus(st, 0))
	# Avec une recherche en cours, le bond va à la technologie en tête de file.
	var st2 := _state()
	_peace(st2)
	st2.tick += 360
	TechTrade._sign_pact(st2, 0, 1)
	var e2 := st2.get_empire(0)
	var tid := ""
	for t in Research.visible_ids(e2.faction()):
		if Research.is_available(st2, 0, t):
			tid = t
			break
	e2.research_queue = [tid]
	e2.research_progress = 0
	_months(st2, 37)
	_ok(e2.techs.has(tid) or e2.research_progress > 0, "le bond va à la recherche en cours (%s)" % tid)
	# La guerre annule tout.
	var st3 := _state()
	_peace(st3)
	st3.tick += 360
	TechTrade._sign_pact(st3, 0, 1)
	var en := int(st3.get_empire(0).resources["energy"])
	Combat.start_war(st3, 0, 1)
	_months(st3, 1)
	_ok(TechTrade.pact_between(st3, 0, 1).is_empty() and int(st3.get_empire(0).resources["energy"]) == en, "la guerre annule l'accord, l'énergie est perdue")


## Une technologie que le vendeur connaît et que l'acheteur peut chercher.
func _sellable_tech(st: GameState, seller: int, buyer: int) -> String:
	for t in Research.visible_ids(st.get_empire(buyer).faction()):
		if Research.is_available(st, buyer, t) and TechTrade.sellable(st, seller, t):
			return t
	return ""


func _give_era1(st: GameState, eid: int) -> void:
	for t: String in GameData.technologies()["technologies"]:
		if int(Research.tech(t).get("era", 1)) == 1 and not Research.is_specific(t) and Research.is_available(st, eid, t):
			Research.grant(st, eid, [t])


func _test_licence() -> void:
	var st := _state()
	_give_era1(st, 1)
	var tid := _sellable_tech(st, 1, 0)
	_ok(tid != "", "le vendeur a une technologie à vendre (%s)" % tid)
	_meet(st, 0, 1)
	_ok(_apply(st, SimCommands.tech_licence(0, 1, tid)) != "", "pas de licence sans palier de commerce")
	_peace(st, 0, 1, true)
	var k := TechTrade.licence_knowledge(st, 0, tid)
	var price := TechTrade.licence_price(st, 0, tid)
	_ok(k == Research.cost(st, 0, tid) * 60 / 100, "la licence apporte 60 %% du coût en Savoir (%d)" % k)
	_ok(price == k * 2, "et se paie le double en énergie, au prix du Savoir sur le marché (%d)" % price)
	_ok(_apply(st, SimCommands.tech_licence(0, 1, tid)) == "", "on demande la licence")
	var o := TechTrade.offers_to(st, 1)
	_ok(o.size() == 1 and String(o[0]["tech"]) == tid, "le vendeur reçoit la demande")
	_ok(_apply(st, SimCommands.tech_answer(1, int(o[0]["id"]), true)) == "", "il accepte")
	_ok(Research.progress_of(st, 0, tid) == k, "l'acheteur a le Savoir mis de côté")
	_ok(int(st.get_empire(0).resources["energy"]) == 5000 - price and int(st.get_empire(1).resources["energy"]) == 5000 + price, "l'énergie passe de l'un à l'autre")
	Research.complete(st, 0, tid)
	_meet(st, 0, 2)
	Diplomacy.sign_treaty(st, 0, 2, Diplomacy.PEACE)
	Diplomacy.sign_treaty(st, 0, 2, Diplomacy.TRADE)
	_ok(not TechTrade.sellable(st, 0, tid), "une technologie achetée ne se revend pas")
	# Ni technologie de peuple, ni méga-vaisseaux.
	_ok(not TechTrade.sellable(st, 1, "leviathans"), "pas de licence de Léviathan")
	var spec := ""
	for t: String in GameData.technologies()["technologies"]:
		if Research.is_specific(t):
			spec = t
			break
	Research.grant(st, 1, [spec])
	_ok(not TechTrade.sellable(st, 1, spec), "ni de technologie de peuple (%s)" % spec)
	# Trop avancée : plus d'une ère d'écart.
	var far := ""
	for t: String in GameData.technologies()["technologies"]:
		if int(Research.tech(t).get("era", 1)) >= 3 and not Research.is_specific(t):
			far = t
			break
	Research.grant(st, 1, [far])
	_ok(_apply(st, SimCommands.tech_licence(0, 1, far)) != "", "pas de technologie de deux ères d'avance (%s)" % far)
	_ok(_apply(st, SimCommands.tech_answer(1, 9999, true)) != "", "pas de réponse à une proposition inconnue")


func _test_diffusion() -> void:
	var st := _state()
	_peace(st, 0, 1, true)
	Trade.compute(st)
	var base := int(Trade.income(st, 0).get("knowledge", 0))
	_ok(base == 0, "à niveau égal, pas de diffusion")
	_give_era1(st, 1)
	var gap := TechTrade.tech_gap(st, 0, 1)
	Trade.compute(st)
	var k := int(Trade.income(st, 0).get("knowledge", 0))
	_ok(gap > 0 and k > 0 and k <= int(TechTrade.data()["diffusion_route_max"]) * 2, "une route vers plus avancé rapporte du Savoir (%d pour %d technologies d'écart)" % [k, gap])
	_ok(int(Trade.income(st, 1).get("knowledge", 0)) == 0, "le plus avancé n'apprend rien")
	var net: Dictionary = Economy.empire_income(st, 0)["gross"]
	_ok(int(net.get("knowledge", 0)) > 0, "le Savoir de diffusion entre dans le bilan")


func _test_ai() -> void:
	var st := GameState.create(4242, 150, 1800.0, "", {"spectator": true, "ai_level": "normal"})
	var sim := Simulation.new(st)
	var pacts := 0
	var lic := 0
	for i in 360 * 12:
		sim.step()
		if st.tick % 30 == 0:
			pacts = maxi(pacts, (st.goods.get("pacts", []) as Array).size())
	for k in st.goods.get("tlic", {}):
		lic += (st.goods["tlic"][k] as Array).size()
	_ok(pacts > 0 or lic > 0, "en 12 ans, les IA signent des accords de recherche ou achètent des licences (%d accords, %d licences)" % [pacts, lic])


func _test_save() -> void:
	var st := _state()
	_peace(st, 0, 1, true)
	st.tick += 360
	TechTrade._sign_pact(st, 0, 1)
	_give_era1(st, 1)
	var tid := _sellable_tech(st, 1, 0)
	TechTrade._sell_licence(st, 0, 1, tid)
	_meet(st, 0, 2)
	Diplomacy.sign_treaty(st, 0, 2, Diplomacy.PEACE)
	st.tick += 360
	TechTrade.propose_pact(st, 2, 0)
	var d := st.to_dict()
	_ok(int(d["version"]) >= 38, "sauvegarde version 38 ou plus")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and JSON.stringify(back.goods["pacts"], "", true) == JSON.stringify(st.goods["pacts"], "", true)
			and JSON.stringify(back.goods["toff"], "", true) == JSON.stringify(st.goods["toff"], "", true), "accords et propositions survivent")
	_ok(back != null and TechTrade.licensed(back, 0).has(tid), "les licences obtenues aussi")
	_ok(back != null and back.checksum() == GameState.from_dict(JSON.parse_string(JSON.stringify(back.to_dict()))).checksum(), "deux allers-retours, même empreinte")
