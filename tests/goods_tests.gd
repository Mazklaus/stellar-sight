extends RefCounted
## Tests du commerce, lot 2A (Goods, GoodsSystem, AiGoods) : gisements posés sans toucher la galaxie,
## luxes (effet, stabilité, exemplaires en plus), stratégiques (ère, coûts des modules), licences
## (achat, fin, valeur des routes), monopoles, marché intérieur (prix, frais, retour, ordres),
## contrats d'échange (en une fois, mensuels, rupture), IA et sauvegarde 36. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Luxes, stratégiques et marché…")
	_test_setup()
	_test_luxuries()
	_test_strategic()
	_test_licences()
	_test_monopoly()
	_test_market()
	_test_deals()
	_test_ai()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


func _state(mode := "normaux", market := "actif") -> GameState:
	var st := GameState.create(4242, 150, 1800.0, "vael", {"ai_level": "", "goods": mode, "market": market})
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


func _partners(st: GameState, a := 0, b := 1) -> void:
	_meet(st, a, b)
	Diplomacy.sign_treaty(st, a, b, Diplomacy.PEACE)
	Diplomacy.sign_treaty(st, a, b, Diplomacy.TRADE)


## Plante une colonie établie de l'empire sur une planète qui porte ce bien. Renvoie la planète (-1 sinon).
func _take(st: GameState, eid: int, good: String, skip := []) -> int:
	var ids: Array = st.goods["dep"].keys()
	ids.sort()
	for pid in ids:
		if String(st.goods["dep"][pid]) != good or st.colonies.has(int(pid)) or skip.has(int(pid)):
			continue
		var c := Colony.new()
		c.planet_id = int(pid)
		c.owner = eid
		c.kind = Colony.KIND_OUTPOST
		st.add_colony(c)
		return int(pid)
	return -1


## Pose un gisement de ce bien sur une planète libre (pour ne pas dépendre du tirage).
func _plant(st: GameState, good: String) -> void:
	for s in st.galaxy.systems:
		for pid in s.planet_ids:
			if not st.goods["dep"].has(pid) and not st.colonies.has(pid):
				st.goods["dep"][pid] = good
				return


func _month(st: GameState) -> void:
	Goods.monthly(st)


func _test_setup() -> void:
	var none := GameState.create(4242, 150, 1800.0, "vael", {"ai_level": ""})
	var st := _state()
	_ok(none.goods["dep"].is_empty() and not Goods.active(none) and not Goods.market_on(none), "sans réglage : ni luxes, ni stratégiques, ni marché")
	_ok(JSON.stringify(none.galaxy.to_dict()) == JSON.stringify(st.galaxy.to_dict()) and str(none.rng.state) == str(st.rng.state),
			"les gisements ne changent ni la galaxie ni le flux aléatoire de la partie")
	var n: int = st.goods["dep"].size()
	var planets := 0
	for s in st.galaxy.systems:
		planets += s.planet_ids.size()
	_ok(n > planets / 20 and n < planets / 4, "réglage Normaux : environ une planète sur huit porte un bien (%d sur %d)" % [n, planets])
	var again := _state()
	_ok(str(again.goods["dep"]) == str(st.goods["dep"]), "même graine, mêmes gisements")
	var kinds := {}
	for pid in st.goods["dep"]:
		kinds[String(st.goods["dep"][pid])] = true
	_ok(kinds.size() >= 10, "luxes et stratégiques variés (%d sortes)" % kinds.size())
	var rare := _state("rares")
	var lots := _state("abondants")
	_ok(rare.goods["dep"].size() < n and n < lots.goods["dep"].size(), "rares < normaux < abondants")
	var home := st.get_empire(0).capital_planet
	_ok(not st.goods["dep"].has(home), "jamais sur une capitale de départ")


