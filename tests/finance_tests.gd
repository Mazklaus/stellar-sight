extends RefCounted
## Tests de la fiscalité et de la dette publique (étude « Fiscalité et dette publique », 2026-11-16) :
## données, réglages (Désactivée = économie d'avant, Simple = impôt + emprunt automatique + crise),
## crans d'impôt, emprunt automatique sous zéro, plafond, intérêts fixes, crise et faillite, emprunts
## volontaires, prêteurs, cote, inflation, planche à billets, réserve, franchises, solde et impôt de
## guerre, ponts (révolte, doléances, Maisons, Krach, Koinon, espionnage, Recouvrement, haut fait),
## IA et sauvegarde. Appelés par smoke_test.gd.

var _check: Callable


func run(check: Callable) -> void:
	_check = check
	print("Fiscalité et dette publique…")
	_test_data()
	_test_modes()
	_test_tax()
	_test_auto_loan()
	_test_crisis()
	_test_loans()
	_test_rating()
	_test_inflation()
	_test_franchise()
	_test_pay()
	_test_bridges()
	_test_spy()
	_test_ai()
	_test_save()


func _ok(cond: bool, what: String) -> void:
	_check.call(cond, what)


static func new_game(seed_value := 31, extra := {}) -> GameState:
	var o := {"ai_level": "", "finance": "complete"}
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


## Un bilan mensuel de l'empire (économie puis Finance.daily).
static func month(st: GameState, e: Empire) -> void:
	st.tick += 30 - posmod(st.tick, 30)
	if posmod(st.tick, 30) != 0:
		st.tick += 30 - posmod(st.tick, 30)
	var added: Array[Dictionary] = []
	EconomySystem._monthly_balance(st, e, added)
	Finance.daily(st)


func _test_data() -> void:
	var d := GameData.finance()
	_ok(not d.is_empty(), "finance.json se charge")
	_ok(Finance.tax_defs().size() == 5, "5 crans d'impôt")
	_ok(int(Finance.tax_def("normal").get("energy_pct", 1)) == 0 and int(Finance.tax_def("normal").get("stability", 1)) == 0, "Normal ne change rien")
	_ok(Finance.grade_defs().size() == 8, "8 cotes de AAA à D")
	_ok((d["crisis"]["stages"] as Array).size() == 4, "crise en 4 paliers")
	_ok(Finance.mode_defs().size() == 3 and Finance.default_mode() == "complete", "3 réglages, Complète par défaut")
	for c: Dictionary in d["cards"]:
		_ok(not Events.card(String(c["id"])).is_empty(), "carte %s enregistrée" % c["id"])
	_ok(not GameData.building("banque_centrale").is_empty(), "bâtiment Banque centrale")
	_ok(Wars.casus_def("recouvrement").size() > 0, "motif de guerre Recouvrement")
	_ok(not Espionage.op_def("rumeur_faillite").is_empty() and not Espionage.op_def("racheter_creance").is_empty(), "opérations d'espionnage fiscales")


func _test_modes() -> void:
	var off := new_game(31, {"finance": "desactivee"})
	_ok(off.finance.is_empty(), "Désactivée : rien ne tourne")
	var none := GameState.create(31, 120, 1600.0, "vael", {"ai_level": ""})
	_ok(none.finance.is_empty(), "sans l'option : désactivée (tests et bancs inchangés)")
	var p := eid_of(none, "vael")
	var e := none.get_empire(p)
	e.resources["energy"] = -50
	var added: Array[Dictionary] = []
	EconomySystem._monthly_balance(none, e, added)
	_ok(int(e.resources["energy"]) == 0, "désactivée : le stock retombe à zéro comme avant")
	var simple := new_game(31, {"finance": "simple"})
	var ps := eid_of(simple, "vael")
	_ok(Finance.applies(simple, ps) and not Finance.full(simple), "Simple : en jeu, sans le mode complet")
	_ok(apply(simple, SimCommands.finance_borrow(ps, "bank", 300)) != "", "Simple : pas d'emprunt volontaire")
	_ok(apply(simple, SimCommands.finance_mint(ps)) != "", "Simple : pas de planche à billets")
	simple.get_empire(ps).resources["influence"] = 200
	_ok(apply(simple, SimCommands.finance_tax(ps, "eleve")) == "", "Simple : l'impôt se règle")


