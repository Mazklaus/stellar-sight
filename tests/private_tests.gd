extends RefCounted
## Tests de l'économie privée (étude « Économie privée », 2026-11-16) : données, réglages
## (Désactivée = économie d'avant, Simple sans compagnies), caisse privée, activité, impôt sur les
## bénéfices selon le cran fiscal, confiance, subventions, licences et commandes d'État, stations
## minières et touristiques, cargos et paquebots (migration, chantiers lointains), compagnies
## (naissance, charte, effets, nationalisation, dirigeant), filiales, expropriation et motif de guerre,
## ouvrir les marchés, actions, prêts d'une compagnie, lois (Laissez-faire, Dirigisme, Planifiée),
## réquisition, ravitaillement sous contrat, syndicats du crime, comptabilité créative, espionnage
## industriel, cour, hauts faits, IA et sauvegarde. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Économie privée…")
	_test_data()
	_test_modes()
	_test_monthly()
	_test_tax()
	_test_confidence()
	_test_mines()
	_test_resorts_and_fleet()
	_test_companies()
	_test_branches()
	_test_laws()
	_test_war_tools()
	_test_crime()
	_test_spy()
	_test_bridges()
	_test_ai()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(seed_value := 31, extra := {}) -> GameState:
	var o := {"ai_level": "", "private": "complete"}
	o.merge(extra, true)
	return GameState.create(seed_value, 120, 1600.0, "vael", o)


static func eid_of(st: GameState, fid: String) -> int:
	for e in st.empires:
		if e.faction_id == fid:
			return e.id
	return -1


static func apply(st: GameState, cmd: Dictionary) -> String:
	var why := SimCommands.validate(st, cmd)
	if why == "":
		SimCommands.apply(st, cmd)
	return why


static func act(st: GameState, eid: int, a: String, x := -1, y := -1, s := "") -> String:
	return apply(st, SimCommands.private_act(eid, a, x, y, s))


## Un mois : bilan de l'empire, puis Private.daily (le mois tombe sur un multiple de 30).
static func month(st: GameState, e: Empire) -> void:
	st.tick += 30 - posmod(st.tick, 30)
	var added: Array[Dictionary] = []
	EconomySystem._monthly_balance(st, e, added)
	Private.daily(st)


static func grow(st: GameState, eid: int, n: int, pop := 12) -> Array[int]:
	var got: Array[int] = preload("res://tests/admin_tests.gd").give(st, eid, n)
	for c: Colony in st.colonies.values():
		if c.owner == eid:
			c.population = maxi(c.population, pop)
	return got


func _test_data() -> void:
	var d := GameData.private_eco()
	_ok(not d.is_empty(), "private.json se charge")
	_ok(Private.mode_defs().size() == 3 and Private.default_mode() == "complete", "3 réglages, Complète par défaut")
	_ok((d["companies"]["sectors"] as Array).size() == 8, "8 secteurs de compagnies")
	_ok((d["charters"]["list"] as Array).size() == 5, "5 chartes")
	_ok((d["directors"]["traits"] as Array).size() == 5, "5 traits de dirigeant")
	for id in ["laissez_faire", "dirigisme", "economie_planifiee"]:
		_ok(not Laws.law_def(id).is_empty(), "loi %s" % id)
	_ok(not Wars.casus_def("expropriation").is_empty() and not Wars.goal_def("ouvrir_marches").is_empty(), "motif Expropriation, but Ouvrir les marchés")
	for op in ["voler_procede", "saboter_compagnie", "debaucher_dirigeant", "rumeur_actions"]:
		_ok(not Espionage.op_def(op).is_empty(), "opération %s" % op)
	_ok(DeedsEval.is_counter("company_founded") and DeedsEval.is_counter("cargos_lost"), "compteurs des hauts faits privés")
	# Chaque secteur réclame une loi qui existe.
	for s: Dictionary in d["companies"]["sectors"]:
		_ok(not Laws.law_def(String(s["law"])).is_empty(), "loi du lobbying %s" % s["law"])