func _test_luxuries() -> void:
	var st := _state()
	for g in ["soie_vide", "epices_kesh"]:
		_plant(st, g)
		_plant(st, g)
	var before := Research.fx_sub(st, 0, "production_pct", "influence")
	var p := _take(st, 0, "soie_vide")
	_ok(p >= 0, "une colonie sur un gisement de Soie du vide")
	_month(st)
	_ok(Goods.luxuries_of(st, 0) == ["soie_vide"], "le luxe est exploité au bilan")
	_ok(Research.fx_sub(st, 0, "production_pct", "influence") == before + 5, "son effet s'ajoute à l'empire (+5 %% influence)")
	var parts := Goods.stability_parts(st, 0)
	_ok(parts.size() == 1 and int(parts[0][1]) == 1, "un luxe commun : +1 stabilité partout")
	var cx := Stability.context(st, 0)
	var found := false
	for l in cx["global"]:
		if String(l[0]).begins_with("Luxes"):
			found = true
	_ok(found, "la diversité des luxes compte dans la stabilité")
	_take(st, 0, "soie_vide")
	_take(st, 0, "epices_kesh")
	_month(st)
	_ok(Goods.luxuries_of(st, 0).size() == 2 and int(Goods.stability_parts(st, 0)[0][1]) == 2, "deux luxes, deux fois la stabilité")
	_ok(int(Goods.income(st, 0).get("energy", 0)) >= int(Goods.data()["extra_energy"]), "un gisement en double se vend : +%d énergie" % int(Goods.data()["extra_energy"]))
	_ok(int(Diplomacy.treaty_income(st, 0).get("energy", 0)) >= int(Goods.data()["extra_energy"]), "ce revenu entre dans le bilan")
	var off := _state("aucuns")
	_ok(Goods.effects(off, 0).is_empty() and Goods.stability_parts(off, 0).is_empty(), "sans luxes en jeu, aucun effet")


func _test_strategic() -> void:
	var st := _state()
	_plant(st, "plasmine")
	var p := _take(st, 0, "plasmine")
	_month(st)
	_ok(int(st.get_empire(0).resources.get("plasmine", 0)) == 0, "un stratégique de l'ère II ne rend rien à l'ère I")
	var t2: Array = []
	for t in GameData.technologies()["technologies"]:
		if int(Research.tech(String(t)).get("era", 1)) <= 2:
			t2.append(String(t))
	Research.grant(st, 0, t2)
	_ok(Research.current_era(st, 0) >= 2, "l'empire atteint l'ère II")
	_month(st)
	_ok(p >= 0 and int(st.get_empire(0).resources.get("plasmine", 0)) == 1, "puis 1 par gisement et par mois")
	var c := Designs.compute("croiseur", ["piece_artillerie"])
	_ok(int(c.get("strategic", {}).get("plasmine", 0)) == 2, "une pièce d'artillerie sur un croiseur demande 2 Plasmine")
	var off := _state("aucuns")
	var base := Goods.with_strategic(off, {"materials": 10}, {"plasmine": 2})
	_ok(not base.has("plasmine"), "sans stratégiques en jeu, le coût n'en demande pas")
	_ok(int(Goods.with_strategic(st, {"materials": 10}, {"plasmine": 2}).get("plasmine", 0)) == 2, "avec, il en demande")
	_ok(GameData.format_amounts({"plasmine": 3}).contains("Plas"), "les coûts affichent les stratégiques")
	_ok(int(Economy.building_cost(st, 0, "bourse_mille_soleils").get("ferronoir", 0)) == 20, "la Bourse des Mille Soleils demande du Ferronoir")
	_ok(not Economy.building_cost(off, 0, "bourse_mille_soleils").has("ferronoir"), "sauf sans stratégiques")


