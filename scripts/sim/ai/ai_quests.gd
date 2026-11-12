class_name AiQuests
extends RefCounted
## Quêtes des empires IA (voir Quests). À chaque réflexion :
## - payer une branche « payer » quand les réserves le permettent largement ;
## - envoyer un éclaireur (flotte sans armes, ni colon ni flotte-ville) vers le système d'une branche
##   « aller à », ou près de l'artéfact du Passage ;
## - financer le remède de la Rouille grise ;
## - au Conclave, choisir un camp selon son agressivité, puis mettre un héros libre en gouverneur d'un
##   Phare qu'on possède ;
## - réveil des tombeaux : un peuple synthétique parlemente ; une flotte de guerre inactive et assez
##   forte va abattre les gardiens d'un tombeau voisin.
## Le reste (batailles, systèmes, technologies) avance avec le jeu normal de l'IA.

const PAY_MARGIN := 2
const CONTRIBUTE_MARGIN := 3
const INFLUENCE_RESERVE := 60
const PASSAGE_JUMPS := 8
const TOMB_JUMPS := 5


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not Quests.enabled(state) or AiPlayer._forgets(ctx):
		return
	var sent := false
	for qid in Quests.of(state, e.id, true):
		var q: Dictionary = state.quests[qid]
		var brs: Array = Quests.chapter(q)["branches"]
		for b in brs.size():
			var g: Dictionary = brs[b]["goal"]
			match String(g["k"]):
				"pay":
					if Quests.check_pay(state, e.id, qid, b) == "" and _rich(e, Quests.pay_cost(state, e.id, g), PAY_MARGIN):
						AiPlayer._issue(ctx, SimCommands.quest_pay(e.id, qid, b))
						return
				"visit":
					var sid := int(q["subj"]["system"])
					if not sent and not Quests._fleet_in(state, e.id, sid):
						sent = _send_scout(ctx, sid, 999)
	if Quests.galactic_on(state):
		_galactic(ctx, sent)


static func _rich(e: Empire, cost: Dictionary, margin: int) -> bool:
	for r in cost:
		if int(e.resources.get(r, 0)) < int(cost[r]) * margin:
			return false
	return true


## Envoie la flotte sans armes la plus proche (à max_jumps ou moins) vers le système.
static func _send_scout(ctx: Dictionary, sid: int, max_jumps: int) -> bool:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if sid < 0:
		return false
	var jumps := FactionTraits.jumps_from(state.galaxy, sid)
	var best: Fleet = null
	var bj := max_jumps + 1
	for f in Fleets.empire_fleets(state, e.id):
		if f.ships.is_empty() or Combat.is_armed(f) or Fleets.colonizer_ship(f) != "" or FactionTraits.is_city_fleet(f):
			continue
		if f.system_id == sid and f.path.is_empty():
			return false
		if f.is_moving() and f.standing_order == "":
			continue
		var j := int(jumps.get(f.system_id, 9999))
		if j < bj:
			bj = j
			best = f
	if best == null:
		return false
	return AiPlayer._issue(ctx, SimCommands.move_fleet(e.id, best.id, sid))


static func _galactic(ctx: Dictionary, sent: bool) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var cur := Quests.current(state)
	if cur.is_empty():
		return
	match String(cur["id"]):
		"passage":
			if not sent:
				_send_scout(ctx, Quests.passage_system(cur), PASSAGE_JUMPS)
		"fleau":
			if Quests.check_contribute(state, e.id) == "" and _rich(e, Quests.contribute_cost(state, e.id), CONTRIBUTE_MARGIN):
				AiPlayer._issue(ctx, SimCommands.quest_contribute(e.id))
		"conclave":
			_conclave(ctx, cur)
		"tombeaux":
			_tombs(ctx, cur)


static func _conclave(ctx: Dictionary, cur: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if String(cur["phase"]) == "choose":
		if Quests.camp_of(state, e.id) < 0:
			var camp := 1 if AiLevels.aggression(e) > 0 else 0
			AiPlayer._issue(ctx, SimCommands.quest_camp(e.id, camp))
		return
	for sid in cur["phares"]:
		if state.system_owner(int(sid)) != e.id or not Heroes.assigned_to(state, "system", int(sid), e.id).is_empty():
			continue
		for hid in Heroes.ids_of(state, e.id):
			var h: Dictionary = state.heroes[hid]
			if String(h["post"]) == "" and Heroes.check_assign(state, e.id, hid, "system", int(sid)) == "":
				AiPlayer._issue(ctx, SimCommands.hero_assign(e.id, hid, "system", int(sid)))
				return


static func _tombs(ctx: Dictionary, cur: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	for t: Dictionary in cur["tombs"]:
		if int(t["alive"]) == 0:
			continue
		var sid := int(t["sid"])
		if Quests.check_parley(state, e.id, sid) == "" and int(e.resources.get("influence", 0)) >= int(Quests.gdef("tombeaux")["parley_cost"].get("influence", 0)) + INFLUENCE_RESERVE:
			AiPlayer._issue(ctx, SimCommands.tomb_parley(e.id, sid))
			return
	if not (cur.get("near", []) as Array).has(e.id) or not e.wars.is_empty():
		return
	# Une flotte de guerre inactive, une fois et demie plus forte que les gardiens, va les abattre.
	for t: Dictionary in cur["tombs"]:
		if int(t["alive"]) == 0 or not state.fleets.has(int(t["fleet"])):
			continue
		var guard := _strength(state.fleets[int(t["fleet"])])
		var jumps := FactionTraits.jumps_from(state.galaxy, int(t["sid"]))
		for f in Fleets.empire_fleets(state, e.id):
			if f.is_idle() and Combat.is_warfleet(f) and int(jumps.get(f.system_id, 999)) <= TOMB_JUMPS and _strength(f) * 2 >= guard * 3:
				AiPlayer._issue(ctx, SimCommands.move_fleet(e.id, f.id, int(t["sid"])))
				return


static func _strength(f: Fleet) -> int:
	var n := 0
	for s in f.ships:
		n += Combat.ship_strength(s)
	return n
