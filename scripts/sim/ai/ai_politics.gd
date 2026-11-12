class_name AiPolitics
extends RefCounted
## Politique intérieure des empires IA (voir Politics) : le soutien officiel avant chaque élection
## (ou le courant nommé, en théocratie et en horde). Une fois par mois, décalé selon l'empire, dans
## les 90 jours qui précèdent le vote.
## Recrue : son courant principal, toujours. Normale et au-dessus : le Glaive si elle est belliqueuse
## (agressivité 2 ou plus), la Concorde si elle est pacifique (-2 ou moins), sinon son courant
## principal ; mais si trop de ses systèmes ne sont pas représentés (rally_pct), elle soutient le
## courant le plus fort de son opinion pour les rallier.


static func think(ctx: Dictionary) -> void:
	var state: GameState = ctx["state"]
	var e: Empire = ctx["e"]
	if not Politics.applies(state, e.id) or Politics.mode(state, e.id) == "continuous":
		return
	if posmod(state.tick + e.id * 11, 30) != 0:
		return
	var nxt := Politics.next_election(state, e.id)
	if nxt < 0 or nxt - state.tick > 90 or Politics.pick(state, e.id) >= 0:
		return
	AiPlayer._issue(ctx, SimCommands.politics_support(e.id, choose(state, e, int(ctx["lv"].get("faction_use", 1)))))


## Courant que l'IA soutient.
static func choose(state: GameState, e: Empire, skill: int) -> int:
	var main := Politics.principal(state, e.id)
	if skill <= 0:
		return main
	var ag := AiLevels.aggression(e)
	if ag >= 2:
		return Politics.index_of("glaive")
	if ag <= -2:
		return Politics.index_of("concorde")
	var out := 0
	var tot := 0
	for sid in Stability.systems_of(state, e.id):
		var en := Politics.sys_entry(state, sid)
		if en.is_empty() or int(en.get("rep", -1)) < 0:
			continue
		tot += 1
		if not Politics.in_power(state, e.id, int(en["rep"])):
			out += 1
	if tot > 0 and out * 100 >= tot * int(Politics.data()["ai"]["rally_pct"]):
		return Politics._argmax(Politics.empire_opinion(state, e.id))
	return main
