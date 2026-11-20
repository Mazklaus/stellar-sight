class_name AiCrisis
extends RefCounted
## L'IA face à la crise de fin de partie (voir Crisis, prop. 29) : elle s'arme dès le préavis, plus
## encore quand la crise est arrivée, et ses flottes de guerre vont frapper les points faibles et
## libérer les systèmes tombés quand elles sont assez fortes (la Recrue part sans compter).


## Navires de guerre voulus : n, ajusté selon la crise.
static func wanted(state: GameState, n: int, eid := -1) -> int:
	if Crisis.active(state):
		return n * 2 + 2
	if Crisis.ongoing(state) and (eid < 0 or Crisis.known(state, eid)):
		@warning_ignore("integer_division")
		return n * 3 / 2 + 1
	return n


## Puissance de la crise dans un système.
static func power_at(state: GameState, sid: int) -> int:
	var p := 0
	for g in Fleets.fleets_at(state, sid, GameState.CRISIS_ID):
		p += Combat.fleet_power(g)
	return p


## Cible de la flotte : point faible, système tombé ou flotte de la crise à portée ; -1 sinon.
## skill : 0 Recrue (part sans compter), 1 et plus (veut 120 % de la force en face).
static func target(state: GameState, e: Empire, f: Fleet, skill: int) -> int:
	if not Crisis.active(state):
		return -1
	var cands := {}
	for g in Crisis.stations(state):
		cands[g.system_id] = true
	for sid in Crisis.held(state):
		cands[int(sid)] = true
	var home := FactionTraits.capital_system(state, e.id)
	var hj := FactionTraits.jumps_from(state.galaxy, home) if home >= 0 else {}
	for g in Crisis.war_fleets(state):
		if not g.is_moving() and int(hj.get(g.system_id, 99)) <= 4:
			cands[g.system_id] = true
	var jumps := FactionTraits.jumps_from(state.galaxy, f.system_id)
	var mine := Combat.fleet_power(f)
	var best := -1
	var best_s := 1 << 40
	var ids := cands.keys()
	ids.sort()
	for k in ids:
		var sid := int(k)
		var j := int(jumps.get(sid, 999))
		if j >= 999:
			continue
		var pw := power_at(state, sid)
		if skill >= 1 and mine * 100 < pw * 120:
			continue
		# Les points faibles d'abord, puis les systèmes tombés chez soi, puis le reste.
		var s := j * 100
		if Crisis.role_of(state, _first_station(state, sid)) != "":
			s -= 250
		if int((Crisis.held(state).get(sid, {}) as Dictionary).get("owner", -1)) == e.id:
			s -= 300
		if s < best_s:
			best_s = s
			best = sid
	return best


static func _first_station(state: GameState, sid: int) -> int:
	for g in Crisis.stations(state):
		if g.system_id == sid:
			return g.id
	return -1


## Chaque jour de réflexion : verser au grand chantier commun (un lot par trimestre, si les réserves le
## permettent largement ; la Recrue oublie souvent).
static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	if state.crisis.is_empty():
		return
	_nemesis(ctx)
	if not Crisis.active(state):
		return
	var e: Empire = ctx["e"]
	var pj := CrisisKinds.project(state)
	if pj.is_empty():
		return
	# Environ un lot par trimestre, quel que soit le rythme de réflexion du niveau.
	var every := maxi(1, int(ctx["lv"].get("think_days", 10)))
	if Crisis._h(state, ["fonds", e.id, state.tick]) % 90 >= every:
		return
	var pack := int(pj.get("pack", 100))
	var res := "energy" if int(e.resources.get("energy", 0)) >= int(e.resources.get("materials", 0)) else "materials"
	if int(e.resources.get(res, 0)) < pack * 3:
		return
	if int(ctx["lv"].get("faction_use", 1)) <= 0 and (state.tick / 90) % 2 == 0:
		return
	if AiPlayer._issue(ctx, SimCommands.crisis_fund(e.id, res)):
		AiPlayer._intent(ctx, "Verse au %s" % String(pj.get("name", "grand chantier")))


## Devenir la crise (prop. 23) : un empire agressif, assez habile, peut prendre la voie (une chance sur
## « ai_one_in » par an selon son agressivité, data/crises.json) ; devenu le
## Fléau, il verse à son grand œuvre dès que ses réserves le permettent.
static func _nemesis(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	if not CrisisNemesis.enabled(state):
		return
	var e: Empire = ctx["e"]
	if CrisisNemesis.who(state) < 0:
		var one_in := int((CrisisNemesis.data().get("ai_one_in", {}) as Dictionary).get(str(AiLevels.aggression(e)), 0))
		if one_in > 0 and int(ctx["lv"].get("faction_use", 1)) >= 1 and CrisisNemesis.check_ambition(state, e.id) == "" \
				and Crisis._h(state, ["ambition", e.id, state.tick / 360]) % one_in == 0:
			if AiPlayer._issue(ctx, SimCommands.crisis_ambition(e.id)):
				AiPlayer._intent(ctx, "Nourrit une ambition démesurée")
		return
	if not CrisisNemesis.is_scourge(state, e.id):
		return
	var pack := int(CrisisNemesis.data()["oeuvre"].get("pack", 200))
	var res := "energy" if int(e.resources.get("energy", 0)) >= int(e.resources.get("materials", 0)) else "materials"
	if int(e.resources.get(res, 0)) >= pack * 2 and AiPlayer._issue(ctx, SimCommands.crisis_oeuvre(e.id, res)):
		AiPlayer._intent(ctx, "Bâtit %s" % String(CrisisNemesis.data()["oeuvre"].get("name", "son grand œuvre")))