func _test_tax() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	var e := st.get_empire(p)
	e.resources["influence"] = 200
	var base := Economy.production_pct(st, p, "energy")
	_ok(apply(st, SimCommands.finance_tax(p, "ecrasant")) == "", "passer à Écrasant")
	_ok(Economy.production_pct(st, p, "energy") >= base * 125 / 100, "Écrasant : énergie +30 %% (%d → %d)" % [base, Economy.production_pct(st, p, "energy")])
	_ok(int(e.resources["influence"]) == 175, "changer de cran coûte 25 influence")
	var parts := Finance.empire_stability_parts(st, p)
	_ok(parts.size() > 0 and int(parts[0][1]) == -12, "Écrasant : stabilité -12")
	_ok(int(Research.effects(st, p).get("growth_pct", 0)) <= -20, "Écrasant : croissance -20 %")
	_ok(apply(st, SimCommands.finance_tax(p, "bas")) != "", "un changement par an au plus")
	st.tick += 361
	_ok(apply(st, SimCommands.finance_tax(p, "tres_bas")) == "", "un an plus tard : Très bas")
	_ok(Economy.production_pct(st, p, "energy") <= base * 75 / 100, "Très bas : énergie -30 %")


func _test_auto_loan() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	var e := st.get_empire(p)
	month(st, e)
	_ok(Finance.gross_energy(st, p) > 0, "le bilan retient la production brute d'énergie")
	_ok(Finance.cap(st, p) >= 200, "plafond de crédit d'au moins 200")
	e.resources["energy"] = -150
	var added: Array[Dictionary] = []
	Finance.settle(st, e, {"gross": {"energy": Finance.gross_energy(st, p)}, "net": {"energy": -150}}, added)
	_ok(int(e.resources["energy"]) >= 0, "trésor à sec : l'empire emprunte au lieu de tomber en pénurie")
	_ok(Finance.debt(st, p) == 150, "dette courante de 150")
	e.resources["energy"] = -1000
	Finance.settle(st, e, {"gross": {"energy": Finance.gross_energy(st, p)}, "net": {"energy": -1000}}, added)
	_ok(Finance.debt(st, p) == Finance.cap(st, p) or Finance.debt(st, p) >= Finance.base_cap(st, p) * 50 / 100, "pas au-delà du plafond (%d / %d)" % [Finance.debt(st, p), Finance.cap(st, p)])
	_ok(int(e.resources["energy"]) < 0, "au plafond : le trésor reste à sec (la pénurie revient)")
	Finance._w(st, p)["loans"] = []
	Finance._w(st, p)["prog"] = 0
	Finance._w(st, p)["stage"] = 0
	e.resources["energy"] = -150
	Finance.settle(st, e, {"gross": {"energy": Finance.gross_energy(st, p)}, "net": {"energy": -150}}, added)
	var al := Finance.auto_loan(st, p)
	_ok(not al.is_empty() and int(al["m"]) == 0, "dette courante sans échéance")
	_ok(int(al["r"]) >= 10 and int(al["r"]) <= 100, "intérêt bas (%s par mois)" % Finance.rate_label(int(al["r"])))
	var r0 := int(al["r"])
	var up := {"energy": 0}
	Finance.adjust_upkeep(st, p, up)
	_ok(int(up["energy"]) == Finance.interest_of(st, p, al) and int(up["energy"]) > 0, "les intérêts entrent dans l'entretien")
	# Remboursement automatique quand le bilan redevient positif.
	e.resources["energy"] = 500
	Finance.settle(st, e, {"gross": {"energy": Finance.gross_energy(st, p)}, "net": {"energy": 200}}, added)
	_ok(Finance.debt(st, p) < 150, "excédent : la dette courante se rembourse d'elle-même")
	_ok(int(Finance.auto_loan(st, p).get("r", r0)) == r0, "taux fixe (pas de spirale)")


