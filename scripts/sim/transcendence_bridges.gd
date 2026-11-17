class_name TranscendenceBridges
extends RefCounted
## La Transcendance et les autres piliers (lot 3, voir Transcendence) : en attente.


static func extra_relays(_state: GameState, _eid: int) -> int:
	return 0


static func on_break(_state: GameState, _eid: int, _pct: int, _added: Array[Dictionary]) -> void:
	pass


static func effects(_state: GameState, _eid: int) -> Dictionary:
	return {}


static func check(_state: GameState, _eid: int, _act: String, _d: Dictionary) -> String:
	return "action inconnue"


static func apply(_state: GameState, _eid: int, _act: String, _d: Dictionary, _added: Array[Dictionary]) -> void:
	pass


static func monthly(_state: GameState, _added: Array[Dictionary]) -> void:
	pass
