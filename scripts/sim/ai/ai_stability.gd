class_name AiStability
extends RefCounted
## Stabilité des empires IA (voir Stability) : décrets, offrande des théocraties, réintégration des
## mondes libres. Une fois par mois, décalé selon l'empire.
## Recrue : rien (elle laisse faire, comme elle oublie ses talents). Normale : Fêtes publiques sur les
## systèmes en Révolte, réintégration des mondes libres voisins. Vétéran et au-dessus : aussi les
## systèmes en Agitation, et la loi martiale quand une flotte armée est sur place ; une théocratie
## offre la stabilité de ses systèmes en Ferveur quand sa ferveur faiblit.


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var every := maxi(1, int(ctx["lv"].get("think_days", 10)))
	if posmod(state.tick + e.id * 7, 30) >= mini(every, 30):
		return
	var skill := int(ctx["lv"].get("faction_use", 1))
	if skill <= 0 or not Stability.applies(state, e.id) or state.stability.is_empty():
		return
	_decrees(ctx, skill)
	if skill >= 2:
		_offering(ctx)
	_reintegrate(ctx)


static func _decrees(ctx: Dictionary, skill: int) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var worst := []
	for sid in Stability.systems_of(state, e.id):
		var t := Stability.tier_id(state, sid)
		if t == "revolte" or (skill >= 2 and t == "agitation"):
			worst.append([Stability.value(state, sid), sid])
	worst.sort()
	for w in worst:
		var sid := int(w[1])
		if Stability.active_decree(state, sid) != "":
			continue
		if skill >= 2 and AiPlayer._issue(ctx, SimCommands.decree(e.id, sid, "loi_martiale")):
			continue
		if not AiPlayer._issue(ctx, SimCommands.decree(e.id, sid, "fetes")):
			AiPlayer._issue(ctx, SimCommands.decree(e.id, sid, "concessions"))


static func _offering(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not FactionTraits.has_fervor(e.faction()) or FactionTraits.is_exalted(state, e.id):
		return
	for sid in Stability.systems_of(state, e.id):
		if Stability.value(state, sid) >= 85:
			AiPlayer._issue(ctx, SimCommands.stab_offering(e.id, sid))
			return


static func _reintegrate(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	for sid in Stability.systems_of(state, e.id):
		for n in state.galaxy.systems[sid].neighbors:
			if state.system_owner(n) == GameState.NPC_ID:
				AiPlayer._issue(ctx, SimCommands.reintegrate(e.id, n))
