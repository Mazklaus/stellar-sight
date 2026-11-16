class_name AiAdmin
extends RefCounted
## Administration des empires IA (étude « Administration et corruption », prop. 33) : effort
## administratif selon le trésor et la corruption, intégration des conquêtes dès que l'influence le
## permet, Tribunal là où la corruption mord (voir AiPlayer.building_wishes), retenue dans l'expansion
## selon l'agressivité (un empire pacifique s'arrête plus tôt au-dessus de sa capacité). L'IA ne
## déplace jamais sa capitale (trop rare et trop risqué pour valoir un calcul).
## La carte « Détournement révélé » passe par AiEvents.

static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if state.admin.is_empty() or not Admin.applies(state, e.id):
		return
	var every := maxi(1, int(ctx["lv"].get("think_days", 10)))
	if posmod(state.tick + e.id * 11, 30) >= mini(every, 30):
		return
	_effort(ctx, state, e)
	_integrate(ctx, state, e)


## Effort : Généreux quand l'énergie abonde et que la capacité ou la corruption pèsent, Frugal quand
## le trésor est à sec, Normal sinon. Le niveau Recrue ne touche à rien.
static func _effort(ctx: Dictionary, state: GameState, e: Empire) -> void:
	if AiPlayer._skill(ctx) < 1:
		return
	var energy := AiPlayer._res(ctx, "energy")
	var want := "normal"
	if energy < 80:
		want = "frugal"
	elif energy >= 600 and (Admin.over_pct(state, e.id) > 0 or Admin.average_corruption(state, e.id) >= 15):
		want = "genereux"
	if want != Admin.effort(state, e.id) and Admin.check_effort(state, e.id, want) == "":
		AiPlayer._issue(ctx, SimCommands.admin_effort(e.id, want))


## Intégrer les systèmes conquis, les plus peuplés d'abord, en gardant la réserve d'influence du niveau.
static func _integrate(ctx: Dictionary, state: GameState, e: Empire) -> void:
	if not Admin.full(state):
		return
	var reserve := int(ctx["lv"].get("reserve_influence", 0))
	var best := -1
	var best_pop := -1
	for k in (state.admin["ni"] as Dictionary).keys():
		var sid := int(k)
		if int((state.admin["sys"] as Dictionary).get(str(sid), -1)) != e.id:
			continue
		if Admin.check_integrate(state, e.id, sid) != "":
			continue
		var cost := int(Admin.integrate_cost(state, e.id, sid).get("influence", 0))
		if AiPlayer._res(ctx, "influence") - cost < reserve:
			continue
		var pop := Stability.system_pop(state, sid, e.id)
		if pop > best_pop:
			best_pop = pop
			best = sid
	if best >= 0:
		AiPlayer._issue(ctx, SimCommands.admin_integrate(e.id, best))


## Retenue : au-delà de ce dépassement de capacité (en %), l'IA ne lance plus de revendication.
## Pacifique dès 20 %, agressive jusqu'à 60 % (la conquête paie la note).
static func restrain(ctx: Dictionary) -> bool:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if state.admin.is_empty() or not Admin.applies(state, e.id) or AiPlayer._skill(ctx) < 1:
		return false
	return Admin.over_pct(state, e.id) >= 40 + 7 * AiLevels.aggression(e)


## Tribunal voulu dans ce système ? (corruption d'au moins 15 et pas encore de Tribunal)
static func wants_tribunal(ctx: Dictionary, sid: int) -> bool:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not Admin.full(state) or not Admin.has_corruption(state, e.id) or AiPlayer._skill(ctx) < 1:
		return false
	return Admin.corruption(state, sid) >= 15 and not Admin._has_building(state, e.id, sid, "tribunal") \
			and AiPlayer._res(ctx, "materials") >= 200