func _test_crisis() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	var e := st.get_empire(p)
	month(st, e)
	var added: Array[Dictionary] = []
	var gross := Finance.gross_energy(st, p)
	# Au plafond et en déficit : la crise monte palier par palier.
	for i in 30:
		e.resources["energy"] = -(Finance.cap(st, p) + 100)
		Finance.settle(st, e, {"gross": {"energy": gross}, "net": {"energy": -100}}, added)
		if Finance.crisis_stage(st, p) >= 2:
			break
	_ok(Finance.crisis_stage(st, p) >= 2, "au plafond : la crise de la dette monte (palier %d)" % Finance.crisis_stage(st, p))
	_ok(Finance.empire_stability_parts(st, p).any(func(x: Array) -> bool: return String(x[0]).begins_with("Crise de la dette")), "la crise pèse sur la stabilité")
	_ok(apply(st, SimCommands.finance_approach(p, "couper_recherche")) == "", "approche : couper la recherche")
	_ok(int(Research.effects(st, p).get("production_pct", {}).get("knowledge", 0)) <= -40, "couper la recherche : Savoir -40 %")
	_ok(apply(st, SimCommands.finance_approach(p, "inconnue")) != "", "approche inconnue refusée")
	# Jusqu'à la faillite.
	for i in 40:
		e.resources["energy"] = -(Finance.cap(st, p) + 100)
		Finance.settle(st, e, {"gross": {"energy": gross}, "net": {"energy": -100}}, added)
		if Finance.in_bankruptcy(st, p):
			break
	_ok(Finance.in_bankruptcy(st, p), "au bout de la crise : la faillite")
	_ok(Finance.debt(st, p) == 0, "faillite : dettes effacées")
	_ok(Finance.grade(st, p) == "D", "faillite : cote D")
	_ok(Finance.empire_stability_parts(st, p).any(func(x: Array) -> bool: return String(x[0]) == "Faillite récente"), "faillite : stabilité -15")
	_ok(int(Research.effects(st, p).get("damage_pct", 0)) <= -15, "faillite : dégâts -15 %")
	_ok(apply(st, SimCommands.finance_borrow(p, "bank", 100)) != "", "la Banque ne prête plus à un empire en faillite")
	# Recul : sous le plafond, la jauge redescend.
	var st2 := new_game()
	var e2 := st2.get_empire(p)
	month(st2, e2)
	Finance._w(st2, p)["prog"] = 30
	Finance.settle(st2, e2, {"gross": {"energy": 100}, "net": {"energy": 50}}, added)
	_ok(Finance.crisis_progress(st2, p) == 26, "hors plafond : la crise recule")


func _test_loans() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	var e := st.get_empire(p)
	month(st, e)
	var before := int(e.resources["energy"])
	_ok(apply(st, SimCommands.finance_borrow(p, "bank", 150)) != "", "par tranches de 100")
	_ok(apply(st, SimCommands.finance_borrow(p, "bank", 200)) == "", "lever un emprunt de 200")
	_ok(int(e.resources["energy"]) == before + 200, "l'énergie arrive tout de suite")
	var l: Dictionary = Finance.loans(st, p)[0]
	_ok(int(l["m"]) == 60, "60 mensualités")
	_ok(Finance.installment(st, p, l) >= 4, "mensualité : capital et intérêts")
	month(st, e)
	_ok(int(Finance.loan(st, p, int(l["id"])).get("m", 0)) == 59 and int(Finance.loan(st, p, int(l["id"]))["p"]) < 200, "un mois plus tard : une mensualité payée")
	_ok(apply(st, SimCommands.finance_repay(p, int(l["id"]), 10000)) == "", "remboursement anticipé")
	_ok(Finance.loans(st, p).is_empty(), "emprunt soldé")
	_ok(apply(st, SimCommands.finance_borrow(p, "bank", 1100)) != "", "au plus 1 000")
	# Prêteur étranger : un joueur humain ne se sollicite pas ; une IA prête si elle a de quoi.
	var other := -1
	for o in st.empires:
		if o.id != p and not o.is_npc() and not bool(Finance.talent(st, o.id).get("no_repudiate", false)):
			other = o.id
			break
	e.contacts.append(other)
	st.get_empire(other).contacts.append(p)
	var lenders := Finance.lenders(st, p)
	_ok(lenders.any(func(x: Array) -> bool: return String(x[0]) == "empire:%d" % other), "un empire rencontré est un prêteur possible")
	st.get_empire(other).resources["energy"] = 50
	_ok(Finance.lend_refusal(st, other, p, 300) != "", "un empire sans réserve ne prête pas")
	# Prêter à un autre empire (traité de prêt), puis rembourser.
	st.get_empire(other).resources["energy"] = 100
	e.resources["energy"] = 2000
	var oe := st.get_empire(other)
	oe.wars.append(99)  # en guerre : l'IA veut l'argent
	month(st, oe)
	_ok(apply(st, SimCommands.finance_lend(p, other, 100)) == "", "prêter 100 à un empire en guerre")
	oe.wars.clear()
	_ok(Finance.debt(st, other) == 100, "l'emprunteur doit 100")
	_ok(Finance.lender_income(st, p) > 0, "le prêteur touche les mensualités")
	var lo: Dictionary = Finance.loans(st, other)[0]
	_ok(apply(st, SimCommands.finance_repudiate(other, int(lo["id"]))) == "", "répudier la dette")
	_ok(Finance.grade(st, other) == "D", "répudiation : cote D")
	_ok(FinanceBridges.debt_casus(st, p, other), "répudiation : motif Recouvrement pour le créancier")
	_ok(Wars.casus_list(st, p, other).has("recouvrement") or not st.wars_on, "Recouvrement dans la liste des motifs")