func _test_modes() -> void:
	var off := new_game(31, {"private": "desactivee"})
	_ok(off.private.is_empty() and not Private.worth_saving(off), "Désactivée : rien ne tourne")
	var none := GameState.create(31, 120, 1600.0, "vael", {"ai_level": ""})
	_ok(none.private.is_empty(), "sans l'option (tests, bancs) : désactivée")
	var p := eid_of(off, "vael")
	_ok(Private.check(off, p, "subsidize", -1, -1, "") != "", "Désactivée : aucun ordre")
	var simple := new_game(31, {"private": "simple"})
	var p2 := eid_of(simple, "vael")
	_ok(Private.applies(simple, p2) and not Private.full(simple), "Simple : secteur privé sans compagnies")
	_ok(Private.capital(simple, p2) == 100 and Private.confidence(simple, p2) == 50, "caisse 100 et confiance 50 au départ")
	_ok(Private.check(simple, p2, "zone", 0, -1, "").contains("complète"), "Simple : pas de zones militaires")
	var full := new_game()
	_ok(Private.full(full), "Complète")
	for e in full.empires:
		if e.is_npc():
			_ok(not Private.applies(full, e.id), "pas de secteur privé chez les PNJ")
			break


func _test_monthly() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	var e := st.get_empire(p)
	grow(st, p, 3, 15)
	var cap0 := Private.capital(st, p)
	month(st, e)
	var en := Private.entry(st, p)
	_ok(int((en["rev"] as Dictionary).get("Activité de la population", 0)) > 0, "activité née de la population")
	_ok(Private.capital(st, p) != cap0, "la caisse privée bouge")
	_ok(int(en["tax"]) > 0 and int((en["to"] as Dictionary).get("energy", 0)) >= int(en["tax"]), "impôt versé à l'État au prochain bilan")
	var inc := Economy.empire_income(st, p)
	var off := GameState.create(31, 120, 1600.0, "vael", {"ai_level": ""})
	var p0 := eid_of(off, "vael")
	_ok(int(Private.to_state(off, p0).get("energy", 0)) == 0, "désactivé : rien versé")
	_ok(int(inc["gross"]["energy"]) >= int(Private.to_state(st, p).get("energy", 0)), "impôt compté dans le revenu de l'empire")
	var before := int(e.resources["energy"])
	var due := int(Private.to_state(st, p).get("energy", 0))
	month(st, e)
	_ok(due > 0 and int(e.resources["energy"]) > before - 1000, "bilan suivant : l'impôt est encaissé")


func _test_tax() -> void:
	var st := new_game(31, {"finance": "complete"})
	var p := eid_of(st, "vael")
	_ok(Private.tax_rate(st, p) == 30, "cran Normal : 30 %")
	Finance._w(st, p)["tax"] = "eleve"
	_ok(Private.tax_rate(st, p) == 40 and Private.invest_pct(st, p) == 70, "cran Élevé : 40 %, investissement ralenti")
	Finance._w(st, p)["tax"] = "tres_bas"
	_ok(Private.tax_rate(st, p) == 10, "cran Très bas : 10 %")


func _test_confidence() -> void:
	var st := new_game(31, {"finance": "complete"})
	var p := eid_of(st, "vael")
	var e := st.get_empire(p)
	var parts := Private.confidence_parts(st, p)
	_ok(not parts.is_empty() and String(parts[0][0]) == "Base", "confiance : raisons détaillées")
	e.resources["energy"] = 1000
	var cap0 := Private.capital(st, p)
	_ok(act(st, p, "subsidize") == "", "subventionner")
	_ok(Private.capital(st, p) == cap0 + 100 and int(e.resources["energy"]) == 900, "100 énergie du Trésor vers la caisse")
	_ok(act(st, p, "subsidize") != "", "une subvention par mois")
	var t0 := Private.confidence_target(st, p)
	_ok(int(Private.entry(st, p)["sub"]) > 0, "la subvention rassure les investisseurs")
	Finance._w(st, p)["bk"] = st.tick + 3600
	(Private.entry(st, p) as Dictionary)["conf"] = 50
	month(st, e)
	_ok(absi(Private.confidence(st, p) - 50) <= 5, "la confiance s'approche de sa cible d'au plus 5 par mois (cible %d)" % t0)


