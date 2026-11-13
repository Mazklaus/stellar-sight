extends RefCounted
## Tests du commerce, lot 1 (Trade, TradeSystem, AiTrade) : paliers de traité (comptoirs, accord,
## libre-échange et leurs conditions), routes et valeur, capacité et comptoirs, routes intérieures,
## blocus, embargo et alliés qui suivent, risque pirate et repaire qui s'installe, opinion,
## Charte de Vael, sauvegarde 35 et migration des vieilles sauvegardes. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Commerce…")
	_test_tiers()
	_test_routes()
	_test_capacity()
	_test_internal()
	_test_blockade()
	_test_embargo()
	_test_piracy()
	_test_ai()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _state(pirates := "aucun") -> GameState:
	var st := GameState.create(4242, 150, 1800.0, "vael", {"ai_level": "", "pirates": pirates})
	for e in st.empires:
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


func _sign(st: GameState, a: int, b: int, treaty: String) -> bool:
	if _apply(st, SimCommands.propose_treaty(a, b, treaty)) != "":
		return false
	var p := Diplomacy.pending(st, a, b, treaty)
	if p.is_empty():
		return false
	var ok := _apply(st, SimCommands.answer_proposal(b, int(p["id"]), true)) == ""
	# Le délai entre deux propositions ne compte pas ici : on enchaîne les paliers.
	Diplomacy._rel_w(st, a, b)["cool"] = {}
	return ok


func _partners(st: GameState, a := 0, b := 1) -> void:
	_meet(st, a, b)
	_sign(st, a, b, Diplomacy.PEACE)
	_sign(st, a, b, Diplomacy.TRADE)


func _test_tiers() -> void:
	var st := _state()
	_meet(st, 0, 1)
	_ok(Trade.check_next_tier(st, 0, 1) != "", "pas de commerce sans la paix")
	_sign(st, 0, 1, Diplomacy.PEACE)
	_ok(_sign(st, 0, 1, Diplomacy.TRADE) and Trade.tier(st, 0, 1) == Trade.OPEN, "1er palier : comptoirs ouverts")
	_ok(Trade.tier(st, 1, 0) == Trade.OPEN, "le palier est le même des deux côtés")
	_ok(_sign(st, 0, 1, Diplomacy.TRADE) and Trade.tier(st, 0, 1) == Trade.AGREEMENT, "2e palier : accord commercial")
	var why := Trade.check_next_tier(st, 0, 1)
	_ok(why.contains("deux ans"), "le libre-échange exige deux ans d'accord (%s)" % why)
	Diplomacy._rel_w(st, 0, 1)["tier_since"] = st.tick - 800
	why = Trade.check_next_tier(st, 0, 1)
	_ok(why.contains("opinion") or why == "", "puis une opinion suffisante de part et d'autre (%s)" % why)
	Diplomacy._rel_w(st, 0, 1)["trade_since"] = st.tick - 360 * 7
	var parts := Trade.opinion_parts(st, 0, 1)
	_ok(parts.size() == 2 and int(parts[1][1]) == 10, "opinion : +2 par an de commerce, au plus 5 ans (%s)" % str(parts))
	Trade.raise_tier(st, 0, 1)
	_ok(Trade.tier(st, 0, 1) == Trade.FREE and Trade.check_next_tier(st, 0, 1) != "", "3e palier : libre-échange, rien au-delà")
	Trade.compute(st)
	_ok(int(Trade.income(st, 0).get("influence", 0)) == 2, "libre-échange : +2 influence par mois (%s)" % str(Trade.income(st, 0)))
	Diplomacy.cancel(st, 0, 1, Diplomacy.TRADE)
	_ok(Trade.tier(st, 0, 1) == 0 and st.memories.any(func(m: Dictionary) -> bool: return int(m["who"]) == 1 and String(m["kind"]) == "trade_cut"), "rompre le commerce : tout tombe, et l'autre s'en souvient")


func _test_routes() -> void:
	var st := _state()
	_partners(st)
	Trade.compute(st)
	var r0 := Trade.sent_by(st, 0)
	var r1 := Trade.sent_by(st, 1)
	_ok(r0.size() == 1 and r1.size() == 1, "chaque empire envoie une route à son partenaire (%d, %d)" % [r0.size(), r1.size()])
	if r0.is_empty():
		return
	var r: Dictionary = r0[0]
	var p: Array = r["path"]
	var rd: Dictionary = Trade.data()["route"]
	@warning_ignore("integer_division")
	var want := mini(int(rd["cap"]), int(rd["base"]) + clampi(p.size() - 1, 1, int(rd["max_jumps"])) * (Trade.system_pop(st, int(p[0])) + Trade.system_pop(st, int(p[-1]))) / int(rd["pop_div"]))
	_ok(int(r["value"]) == want and want > int(rd["base"]), "valeur = base + sauts × population des deux bouts / 10 (%d)" % want)
	@warning_ignore("integer_division")
	_ok(int(r["net"]) == want * 80 / 100, "comptoirs ouverts : 20 %% de douane (%d)" % int(r["net"]))
	_ok(int(Trade.income(st, 0).get("energy", 0)) == int(Trade.income(st, 1).get("energy", 0)) and int(Trade.income(st, 0).get("energy", 0)) > 0,
			"les deux bouts touchent la même somme (%s)" % str(Trade.income(st, 0)))
	_ok(Trade.value_between(st, 0, 1) == int(r0[0]["net"]) + int(r1[0]["net"]), "valeur entre deux empires = somme des deux routes")
	var d := Diplomacy.treaty_income(st, 0)
	_ok(int(d.get("energy", 0)) >= int(Trade.income(st, 0).get("energy", 0)), "le revenu des routes entre dans le bilan des traités")


