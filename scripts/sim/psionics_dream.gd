class_name PsionicsDream
extends RefCounted
## Pouvoirs psioniques, lot 2 : le Songe et la guerre (voir Psionics, data/psionics.json).


static func check_power(_state: GameState, _eid: int, _power: String, _target: int) -> String:
	return ""


static func effect(_state: GameState, _eid: int, _power: String, _target: int, _added: Array[Dictionary]) -> void:
	pass


static func felure(_state: GameState, _eid: int, _f: Dictionary, _added: Array[Dictionary]) -> void:
	pass


static func check(_state: GameState, _eid: int, act: String, _d: Dictionary) -> String:
	return "ordre psionique inconnu : %s" % act


static func apply(_state: GameState, _eid: int, _act: String, _d: Dictionary, _added: Array[Dictionary]) -> void:
	pass


static func monthly(_state: GameState, _added: Array[Dictionary]) -> void:
	pass