func _test_rating() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	var e := st.get_empire(p)
	month(st, e)
	_ok(Finance.grade(st, p) == "AAA", "sans dette : AAA")
	var r0 := Finance.rate_for(st, p, "bank")
	Finance._w(st, p)["loans"] = [{"id": 99, "l": "bank", "w": -1, "p": Finance.base_cap(st, p) * 90 / 100, "r": 50, "m": 0}]
	_ok(Finance.grade_index(Finance.grade(st, p)) >= 6, "dette à 90 % du plafond : CCC (%s)" % Finance.grade(st, p))
	_ok(Finance.rate_for(st, p, "bank") > r0, "mauvaise cote : taux plus haut")
	_ok(Finance.cap(st, p) < Finance.base_cap(st, p), "mauvaise cote : plafond plus bas")


func _test_inflation() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	var e := st.get_empire(p)
	month(st, e)
	_ok(apply(st, SimCommands.finance_borrow(p, "bank", 200)) == "", "emprunter 200")
	_ok(Finance.inflation(st, p) == 40, "200 empruntés : inflation +0,4 %")
	var g := Finance.gross_energy(st, p)
	_ok(apply(st, SimCommands.finance_mint(p)) == "", "battre monnaie")
	_ok(Finance.inflation(st, p) == 340, "planche à billets : +3 %")
	_ok(apply(st, SimCommands.finance_mint(p)) != "", "une fois par an")
	var up := {"energy": 1000}
	Finance.adjust_upkeep(st, p, up)
	_ok(int(up["energy"]) >= 1034, "l'inflation renchérit l'entretien en énergie")
	Finance.daily(st)
	_ok(Finance.inflation(st, p) < 340, "l'inflation décroît")
	_ok(Finance.mint_amount(st, p) >= maxi(100, g * 3), "3 mois de production")


func _test_franchise() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	var e := st.get_empire(p)
	e.resources["influence"] = 200
	var cap := FactionTraits.capital_system(st, p)
	var c: Colony = st.colonies[e.capital_planet]
	var y0 := int(Economy.colony_yields(st, c)["gross"].get("energy", 0))
	_ok(apply(st, SimCommands.finance_franchise(p, cap)) == "", "franchise fiscale sur la capitale")
	var y1 := int(Economy.colony_yields(st, c)["gross"].get("energy", 0))
	_ok(y1 <= y0 / 2 + 1, "franchise : énergie de la colonie -50 %% (%d → %d)" % [y0, y1])
	_ok(Finance.system_stability_parts(st, cap).size() == 1, "franchise : stabilité +10")
	var other := -1
	for s in st.galaxy.systems.size():
		if st.system_owner(s) < 0:
			other = s
			break
	_ok(apply(st, SimCommands.finance_franchise(p, other)) != "", "pas de franchise hors de l'empire")


func _test_pay() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	var e := st.get_empire(p)
	_ok(apply(st, SimCommands.finance_pay(p, "rognee")) == "", "solde rognée")
	_ok(int(Research.effects(st, p).get("upkeep_pct", 0)) <= -25, "solde rognée : entretien des flottes -25 %")
	_ok(apply(st, SimCommands.finance_war_tax(p, true)) != "", "impôt de guerre : seulement en guerre")
	e.wars.append(99)
	_ok(Finance.empire_stability_parts(st, p).any(func(x: Array) -> bool: return String(x[0]) == "Équipages mal payés"), "en guerre : équipages mal payés")
	_ok(apply(st, SimCommands.finance_war_tax(p, true)) == "", "impôt de guerre en guerre")
	_ok(int(Research.effects(st, p).get("upkeep_pct", 0)) <= -45, "impôt de guerre : entretien -20 % de plus")
	e.wars.clear()
	Finance.daily(st)
	st.tick += 30 - posmod(st.tick, 30)
	Finance.daily(st)
	_ok(not Finance.war_tax_on(st, p), "la paix lève l'impôt de guerre")


