class_name WondersBridges
extends RefCounted
## Ponts des merveilles (lot 3) : guerre, espionnage, Amphictyonie, œuvres collectives, victoire.
## Porte aussi les ordres « won_act » de tous les lots.


static func check_act(state: GameState, player: int, act: String, wid: String, x: int, n: int) -> String:
	if state.get_empire(player) == null:
		return "empire inconnu"
	if not Wonders.enabled(state):
		return "pas de merveilles dans cette partie"
	match act:
		"start":
			return Wonders.check_start(state, player, x, wid)
		"cancel":
			return Wonders.check_cancel(state, player, wid)
		"contribute":
			return Wonders.check_contribute(state, player, wid, x)
		"rush":
			return Wonders.check_rush(state, player, wid)
	return _check_more(state, player, act, wid, x, n)


static func act(state: GameState, player: int, act_id: String, wid: String, x: int, n: int, added: Array[Dictionary]) -> void:
	match act_id:
		"start":
			Wonders.start(state, player, x, wid, added)
		"cancel":
			Wonders.cancel(state, player, wid, added)
		"contribute":
			Wonders.contribute(state, player, wid, x)
		"rush":
			Wonders.rush(state, player, wid)
		_:
			_act_more(state, player, act_id, wid, x, n, added)


static func _check_more(state: GameState, player: int, act_id: String, wid: String, _x: int, _n: int) -> String:
	match act_id:
		"restore":
			return WondersCatalog.check_restore(state, player, wid)
		"tribunal":
			return WondersCatalog.check_tribunal(state, player)
	return "ordre inconnu : %s" % act_id


static func _act_more(state: GameState, player: int, act_id: String, wid: String, _x: int, _n: int, added: Array[Dictionary]) -> void:
	match act_id:
		"restore":
			WondersCatalog.restore(state, player, wid, added)
		"tribunal":
			WondersCatalog.tribunal(state, player, added)


static func oeuvres_on(_state: GameState) -> bool:
	return false


static func check_collective(_state: GameState, _eid: int, _wid: String) -> String:
	return ""


static func blocked(_state: GameState, _eid: int, _entry: Dictionary) -> bool:
	return false


static func daily(_state: GameState, _added: Array[Dictionary]) -> void:
	pass


static func on_complete_collective(_state: GameState, _wid: String, _eid: int, _pid: int, _entry: Dictionary) -> void:
	pass


static func on_complete(_state: GameState, _wid: String, _eid: int, _pid: int, _added: Array[Dictionary]) -> void:
	pass


## Ponts de l'IA (lots 2-3) : ruines, œuvres collectives, espionnage des chantiers.
static func ai_think(_ctx: Dictionary) -> void:
	pass
