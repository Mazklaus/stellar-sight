class_name AiVassals
extends RefCounted
## Paix à conditions et sujets vus par les empires IA (voir Vassals), une fois par mois (décalé selon
## l'empire) :
## - vainqueur : après 120 jours de guerre et 40 points de score, il impose les conditions que son score
##   paie (vassalité d'un petit vaincu, systèmes, tribut, réparations, alliances) ; la Recrue en demande
##   trop (et se fait éconduire) ;
## - vaincu presque mort (2 systèmes ou moins, ou capitale perdue) : il se rend plutôt que de disparaître ;
## - faible en mauvaise posture : il demande la protection d'un voisin puissant qu'il apprécie ;
## - suzerain : il assouplit les clauses d'un sujet au bord de la révolte, intègre un sujet loyal ;
## - sujet : déloyal et assez fort, il exige sa liberté ; déloyal, il jure une allégeance secrète ;
## - tiers (Vétéran et au-dessus) : il soutient l'indépendance des sujets d'un empire qu'il déteste.


static func cfg() -> Dictionary:
	return Vassals.data().get("ai", {})


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	if not state.vassals_on and (state.vassals.get("subs", {}) as Dictionary).is_empty():
		return
	var e: Empire = ctx["e"]
	var every := maxi(1, int(ctx["lv"].get("think_days", 10)))
	if posmod(state.tick + e.id * 11 + 3, 30) >= every:
		return
	run(ctx)


## Sans cadence (tests, outils).
static func think_state(state: GameState, eid: int) -> void:
	var e := state.get_empire(eid)
	run({"state": state, "e": e, "lv": AiLevels.level(e.ai_level), "ai": AiLevels.personality(e), "salt": 0, "intent": ""})


