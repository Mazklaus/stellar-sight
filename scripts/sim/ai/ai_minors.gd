class_name AiMinors
extends RefCounted
## L'IA face aux peuples mineurs (prop. 33) : elle courtise ceux qu'elle connaît (émissaires sur les plus
## prometteurs, postes d'observation, quêtes de livraison), intègre ses protégés si elle est pacifique,
## conquiert un pré-spatial voisin si elle est belliqueuse, lève les troupes de ses protégés en guerre
## et active les traits d'assimilation libres. La Recrue gère mal : elle oublie ses émissaires.


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	if not Minors.enabled(state):
		return
	var e: Empire = ctx["e"]
	var every := maxi(1, int(ctx["lv"].get("think_days", 10)))
	if posmod(state.tick + e.id * 7, 30) >= every:
		return  # environ une fois par mois
	_traits(ctx)
	var met := Minors.met(state, e.id)
	if met.is_empty():
		return
	var temper := clampi(AiLevels.aggression(e), -2, 2)
	for id in met:
		if Minors.at_war_with(state, id, e.id):
			# Paix quand la guerre s'éternise sans prise (deux ans), ou tout de suite pour un pacifique.
			var since := int(Minors.get_m(state, id)["war"][e.id])
			if (temper <= 0 or state.tick - since > 720) and AiPlayer._issue(ctx, SimCommands.min_act(e.id, "peace", id)):
				AiPlayer._intent(ctx, "Fait la paix avec %s" % Minors.name_of(state, id))
	_posts(ctx, met)
	_envoys(ctx, met)
	for id in met:
		if AiPlayer._issue(ctx, SimCommands.min_act(e.id, "deliver", id)):
			AiPlayer._intent(ctx, "Aide %s" % Minors.name_of(state, id))
			break
	if temper <= 1:
		for id in met:
			if AiPlayer._issue(ctx, SimCommands.min_act(e.id, "integrate", id)):
				AiPlayer._intent(ctx, "Intègre %s" % Minors.name_of(state, id))
				break
	if not e.wars.is_empty():
		for id in Minors.proteges_of(state, e.id):
			if AiPlayer._issue(ctx, SimCommands.min_act(e.id, "levy", id)):
				AiPlayer._intent(ctx, "Lève les troupes %s" % Crisis.de_name(Minors.name_of(state, id)))
	MinorsLife.ai_think(ctx, met, temper)
	MinorsBridges.ai_think(ctx, met)
	if temper >= 1:
		_conquest(ctx, met, temper)


static func _traits(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var act := Minors.active_traits(state, e.id)
	if act.size() >= Minors.trait_slots(state, e.id):
		return
	for k in Minors.absorbed(state, e.id):
		if not act.has(k) and AiPlayer._issue(ctx, SimCommands.min_act(e.id, "trait", -1, String(k))):
			return


## Un poste discret au-dessus d'un pré-spatial connu, quand les réserves le permettent.
static func _posts(ctx: Dictionary, met: Array[int]) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if int(e.resources.get("materials", 0)) < 300 or int(e.resources.get("influence", 0)) < 60:
		return
	for id in met:
		if Minors.is_pre(state, id) and not Minors.has_post(state, id, e.id):
			if AiPlayer._issue(ctx, SimCommands.min_act(e.id, "post", id, "discret")):
				AiPlayer._intent(ctx, "Observe %s" % Minors.name_of(state, id))
			return


## Émissaires sur les peuples les plus prometteurs (faveur déjà acquise, cadeau, suzerain en vue).
static func _envoys(ctx: Dictionary, met: Array[int]) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var inf := int(e.resources.get("influence", 0))
	@warning_ignore("integer_division")
	var slots := clampi(inf / 120, 0, 3)
	var ranked: Array = []
	for id in met:
		if not Minors.can_talk(state, id, e.id) or Minors.at_war_with(state, id, e.id) or Minors.grudge(state, id, e.id):
			continue
		var v := Minors.fav(state, id, e.id) * 2 + Minors._h(state, ["ia-gout", e.id, id]) % 40
		if Minors.suzerain(state, id) == e.id:
			v += 30
		var suz := Minors.suzerain(state, id)
		if suz >= 0 and suz != e.id and Minors.fav(state, id, suz) - Minors.fav(state, id, e.id) > 40:
			v -= 60  # trop loin derrière le suzerain
		ranked.append([-v, id])
	ranked.sort()
	var keep := {}
	for i in mini(slots, ranked.size()):
		keep[int(ranked[i][1])] = true
	for id in met:
		var cur := Minors.envoy_level(state, id, e.id)
		if keep.has(id):
			var want := 2 if Minors.fav(state, id, e.id) >= 40 and Minors.suzerain(state, id) != e.id else 1
			if cur != want and not AiPlayer._forgets(ctx):
				if AiPlayer._issue(ctx, SimCommands.min_act(e.id, "envoy", id, "", want)) and cur == 0:
					AiPlayer._intent(ctx, "Envoie un émissaire %s" % Crisis.de_name(Minors.name_of(state, id)).trim_prefix("de ").trim_prefix("du "))
			elif cur > 0 and AiPlayer._forgets(ctx):
				AiPlayer._issue(ctx, SimCommands.min_act(e.id, "envoy", id, "", 0))  # la Recrue oublie
		elif cur > 0:
			AiPlayer._issue(ctx, SimCommands.min_act(e.id, "envoy", id, "", 0))


## Un belliqueux sans autre guerre attaque un pré-spatial voisin mal défendu, non protégé par plus fort.
static func _conquest(ctx: Dictionary, met: Array[int], temper: int) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not e.wars.is_empty() or AiPlayer._skill(ctx) < 1 or state.tick < 720:
		return
	for id in met:
		if Minors.at_war_with(state, id, e.id):
			return  # une conquête à la fois
	if Minors._h(state, ["ia-conquete", e.id, state.tick]) % 6 >= temper:
		return
	var cap := FactionTraits.capital_system(state, e.id)
	if cap < 0:
		return
	var jumps := FactionTraits.jumps_from(state.galaxy, cap)
	var mine := Ancients.empire_power(state, e.id)
	for id in met:
		var sid := Minors.system_of(state, id)
		if not Minors.is_pre(state, id) or int(jumps.get(sid, 999)) > 4:
			continue
		var suz := Minors.suzerain(state, id)
		if suz >= 0 and Ancients.empire_power(state, suz) > mine:
			continue
		if Combat.garrison(state, sid) > 30:
			continue
		if AiPlayer._issue(ctx, SimCommands.min_act(e.id, "war", id)):
			AiPlayer._intent(ctx, "Part conquérir %s" % Minors.name_of(state, id))
			return


## Cible d'une flotte de guerre en paix avec les empires : le monde du peuple mineur attaqué le plus proche.
static func conquest_target(state: GameState, e: Empire, f: Fleet) -> int:
	if not Minors.enabled(state):
		return -1
	var best := -1
	var best_j := 999
	var jumps := {}
	for id in Minors.ids(state):
		if not Minors.at_war_with(state, id, e.id):
			continue
		if jumps.is_empty():
			jumps = FactionTraits.jumps_from(state.galaxy, f.system_id)
		var sid := Minors.system_of(state, id)
		var j := int(jumps.get(sid, 999))
		if j < best_j:
			best_j = j
			best = sid
	return best