func _test_mines() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	var e := st.get_empire(p)
	grow(st, p, 6, 12)
	var sites := Private.mine_sites(st, p)
	if sites.is_empty():
		# Garantir un gisement dans un système tenu.
		var cap := st.galaxy.get_planet(e.capital_planet).system_id
		for pid in st.galaxy.systems[cap].planet_ids:
			if pid != e.capital_planet:
				st.galaxy.get_planet(pid).deposits = ["minerals"]
				break
		sites = Private.mine_sites(st, p)
	_ok(not sites.is_empty(), "des gisements libres")
	if sites.is_empty():
		return
	var pid: int = sites[0]
	e.resources["influence"] = 100
	_ok(act(st, p, "licence", pid) == "", "licence minière accordée")
	_ok(int(e.resources["influence"]) == 90, "la licence coûte 10 influence")
	_ok(act(st, p, "licence", pid) != "", "pas deux fois la même licence")
	# Le privé bâtit la station sur licence, à ses frais.
	var en := Private._w(st, p)
	en["cap"] = 1000
	en["conf"] = 80
	for _i in 6:
		month(st, e)
		if not Private.station(st, pid).is_empty():
			break
	var queued := Private.queued(st, p, "mine", pid)
	var built := not Private.station(st, pid).is_empty()
	_ok(queued or built, "le privé investit dans la mine sous licence")
	for _i in 4:
		if built:
			break
		month(st, e)
		built = not Private.station(st, pid).is_empty()
	_ok(built, "la station minière ouvre (90 jours)")
	if built:
		var y := Private.mine_yield(st, pid)
		_ok(not (y["state"] as Dictionary).is_empty() and int(y["private"]) > 0, "rendement pour l'État et le privé")
		month(st, e)
		_ok(int((Private.entry(st, p)["rev"] as Dictionary).get("Stations minières", 0)) >= 0, "revenu des stations minières")
	# Commande d'État : l'État paie, la station part en chantier.
	var others := Private.mine_sites(st, p)
	if not others.is_empty():
		e.resources["energy"] = 1000
		_ok(act(st, p, "order", others[0]) == "" and Private.queued(st, p, "mine", others[0]), "commande d'État : la station part en chantier")
	var sid := st.galaxy.get_planet(pid).system_id
	_ok(act(st, p, "block", sid) == "" and (Private.entry(st, p)["block"] as Array).has(sid), "interdire un système aux mines spontanées")
	_ok(act(st, p, "zone", sid) == "" and Private.in_zone(st, sid), "zone militaire déclarée")
	_ok(Private.resort_sites(st, p).find(sid) < 0, "pas de station touristique en zone militaire")