func _test_capacity() -> void:
	var st := _state()
	_partners(st, 0, 1)
	_partners(st, 0, 2)
	Trade.compute(st)
	_ok(Trade.capacity(st, 0) == 1 and Trade.sent_by(st, 0).size() == 1, "capacité de base : une route pour deux partenaires")
	var cap_pid := st.get_empire(0).capital_planet
	(st.colonies[cap_pid] as Colony).buildings.append("comptoir")
	_ok(Trade.capacity(st, 0) == 2 and Trade.comptoirs(st, 0).size() == 1, "un comptoir ajoute une route")
	Research.grant(st, 0, ["bourses"])
	_ok(Trade.capacity(st, 0) == 3, "les Bourses ajoutent une route (%d)" % Trade.capacity(st, 0))
	Trade.compute(st)
	_ok(Trade.sent_by(st, 0).size() == 2, "deux partenaires, deux routes, une place libre")
	var e2 := Trade.sent_by(st, 0)
	_ok(e2.size() < 2 or int(e2[0]["value"]) >= int(e2[1]["value"]), "les routes les plus rentables d'abord")


func _test_internal() -> void:
	var st := _state()
	var cap := FactionTraits.capital_system(st, 0)
	var jumps := FactionTraits.jumps_from(st.galaxy, cap)
	var sid := -1
	for s in st.galaxy.systems:
		if int(jumps.get(s.id, 99)) == 2 and st.system_owner(s.id) < 0 and not s.planet_ids.is_empty():
			sid = s.id
			break
	_ok(sid >= 0, "un système libre à deux sauts")
	if sid < 0:
		return
	var c := Colony.new()
	c.planet_id = st.galaxy.systems[sid].planet_ids[0]
	c.owner = 0
	c.kind = Colony.KIND_COLONY
	c.population = 2
	st.add_colony(c)
	_ok(Trade.young_colonies(st, 0).has(c.planet_id), "une colonie de 2 habitants est jeune")
	Trade.compute(st)
	_ok(Trade.served(st, c.planet_id), "une place libre sert la jeune colonie")
	_ok(int(Trade.income(st, 0).get("food", 0)) == 2 and int(Trade.income(st, 0).get("materials", 0)) == 2, "route intérieure : +2 nourriture, +2 matériaux")
	_ok(Trade.internal_growth(st, c.planet_id) == 4, "et la colonie grandit plus vite")
	_partners(st)
	Trade.compute(st)
	_ok(not Trade.served(st, c.planet_id), "un partenaire passe avant les colonies sans réserve")
	_ok(_apply(st, SimCommands.trade_reserve(0, 1)) == "" and Trade.reserved(st, 0) == 1, "on réserve une place aux routes intérieures")
	Trade.compute(st)
	_ok(Trade.served(st, c.planet_id) and Trade.sent_by(st, 0).size() == 1, "la réserve passe avant le partenaire")
	_ok(_apply(st, SimCommands.trade_reserve(0, 5)) != "", "pas plus de réserve que de capacité")


func _test_blockade() -> void:
	var st := _state()
	_partners(st)
	Trade.compute(st)
	var r: Dictionary = Trade.sent_by(st, 0)[0]
	var p: Array = r["path"]
	var mid := int(p[p.size() / 2])
	_meet(st, 0, 2)
	_meet(st, 1, 2)
	var armed := st.spawn_ship(2, "corvette", mid)
	_ok(Combat.is_armed(armed), "une corvette du troisième empire sur le chemin")
	Trade.compute(st)
	_ok(not bool(Trade.sent_by(st, 0)[0]["blocked"]), "une flotte en paix ne bloque rien")
	st.get_empire(2).wars.append(0)
	st.get_empire(0).wars.append(2)
	Trade.compute(st)
	var rb: Dictionary = Trade.sent_by(st, 0)[0]
	var blocked := bool(rb["blocked"]) and int(rb["net"]) == 0 and int(rb["by"]) == 2
	# Le chemin peut contourner le système de l'ennemi : alors la route n'est pas bloquée.
	_ok(blocked or not (rb["path"] as Array).has(mid), "une flotte ennemie sur le chemin bloque la route")