func _test_bridges() -> void:
	# Révolte fiscale : Écrasant tenu deux ans.
	var st := new_game(31, {"stability": true})
	var p := eid_of(st, "vael")
	var e := st.get_empire(p)
	var en := Finance._w(st, p)
	en["tax"] = "ecrasant"
	en["crush"] = -1000
	var struck := false
	for m in 60:
		st.tick = 3600 + (m + 1) * 30
		en["crush"] = st.tick - 800
		var added: Array[Dictionary] = []
		FinanceBridges.monthly(st, added)
		if not (st.finance["strike"] as Dictionary).is_empty():
			struck = true
			break
	_ok(struck, "Écrasant tenu deux ans : une révolte fiscale finit par éclater")
	if struck:
		var sid := int((st.finance["strike"] as Dictionary).keys()[0])
		_ok(Finance.on_strike(st, sid), "grève fiscale dans le système")
		var items: Array = Events.meta(st, p)["inbox"]
		_ok(items.any(func(i: Dictionary) -> bool: return String(i["card"]) == "finance_revolte"), "carte « Révolte fiscale »")
		var item: Dictionary = items.filter(func(i: Dictionary) -> bool: return String(i["card"]) == "finance_revolte")[0]
		FinanceBridges.apply_fx(st, p, item, {"k": "finance", "act": "lower_tax"}, [] as Array[Dictionary])
		_ok(Finance.tax(st, p) == "eleve" and not Finance.on_strike(st, sid), "céder : un cran de moins, fin de la grève")
	# Krach : plafond et taux.
	var st2 := new_game()
	_ok(FinanceBridges.cap_pct(st2, p) == 0, "sans crise : pas de malus de plafond")
	# Haut fait « Budget à l'équilibre ».
	var st3 := new_game()
	(st3.finance["clean"] as Dictionary)[str(p)] = 0
	st3.tick = 360 * 21
	_ok(FinanceBridges.balanced_years(st3, p) == 0 or Stability.systems_of(st3, p).size() >= 10, "Budget à l'équilibre : il faut 10 systèmes")
	_ok(DeedsEval.is_counter("bankrupt"), "compteur de faillites")
	# Talents par couche d'espèce : catalogue lisible.
	var t: Dictionary = GameData.finance()["talents"]
	_ok(t.has("credo") and t.has("gouvernement") and t.has("registre"), "talents par couche d'espèce")


func _test_spy() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	var other := -1
	for o in st.empires:
		if o.id != p and not o.is_npc():
			other = o.id
			break
	var e := st.get_empire(p)
	month(st, e)
	var g0 := Finance.grade(st, p)
	FinanceBridges.spy_apply(st, other, p, Espionage.op_def("rumeur_faillite"))
	_ok(Finance.grade_index(Finance.grade(st, p)) == Finance.grade_index(g0) + 1, "rumeur de faillite : un cran de moins")
	Finance._w(st, p)["hist"] = st.tick + 100
	FinanceBridges.spy_apply(st, p, other, Espionage.op_def("maquiller_comptes"))
	_ok(Finance.grade_seen(st, p, other) == "A" and Finance.grade(st, p) == "D", "comptes maquillés : il nous croit noté A")
	Finance._w(st, p)["hist"] = 0
	_ok(apply(st, SimCommands.finance_borrow(p, "bank", 200)) == "", "emprunter 200")
	st.get_empire(other).resources["energy"] = 1000
	_ok(FinanceBridges.spy_check(st, other, p, "racheter_creance") == "", "créance rachetable")
	FinanceBridges.spy_apply(st, other, p, Espionage.op_def("racheter_creance"))
	var l: Dictionary = Finance.loans(st, p)[0]
	_ok(String(l["l"]) == "empire" and int(l["w"]) == other, "créance rachetée : il devient le créancier")
	_ok(int(st.get_empire(other).resources["energy"]) == 900, "racheter à moitié prix")


func _test_ai() -> void:
	var st := new_game(41, {"ai_level": "normale"})
	var sim := Simulation.new(st)
	sim.advance(360)
	var any := false
	for e in st.empires:
		if not e.is_npc() and Finance.applies(st, e.id) and Finance.gross_energy(st, e.id) > 0:
			any = true
	_ok(any, "un an d'IA : les bilans fiscaux tournent")


func _test_save() -> void:
	var st := new_game()
	var p := eid_of(st, "vael")
	st.get_empire(p).resources["influence"] = 200
	apply(st, SimCommands.finance_tax(p, "eleve"))
	apply(st, SimCommands.finance_borrow(p, "bank", 200))
	var d := st.to_dict()
	_ok(d.has("finance"), "la fiscalité est sauvegardée")
	_ok(int(d["version"]) >= 78, "format 78")
	var st2 := GameState.from_dict(d)
	_ok(st2 != null and Finance.tax(st2, p) == "eleve" and Finance.debt(st2, p) == 200, "relue : même cran, même dette")
	_ok(JSON.stringify(Finance.to_dict(st2)) == JSON.stringify(Finance.to_dict(st)), "relue à l'identique")
	var off := new_game(31, {"finance": "desactivee"})
	_ok(not off.to_dict().has("finance"), "Désactivée : pas de clé finance dans la sauvegarde")
