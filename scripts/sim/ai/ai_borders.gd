class_name AiBorders
extends RefCounted
## Frontières vues par les empires IA (voir Borders), une fois par mois (décalé selon l'empire) :
## - politique : Ouverte envers ceux qu'elle aime (opinion >= open_at), Close envers ceux qu'elle
##   déteste (<= close_at), Gardée sinon ; la Recrue oublie parfois d'y penser ;
## - les itinéraires contournent d'eux-mêmes l'espace interdit (Fleets._dijkstra) ;
## - le traité de libre-passage se propose avec les autres traités (AiDiplomacy._propose) ;
## - tous les cinq jours : sommer les intrus vus (sauf ceux qu'elle aime), obéir ou non à une sommation
##   selon le tempérament et le rapport de forces ;
## - chaque mois : laissez-passer pour ses flottes en intrusion, riposte des belliqueux contre les intrus
##   qui ont ignoré la sommation, péage des agressifs ;
## - elle répond aux demandes de laissez-passer (pass_score).


static func cfg() -> Dictionary:
	return Borders.data().get("ai", {})


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	if not Borders.active(state):
		return
	var e: Empire = ctx["e"]
	if e.eliminated:
		return
	if posmod(state.tick + e.id * 3, 5) == 0:
		_summons(ctx)
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
	_summons(ctx)
	_passes(ctx)
	_riposte(ctx)
	_toll(ctx)


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


## Réponse à une demande de laissez-passer de v pour la flotte f (accepté si >= 0).
static func pass_score(state: GameState, o: int, v: int, f: Fleet) -> int:
	var c := cfg()
	var score := int(c["pass_base"]) + Diplomacy.opinion(state, o, v) / 2
	@warning_ignore("integer_division")
	score -= f.ships.size() * 10 / maxi(1, int(c["pass_size_div"]))
	score += int(Borders.talent(state, v).get("pass_bonus", 0))
	var eo := state.get_empire(o)
	if eo != null:
		score -= AiLevels.aggression(eo) * 5
	if Borders.has_cb(state, o, v):
		score -= 30
	return score


## Sommer les intrus vus ; obéir (ou non) aux sommations reçues.
static func _summons(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	for other in e.contacts:
		if Borders.check_summons(state, e.id, other) == "" and Diplomacy.opinion(state, e.id, other) < int(cfg()["open_at"]):
			if AiPlayer._issue(ctx, SimCommands.border_act(e.id, "summons", other)):
				AiPlayer._intent(ctx, "Sommation à %s" % state.get_empire(other).short_name())
	for other in e.contacts:
		if Borders.summons_end(state, other, e.id) <= 0 or not obeys(state, e.id, other):
			continue
		for fid in Borders.intruders(state, other, e.id):
			var f: Fleet = state.fleets.get(fid)
			if f == null or f.is_moving():
				continue
			var dest := Borders.nearest_permitted(state, f)
			if dest >= 0 and dest != f.system_id:
				AiPlayer._issue(ctx, SimCommands.move_fleet(e.id, fid, dest))


## Obéit-elle à la sommation de o ? Les belliqueux plus forts que o restent.
static func obeys(state: GameState, eid: int, o: int) -> bool:
	var e := state.get_empire(eid)
	var ag := AiLevels.aggression(e)
	if ag <= 0:
		return true
	return Diplomacy.warships(state, eid) <= Diplomacy.warships(state, o) * (1 + ag)


## Laissez-passer pour une flotte armée en intrusion (sans sommation), si l'influence le permet.
static func _passes(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var b: Dictionary = state.borders.get("intr", {})
	var keys: Array = b.keys()
	keys.sort_custom(func(x: String, y: String) -> bool: return int(x) < int(y))
	for k in keys:
		var f: Fleet = state.fleets.get(int(k))
		if f == null or f.owner != e.id:
			continue
		var o := int(b[k]["o"])
		var cost := int(Borders.pass_cost(state, e.id).get("influence", 0))
		if int(e.resources.get("influence", 0)) < cost * 3 or Borders.summons_end(state, o, e.id) > 0:
			continue
		if AiPlayer._issue(ctx, SimCommands.border_act(e.id, "pass", f.id, o)):
			AiPlayer._intent(ctx, "Laissez-passer demandé à %s" % state.get_empire(o).short_name())
			return


## Riposte : un belliqueux envoie une flotte de guerre au contact d'un intrus qui a ignoré sa sommation.
static func _riposte(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if AiLevels.aggression(e) < int(cfg()["riposte_aggr"]):
		return
	for it in Borders.intrusions_in(state, e.id):
		var target: Fleet = state.fleets.get(int(it[0]))
		if target == null or not Borders.riposte_on(state, e.id, target):
			continue
		for f in Fleets.empire_fleets(state, e.id):
			if f.is_moving() or not Combat.is_warfleet(f) or f.standing_order != "" or f.system_id == target.system_id:
				continue
			if AiPlayer._issue(ctx, SimCommands.move_fleet(e.id, f.id, target.system_id)):
				AiPlayer._intent(ctx, "Riposte contre l'intrus de %s" % state.get_empire(target.owner).short_name())
				return


## Péage : les agressifs taxent le passage des flottes de guerre.
static func _toll(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	var want := 1 if AiLevels.aggression(e) >= int(cfg()["toll_at_aggr"]) else 0
	if Borders.toll_level(state, e.id) != want:
		AiPlayer._issue(ctx, SimCommands.border_act(e.id, "toll", want))
