class_name ContactVoices
extends RefCounted
## Les voix du Contact (lot 3) : peuples, Taiseux, saboteurs, Voyage des Cinq, anciennes puissances,
## crises appelées, ponts. Voir Contact.


static func extra_ears(_state: GameState, _eid: int) -> int:
	return 0


static func kheb_sites(_state: GameState) -> Array[int]:
	var out: Array[int] = []
	return out


static func extra_alerts(_state: GameState, _eid: int) -> int:
	return 0


static func gauge_pct_parts(_state: GameState, _eid: int) -> Array:
	return []


static func on_layer(_state: GameState, _eid: int, _id: String, _added: Array[Dictionary]) -> void:
	pass


static func on_porteuse(_state: GameState, _eid: int, _added: Array[Dictionary]) -> void:
	pass


static func aster_key(_state: GameState, _eid: int) -> bool:
	return false


static func city_heraut_system(_state: GameState, _eid: int) -> int:
	return -1


static func transmit_block(_state: GameState, _eid: int) -> String:
	return ""


static func tx_paused(_state: GameState, _eid: int) -> bool:
	return false


static func on_fail(_state: GameState, _eid: int, _crisis: String, _added: Array[Dictionary]) -> void:
	pass


static func stability_parts(_state: GameState, _eid: int) -> Array:
	return []


static func check(_state: GameState, _eid: int, _act: String, _d: Dictionary) -> String:
	return "action inconnue"


static func apply(_state: GameState, _eid: int, _act: String, _d: Dictionary, _added: Array[Dictionary]) -> void:
	pass


static func monthly(_state: GameState, _added: Array[Dictionary]) -> void:
	pass