static func run(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if e.eliminated or Diplomacy.no_treaties(state, e.id):
		return
	if state.vassals_on:
		if _surrender(ctx):
			return
		_impose(ctx)
		_protection(ctx)
		_support(ctx)
	_lord(ctx)
	_subject(ctx)


## Vainqueur : conditions payées par le score.
static func _impose(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var c := cfg()
	var use := AiPlayer._use(ctx)
	for w in e.wars:
		var l := int(w)
		if GameState.is_npc(l) or Diplomacy.no_treaties(state, l):
			continue
		var score := Diplomacy.war_score(state, e.id, l)
		if score < int(c["terms_min_score"]) or Vassals.war_days(state, e.id, l) < int(c["terms_min_days"]):
			continue
		@warning_ignore("integer_division")
		var budget := score if use > 0 else score * 3 / 2
		var terms := build_terms(state, e.id, l, budget)
		if terms.is_empty():
			continue
		if AiPlayer._issue(ctx, SimCommands.vas_act(e.id, "terms", l, "", terms)):
			return


## Conditions qu'un budget de score paie : vassalité d'un petit vaincu d'abord, puis systèmes
## (les plus peuplés), tribut, réparations, rupture des alliances.
static func build_terms(state: GameState, w: int, l: int, budget: int) -> Dictionary:
	var terms := {}
	var left := budget
	if not Vassals.is_subject(state, l) and not Vassals.is_subject(state, w) and EmpireReport.owned_systems(state, l).size() <= 4:
		var vp := Vassals.vassal_price(state, l)
		if vp <= left:
			terms["vassal"] = "vassal"
			left -= vp
	if not terms.has("vassal"):
		var cands := Vassals.cedable(state, l)
		cands.sort_custom(func(x: int, y: int) -> bool:
			var px := Vassals.system_pop(state, x, l)
			var py := Vassals.system_pop(state, y, l)
			return px > py or (px == py and x < y))
		var cede: Array = []
		for sid in cands:
			if cede.size() >= int(Vassals.data()["terms"]["cede_max"]):
				break
			var p := Vassals.cede_price(state, l, sid)
			if p <= left:
				cede.append(sid)
				left -= p
		if not cede.is_empty():
			terms["cede"] = cede
	var t: Dictionary = Vassals.data()["terms"]
	if int(t["tribute_price"]) <= left:
		terms["trib"] = true
		left -= int(t["tribute_price"])
	if int(t["repar_price"]) <= left:
		terms["repar"] = true
		left -= int(t["repar_price"])
	if int(t["break_price"]) <= left and not Diplomacy.allies(state, l).is_empty():
		terms["break"] = true
		left -= int(t["break_price"])
	return terms


## Vaincu presque mort : reddition au plus fort de ses vainqueurs.
static func _surrender(ctx: Dictionary) -> bool:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if Vassals.is_subject(state, e.id):
		return false
	var small := EmpireReport.owned_systems(state, e.id).size() <= int(cfg()["surrender_systems"])
	var best := -1
	var best_score := 0
	for w in e.wars:
		var x := int(w)
		if Vassals.check_surrender(state, e.id, x) != "":
			continue
		var sc := Diplomacy.war_score(state, x, e.id)
		if not small and not Vassals.capital_lost(state, e.id, x):
			continue
		if best < 0 or sc > best_score:
			best = x
			best_score = sc
	if best >= 0:
		return AiPlayer._issue(ctx, SimCommands.vas_act(e.id, "surrender", best))
	return false


## Faible et perdant : demande la protection d'un voisin puissant qu'il apprécie.
static func _protection(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var c := cfg()
	if Vassals.is_subject(state, e.id) or not Vassals.subjects_of(state, e.id).is_empty():
		return
	var losing := false
	for w in e.wars:
		if Diplomacy.war_score(state, e.id, int(w)) <= int(c["protect_lose_score"]):
			losing = true
	if not losing:
		return
	var best := -1
	var best_op := -999
	for o in e.contacts:
		var x := int(o)
		if GameState.is_npc(x) or Vassals.check_protect(state, e.id, x) != "":
			continue
		var op := Diplomacy.opinion(state, e.id, x)
		if op >= int(c["protect_opinion"]) and op > best_op:
			best = x
			best_op = op
	if best >= 0:
		AiPlayer._issue(ctx, SimCommands.vas_act(e.id, "protect", best))


## Suzerain : assouplir avant la révolte, intégrer un sujet loyal.
static func _lord(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var c := cfg()
	var use := AiPlayer._use(ctx)
	for s in Vassals.subjects_of(state, e.id):
		if Vassals.locked(state, s):
			continue
		if Vassals.loyalty(state, s) < int(c["loosen_below"]) and use > 0:
			var soft := loosen(Vassals.link(state, s)["cl"])
			if not soft.is_empty() and AiPlayer._issue(ctx, SimCommands.vas_act(e.id, "set_terms", s, "", soft)):
				continue
		var th: Array = c.get("integrate_loyalty", [9999, 0, 200])
		if Vassals.loyalty(state, s) >= int(th[clampi(use, 0, th.size() - 1)]):
			AiPlayer._issue(ctx, SimCommands.vas_act(e.id, "integrate", s))
		_specialize(ctx, s)
		_possessions(ctx, s)


## Lot 3 : donne une spécialité à un sujet loyal qui n'en a pas (talent de peuple d'abord).
static func _specialize(ctx: Dictionary, s: int) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if Vassals.spec_of(state, s) != "" or Vassals.loyalty(state, s) < 100 or AiPlayer._use(ctx) <= 0:
		return
	var tal := Vassals.talent(state, e.id)
	var want := "satrapie" if bool(tal.get("satrapy", false)) else ("filiale" if bool(tal.get("filiale", false)) else ("rempart" if not e.wars.is_empty() else "prospecteur"))
	var cl: Dictionary = (Vassals.link(state, s)["cl"] as Dictionary).duplicate(true)
	cl["spec"] = want
	AiPlayer._issue(ctx, SimCommands.vas_act(e.id, "set_terms", s, "", cl))


## Lot 3 : comptoir quand le sujet paie tribut, mission chez un sujet peu loyal, garnison chez un sujet de même credo.
static func _possessions(ctx: Dictionary, s: int) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if AiPlayer._use(ctx) < 2:
		return
	var order: Array[String] = []
	if Vassals.loyalty(state, s) < 200:
		order.append("mission")
	if not Vassals.tribute_of(state, s).is_empty():
		order.append("comptoir")
	if TradeLinks.same_credo(state, e.id, s):
		order.append("garnison")
	for pid in order:
		if AiPlayer._issue(ctx, SimCommands.vas_act(e.id, "build", s, pid)):
			return


## Un cran plus souple : tribut d'abord, puis diplomatie, guerres, expansion ({} si déjà au plus souple).
static func loosen(cl: Dictionary) -> Dictionary:
	var n: Dictionary = cl.duplicate(true)
	if not (n.get("trib", {}) as Dictionary).is_empty():
		n["trib"] = {}
	elif String(n.get("dip", "")) != "libre":
		n["dip"] = "libre"
	elif String(n.get("war", "")) == "toutes":
		n["war"] = "def"
	elif String(n.get("exp", "")) != "libre":
		n["exp"] = "libre"
	else:
		return {}
	return n


## Sujet : liberté exigée, allégeance secrète.
static func _subject(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var c := cfg()
	var lord := Vassals.lord_of(state, e.id)
	if lord < 0 or Vassals.locked(state, e.id):
		return
	var loy := Vassals.loyalty(state, e.id)
	@warning_ignore("integer_division")
	var pct := 100 * Vassals.freedom_power(state, e.id) / maxi(1, Vassals.power(state, lord))
	if loy <= int(c["freedom_below"]) and pct >= int(c["freedom_power_pct"]):
		if AiPlayer._issue(ctx, SimCommands.vas_act(e.id, "freedom")):
			return
	if loy < 0 and int(Vassals.link(state, e.id)["fealty"]) < 0 and AiPlayer._use(ctx) > 0:
		var best := -1
		var best_op := -999
		for o in e.contacts:
			var x := int(o)
			if GameState.is_npc(x) or Vassals.check_fealty(state, e.id, x) != "":
				continue
			var op := Diplomacy.opinion(state, e.id, x)
			if op >= int(c["fealty_opinion"]) and Diplomacy.opinion(state, x, lord) < 0 and op > best_op:
				best = x
				best_op = op
		if best >= 0:
			AiPlayer._issue(ctx, SimCommands.vas_act(e.id, "fealty", best))


## Tiers (Vétéran et au-dessus) : soutien à l'indépendance des sujets d'un empire détesté.
static func _support(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if AiPlayer._use(ctx) < 2 or Vassals.is_subject(state, e.id):
		return
	for s in Vassals.all_subjects(state):
		var lord := Vassals.lord_of(state, s)
		if lord == e.id or s == e.id or Vassals.loyalty(state, s) >= 0:
			continue
		if Diplomacy.opinion(state, e.id, lord) > int(cfg()["support_opinion"]):
			continue
		if AiPlayer._issue(ctx, SimCommands.vas_act(e.id, "support", s)):
			return
