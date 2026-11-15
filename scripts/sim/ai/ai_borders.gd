class_name AiBorders
extends RefCounted
## Frontières vues par les empires IA (voir Borders), une fois par mois (décalé selon l'empire) :
## - politique : Ouverte envers ceux qu'elle aime (opinion >= open_at), Close envers ceux qu'elle
##   déteste (<= close_at), Gardée sinon ; la Recrue oublie parfois d'y penser ;
## - les itinéraires contournent d'eux-mêmes l'espace interdit (Fleets._dijkstra) ;
## - le traité de libre-passage se propose avec les autres traités (AiDiplomacy._propose).


static func cfg() -> Dictionary:
	return Borders.data().get("ai", {})


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	if not Borders.active(state):
		return
	var e: Empire = ctx["e"]
	if posmod(state.tick + e.id * 11 + 3, 30) != 0:
		return
	run(ctx)


## Sans cadence (tests, outils).
static func think_state(state: GameState, eid: int) -> void:
	var e := state.get_empire(eid)
	run({"state": state, "e": e, "lv": AiLevels.level(e.ai_level), "ai": AiLevels.personality(e), "salt": 0, "intent": ""})


static func run(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if e.eliminated:
		return
	_policies(ctx)


## La politique voulue envers other.
static func wanted_policy(state: GameState, eid: int, other: int) -> String:
	var c := cfg()
	var base := Borders.default_policy(state, eid)
	if Diplomacy.no_treaties(state, eid):
		return base
	var op := Diplomacy.opinion(state, eid, other)
	if op >= int(c["open_at"]) and base != Borders.CLOSED:
		return Borders.OPEN
	if op <= int(c["close_at"]):
		return Borders.CLOSED
	return base


static func _policies(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	for other in e.contacts:
		var o := state.get_empire(other)
		if o == null or o.eliminated or o.is_npc() or Combat.at_war(state, e.id, other) or Borders.strong_link(state, e.id, other):
			continue
		var want := wanted_policy(state, e.id, other)
		if want == Borders.policy(state, e.id, other) or AiPlayer._forgets(ctx):
			continue
		if AiPlayer._issue(ctx, SimCommands.border_act(e.id, "policy", other, -1, want)):
			AiPlayer._intent(ctx, "Frontières %s envers %s" % [Borders.policy_label(want).to_lower(), o.short_name()])
