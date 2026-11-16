class_name AiRulers
extends RefCounted
## Souverains des empires IA (étude « Souverain et dynastie », prop. 39) : poste du souverain (au palais,
## au front seulement pour un tempérament belliqueux en guerre), pouvoir de l'archétype au bon moment,
## éducation des héritiers, héritages, mariages, abdication d'un souverain trop vieux. L'ambition et les
## cartes (funérailles, régence, étoile montante) passent par AiEvents. La Couronne vacillante d'un
## rival rend ses revendications moins chères : l'IA en profite d'elle-même (Wars.claim_cost).

static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if state.rulers.is_empty() or Rulers.entry(state, e.id).is_empty() or not Rulers.has_ruler(state, e.id):
		return
	if posmod(state.tick + e.id * 5, 15) != 0:
		return
	_post(ctx, state, e)
	_power(ctx, state, e)
	_educate(ctx, state, e)
	_legacy(ctx, state, e)
	if posmod(state.tick + e.id * 11, 180) < 15:
		_marry(ctx, state, e)
		_abdicate(ctx, state, e)


static func _post(ctx: Dictionary, state: GameState, e: Empire) -> void:
	var r := Rulers.ruler(state, e.id)
	var bold := AiLevels.aggression(e) >= 2 and not e.wars.is_empty()
	if bold:
		var best: Fleet = null
		for fid in state.sorted_fleet_ids():
			var f: Fleet = state.fleets[fid]
			if f.owner == e.id and Combat.is_armed(f) and (best == null or Combat.fleet_power(f) > Combat.fleet_power(best)):
				best = f
		if best != null and not Rulers.commands(state, e.id, best.id):
			AiPlayer._issue(ctx, SimCommands.ruler_act(e.id, "post", best.id, "fleet"))
			return
	if String(r.get("post", "")) != "capital" and not bold:
		AiPlayer._issue(ctx, SimCommands.ruler_act(e.id, "post", -1, "capital"))


static func _power(ctx: Dictionary, state: GameState, e: Empire) -> void:
	if Rulers.check_power(state, e.id) != "":
		return
	var arch := String(Rulers.ruler(state, e.id)["arch"])
	match arch:
		"conquerant", "heros":
			if e.wars.is_empty():
				return
		"zelote":
			if Stability.empire_value(state, e.id) >= 60:
				return
		"savant":
			if e.research_queue.is_empty():
				return
	AiPlayer._issue(ctx, SimCommands.ruler_act(e.id, "power"))


static func _educate(ctx: Dictionary, state: GameState, e: Empire) -> void:
	for c: Dictionary in RulersDynasty.heirs(state, e.id):
		if String(c["edu"]) == "" and RulersDynasty.child_age(state, c) >= Rulers.r_int("education_age"):
			AiPlayer._issue(ctx, SimCommands.ruler_act(e.id, "educate", int(c["id"]), RulersDynasty._best_cls(c)))


static func _legacy(ctx: Dictionary, state: GameState, e: Empire) -> void:
	var arch := String(Rulers.ruler(state, e.id)["arch"])
	var pref := {"conquerant": "guerre", "heros": "guerre", "batisseur": "administration", "marchand": "administration", "savant": "administration",
			"intrigant": "intrigue", "zelote": "foi", "diplomate": "sang"}
	var tracks: Array = [String(pref.get(arch, "administration"))]
	for t in RulersDynasty.legacy_defs():
		if not tracks.has(t):
			tracks.append(t)
	for t in tracks:
		if Rulers.check_act(state, e.id, "legacy", -1, String(t)) == "":
			AiPlayer._issue(ctx, SimCommands.ruler_act(e.id, "legacy", -1, String(t)))
			return


static func _marry(ctx: Dictionary, state: GameState, e: Empire) -> void:
	if not Rulers.hereditary(state, e.id) or int(Rulers.entry(state, e.id).get("spouse", -1)) >= 0:
		return
	var best := -1
	var bv := 10
	for o in e.contacts:
		if Rulers.check_act(state, e.id, "marry", int(o), "") != "":
			continue
		var v := Diplomacy.opinion(state, e.id, int(o))
		if v > bv:
			bv = v
			best = int(o)
	if best >= 0 and state.get_empire(best).is_ai():
		AiPlayer._issue(ctx, SimCommands.ruler_act(e.id, "marry", best, ""))


static func _abdicate(ctx: Dictionary, state: GameState, e: Empire) -> void:
	var r := Rulers.ruler(state, e.id)
	var life := int(r.get("life", 0))
	if life <= 0 or Rulers.age(state, r) < life - 5:
		return
	var adult := not Heroes.heir_of(state, e.id).is_empty()
	for c: Dictionary in RulersDynasty.heirs(state, e.id):
		if RulersDynasty.child_age(state, c) >= Rulers.r_int("majority"):
			adult = true
	if adult:
		AiPlayer._issue(ctx, SimCommands.ruler_act(e.id, "abdicate"))