func _test_licences() -> void:
	var st := _state()
	_plant(st, "encens_fossile")
	_take(st, 1, "encens_fossile")
	_month(st)
	_ok(_apply(st, SimCommands.licence_buy(0, 1, "encens_fossile")) != "", "pas de licence sans traité de commerce")
	_partners(st)
	Trade.compute(st)
	var v0 := int(Trade.sent_by(st, 0)[0]["value"]) if not Trade.sent_by(st, 0).is_empty() else 0
	var price := Goods.licence_price(st, 1, 0, "encens_fossile")
	var e0 := int(st.get_empire(0).resources["energy"])
	_ok(_apply(st, SimCommands.licence_buy(0, 1, "encens_fossile")) == "", "licence achetée chez un partenaire")
	_ok(int(st.get_empire(0).resources["energy"]) == e0 - price, "le premier mois se paie tout de suite (%d)" % price)
	_ok(Goods.has_luxury(st, 0, "encens_fossile") and Goods.has_luxury(st, 1, "encens_fossile"), "l'acheteur en profite, le vendeur le garde")
	_ok(_apply(st, SimCommands.licence_buy(0, 1, "encens_fossile")) != "", "pas deux fois le même luxe")
	_month(st)
	_ok(int(Goods.income(st, 0).get("energy", 0)) == -price and int(Goods.income(st, 1).get("energy", 0)) == price, "puis chaque mois, au bilan")
	Trade.compute(st)
	var v1 := int(Trade.sent_by(st, 0)[0]["value"]) if not Trade.sent_by(st, 0).is_empty() else 0
	_ok(v0 == 0 or v1 == mini(v0 + 2, v1), "la licence enrichit la route entre eux (%d -> %d)" % [v0, v1])
	_ok(_apply(st, SimCommands.licence_close(1, "encens_fossile", true)) == "" and not Goods.sells_licence(st, 1, "encens_fossile"), "on ferme la vente d'un luxe")
	_ok(_apply(st, SimCommands.licence_cancel(0, 1, "encens_fossile")) == "" and not Goods.has_luxury(st, 0, "encens_fossile"), "on met fin à une licence")
	_ok(Goods.check_licence(st, 0, 1, "encens_fossile") != "", "plus de nouvelle licence une fois la vente fermée")
	Goods.set_closed(st, 1, "encens_fossile", false)
	_apply(st, SimCommands.licence_buy(0, 1, "encens_fossile"))
	Diplomacy.cancel(st, 0, 1, Diplomacy.TRADE)
	_month(st)
	_ok(not Goods.has_luxury(st, 0, "encens_fossile"), "sans traité, la licence tombe")


func _test_monopoly() -> void:
	var st := _state()
	_meet(st, 0, 1)
	_meet(st, 0, 2)
	for i in 3:
		_plant(st, "lait_etoile")
	var all := 0
	for pid in st.goods["dep"]:
		if String(st.goods["dep"][pid]) == "lait_etoile":
			all += 1
	for i in all:
		_take(st, 0, "lait_etoile")
	_month(st)
	_ok(Goods.monopoly_of(st, "lait_etoile") == 0, "tous les gisements d'un luxe : monopole")
	_ok(int(Goods.income(st, 0).get("energy", 0)) >= 25, "un monopole complet rapporte 25 énergie par mois (%d)" % int(Goods.income(st, 0).get("energy", 0)))
	var hoard := false
	for m in st.memories:
		if int(m["about"]) == 0 and String(m["kind"]) == "hoarder":
			hoard = true
	_ok(hoard, "les autres s'en souviennent : accapareur")
	_partners(st, 0, 1)
	var normal := int(Goods.tier_def(3)["licence_price"])
	_ok(Goods.licence_price(st, 0, 1, "lait_etoile") >= normal * 3 / 2, "les licences d'un monopole coûtent plus cher")
	_take(st, 1, "lait_etoile")
	_plant(st, "lait_etoile")
	_plant(st, "lait_etoile")
	_take(st, 1, "lait_etoile")
	_take(st, 1, "lait_etoile")
	_month(st)
	_ok(Goods.monopoly_of(st, "lait_etoile") != 1, "pas de monopole pour une part minoritaire")


