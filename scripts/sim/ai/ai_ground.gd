class_name AiGround
extends RefCounted
## IA des armées (combat au sol complet, voir Ground) : recrute à la capitale selon les places de ses
## transports (davantage en guerre), embarque les régiments qui attendent là où une flotte de guerre
## est à l'arrêt, et ne débarque que si ses régiments l'emportent sur la défense estimée (sauf la
## Recrue, qui débarque dès qu'elle peut). Le Vétéran et plus sonne la retraite d'une bataille perdue.
## Appelée par AiPlayer._military, avant le commandement des flottes.


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	if not Ground.full(state):
		return
	_recruit(ctx)
	_embark(ctx)
	_retreat(ctx)
	_tactics(ctx)
	_bombard(ctx)
	_sortie(ctx)
	_hire(ctx)


static func _recruit(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var home := FactionTraits.capital_system(state, e.id)
	if home < 0 or WarPeace.holder(state, home) != e.id or Ground.species_in(state, e.id, home).is_empty():
		home = _recruit_system(state, e.id)
	if home < 0:
		return
	var at_war := not e.wars.is_empty()
	var places := 0
	for f in AiPlayer._warfleets(ctx):
		places += Ground.capacity(state, f)
	@warning_ignore("integer_division")
	var want := (places / 4 + 1) if at_war else mini(2, places / 8 + 1)
	var have := Ground.regiments_of(state, e.id).size() + Ground.queue_of(state, e.id).size()
	if have >= want:
		return
	if AiPlayer._res(ctx, "materials") < 120 and not at_war:
		return
	var t := _pick_type(ctx, have)
	if AiPlayer._issue(ctx, SimCommands.ground_act(e.id, "recruit", home, t)):
		AiPlayer._intent(ctx, "Lève un régiment de %s" % Ground.type_label(t).to_lower())
	elif t != "infanterie":
		AiPlayer._issue(ctx, SimCommands.ground_act(e.id, "recruit", home, "infanterie"))


static func _recruit_system(state: GameState, eid: int) -> int:
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner == eid and c.is_colony() and c.is_established() and c.population >= 2:
			var sid := state.galaxy.get_planet(pid).system_id
			if WarPeace.holder(state, sid) == eid:
				return sid
	return -1


## Recrue : toujours de l'infanterie. Sinon un blindé sur trois et un aérien sur quatre quand ils
## sont ouverts (le Vétéran regarde ce que l'ennemi aligne : aérien contre les blindés).
static func _pick_type(ctx: Dictionary, have: int) -> String:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var skill := AiPlayer._skill(ctx)
	if skill <= 0:
		return "infanterie"
	# Lot 3 : le titan (Vétéran et plus, riche), puis un régiment de peuple sur trois.
	if skill >= 2 and Ground.type_allowed(state, e.id, "marcheur") and AiPlayer._res(ctx, "materials") > 1500 \
			and Ground.check_recruit(state, e.id, FactionTraits.capital_system(state, e.id), "marcheur") == "":
		return "marcheur"
	if posmod(have, 3) == 0:
		for t in ["essaims", "automates", "colosses", "possedes", "fanatiques", "troupes_choc"]:
			if Ground.type_allowed(state, e.id, t):
				return t
	var ok_air := Ground.type_allowed(state, e.id, "aerien")
	var ok_arm := Ground.type_allowed(state, e.id, "blindes")
	if skill >= 2 and ok_air and _enemy_armor(ctx):
		return "aerien"
	if skill >= 2 and Ground.type_allowed(state, e.id, "genie") and not e.wars.is_empty() and posmod(have, 5) == 2:
		return "genie"
	if skill >= 2 and Ground.type_allowed(state, e.id, "commandos") and posmod(have, 6) == 4:
		return "commandos"
	if ok_air and posmod(have, 4) == 3:
		return "aerien"
	if ok_arm and posmod(have, 3) == 1:
		return "blindes"
	return "infanterie"


static func _enemy_armor(ctx: Dictionary) -> bool:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	for w in e.wars:
		for r in Ground.regiments_of(state, int(w)):
			if String(Ground.type_def(String(r["t"])).get("family", "")) == "blindes":
				return true
	return false


static func _embark(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var home := FactionTraits.capital_system(state, e.id)
	for f in AiPlayer._warfleets(ctx):
		if f.is_moving() or not state.fleets.has(f.id):
			continue
		var waiting := Ground.on_ground(state, f.system_id, e.id).size()
		# On laisse un régiment de garde à la capitale.
		if f.system_id == home and waiting <= 1 and not e.wars.is_empty():
			continue
		if waiting > 0 and Ground.free_places(state, f) >= 4:
			AiPlayer._issue(ctx, SimCommands.ground_act(e.id, "embark", f.id))


## Débarquer ? La Recrue débarque dès qu'elle a des troupes ; les autres attendent d'avoir l'avantage
## (le siège use la milice entre-temps).
static func should_land(ctx: Dictionary, f: Fleet) -> bool:
	var state: GameState = ctx["state"]
	if not Ground.full(state):
		return true
	if AiPlayer._skill(ctx) <= 0:
		return true
	var sid := f.system_id
	var mine := Ground.strength(Ground.aboard(state, f.id))
	var b := Ground.battle(state, sid)
	if not b.is_empty() and int(b["a"]) == f.owner:
		return true  # renfort d'une bataille en cours
	var defender := WarPeace.holder(state, sid)
	var def := Ground.militia_strength(state, sid) + Ground.strength(Ground.on_ground(state, sid, defender))
	var need := 150 if AiPlayer._skill(ctx) >= 2 else 120
	return mine * 100 >= def * need


static func _retreat(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if AiPlayer._skill(ctx) < 2:
		return
	for b in Ground.battles(state):
		if int(b["a"]) != e.id or Ground.check_retreat(state, e.id, int(b["s"])) != "":
			continue
		var sid := int(b["s"])
		var mine := Ground.strength(Ground.on_ground(state, sid, e.id))
		var theirs := Ground.strength(Ground.on_ground(state, sid, int(b["d"]))) + Ground.militia_strength_from(b)
		if mine * 100 < theirs * 40:
			if AiPlayer._issue(ctx, SimCommands.ground_act(e.id, "retreat", sid)):
				AiPlayer._intent(ctx, "Rembarque ses troupes de %s" % state.galaxy.systems[sid].system_name)


## Tactiques (lot 2) : la Recrue garde l'assaut et la défense ; ensuite, Blitz quand on écrase la
## défense, Bombardement préventif (Vétéran et plus) contre une grosse milice, Infiltration face aux
## batteries ; en défense, Résistance locale (Vétéran et plus).
static func _tactics(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var skill := AiPlayer._skill(ctx)
	if skill <= 0:
		return
	if skill >= 2 and Ground.default_tactic(state, e.id, "defense") != "resistance":
		AiPlayer._issue(ctx, SimCommands.ground_act(e.id, "default_tactic", -1, "defense", "resistance"))
	for b in Ground.battles(state):
		if int(b["a"]) != e.id or state.tick >= int(b["land"]):
			continue
		var sid := int(b["s"])
		var mine := Ground.strength(Ground.on_ground(state, sid, e.id))
		var theirs := Ground.strength(Ground.on_ground(state, sid, int(b["d"]))) + Ground.militia_strength_from(b)
		var want := "assaut"
		if mine > theirs * 2:
			want = "blitz"
		elif skill >= 2 and (b["mil"] as Array).size() >= 4:
			want = "bombardement"
		elif Ground.landing_fire_pct(state, sid, e.id, []) >= 20:
			want = "infiltration"
		if String(b.get("ta", "assaut")) != want:
			AiPlayer._issue(ctx, SimCommands.ground_act(e.id, "tactic", sid, want))


## Bombardement : les flottes de guerre qui assiègent passent en Sélectif.
static func _bombard(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if AiPlayer._skill(ctx) <= 0:
		return
	for f in AiPlayer._warfleets(ctx):
		if f.is_moving() or not state.fleets.has(f.id):
			continue
		var besieging := Combat.is_besieged(state, f.system_id) and state.system_owner(f.system_id) != e.id
		var p := GroundSiege.posture(state, f.id)
		if besieging and p == "":
			AiPlayer._issue(ctx, SimCommands.ground_act(e.id, "bomb", f.id, "selectif"))
		elif not besieging and p != "":
			AiPlayer._issue(ctx, SimCommands.ground_act(e.id, "bomb", f.id, ""))


## Sortie (Vétéran et plus) : quand la garnison au sol l'emporte sur les troupes à bord des assiégeants.
static func _sortie(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if AiPlayer._skill(ctx) < 2:
		return
	for sid in state.sieges.keys():
		if GroundSiege.check_sortie(state, e.id, int(sid)) != "":
			continue
		var theirs := 0
		for f in Combat.besiegers(state, int(sid)):
			theirs += Ground.strength(Ground.aboard(state, f.id))
		if Ground.strength(Ground.on_ground(state, int(sid), e.id)) > theirs:
			AiPlayer._issue(ctx, SimCommands.ground_act(e.id, "sortie", int(sid)))


## Mercenaires (lot 3) : en guerre, riche en énergie et à court de régiments, l'IA en loue à la capitale.
static func _hire(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if AiPlayer._skill(ctx) <= 0 or e.wars.is_empty() or AiPlayer._res(ctx, "energy") < 400:
		return
	var home := FactionTraits.capital_system(state, e.id)
	if home < 0 or Ground.recruits(state, e.id) >= 2 or GroundOccupation.check_hire(state, e.id, home) != "":
		return
	if AiPlayer._issue(ctx, SimCommands.ground_act(e.id, "hire", home)):
		AiPlayer._intent(ctx, "Loue une compagnie de mercenaires")
