class_name CodexProgress
extends RefCounted
## Ce que chaque empire a rencontré, pour le Codex de l'Archonte (glossaire en jeu, prop. 18 et 30) :
## les fiches des peuples, des puissances anciennes, de la faune, des gardiens et des crises restent
## « ??? » tant qu'on ne les a pas croisés. Une fiche rencontrée le reste (même après la mort d'un
## empire ou la fin d'une crise) : state.codex = {"seen": {"<empire>": [identifiants]}}, sauvegarde 98.
## Relevé une fois par mois, sans aléatoire ; à la demande, ce qui est connu à l'instant compte aussi.


static func _seen(state: GameState, eid: int) -> Array:
	return (state.codex.get("seen", {}) as Dictionary).get(str(eid), [])


## Identifiants des fiches que l'empire connaît en ce moment (sans la mémoire du Codex).
static func known_now(state: GameState, eid: int) -> Array[String]:
	var out: Array[String] = []
	var e := state.get_empire(eid)
	if e == null:
		return out
	out.append("cat:peuples:" + e.faction_id)
	for o in e.contacts:
		var other := state.get_empire(int(o))
		if other != null and not out.has("cat:peuples:" + other.faction_id):
			out.append("cat:peuples:" + other.faction_id)
	for aid in Ancients.met(state, eid):
		out.append("cat:anciennes:" + Ancients.kind_of(state, aid))
	for sp in Fauna.known_species(state, eid):
		out.append("cat:faune:" + sp)
	for gid in Guardians.known(state, eid):
		out.append("cat:gardiens:" + gid)
	if Crisis.known(state, eid) and Crisis.kind(state) != "":
		out.append("cat:crises:" + Crisis.kind(state))
	return out


## L'empire a-t-il rencontré cette fiche ? (les identifiants hors catalogue verrouillé sont toujours connus)
static func unlocked(state: GameState, eid: int, id: String) -> bool:
	if state == null or eid < 0:
		return true
	if _seen(state, eid).has(id):
		return true
	return known_now(state, eid).has(id)


## Chaque mois : ce qui est connu entre dans la mémoire du Codex.
static func monthly(state: GameState) -> void:
	for e in state.empires:
		if GameState.is_npc(e.id) or e.eliminated:
			continue
		remember(state, e.id)


static func remember(state: GameState, eid: int) -> void:
	var now := known_now(state, eid)
	if now.is_empty():
		return
	if not state.codex.has("seen"):
		state.codex["seen"] = {}
	var key := str(eid)
	var list: Array = (state.codex["seen"] as Dictionary).get(key, [])
	var changed := false
	for id in now:
		if not list.has(id):
			list.append(id)
			changed = true
	if changed:
		list.sort()
		state.codex["seen"][key] = list


static func worth_saving(state: GameState) -> bool:
	return not state.codex.is_empty()


static func to_dict(state: GameState) -> Dictionary:
	return state.codex.duplicate(true)


static func from_dict(state: GameState, d: Variant) -> void:
	state.codex = {}
	if not d is Dictionary:
		return
	var seen: Dictionary = {}
	for k in (d as Dictionary).get("seen", {}):
		var list: Array = []
		for id in d["seen"][k]:
			list.append(String(id))
		seen[str(k)] = list
	if not seen.is_empty():
		state.codex["seen"] = seen
