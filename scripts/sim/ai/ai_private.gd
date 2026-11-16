class_name AiPrivate
extends RefCounted
## Économie privée des empires IA (étude « Économie privée », prop. 35) : subventionner quand la
## confiance s'effondre, accorder des licences minières, distribuer les chartes (armement en guerre,
## commerce en paix), réquisitionner les cargos en guerre (en payant), ravitaillement sous contrat,
## descentes de police contre les syndicats, filiales chez les partenaires, confiscation des comptes
## ennemis, comptabilité créative quand le trésor est à sec. La Recrue oublie la moitié de ces gestes
## (elle ne subventionne jamais et réquisitionne sans payer) ; les niveaux hauts ouvrent des filiales.

static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if state.private.is_empty() or not Private.applies(state, e.id):
		return
	if posmod(state.tick + e.id * 7, 30) != 0:
		return
	var skill := AiPlayer._skill(ctx)
	var en := Private.entry(state, e.id)
	var energy := int(e.resources.get("energy", 0))
	var infl := int(e.resources.get("influence", 0))
	# Subvention : confiance basse et trésor confortable.
	if skill >= 1 and int(en.get("conf", 50)) < 40 and energy >= 400:
		_try(ctx, state, e.id, "subsidize")
	# Licence minière : le meilleur gisement libre.
	if infl >= 40 and (en.get("lic", []) as Array).size() < 4:
		var best := -1
		var bv := 0
		for pid in Private.mine_sites(state, e.id):
			if (en.get("lic", []) as Array).has(pid):
				continue
			var v := int(Private.mine_yield(state, pid)["private"])
			if v > bv:
				bv = v
				best = pid
		if best >= 0:
			_try(ctx, state, e.id, "licence", best)
	if not Private.full(state):
		return
	var war := not e.wars.is_empty()
	# Réquisition et contrats en guerre.
	if war and int(en.get("req", 0)) <= 0 and skill >= 0:
		_try(ctx, state, e.id, "requisition", 1, 1 if skill >= 1 else 0)
	elif not war and int(en.get("req", 0)) > 0:
		_try(ctx, state, e.id, "requisition", 0)
	if not state.logistics.is_empty() and (int(en.get("contract", 0)) > 0) != war and skill >= 1:
		_try(ctx, state, e.id, "contract", 1 if war else 0)
	# Chartes.
	if skill >= 1:
		var want := "armement" if war else "commerce"
		for c in Private.companies_of(state, e.id):
			if String(c.get("ch", "")) == "" and not bool(c.get("nat", false)):
				var s := want
				var alone := true
				for o in Private.companies_of(state, e.id):
					if int(o["id"]) != int(c["id"]) and String(o["sec"]) == String(c["sec"]):
						alone = false
				if alone and skill >= 2 and not war:
					s = "monopole"
				_try(ctx, state, e.id, "charter", int(c["id"]), -1, s)
	# Descentes de police.
	if skill >= 1 and infl >= 80:
		for sid in PrivateBridges.dens_of(state, e.id):
			if _try(ctx, state, e.id, "raid", sid):
				break
	# Confiscation des comptes ennemis.
	for o in e.wars:
		if not Private.branches_in(state, e.id, int(o)).is_empty():
			_try(ctx, state, e.id, "confiscate", int(o))
	# Filiales chez les partenaires (niveaux hauts).
	if skill >= 2 and not war:
		_branch(ctx, state, e)
	# Comptabilité créative en dernier recours.
	if energy < 30 and skill >= 1:
		_try(ctx, state, e.id, "creative")


static func _branch(ctx: Dictionary, state: GameState, e: Empire) -> void:
	var best: Dictionary = {}
	for c in Private.companies_of(state, e.id):
		if not bool(c.get("nat", false)) and (best.is_empty() or int(c["pr"]) > int(best["pr"])):
			best = c
	if best.is_empty():
		return
	for o in Trade.partners(state, e.id):
		var bp := -1
		var pop := 0
		for c in Private.colonies_of(state, int(o)):
			if c.is_colony() and c.population > pop and Private.check_branch(state, e.id, int(best["id"]), c.planet_id) == "":
				pop = c.population
				bp = c.planet_id
		if bp >= 0:
			_try(ctx, state, e.id, "branch", int(best["id"]), bp)
			return


static func _try(ctx: Dictionary, state: GameState, eid: int, act: String, a := -1, b := -1, s := "") -> bool:
	if Private.check(state, eid, act, a, b, s) != "":
		return false
	AiPlayer._issue(ctx, SimCommands.private_act(eid, act, a, b, s))
	return true