func _test_market() -> void:
	var st := _state()
	var e := st.get_empire(0)
	e.resources["energy"] = 5000
	var c10 := Goods.buy_cost(st, 0, "materials", 10)
	var c100 := Goods.buy_cost(st, 0, "materials", 100)
	_ok(c10 == 13, "10 matériaux coûtent 13 énergie (frais de 30 %%) (%d)" % c10)
	var m0 := int(e.resources["materials"])
	_ok(_apply(st, SimCommands.market_trade(0, "materials", 100)) == "", "on achète au marché")
	_ok(int(e.resources["materials"]) == m0 + 100, "les matériaux arrivent")
	_ok(Goods.price_mult(st, 0, "materials") > 1000, "le prix monte après l'achat (%d ‰)" % Goods.price_mult(st, 0, "materials"))
	_ok(Goods.buy_cost(st, 0, "materials", 100) > c100, "le suivant paie plus cher (%d -> %d)" % [c100, Goods.buy_cost(st, 0, "materials", 100)])
	_month(st)
	_ok(Goods.price_mult(st, 0, "materials") < 1040, "chaque mois, le prix revient vers sa base")
	_ok(_apply(st, SimCommands.market_trade(0, "food", -100000)) != "", "pas de vente de ce qu'on n'a pas")
	var f0 := int(e.resources["food"])
	var en := int(e.resources["energy"])
	_ok(_apply(st, SimCommands.market_trade(0, "food", -50)) == "" and int(e.resources["food"]) == f0 - 50 and int(e.resources["energy"]) > en, "on vend contre de l'énergie")
	_ok(Goods.sell_gain(st, 0, "food", 10) < Goods.buy_cost(st, 0, "food", 10), "vendre rapporte moins qu'acheter ne coûte")
	_ok(_apply(st, SimCommands.market_order(0, "crystals", 10)) == "" and Goods.order_of(st, 0, "crystals") == 10, "ordre mensuel : 10 cristaux")
	var cr := int(e.resources["crystals"])
	_month(st)
	_ok(int(e.resources["crystals"]) == cr + 10, "l'ordre passe au bilan")
	_ok(Goods.market_ids(st).has("etherine"), "les stratégiques se vendent au marché")
	var closed := _state("normaux", "aucun")
	_ok(_apply(closed, SimCommands.market_trade(0, "materials", 10)) != "", "sans marché, rien à acheter")


func _test_deals() -> void:
	var st := _state()
	_meet(st, 0, 1)
	var a := st.get_empire(0)
	var b := st.get_empire(1)
	a.resources["materials"] = 1000
	b.resources["energy"] = 1000
	var m0 := int(a.resources["materials"])
	var e0 := int(a.resources["energy"])
	var gave := _apply(st, SimCommands.deal_offer(0, 1, {"materials": 100}, {"energy": 40}, 0))
	_ok(gave == "", "proposition d'échange envoyée")
	var o := Goods.offers_to(st, 1)
	_ok(o.size() == 1 and int(a.resources["materials"]) == m0, "un joueur doit répondre : rien ne bouge avant")
	if not o.is_empty():
		_ok(_apply(st, SimCommands.deal_answer(1, int(o[0]["id"]), true)) == "", "l'autre accepte")
		_ok(int(a.resources["materials"]) == m0 - 100 and int(a.resources["energy"]) == e0 + 40, "l'échange se fait en une fois")
	_ok(_apply(st, SimCommands.deal_offer(0, 1, {"materials": 10}, {"energy": 5}, 5)) != "", "durée impossible refusée")
	_apply(st, SimCommands.deal_offer(0, 1, {"materials": 10}, {"energy": 5}, 12))
	o = Goods.offers_to(st, 1)
	if not o.is_empty():
		_apply(st, SimCommands.deal_answer(1, int(o[0]["id"]), true))
	_ok(Goods.deals_of(st, 0).size() == 1 and int(Goods.deals_of(st, 0)[0]["left"]) == 11, "contrat mensuel sur un an")
	var m1 := int(a.resources["materials"])
	_month(st)
	_ok(int(a.resources["materials"]) == m1 - 10 and int(Goods.deals_of(st, 0)[0]["left"]) == 10, "chaque bilan, un versement")
	_ok(_apply(st, SimCommands.deal_cancel(0, int(Goods.deals_of(st, 0)[0]["id"]))) == "" and Goods.deals_of(st, 0).is_empty(), "on rompt le contrat")
	var broken := false
	for m in st.memories:
		if int(m["who"]) == 1 and int(m["about"]) == 0 and String(m["kind"]) == "deal_broken":
			broken = true
	_ok(broken, "l'autre se souvient du contrat rompu")
	# Une IA juge selon la valeur.
	var ai := GameState.create(4242, 150, 1800.0, "vael", {"ai_level": "normal", "goods": "normaux", "market": "actif"})
	_meet(ai, 0, 1)
	ai.get_empire(0).resources["materials"] = 1000
	var good := AiGoods.evaluate_offer(ai, 1, {"from": 0, "to": 1, "give": {"materials": 200}, "get": {"energy": 50}, "months": 0})
	var bad := AiGoods.evaluate_offer(ai, 1, {"from": 0, "to": 1, "give": {"materials": 10}, "get": {"energy": 300}, "months": 0})
	_ok(int(good["score"]) > int(bad["score"]) and int(bad["score"]) < 0, "l'IA accepte une bonne affaire, refuse une mauvaise (%d / %d)" % [int(good["score"]), int(bad["score"])])


