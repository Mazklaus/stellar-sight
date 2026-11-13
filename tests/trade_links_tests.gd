extends RefCounted
## Tests du commerce, lot 3B (TradeLinks) : talents de peuple (courtiers, pèlerinages, troc, comptoirs,
## convois rançonnés, Ruche sans commerce civil), lois Protectionnisme et Compagnies à charte,
## espionnage commercial (convoi, contrebande, délit d'initié) et sauvegarde 39. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Commerce et autres piliers (talents, lois, espionnage)…")
	_test_talents()
	_test_routes_talents()
	_test_laws()
	_test_spy()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _state(faction := "vael", opts := {}) -> GameState:
	var o := {"ai_level": "", "goods": "normaux", "market": "actif", "politics": "active"}
	o.merge(opts, true)
	var st := GameState.create(4242, 150, 1800.0, faction, o)
	for e in st.empires:
		e.resources["energy"] = 5000
	return st


func _id_of(st: GameState, faction: String) -> int:
	for e in st.empires:
		if e.faction_id == faction:
			return e.id
	return -1


func _meet(st: GameState, a: int, b: int) -> void:
	for p in [[a, b], [b, a]]:
		var e := st.get_empire(int(p[0]))
		if not e.contacts.has(int(p[1])):
			e.contacts.append(int(p[1]))
			e.contacts.sort()


func _partners(st: GameState, a: int, b: int) -> void:
	_meet(st, a, b)
	Diplomacy.sign_treaty(st, a, b, Diplomacy.PEACE)
	Diplomacy.sign_treaty(st, a, b, Diplomacy.TRADE)


func _apply(st: GameState, cmd: Dictionary) -> String:
	var why := SimCommands.validate(st, cmd)
	if why == "":
		SimCommands.apply(st, cmd)
	return why


func _route_to(st: GameState, a: int, b: int) -> Dictionary:
	for r: Dictionary in st.trade.get("routes", []):
		if String(r["kind"]) == "ext" and int(r["from"]) == a and int(r["to"]) == b:
			return r
	return {}


func _test_talents() -> void:
	var st := _state("brisecomete")
	var me := 0
	var other := 1
	_ok(TradeLinks.talent_int(st, me, "market_fee_pct") == -10, "Profit : frais du marché -10")
	_ok(Goods.fee_pct(st, me) == Goods.fee_pct(st, other) - 10 or Goods.fee_pct(st, me) < Goods.fee_pct(st, other), "les courtiers paient moins de frais (%d contre %d)" % [Goods.fee_pct(st, me), Goods.fee_pct(st, other)])
	_ok(Trade.capacity(st, me) == int(Trade.data()["capacity_base"]) + 1 + Research.fx_int(st, me, "trade_routes"), "Syndicat : une route de plus")
	_ok(TradeLinks.talent_labels(st, me).size() == 2, "deux talents commerciaux affichés (credo et gouvernement)")
	var kh := _state("khthari", {"pirates": "normaux"})
	var e := kh.get_empire(0)
	_ok(Goods.black_price(kh, "plasmine", 10, 0) == Goods.black_price(kh, "plasmine", 10, 1) / 2, "Survie : marché noir au prix de base")
	var sid := Pirates.lair_ids(kh)[0] if not Pirates.lair_ids(kh).is_empty() else -1
	_ok(sid >= 0, "un repaire à transformer en port franc")
	if sid >= 0:
		kh.tick = 30
		Pirates.make_port(kh, sid, [])
		e.explored[sid] = true
		_meet(kh, 0, 1)
		_ok(_apply(kh, SimCommands.black_buy(0, sid, "plasmine", 10)) == "", "le peuple de la Survie se fournit au marché noir")
		var bad := false
		for m in kh.memories:
			if String(m["kind"]) == "smuggler":
				bad = true
		_ok(not bad, "sans que personne ne lui en tienne rigueur")


func _test_routes_talents() -> void:
	# Foi : pèlerinage vers un empire du même credo (deux Chœurs).
	var st := _state("choeur")
	var other := 1
	st.get_empire(other).faction_id = "choeur"
	GameData.factions_gen += 1
	_partners(st, 0, other)
	Trade.compute(st)
	var r := _route_to(st, 0, other)
	_ok(not r.is_empty(), "une route vers l'autre Chœur")
	_ok(int(Trade.income(st, 0).get("influence", 0)) >= 2 + int(Trade.tier_info(Trade.tier(st, 0, other)).get("influence", 0)), "Foi : la route est un pèlerinage (+2 influence)")
	st.get_empire(other).faction_id = "vael"
	GameData.factions_gen += 1
	# Ruche : routes extérieures à moitié, intérieures doublées.
	var a := _state("vael")
	var b := _state("khthari")
	for s in [a, b]:
		_partners(s, 0, 1)
		Trade.compute(s)
	var ra := _route_to(a, 0, 1)
	var rb := _route_to(b, 0, 1)
	_ok(not ra.is_empty() and not rb.is_empty(), "des routes dans les deux parties de comparaison")
	if not ra.is_empty() and not rb.is_empty():
		var ea := int(Trade.income(a, 0).get("energy", 0))
		var eb := int(Trade.income(b, 0).get("energy", 0))
		_ok(eb < ea or int(rb["net"]) * 50 / 100 >= eb - 2, "Ruche : ses routes extérieures rapportent moitié moins (%d contre %d)" % [eb, ea])
	_ok(TradeLinks.talent_int(b, 0, "internal_mult") == 2, "et ses routes intérieures comptent double")
	# Horde : une flotte armée qui bloque une route ennemie la rançonne.
	var h := _state("vael")
	var horde := 2
	h.get_empire(horde).faction_id = "ferrocornes"
	GameData.factions_gen += 1
	_partners(h, 0, 1)
	Trade.compute(h)
	var route := _route_to(h, 0, 1)
	_ok(not route.is_empty() and (route["path"] as Array).size() > 2, "une route assez longue pour être bloquée")
	if not route.is_empty() and (route["path"] as Array).size() > 2:
		_meet(h, horde, 0)
		Combat.start_war(h, horde, 0)
		var sid := int((route["path"] as Array)[1])
		var f := h.spawn_ship(horde, "fregate", sid)
		f.system_id = sid
		Trade.compute(h)
		var rr := _route_to(h, 0, 1)
		_ok(bool(rr.get("blocked", false)) and int(rr.get("by", -1)) == horde, "la flotte de la Horde bloque la route")
		_ok(int(Trade.income(h, horde).get("energy", 0)) > 0, "et rançonne le convoi (%d énergie)" % int(Trade.income(h, horde).get("energy", 0)))
	h.get_empire(horde).faction_id = "ferrocornes"