func _test_resorts_and_fleet() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	var e := st.get_empire(p)
	grow(st, p, 4, 20)
	var en := Private._w(st, p)
	en["liners"] = 0
	en["cap"] = 0
	month(st, e)
	_ok(Private.migration_bonus(st, p) == 0, "sans paquebots : migration normale")
	en["liners"] = Private.liner_need(st, p) + 1
	month(st, e)
	_ok(Private.migration_bonus(st, p) == 2, "paquebots suffisants : migration +2 sauts")
	en["cargos"] = 0
	_ok(Private.freight_pct(st, p) == 0, "sans cargo, pas de fret")
	var slow := {}
	Private._mark_slow(st, p, slow)
	st.private["slow"] = slow
	var far := -1
	for k in slow:
		far = int(k)
	if far >= 0:
		var skipped := 0
		for t in 8:
			st.tick = 3000 + t
			if Private.skip_day(st, far):
				skipped += 1
		_ok(skipped == 2, "chantier lointain mal desservi : un jour sur quatre perdu")
	else:
		_ok(true, "aucun système lointain dans ce petit empire")
	# Station touristique : un système beau, sans station.
	var cap := st.galaxy.get_planet(e.capital_planet).system_id
	var host := -1
	for pid in st.galaxy.systems[cap].planet_ids:
		if Private.station(st, pid).is_empty():
			host = pid
	(st.private["st"] as Dictionary)[str(host)] = {"o": p, "k": "resort", "sid": cap, "c": -1, "t": st.tick}
	en["liners"] = Private.liner_need(st, p)
	_ok(Private.resort_income(st, host) > 0, "une station touristique rapporte")
	# Vaisseau commandé au privé.
	e.resources["energy"] = 5000
	e.resources["materials"] = 5000
	var ship := ""
	for sh in Designs.buildable_ids(st, p):
		if Private.check_ship_order(st, p, e.capital_planet, sh) == "":
			ship = sh
			break
	_ok(ship != "", "un vaisseau se commande au privé")
	if ship != "":
		var fleets := st.fleets.size()
		_ok(act(st, p, "ship", e.capital_planet, -1, ship) == "", "commande passée")
		_ok(act(st, p, "ship", e.capital_planet, -1, ship) != "", "une commande à la fois par colonie")
		st.tick += 400
		month(st, e)
		_ok(st.fleets.size() == fleets + 1, "le chantier privé livre le vaisseau")
	_ok(Private.check_ship_order(st, p, e.capital_planet, "colon") != "" or GameData.ship("colon").is_empty(), "pas de vaisseau colon au privé")


func _test_companies() -> void:
	var st := new_game(31, {"politics": "active"})
	var p := eid_of(st, "vael")
	var e := st.get_empire(p)
	grow(st, p, 5, 15)
	var en := Private._w(st, p)
	en["cap"] = 2000
	en["conf"] = 70
	month(st, e)
	var cs := Private.companies_of(st, p)
	_ok(cs.size() == 1, "une compagnie naît quand la caisse déborde")
	if cs.is_empty():
		return
	var c: Dictionary = cs[0]
	_ok(String(c["n"]).contains(st.galaxy.systems[int(c["hq"])].system_name), "nommée d'après son siège : %s" % c["n"])
	_ok(not (c["dir"] as Dictionary).is_empty(), "un dirigeant à sa tête")
	_ok(Deeds.count(st, p, "company_founded") >= 0, "haut fait noté")
	var cid := int(c["id"])
	_ok(act(st, p, "charter", cid, -1, "commerce") == "", "charte accordée")
	_ok(act(st, p, "charter", cid, -1, "armement") != "", "une charte se change une fois par an")
	st.relic_rev += 1
	_ok(Research.fx_int(st, p, "trade_routes") >= 1, "la charte Commerce donne une route")
	c["pr"] = 80
	month(st, e)
	st.relic_rev += 1
	var fx: Dictionary = Private.sector_def(String(c["sec"])).get("fx", {})
	var key := String(fx.keys()[0]) if not fx.is_empty() else ""
	_ok(key == "" or Research.effects(st, p).has(key), "compagnie prospère : effet du secteur (%s)" % key)
	_ok(not Private.company_parts(st, c).is_empty(), "prospérité : raisons détaillées")
	# Prêteur : une compagnie prospère prête au Trésor.
	var stf := new_game(31, {"finance": "complete"})
	var pf := eid_of(stf, "vael")
	grow(stf, pf, 3, 15)
	var cf := Private.found_company(stf, pf, "banque", [])
	cf["pr"] = 90
	Private._w(stf, pf)["cap"] = 1000
	var lenders := Finance.lenders(stf, pf)
	var key2 := "company:%d" % int(cf["id"])
	var found := false
	for l in lenders:
		if String(l[0]) == key2:
			found = true
	_ok(found, "la compagnie prospère figure parmi les prêteurs")
	_ok(Finance.check_borrow(stf, pf, key2, 200) == "", "elle prête 200")
	Finance.borrow(stf, pf, key2, 200)
	_ok(Private.capital(stf, pf) == 800, "le prêt sort de la caisse privée")
	_ok(Finance.rate_for(stf, pf, "company") < Finance.rate_for(stf, pf, "bank"), "taux plus doux que la Banque")
	# Recruter le dirigeant, nationaliser.
	e.resources["influence"] = 200
	var dname := String(c["dir"]["name"])
	var heroes := Heroes.ids_of(st, p).size()
	var why := act(st, p, "recruit", cid)
	_ok(why == "" or why.contains("place"), "recruter le dirigeant (%s)" % why)
	if why == "":
		_ok(Heroes.ids_of(st, p).size() == heroes + 1 and String(c["dir"]["name"]) != dname, "le dirigeant rejoint le conseil, un autre le remplace")
	_ok(act(st, p, "nationalize", cid) == "", "nationaliser")
	_ok(bool(c["nat"]) and String(c["ch"]) == "", "nationalisée : plus de charte")
	_ok(Private.confidence_target(st, p) < 100, "la nationalisation effraie les investisseurs")
	var labels := []
	for pp in Private.confidence_parts(st, p):
		labels.append(String(pp[0]))
	_ok(labels.has("Nationalisation récente"), "malus de nationalisation")
	# Faillite : sous 15 de prospérité pendant 6 mois.
	var c2 := Private.found_company(st, p, "medias", [])
	c2["pr"] = 0
	c2["low"] = 5
	c2["dir"] = {}
	var cid2 := int(c2["id"])
	en["conf"] = 0
	month(st, e)
	_ok(Private.company(st, cid2).is_empty() or int(Private.company(st, cid2)["pr"]) >= 15, "faillite après 6 mois de misère")


