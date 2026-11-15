class_name WondersCatalog
extends RefCounted
## Catalogue des merveilles (lot 2) : effets codés (« special »), ruines, tirage.


static func setup(_state: GameState) -> void:
	pass


static func sees_all(_state: GameState, _eid: int) -> bool:
	return false


static func ruin_of(_state: GameState, _wid: String) -> int:
	return -1


static func daily(_state: GameState, _added: Array[Dictionary]) -> void:
	pass


static func on_stage(_state: GameState, _wid: String, _eid: int, _pid: int, _stage: int, _added: Array[Dictionary]) -> void:
	pass


static func on_complete(_state: GameState, _wid: String, _eid: int, _pid: int, _added: Array[Dictionary]) -> void:
	pass