func _test_embargo() -> void:
	var st := _state()
	_partners(st)
	_meet(st, 0, 2)
	_meet(st, 1, 2)
	_ok(_apply(st, SimCommands.embargo(0, 1)) == "", "on décrète un embargo")
	_ok(Trade.tier(st, 0, 1) == 0 and Trade.embargoed(st, 0, 1), "l'embargo rompt le commerce")
	_ok(Trade.check_next_tier(st, 0, 1) != "", "et interdit d'en signer")
	_ok(_apply(st, SimCommands.embargo(0, 1)) != "", "pas deux fois")
	_ok(_apply(st, SimCommands.lift_embargo(1, 0)) != "", "seul celui qui l'a décrété le lève")
	_ok(_apply(st, SimCommands.lift_embargo(0, 1)) == "" and not Trade.embargoed(st, 0, 1), "on lève l'embargo")
	_ok(Trade.check_next_tier(st, 0, 1) == "", "le commerce redevient possible")


func _test_piracy() -> void:
	var st := _state("normaux")
	_partners(st)
	Trade.compute(st)
	var r: Dictionary = Trade.sent_by(st, 0)[0]
	var p: Array = r["path"]
	var free := -1
	for i in range(1, p.size() - 1):
		if st.system_owner(int(p[i])) < 0:
			free = int(p[i])
			break
	if free < 0:
		_ok(true, "route entièrement tenue : pas de risque pirate à tester")
		return
	# On retire les flottes qui y passent pour que le système soit sans présence.
	for f in st.fleets.values():
		if (f as Fleet).system_id == free and not GameState.is_npc((f as Fleet).owner):
			(f as Fleet).system_id = p[0]
	Trade.compute(st)
	_ok(Trade.risk_at(st, free) > 0, "un système de route sans présence attire les pirates (%d ‰)" % Trade.risk_at(st, free))
	st.trade["risk"][free] = 200
	Trade.compute(st)
	var r2: Dictionary = Trade.sent_by(st, 0)[0]
	_ok(int(r2["loss"]) >= 200 and int(r2["net"]) < int(r2["value"]) * 80 / 100, "les pirates volent une part de la route (%d ‰)" % int(r2["loss"]))
	var before := st.lairs.size()
	var far := true
	var j := FactionTraits.jumps_from(st.galaxy, free)
	for lid in st.lairs:
		if int(j.get(int(lid), 999)) < int(Trade.data()["piracy"]["spawn_min_jumps"]):
			far = false
	st.trade["risk"][free] = 250
	Trade.compute(st)
	if far:
		_ok(st.lairs.size() == before + 1 and Pirates.is_lair(st, free), "au maximum, un repaire s'installe sur la route")
	else:
		_ok(st.lairs.size() == before, "pas de nouveau repaire trop près d'un autre")
	var calm := _state("aucun")
	_partners(calm)
	calm.trade["risk"] = {free: 250}
	Trade.compute(calm)
	_ok(calm.lairs.is_empty(), "sans pirates en jeu, aucun repaire ne naît")


func _test_ai() -> void:
	var st := GameState.create(4242, 150, 1800.0, "", {"spectator": true, "ai_level": "normal"})
	var sim := Simulation.new(st)
	for i in 360 * 6:
		sim.step()
	var any := false
	for e in st.empires:
		for o in st.empires:
			if e.id < o.id and Trade.tier(st, e.id, o.id) > 0:
				any = true
	_ok(any, "en 6 ans, des IA signent du commerce")
	var routes: Array = st.trade.get("routes", [])
	_ok(not routes.is_empty(), "et des routes circulent (%d)" % routes.size())


func _test_save() -> void:
	var st := _state("normaux")
	_partners(st)
	Trade.set_reserve(st, 0, 1)
	Trade.compute(st)
	st.trade["risk"] = {5: 40, 9: 120}
	var d := st.to_dict()
	_ok(int(d["version"]) == 35, "sauvegarde version 35")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and Trade.tier(back, 0, 1) == Trade.OPEN, "le palier survit à la sauvegarde")
	_ok(back != null and Trade.reserved(back, 0) == 1 and Trade.risk_at(back, 9) == 120, "réserve et risques aussi")
	_ok(back != null and Trade.sent_by(back, 0).size() == Trade.sent_by(st, 0).size() and str(Trade.income(back, 0)) == str(Trade.income(st, 0)),
			"routes et revenus aussi")
	# Vieille sauvegarde : l'accord forfaitaire devient un accord commercial (palier 2).
	var old := d.duplicate(true)
	old["version"] = 34
	old.erase("trade")
	var old_back := GameState.from_dict(JSON.parse_string(JSON.stringify(old)))
	_ok(old_back != null and Trade.tier(old_back, 0, 1) == Trade.AGREEMENT, "migration : un ancien accord devient un accord commercial")
	_ok(old_back != null and not Trade.sent_by(old_back, 0).is_empty(), "et ses routes sont calculées au chargement")