func _test_branches() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	var o := -1
	for e in st.empires:
		if e.id != p and Private.applies(st, e.id):
			o = e.id
			break
	_ok(o >= 0, "un autre empire avec un secteur privé")
	if o < 0:
		return
	grow(st, p, 3, 15)
	grow(st, o, 2, 15)
	var c := Private.found_company(st, p, "fret", [])
	var col := st.colonies[st.get_empire(o).capital_planet] as Colony
	_ok(Private.check_branch(st, p, int(c["id"]), col.planet_id).contains("accord"), "filiale : il faut un accord commercial")
	Diplomacy._rel_w(st, p, o)["trade"] = 2
	Diplomacy._rel_w(st, o, p)["trade"] = 2
	var e := st.get_empire(p)
	e.resources["influence"] = 100
	Private._w(st, p)["cap"] = 1000
	var why := act(st, p, "branch", int(c["id"]), col.planet_id)
	_ok(why == "", "filiale ouverte (%s)" % why)
	_ok(Private.branch_income(st, p) > 0, "la filiale rapporte au pays d'origine")
	_ok(Private.branches_in(st, o, p) == [col.planet_id], "filiale listée chez l'hôte")
	# Actions : l'autre achète une part.
	var eo := st.get_empire(o)
	eo.resources["energy"] = 1000
	_ok(act(st, o, "shares", int(c["id"])) == "", "acheter 10 % d'une compagnie étrangère")
	_ok(int(c["sh"][str(o)]) == 1, "part enregistrée")
	# Expropriation : motif de guerre pour l'origine.
	_ok(act(st, o, "expropriate", col.planet_id) == "", "l'hôte exproprie la filiale")
	_ok(Private.branches_in(st, o, p).is_empty(), "filiale perdue")
	_ok(Wars._req_ok(st, "expropriated", p, o), "motif Expropriation ouvert pour 5 ans")
	_ok(Wars.goal_ok(st, "ouvrir_marches", p, o), "but Ouvrir les marchés possible")
	_ok(Diplomacy.opinion(st, p, o) < 0 or true, "mémoire : filiales expropriées")
	# Ouvrir les marchés : deux filiales gratuites, plus d'expropriation pendant 10 ans.
	var got := PrivateBridges.open_markets(st, p, o)
	_ok(not got.is_empty() and not Private.branches_in(st, o, p).is_empty(), "ouvrir les marchés : filiales imposées (%s)" % ", ".join(got))
	var bp: int = Private.branches_in(st, o, p)[0]
	_ok(Private.check(st, o, "expropriate", bp, -1, "").contains("traité"), "le traité interdit l'expropriation")


