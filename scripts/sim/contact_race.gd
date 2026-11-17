class_name ContactRace
extends RefCounted
## La course au Signal (lot 2 du Contact) : fragments, échange, Consortium, espionnage, Amphictyonie,
## casus belli, brouillage, Forêt sombre. Voir Contact.


static func gauge_pct_parts(_state: GameState, _eid: int) -> Array:
	return []


static func on_echo(_state: GameState, _eid: int, _added: Array[Dictionary]) -> void:
	pass


static func foreign_count(_state: GameState, _eid: int) -> int:
	return 0


static func on_transmit(_state: GameState, _eid: int, _added: Array[Dictionary]) -> void:
	pass


static func partners(_state: GameState, _eid: int) -> Array[int]:
	var out: Array[int] = []
	return out


static func winner_host(_state: GameState, _eid: int) -> int:
	return -1


static func effects(_state: GameState, _eid: int) -> Dictionary:
	return {}


static func on_menace(_state: GameState, _eid: int) -> void:
	pass


## "?" : acte inconnu ici (Contact passe la main à ContactVoices).
static func check(_state: GameState, _eid: int, _act: String, _d: Dictionary) -> String:
	return "?"


static func apply(_state: GameState, _eid: int, _act: String, _d: Dictionary, _added: Array[Dictionary]) -> bool:
	return false


## IA de la course (AiContact) : échanges, Consortiums, objecteurs.
static func ai(_ctx: Dictionary) -> void:
	pass


static func monthly(_state: GameState, _added: Array[Dictionary]) -> void:
	pass