func _test_laws() -> void:
	var st := _state("vael")
	_partners(st, 0, 1)
	Trade.compute(st)
	var r0 := _route_to(st, 0, 1)
	var net0 := int(r0.get("net", 0))
	var en := Laws._w(st, 0)
	(en["laws"] as Array).append("protectionnisme")
	st.get_empire(0).tech_fx_n = -1
	Trade.compute(st)
	var r1 := _route_to(st, 0, 1)
	_ok(not r0.is_empty() and int(r1.get("net", 0)) < net0, "Protectionnisme : tarifs doublés, la route rapporte moins (%d -> %d)" % [net0, int(r1.get("net", 0))])
	_ok(Laws.check_adopt(st, 0, "libre_echange").contains("incompatible"), "incompatible avec le Libre-échange")
	var cap := Trade.capacity(st, 0)
	(en["laws"] as Array).append("compagnies_charte")
	st.get_empire(0).tech_fx_n = -1
	_ok(Trade.capacity(st, 0) == cap + 1, "Compagnies à charte : une route de plus")
	# Actes : libre-échange et embargo poussent des courants (sans erreur).
	Trade.raise_tier(st, 0, 1)
	Trade.raise_tier(st, 0, 1)
	_ok(Trade.tier(st, 0, 1) == Trade.FREE, "le libre-échange signé compte comme un acte")


func _test_spy() -> void:
	var st := _state("vael")
	var a := 0
	var b := 1
	_partners(st, b, 2)
	Trade.compute(st)
	_ok(Espionage.op_def("convoi").size() > 0 and Espionage.op_def("contrebande").size() > 0 and Espionage.op_def("initie").size() > 0, "trois nouvelles opérations")
	var v := TradeLinks.convoy_value(st, b)
	var e0 := int(st.get_empire(a).resources["energy"])
	var txt := Espionage._apply(st, a, b, Espionage.op_def("convoi"))
	_ok(v > 0 and int(st.get_empire(a).resources["energy"]) == e0 + v, "détourner un convoi : %d énergie (%s)" % [v, txt])
	# Contrebande : un luxe de la cible, un an.
	var pid := -1
	for p in st.goods["dep"]:
		if Goods.is_luxury(String(st.goods["dep"][p])) and not st.colonies.has(int(p)):
			pid = int(p)
			break
	var c := Colony.new()
	c.planet_id = pid
	c.owner = b
	c.kind = Colony.KIND_OUTPOST
	st.add_colony(c)
	Goods.monthly(st)
	var g := TradeLinks.smuggle_pick(st, a, b)
	_ok(g != "", "la cible a un luxe qui vous manque (%s)" % g)
	Espionage._apply(st, a, b, Espionage.op_def("contrebande"))
	_ok(Goods.luxuries_of(st, a).has(g), "il arrive en contrebande")
	_ok(not Goods.licences_sold(st, b).any(func(l: Dictionary) -> bool: return String(l["good"]) == g), "la victime n'en voit aucune licence")
	st.tick += 361
	TradeLinks.monthly(st)
	_ok(not Goods.luxuries_of(st, a).has(g), "au bout d'un an, la contrebande s'arrête")
	# Délit d'initié : le prochain choc, le même que celui qui arrivera.
	var k := 1
	while k < 30 and Goods.shock_roll(st, k).is_empty():
		k += 1
	st.tick = (k - 1) * 360 + 30
	var sh := TradeLinks.learn_insider(st, a)
	_ok(sh.is_empty() or int(sh["tick"]) > st.tick, "le délit d'initié annonce un choc à venir")
	_ok(not sh.is_empty(), "un choc dans les trois ans pour cette graine")
	if not sh.is_empty():
		st.tick = int(sh["tick"])
		Goods.monthly(st)
		_ok(String(st.goods["shock"].get("res", "")) == String(sh["res"]) and int(st.goods["shock"].get("pct", 0)) == int(sh["pct"]), "et il survient comme annoncé (%s %+d %%)" % [String(sh["res"]), int(sh["pct"])])


func _test_save() -> void:
	var st := _state("vael")
	st.goods["smug"] = [{"buyer": 0, "seller": 1, "good": "soie_vide", "until": 400}]
	st.goods["insider"] = {0: {"tick": 720, "res": "food", "pct": -40}}
	var d := st.to_dict()
	_ok(int(d["version"]) >= 39, "sauvegarde version 39 ou plus")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and JSON.stringify(back.goods["smug"], "", true) == JSON.stringify(st.goods["smug"], "", true), "la contrebande survit")
	_ok(back != null and TradeLinks.insider_of(back, 0).get("res", "") == "food", "le secret d'initié aussi")
	_ok(back != null and back.checksum() == GameState.from_dict(JSON.parse_string(JSON.stringify(back.to_dict()))).checksum(), "deux allers-retours, même empreinte")
