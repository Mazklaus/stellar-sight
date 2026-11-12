class_name AiPirates
extends RefCounted
## Pirates pour les empires IA (voir Pirates) : tribut, contrats, chasse aux repaires.
## Recrue : rien (elle subit les raids). Normale : tribut à un repaire qui l'a pillée dans l'année si
## elle est pacifique ou mesurée et en a les moyens (jamais par honneur) ; les plus agressives, ou en
## guerre, engagent un repaire contre leur ennemi. Vétéran et au-dessus : en paix, la flotte de guerre
## assez forte part démanteler le repaire connu le plus proche (voir AiPlayer._command_fleet).
## Normale et au-dessus : rançon d'un héros captif quand l'énergie le permet ; au port franc, une flotte
## de mercenaires en guerre, un héros s'il reste une place.


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var every := maxi(1, int(ctx["lv"].get("think_days", 10)))
	if posmod(state.tick + e.id * 11, 30) >= mini(every, 30):
		return
	var skill := int(ctx["lv"].get("faction_use", 1))
	if skill <= 0:
		return
	if not state.heroes.is_empty():
		_ransom(ctx)
	if state.lairs.is_empty():
		return
	_tribute(ctx)
	_hire(ctx)
	_port(ctx)


static func _ransom(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	for id in Heroes.held_for_ransom(state, e.id):
		var cost := Heroes.ransom_cost(state.heroes[id])
		if int(e.resources.get("energy", 0)) >= 2 * int(cost["energy"]):
			if AiPlayer._issue(ctx, SimCommands.hero_ransom(e.id, id)):
				AiPlayer._intent(ctx, "Paie la rançon de %s" % String(state.heroes[id]["name"]))
				return


static func _port(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var ports := Pirates.known_ports(state, e.id)
	if ports.is_empty():
		return
	var kinds: Array = []
	if not e.wars.is_empty():
		kinds.append("fleet")
	if Heroes.ids_of(state, e.id).size() < Heroes.cap(state, e.id):
		kinds.append("hero")
	for kind in kinds:
		var cost := Pirates.port_cost(kind)
		var rich := true
		for r in cost:
			if int(e.resources.get(r, 0)) < 3 * int(cost[r]):
				rich = false
		if not rich:
			continue
		for sid in ports:
			if AiPlayer._issue(ctx, SimCommands.port_deal(e.id, sid, kind)):
				AiPlayer._intent(ctx, ("Loue des mercenaires au %s" if kind == "fleet" else "Recrute un héros au %s") % Pirates.port_name(state, sid))
				return


static func _tribute(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if AiLevels.aggression(e) > 0 or int(Pirates.talent(state, e.id).get("tribute_shame", 0)) != 0:
		return
	for sid in Pirates.known_lairs(state, e.id):
		var hit := int((state.lairs[sid]["hits"] as Dictionary).get(e.id, -100000))
		if state.tick - hit > GameCalendar.DAYS_PER_YEAR or Pirates.pays_tribute(state, sid, e.id):
			continue
		var cost := Pirates.tribute_cost(state, e.id)
		if int(e.resources.get("energy", 0)) >= 2 * int(cost.get("energy", 0)):
			if AiPlayer._issue(ctx, SimCommands.pirate_tribute(e.id, sid)):
				AiPlayer._intent(ctx, "Paie tribut à %s" % Pirates.lair_ref(state, sid))


static func _hire(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if e.wars.is_empty() and AiLevels.aggression(e) < 2:
		return
	var foes: Array = e.wars.duplicate() if not e.wars.is_empty() else e.contacts.duplicate()
	foes.sort()
	var cost := Pirates.hire_cost(state, e.id)
	for r in cost:
		if int(e.resources.get(r, 0)) < 3 * int(cost[r]):
			return
	for v in foes:
		for sid in Pirates.known_lairs(state, e.id):
			if AiPlayer._issue(ctx, SimCommands.pirate_hire(e.id, sid, int(v))):
				AiPlayer._intent(ctx, "Engage des pirates contre %s" % state.get_empire(int(v)).short_name())
				return


## Repaire à démanteler pour cette flotte de guerre (Vétéran et plus, en paix) : le repaire connu le
## plus proche de la capitale, à 6 sauts au plus, si la flotte fait au moins 1,5 fois sa garde. -1 sinon.
static func lair_target(ctx: Dictionary, f: Fleet, home: int) -> int:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if state.lairs.is_empty() or int(ctx["lv"].get("faction_use", 1)) < 2 or not e.wars.is_empty() or home < 0:
		return -1
	if not ctx.has("home_jumps"):
		ctx["home_jumps"] = FactionTraits.jumps_from(state.galaxy, home)
	var jumps: Dictionary = ctx["home_jumps"]
	var best := -1
	var best_j := 7
	var power := Combat.fleet_power(f)
	for sid in Pirates.known_lairs(state, e.id):
		var j := int(jumps.get(sid, 99))
		if j < best_j and power * 100 >= 150 * maxi(1, Pirates.guard_power(state, sid)):
			best = sid
			best_j = j
	return best
