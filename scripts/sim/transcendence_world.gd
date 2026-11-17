class_name TranscendenceWorld
extends RefCounted
## La Transcendance et la galaxie (lot 2, voir Transcendence) : en attente.


static func place_minces(_state: GameState) -> void:
	pass


static func gain_parts(_state: GameState, _eid: int) -> Array:
	return []


static func moratorium(_state: GameState) -> bool:
	return false


static func relays_banned(_state: GameState) -> bool:
	return false


static func minces_held(_state: GameState, _eid: int) -> int:
	return 0


static func bless_days(_state: GameState, _eid: int) -> int:
	return 0


static func frozen(_state: GameState, _eid: int) -> bool:
	return false


static func on_passage(_state: GameState, _eid: int, _added: Array[Dictionary]) -> void:
	pass


static func note_aid(_state: GameState, _host: int, _eid: int, _n: int) -> void:
	pass


static func on_renounce(_state: GameState, _eid: int) -> void:
	pass


## Départ (issue « Départ ») : l'empire quitte la galaxie.
static func depart(state: GameState, eid: int, _path_id: String, _added: Array[Dictionary]) -> void:
	var e := state.get_empire(eid)
	if e == null or e.eliminated:
		return
	for pid in state.sorted_colony_ids():
		if (state.colonies[pid] as Colony).owner == eid:
			state.colonies.erase(pid)
	state.rebuild_ownership()
	CombatSystem.eliminate(state, e)


static func effects(_state: GameState, _eid: int) -> Dictionary:
	return {}


static func empire_stability_parts(_state: GameState, _eid: int) -> Array:
	return []


static func monthly(_state: GameState, _added: Array[Dictionary]) -> void:
	pass