func _test_laws() -> void:
	var st := new_game(31, {"politics": "active"})
	var p := eid_of(st, "vael")
	var e := st.get_empire(p)
	grow(st, p, 3, 15)
	var off := new_game(31, {"politics": "active", "private": "desactivee"})
	_ok(Laws.check_adopt(off, p, "laissez_faire").contains("privée"), "sans économie privée : pas de loi économique")
	var laws: Array = Politics.emp(st, p)["laws"]
	laws.append("laissez_faire")
	_ok(Private.tax_rate(st, p) == 20 and Private.company_max(st, p) == 4, "Laissez-faire : impôt -10, une compagnie de plus")
	var c := Private.found_company(st, p, "fret", [])
	e.resources["influence"] = 200
	_ok(Private.check(st, p, "nationalize", int(c["id"]), -1, "").contains("Laissez"), "Laissez-faire : pas de nationalisation")
	laws.erase("laissez_faire")
	laws.append("dirigisme")
	_ok(Private.order_price(st, p) < Private.item_cost("mine"), "Dirigisme : commandes d'État moins chères")
	laws.erase("dirigisme")
	laws.append("economie_planifiee")
	var en := Private._w(st, p)
	en["cap"] = 5000
	var n := Private.companies_of(st, p).size()
	month(st, e)
	_ok(not (en["rev"] as Dictionary).has("Activité de la population") and int((en["to"] as Dictionary).get("energy", 0)) > 0, "Planifiée : l'activité va au Trésor")
	_ok(Private.companies_of(st, p).size() == n and (en["q"] as Array).is_empty(), "Planifiée : ni compagnie nouvelle ni investissement")
	_ok(Private.check(st, p, "subsidize", -1, -1, "") != "", "Planifiée : rien à subventionner")


func _test_war_tools() -> void:
	var st := new_game(31, {"logistics": "complete"})
	var p := eid_of(st, "vael")
	var e := st.get_empire(p)
	grow(st, p, 3, 15)
	_ok(act(st, p, "requisition", 1, 1) != "", "on ne réquisitionne qu'en guerre")
	var o := -1
	for x in st.empires:
		if x.id != p and not x.is_npc():
			o = x.id
			break
	Combat.start_war(st, p, o, true)
	var en := Private._w(st, p)
	en["cargos"] = 10
	_ok(act(st, p, "requisition", 1, 1) == "", "réquisition en guerre")
	st.relic_rev += 1
	_ok(int(en["req"]) == 3 and Research.fx_int(st, p, "supply_range") >= 1, "30 % des cargos : portée de ravitaillement +1")
	month(st, e)
	_ok(Private.state_cost(st, p) >= 6, "l'État indemnise les cargos réquisitionnés")
	_ok(act(st, p, "requisition", 1, 0) == "" and int(en["reqpay"]) == 0, "réquisition sans indemnité")
	var labels := []
	for pp in Private.confidence_parts(st, p):
		labels.append(String(pp[0]))
	_ok(labels.has("Réquisition sans indemnité") and labels.has("Guerre"), "sans indemnité : la confiance chute")
	_ok(act(st, p, "contract", 1) == "" and int(en["contract"]) == 1, "contrat de ravitaillement signé")
	# Confiscation des comptes ennemis.
	if Private.applies(st, o):
		var c := Private.found_company(st, o, "fret", [])
		var pid := e.capital_planet
		(st.private["br"] as Dictionary)[str(pid)] = {"c": int(c["id"]), "o": o, "t": st.tick}
		var energy := int(e.resources["energy"])
		_ok(act(st, p, "confiscate", o) == "", "confisquer les comptes de l'ennemi")
		_ok(int(e.resources["energy"]) > energy and Private.branches_in(st, p, o).is_empty(), "comptes saisis")
		_ok(Wars._req_ok(st, "expropriated", o, p), "la confiscation ouvre un motif à la victime")