func _test_ai() -> void:
	var st := GameState.create(4242, 150, 1800.0, "", {"spectator": true, "ai_level": "normal", "goods": "normaux", "market": "actif"})
	var sim := Simulation.new(st)
	for i in 360 * 8:
		sim.step()
	var lux := 0
	for e in st.empires:
		lux += Goods.luxuries_of(st, e.id).size()
	_ok(lux > 0, "en 8 ans, les IA exploitent des luxes (%d)" % lux)
	var traded := false
	for eid in st.goods.get("mkt", {}):
		traded = true
	_ok(traded or not st.goods.get("lic", []).is_empty(), "et commercent (marché ou licences)")


func _test_save() -> void:
	var st := _state()
	_plant(st, "soie_vide")
	_take(st, 0, "soie_vide")
	_partners(st)
	st.get_empire(0).resources["plasmine"] = 7
	_month(st)
	_apply(st, SimCommands.market_trade(0, "food", -20))
	_apply(st, SimCommands.market_order(0, "materials", 10))
	Goods.set_closed(st, 0, "soie_vide", true)
	var d := st.to_dict()
	_ok(int(d["version"]) == 36, "sauvegarde version 36")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and str(Goods._pairs(back.goods["dep"])) == str(Goods._pairs(st.goods["dep"])), "les gisements survivent à la sauvegarde")
	_ok(back != null and int(back.get_empire(0).resources.get("plasmine", 0)) == 7, "le stock de stratégiques aussi")
	_ok(back != null and Goods.luxuries_of(back, 0) == Goods.luxuries_of(st, 0) and not Goods.sells_licence(back, 0, "soie_vide"), "luxes et ventes fermées aussi")
	_ok(back != null and Goods.price_mult(back, 0, "food") == Goods.price_mult(st, 0, "food") and Goods.order_of(back, 0, "materials") == 10, "prix et ordres aussi")
	_ok(back != null and back.checksum() == GameState.from_dict(JSON.parse_string(JSON.stringify(back.to_dict()))).checksum(), "deux allers-retours, même empreinte")
	var old := d.duplicate(true)
	old["version"] = 35
	old.erase("goods")
	var ob := GameState.from_dict(JSON.parse_string(JSON.stringify(old)))
	_ok(ob != null and not Goods.active(ob) and not Goods.market_on(ob), "vieille sauvegarde : ni luxes ni marché")
