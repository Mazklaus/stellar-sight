class_name AiFinance
extends RefCounted
## Fiscalité des empires IA (étude « Fiscalité et dette publique », prop. 32) : cran d'impôt selon la
## stabilité, la guerre et la crise ; approche de crise ; solde et impôt de guerre ; emprunt pour une
## guerre ; remboursement anticipé en paix ; prêt à un voisin en difficulté quand le trésor déborde ;
## planche à billets en dernier recours. La Recrue est imprudente (elle emprunte sans compter et ne
## rembourse jamais d'avance) ; les niveaux hauts évitent la faillite. Les créances impayées se
## réclament par le motif de guerre « Recouvrement » (voir Wars). Les cartes passent par AiEvents.

static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if state.finance.is_empty() or not Finance.applies(state, e.id):
		return
	var every := maxi(1, int(ctx["lv"].get("think_days", 10)))
	if posmod(state.tick + e.id * 13, 30) >= mini(every, 30):
		return
	var skill := AiPlayer._skill(ctx)
	var net := int(Finance.entry(state, e.id).get("gross", 0)) - _upkeep_guess(state, e.id)
	_tax(ctx, state, e, skill, net)
	_crisis(ctx, state, e, skill)
	if not Finance.full(state):
		return
	_pay(ctx, state, e, skill)
	_war_tax(ctx, state, e, skill, net)
	_borrow(ctx, state, e, skill)
	_repay(ctx, state, e, skill)
	_lend(ctx, state, e, skill)


## Estimation légère du déficit : mensualités des emprunts (le reste du bilan est déjà dans l'énergie).
static func _upkeep_guess(state: GameState, eid: int) -> int:
	var n := 0
	for l: Dictionary in Finance.loans(state, eid):
		n += Finance.installment(state, eid, l)
	return n


static func _avg_stab(state: GameState, eid: int) -> int:
	return Finance._avg_stability(state, eid)


## Cran : Élevé en guerre ou en crise si la stabilité le permet, Bas si l'empire gronde, Normal sinon.
static func _tax(ctx: Dictionary, state: GameState, e: Empire, skill: int, net: int) -> void:
	if skill < 1:
		return
	var stab := _avg_stab(state, e.id)
	var want := "normal"
	if stab < 35:
		want = "bas"
	elif (not e.wars.is_empty() or Finance.crisis_stage(state, e.id) >= 1 or net < 0) and stab >= 50:
		want = "eleve"
	if want != Finance.tax(state, e.id) and Finance.check_tax(state, e.id, want) == "":
		AiPlayer._issue(ctx, SimCommands.finance_tax(e.id, want))


static func _crisis(ctx: Dictionary, state: GameState, e: Empire, skill: int) -> void:
	var st := Finance.crisis_stage(state, e.id)
	if st <= 0 or skill < 1:
		return
	var want := "couper_recherche" if not e.wars.is_empty() else "rogner_soldes"
	if st >= 3 and skill >= 2:
		want = "imposer"
	if want != Finance.approach(state, e.id) and Finance.check_approach(state, e.id, want) == "":
		AiPlayer._issue(ctx, SimCommands.finance_approach(e.id, want))
	# Dernier recours : la planche à billets à la veille de la faillite.
	if st >= 4 and Finance.check_mint(state, e.id) == "":
		AiPlayer._issue(ctx, SimCommands.finance_mint(e.id))


static func _pay(ctx: Dictionary, state: GameState, e: Empire, skill: int) -> void:
	if skill < 1:
		return
	var want := "normale"
	if Finance.crisis_stage(state, e.id) >= 2 and e.wars.is_empty():
		want = "rognee"
	elif not e.wars.is_empty() and int(e.resources.get("energy", 0)) >= 800 and AiLevels.aggression(e) > 0:
		want = "pleine"
	if want != Finance.pay(state, e.id) and Finance.check_pay(state, e.id, want) == "":
		AiPlayer._issue(ctx, SimCommands.finance_pay(e.id, want))


static func _war_tax(ctx: Dictionary, state: GameState, e: Empire, skill: int, net: int) -> void:
	if skill < 1 or e.wars.is_empty() or Finance.war_tax_on(state, e.id):
		return
	if (net < 0 or int(e.resources.get("energy", 0)) < 200) and Finance.check_war_tax(state, e.id, true) == "":
		AiPlayer._issue(ctx, SimCommands.finance_war_tax(e.id, true))


## Emprunt : la Recrue dès que le trésor baisse ; les autres seulement en guerre, sous la moitié du plafond.
static func _borrow(ctx: Dictionary, state: GameState, e: Empire, skill: int) -> void:
	if int(e.resources.get("energy", 0)) >= 150 or Finance.in_bankruptcy(state, e.id):
		return
	var amount := 500
	if skill >= 1:
		if e.wars.is_empty() or Finance.debt(state, e.id) + amount > Finance.cap(state, e.id) / 2:
			return
	if Finance.check_borrow(state, e.id, "bank", amount) == "":
		AiPlayer._issue(ctx, SimCommands.finance_borrow(e.id, "bank", amount))


## Remboursement anticipé en paix, quand le trésor dépasse la moitié de la réserve.
static func _repay(ctx: Dictionary, state: GameState, e: Empire, skill: int) -> void:
	if skill < 1 or not e.wars.is_empty():
		return
	var energy := int(e.resources.get("energy", 0))
	@warning_ignore("integer_division")
	var spare := energy - Finance.reserve(state, e.id) / 2
	if spare < 200:
		return
	var best := {}
	for l: Dictionary in Finance.loans(state, e.id):
		if int(l["m"]) > 0 and String(l["l"]) != "koinon" and (best.is_empty() or int(l["r"]) > int(best["r"])):
			best = l
	if best.is_empty():
		return
	var n := mini(spare, int(best["p"]))
	if Finance.check_repay(state, e.id, int(best["id"]), n) == "":
		AiPlayer._issue(ctx, SimCommands.finance_repay(e.id, int(best["id"]), n))


## Prêter à un voisin connu et apprécié qui en a besoin, quand le trésor déborde (niveaux hauts).
static func _lend(ctx: Dictionary, state: GameState, e: Empire, skill: int) -> void:
	if skill < 2 or int(e.resources.get("energy", 0)) < 2000:
		return
	for o in state.empires:
		if o.id == e.id or o.eliminated or o.is_npc() or not o.is_ai() or not e.contacts.has(o.id):
			continue
		if Diplomacy.opinion(state, e.id, o.id) < 20:
			continue
		if Finance.check_lend(state, e.id, o.id, 300) == "":
			AiPlayer._issue(ctx, SimCommands.finance_lend(e.id, o.id, 300))
			return