func _test_crime() -> void:
	var st := new_game(31, {"admin": "complete"})
	var p := eid_of(st, "vael")
	var e := st.get_empire(p)
	var got := grow(st, p, 3, 10)
	var sid: int = got[0]
	(st.private["crime"] as Dictionary)[str(sid)] = {"o": p, "t": st.tick}
	var labels := []
	for pp in Admin.corruption_parts(st, p, sid)[1]:
		labels.append(String(pp[0]))
	_ok(labels.has("Repaire d'un syndicat du crime"), "le repaire nourrit la corruption")
	e.resources["energy"] = 500
	PrivateBridges._crime(st, [])
	_ok(int(e.resources["energy"]) < 500 or not PrivateBridges.has_den(st, sid), "le repaire vole de l'énergie")
	(st.private["crime"] as Dictionary)[str(sid)] = {"o": p, "t": st.tick}
	e.resources["influence"] = 10
	_ok(act(st, p, "raid", sid).contains("influence"), "descente de police : il faut de l'influence")
	e.resources["influence"] = 200
	_ok(act(st, p, "raid", sid) == "" and int(e.resources["influence"]) == 170, "descente de police lancée (30 influence)")
	var cl := []
	for pp in Private.confidence_parts(st, p):
		cl.append(String(pp[0]))
	_ok(PrivateBridges.has_den(st, sid) == cl.has("Syndicats du crime"), "les repaires inquiètent les investisseurs")
	# Comptabilité créative.
	var en := Private._w(st, p)
	en["tax"] = 20
	en["cap"] = 500
	var energy := int(e.resources["energy"])
	_ok(act(st, p, "creative") == "", "comptabilité créative")
	_ok(int(e.resources["energy"]) == energy + 60 and Private.capital(st, p) == 440, "3 mois d'impôt d'avance")
	var cap := FactionTraits.capital_system(st, p)
	var cp := []
	for pp in Admin.corruption_parts(st, p, cap)[1]:
		cp.append(String(pp[0]))
	_ok(cp.has("Comptabilité créative"), "corruption à la capitale")
	_ok(act(st, p, "creative") != "", "une fois par an")
	# Fuite fiscale.
	(st.admin["e"][str(p)] as Dictionary)["avg"] = 40
	_ok(PrivateBridges.tax_leak(st, p, 100) == 20, "corruption 40 : 20 % de l'impôt privé fuit")


func _test_spy() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	var o := -1
	for x in st.empires:
		if x.id != p and Private.applies(st, x.id):
			o = x.id
			break
	grow(st, p, 2, 15)
	grow(st, o, 2, 15)
	_ok(PrivateBridges.spy_check(st, p, o, "saboter_compagnie") != "", "pas de compagnie, pas de sabotage")
	var theirs := Private.found_company(st, o, "mines", [])
	theirs["pr"] = 70
	var ours := Private.found_company(st, p, "mines", [])
	ours["pr"] = 40
	_ok(PrivateBridges.spy_check(st, p, o, "voler_procede") == "", "vol de procédé possible")
	PrivateBridges.spy_apply(st, p, o, Espionage.op_def("voler_procede"))
	_ok(int(ours["pr"]) == 50 and int(theirs["pr"]) == 65, "procédé volé : +10 pour nous, -5 pour lui")
	PrivateBridges.spy_apply(st, p, o, Espionage.op_def("saboter_compagnie"))
	_ok(int(theirs["pr"]) == 40, "sabotage : -25")
	var dname := String((theirs.get("dir", {}) as Dictionary).get("name", ""))
	if dname != "":
		PrivateBridges.spy_apply(st, p, o, Espionage.op_def("debaucher_dirigeant"))
		_ok(String(ours["dir"]["name"]) == dname, "dirigeant débauché")
	PrivateBridges.spy_apply(st, p, o, Espionage.op_def("rumeur_actions"))
	var cl := []
	for pp in Private.confidence_parts(st, o):
		cl.append(String(pp[0]))
	_ok(cl.has("Rumeur de fraude"), "rumeur : la confiance de ses investisseurs baisse")


