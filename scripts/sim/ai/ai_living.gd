class_name AiLiving
extends RefCounted
## IA et mondes vivants (prop. 32 ; voir LivingWorlds, data/livingworlds.json).
## Les cartes (demandes, éveil, visiteurs) passent par AiEvents, qui lit card_value : l'IA accepte les
## demandes faciles qu'elle peut payer, la paix si elle est pacifique, chasse ses flottes si le monde lui
## est cher. Une fois par mois, si le pilier est en jeu : elle écoute un monde qu'elle connaît mal (si elle
## a des sensitifs), invite chez elle un monde Bienveillant quand elle a de quoi, cueille les nefs-graines
## d'un monde Lié, et fusionne (Vétéran et au-dessus) quand le lien est assez vieux. Ses flottes évitent
## d'attaquer un système dont le monde aime le défenseur (AiPlayer._war_target, ai_avoid).


static func _ai() -> Dictionary:
	return LivingWorlds.cfg("ai")


## Valeur d'un choix de carte « lw » pour AiEvents (plus haut = mieux).
static func card_value(state: GameState, eid: int, item: Dictionary, act: String, temper: int) -> int:
	if state.living.is_empty():
		return 0
	var pid := int(item.get("planet", -1))
	var e := state.get_empire(eid)
	match act:
		"yes":
			var req: Dictionary = LivingWorlds.world(state, pid).get("req", {}) if LivingWorlds.is_living(state, pid) else {}
			var kind := String(req.get("k", ""))
			var rd: Dictionary = LivingWorlds.cfg("requests").get(kind, {})
			var cost: Dictionary = rd.get("cost", {})
			if not cost.is_empty() and not Economy.can_afford(e, cost):
				return -100
			if (_ai().get("accept_easy", []) as Array).has(kind):
				return 80
			if kind == "paix":
				return 60 - temper * 50  # le pacifique cède volontiers, le belliqueux refuse
			if kind == "chasser":
				return 40 if e.wars.is_empty() else -40
			return 20
		"no":
			return 0
		"wake":
			return 60 - maxi(0, temper) * 20
		"sleep":
			return 10 + maxi(0, temper) * 20
		"visit_yes":
			return 50
		"visit_no":
			return 0
	return 0


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if state.living.is_empty() or e.is_npc() or e.eliminated:
		return
	@warning_ignore("integer_division")
	var month := state.tick / int(GameData.rules()["month_days"]) + 1
	if LivingWorlds.stat(state, e.id, "ai_month") >= month:
		return
	LivingWorlds._stat(state, e.id, "ai_month", month - LivingWorlds.stat(state, e.id, "ai_month"))
	if AiPlayer._forgets(ctx):
		return
	var skill := AiPlayer._skill(ctx)
	for pid in LivingWorlds.ids(state):
		if not LivingWorlds.knows(state, pid, e.id):
			continue
		var d := {"p": pid}
		# Écouter : seulement si l'on ne sait pas encore ce qu'il aime.
		if not (LivingWorlds.world(state, pid)["deep"] as Dictionary).has(str(e.id)) \
				and LivingWorlds.check(state, e.id, "listen", d) == "":
			AiPlayer._issue(ctx, SimCommands.living_act(e.id, "listen", d))
			continue
		if LivingWorlds.check(state, e.id, "seed", d) == "":
			AiPlayer._issue(ctx, SimCommands.living_act(e.id, "seed", d))
			continue
		if skill >= 2 and LivingWorlds.check(state, e.id, "fuse", d) == "":
			AiPlayer._issue(ctx, SimCommands.living_act(e.id, "fuse", d))
			AiPlayer._intent(ctx, "Fusion avec %s" % LivingWorlds.name_of(state, pid))
			continue
		if skill >= 1 and _rich(e) and LivingWorlds.check(state, e.id, "invite", d) == "":
			AiPlayer._issue(ctx, SimCommands.living_act(e.id, "invite", d))
			AiPlayer._intent(ctx, "Inviter %s" % LivingWorlds.name_of(state, pid))


static func _rich(e: Empire) -> bool:
	var res: Dictionary = _ai().get("invite_reserve", {})
	for r in res:
		if int(e.resources.get(r, 0)) < int(res[r]) * 2:
			return false
	return true
