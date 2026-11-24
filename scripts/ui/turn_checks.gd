class_name TurnChecks
extends RefCounted
## Ce qui attend le joueur avant la fin du tour (refonte, A6 ; point C7 de l'équilibrage) : décisions à
## trancher, recherche vide, chantiers libres, flottes sans ordres, propositions diplomatiques. Lecture seule.


## [{kind, text, arg}] ; arg est un identifiant de système pour "build", de flotte pour "fleet", sinon -1.
static func todo(state: GameState, player: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var me := state.get_empire(player) if state else null
	if me == null:
		return out
	var waiting := Events.inbox(state, player).size()
	if Deeds.enabled(state):
		waiting += Deeds.inbox(state, player).size()
	if waiting > 0:
		out.append({"kind": "decisions", "arg": -1, "text": "%d décision%s à trancher" % [waiting, "s" if waiting > 1 else ""]})
	var offers := Diplomacy.proposals_for(state, player).size()
	if offers > 0:
		out.append({"kind": "diplomacy", "arg": -1, "text": "%d proposition%s diplomatique%s sans réponse" % [offers, "s" if offers > 1 else "", "s" if offers > 1 else ""]})
	if me.research_queue.is_empty() and _can_research(state, me):
		out.append({"kind": "research", "arg": -1, "text": "Aucune recherche en file"})
	var free: Array[int] = free_yards(state, player)
	if not free.is_empty():
		var p := state.galaxy.get_planet(free[0])
		out.append({"kind": "build", "arg": p.system_id, "text": "Chantier libre : %s%s" % [p.display_name(state.galaxy),
				"" if free.size() == 1 else " et %d autre%s" % [free.size() - 1, "s" if free.size() > 2 else ""]]})
	var idle := Fleets.idle_fleets(state, player)
	if not idle.is_empty():
		out.append({"kind": "fleet", "arg": idle[0].id, "text": "%d flotte%s sans ordres" % [idle.size(), "s" if idle.size() > 1 else ""]})
	return out


## Colonies établies dont le chantier est libre alors qu'un bâtiment au moins peut y être lancé.
static func free_yards(state: GameState, player: int) -> Array[int]:
	var out: Array[int] = []
	for pid in state.sorted_colony_ids():
		var c: Colony = state.colonies[pid]
		if c.owner != player or not c.is_colony() or not c.is_established() or c.construction != "":
			continue
		for bid: String in GameData.buildings():
			if Economy.check_build(state, player, pid, bid) == "":
				out.append(pid)
				break
	return out


static func _can_research(state: GameState, me: Empire) -> bool:
	for tid: String in Research.visible_for(state, me.id):
		if not me.techs.has(tid) and Research.is_available(state, me.id, tid):
			return true
	return false


## Une ligne pour l'avertissement de fin de tour ("" si rien n'attend).
static func summary(list: Array[Dictionary]) -> String:
	if list.is_empty():
		return ""
	var parts := PackedStringArray()
	for a: Dictionary in list:
		parts.append(String(a["text"]))
	return " ; ".join(parts)