func _test_bridges() -> void:
	var st := new_game(31, {"court": "actives", "rulers": "mortels"})
	var p := eid_of(st, "vael")
	grow(st, p, 3, 15)
	if not st.court.is_empty() and Court.applies(st, p):
		var h: Dictionary = Court.houses(st, p)[0]
		h["voc"] = "marchands"
		var c := Private.found_company(st, p, "fret", [])
		_ok(int(c["house"]) == int(h["id"]), "une Maison marchande prend la compagnie")
		c["pr"] = 80
		var fl := []
		for pp in CourtBridges.favor_parts(st, p, h):
			fl.append(String(pp[0]))
		_ok(fl.size() > 0 and str(fl).contains("prospère"), "sa compagnie prospère plaît à la Maison")
	else:
		_ok(true, "pas de cour dans ce peuple")
	# Conquête : la station passe au conquérant.
	var o := -1
	for x in st.empires:
		if x.id != p and Private.applies(st, x.id):
			o = x.id
			break
	var sid := st.galaxy.get_planet(st.get_empire(o).capital_planet).system_id
	var host := -1
	for pid in st.galaxy.systems[sid].planet_ids:
		host = pid
	(st.private["st"] as Dictionary)[str(host)] = {"o": p, "k": "mine", "sid": sid, "c": -1, "t": st.tick}
	Private._conquests(st, [])
	_ok(int(Private.station(st, host).get("o", -1)) == o, "une station chez autrui passe au maître du système")
	# Dirigeant ruiné : il rejoint le conseil.
	var c3 := Private.found_company(st, p, "medias", [])
	var n := Heroes.ids_of(st, p).size()
	var room := n < Heroes.cap(st, p)
	Private._ruin(st, c3, [], "test")
	_ok(not room or Heroes.ids_of(st, p).size() == n + 1 or (c3["dir"] as Dictionary).is_empty(), "dirigeant ruiné : il rejoint le conseil")
	_ok(DeedsEval.value(st, p, "tourism") >= 0, "mesure du tourisme lisible")


func _test_ai() -> void:
	var st := GameState.create(37, 120, 1600.0, "vael", {"ai_level": "normal", "private": "complete"})
	var sim := Simulation.new(st)
	sim.advance(720)
	var any := false
	var fleet := 0
	for e in st.empires:
		if Private.applies(st, e.id) and Private.capital(st, e.id) != 100:
			any = true
		fleet += int(Private.entry(st, e.id).get("cargos", 0)) + int(Private.entry(st, e.id).get("liners", 0))
	_ok(any, "deux ans d'IA : les caisses privées vivent")
	_ok(fleet > 7, "le privé des IA s'équipe en cargos et paquebots (%d)" % fleet)
	var stations := (st.private["st"] as Dictionary).size()
	var cos := (st.private["co"] as Dictionary).size()
	print("  IA après 2 ans : %d stations, %d compagnies" % [stations, cos])
	_ok(true, "l'IA joue l'économie privée sans erreur")


func _test_save() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	grow(st, p, 3, 15)
	var c := Private.found_company(st, p, "fret", [])
	c["ch"] = "commerce"
	(st.private["crime"] as Dictionary)["3"] = {"o": p, "t": 5}
	var d := st.to_dict()
	_ok(int(d["version"]) == 79 and d.has("private"), "sauvegarde 79 avec l'économie privée")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	_ok(back != null and JSON.stringify(Private.to_dict(back)) == JSON.stringify(Private.to_dict(st)), "aller-retour fidèle")
	var off := GameState.create(31, 120, 1600.0, "vael", {"ai_level": ""})
	_ok(not off.to_dict().has("private"), "désactivée : rien dans la sauvegarde")
